import Foundation

/// Finds the art and JSON files: inside the .app when bundled, or the repo's
/// Resources/ folder when started with `swift run`.
enum Resources {
    static let root: URL = {
        if let bundled = Bundle.main.resourceURL,
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("animations.json").path) {
            return bundled
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // CampusCat/
            .deletingLastPathComponent()   // Sources/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Resources")
    }()

    static func url(_ name: String) -> URL {
        root.appendingPathComponent(name)
    }

    /// Where her saved to-do list and the cached messages live:
    /// ~/Library/Application Support/Desktop Cat.
    static let dataFolder: URL = {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let folder = support.appendingPathComponent("Desktop Cat")
        // Builds before the rename kept their data under the old name; move it across once.
        // Can be removed once every install has run a renamed build.
        let old = support.appendingPathComponent("Vrinda's Cat")
        if !fm.fileExists(atPath: folder.path) && fm.fileExists(atPath: old.path) {
            try? fm.moveItem(at: old, to: folder)
        }
        return folder
    }()
}
