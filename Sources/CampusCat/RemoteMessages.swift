import Foundation

/// Fetches messages.json from the repo's main branch every hour, so messages edited on GitHub
/// reach the cat without a new build. The last good copy is kept for the next launch, and the
/// built-in file is used until the first fetch succeeds (or if the Mac is offline).
@MainActor
final class RemoteMessages: NSObject {
    nonisolated static let source = URL(string: "https://raw.githubusercontent.com/JayanthMalladi/cat-buddy/main/Resources/messages.json")!

    nonisolated static var cacheURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Vrinda's Cat/messages.json")
    }

    private let messages: Messages
    private var timer: Timer?

    init(messages: Messages) {
        self.messages = messages
        super.init()
    }

    func start() {
        refresh()
        let timer = Timer(timeInterval: 60 * 60, target: self, selector: #selector(refresh),
                          userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc func refresh() {
        Task { await fetch() }
    }

    private func fetch() async {
        var request = URLRequest(url: Self.source)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            // A typo on GitHub (broken JSON) must not wipe out her messages.
            guard messages.load(data) else {
                NSLog("CampusCat: messages.json on GitHub is broken or empty; keeping the current messages")
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
