import AppKit

/// Keeps the app up to date from the repo's "latest" GitHub release.
///
/// Every hour (and shortly after launch) it compares the commit the release was built from with
/// the one baked into this app's Info.plist (`CatBuildCommit`, set by CI). When they differ it
/// downloads VrindasCat.zip, checks the new app, swaps it in place of this one and relaunches.
/// Builds without a commit (local builds) never update themselves.
@MainActor
final class Updater: NSObject {
    private static let releaseAPI = URL(string: "https://api.github.com/repos/JayanthMalladi/cat-buddy/releases/tags/latest")!
    private static let assetName = "VrindasCat.zip"

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let target_commitish: String
        let assets: [Asset]
    }

    enum Outcome {
        case upToDate, updating, unavailable(String)
    }

    let currentCommit = (Bundle.main.object(forInfoDictionaryKey: "CatBuildCommit") as? String) ?? ""
    private var timer: Timer?
    private var busy = false

    /// Hidden setting; CI turns it off so the app under test doesn't replace itself.
    private var enabled: Bool {
        UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true
    }

    /// Short commit shown in the menu.
    var versionLabel: String {
        currentCommit.isEmpty ? "local build" : "build \(currentCommit.prefix(7))"
    }

    func start() {
        let first = Timer(timeInterval: 30, target: self, selector: #selector(timerFired),
                          userInfo: nil, repeats: false)
        RunLoop.main.add(first, forMode: .common)
        let hourly = Timer(timeInterval: 60 * 60, target: self, selector: #selector(timerFired),
                           userInfo: nil, repeats: true)
        RunLoop.main.add(hourly, forMode: .common)
        timer = hourly
    }

    @objc private func timerFired() {
        guard enabled else { return }
        Task { _ = await check() }
    }

    /// Looks for a newer build and installs it. Also used by the menu's "Check for Updates".
    func check() async -> Outcome {
        let appURL = Bundle.main.bundleURL
        guard !currentCommit.isEmpty else { return .unavailable("This build can't update itself.") }
        guard appURL.pathExtension == "app", !appURL.path.contains("/AppTranslocation/") else {
            return .unavailable("Move the app into Applications first.")
        }
        guard !busy else { return .updating }
        busy = true
        defer { busy = false }

        do {
            var request = URLRequest(url: Self.releaseAPI)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 30
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                return .unavailable("GitHub didn't answer.")
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            guard release.target_commitish != currentCommit else { return .upToDate }
            guard let asset = release.assets.first(where: { $0.name == Self.assetName }) else {
                return .unavailable("The latest release has no app in it yet.")
            }
            try await install(from: asset.browser_download_url, replacing: appURL)
            return .updating
        } catch {
            NSLog("CampusCat: update failed: \(error)")
            return .unavailable("The update didn't work: \(error.localizedDescription)")
        }
    }

    private func install(from zipURL: URL, replacing appURL: URL) async throws {
        let fm = FileManager.default
        // A scratch folder on the same disk as the app, so the swap is a simple rename.
        let work = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask,
                              appropriateFor: appURL, create: true)
        defer { try? fm.removeItem(at: work) }

        let (downloaded, response) = try await URLSession.shared.download(from: zipURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("download failed") }
        let zip = work.appendingPathComponent(Self.assetName)
        try fm.moveItem(at: downloaded, to: zip)

        let unpacked = work.appendingPathComponent("unpacked")
        try await run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
        guard let newApp = try fm.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }),
              let bundle = Bundle(url: newApp),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              let executable = bundle.executableURL, fm.isExecutableFile(atPath: executable.path)
        else { throw UpdateError("the download doesn't contain the cat app") }
        try await run("/usr/bin/codesign", ["--verify", "--deep", newApp.path])
        // Don't let macOS ask about the update as if it were a fresh download.
        try? await run("/usr/bin/xattr", ["-cr", newApp.path])

        _ = try fm.replaceItemAt(appURL, withItemAt: newApp)
        NSLog("CampusCat: installed update, relaunching")
        relaunch(appURL)
    }

    /// Opens the (new) app once this process has quit.
    private func relaunch(_ appURL: URL) {
        let script = "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$2\""
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier), appURL.path]
        try? task.run()
        NSApp.terminate(nil)
    }

    private func run(_ tool: String, _ arguments: [String]) async throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = arguments
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            task.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try task.run() } catch { continuation.resume(throwing: error) }
        }
        guard status == 0 else { throw UpdateError("\(tool) failed (\(status))") }
    }
}

struct UpdateError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
