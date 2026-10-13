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
}
