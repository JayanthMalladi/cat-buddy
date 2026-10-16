import Foundation

/// Fetches the messages (CatController asks every minute), so new ones reach the cat without a new build.
///
/// The source is a Google Sheet (or Drive file) share link pasted in from the menu ("Set Messages
/// Link…"). It's saved only in this Mac's settings, never in the app or the repo, so the public
/// download doesn't reveal it. Without one it falls back to messages.json on the repo's main
/// branch. The last good copy is kept for the next launch, and the built-in file is used until
/// the first fetch succeeds.
@MainActor
final class RemoteMessages: NSObject {
    nonisolated static let gitHubSource = URL(string: "https://raw.githubusercontent.com/JayanthMalladi/cat-buddy/main/Resources/messages.json")!

    private static let linkKey = "messagesLink"

    /// The pasted share link, if any.
    nonisolated static var link: String {
        UserDefaults.standard.string(forKey: linkKey) ?? ""
    }

    nonisolated static var source: URL {
        guard let url = URL(string: link), url.scheme == "https" else { return gitHubSource }
        return downloadURL(for: url)
    }

    /// Saves a new share link (empty to go back to GitHub) and fetches from it right away.
    /// Returns false if it isn't an https link.
    func setLink(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            guard let url = URL(string: trimmed), url.scheme == "https" else { return false }
        }
        UserDefaults.standard.set(trimmed, forKey: Self.linkKey)
        refresh()
        return true
    }

    /// Turns a Google Sheets or Drive share link into a link that downloads the contents.
    nonisolated static func downloadURL(for link: URL) -> URL {
        let parts = link.pathComponents   // e.g. ["/", "spreadsheets", "d", "<id>", "edit"]
        guard let host = link.host, let d = parts.firstIndex(of: "d"), d + 1 < parts.count else { return link }
        let id = parts[d + 1]
        if host == "docs.google.com" && parts.contains("spreadsheets") {
            var csv = "https://docs.google.com/spreadsheets/d/\(id)/export?format=csv"
            // Keep the tab if the link points at one.
            let fromFragment = link.fragment.flatMap { $0.hasPrefix("gid=") ? String($0.dropFirst(4)) : nil }
            let fromQuery = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == "gid" })?.value
            if let gid = fromQuery ?? fromFragment, !gid.isEmpty {
                csv += "&gid=\(gid)"
            }
            return URL(string: csv) ?? link
        }
        if host == "drive.google.com" && parts.contains("file") {
            return URL(string: "https://drive.google.com/uc?export=download&id=\(id)") ?? link
        }
        return link
    }

    nonisolated static var cacheURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Vrinda's Cat/messages.json")
    }

    private let messages: Messages

    init(messages: Messages) {
        self.messages = messages
        super.init()
    }

    func refresh() {
        Task { await fetch() }
    }

    private func fetch() async {
        var request = URLRequest(url: Self.source)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            // A broken or empty file (or a sign-in page, if sharing is off) must not wipe out her messages.
            guard messages.load(data) else {
                NSLog("CampusCat: the online messages are broken, empty or not shared; keeping the current messages")
                return
            }
            let cache = Self.cacheURL
            try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: cache, options: .atomic)
        } catch {
            NSLog("CampusCat: could not fetch messages: \(error.localizedDescription)")
        }
    }
}
