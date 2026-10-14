import Foundation

/// Picks preset lines from messages.json without repeating recent ones.
/// The newest copy from GitHub (see RemoteMessages) wins over the one built into the app.
final class Messages {
    private var all: [String] = []
    private var recent: [String] = []

    init() {
        if let cached = try? Data(contentsOf: RemoteMessages.cacheURL), load(cached) { return }
        do {
            if !load(try Data(contentsOf: Resources.url("messages.json"))) {
                NSLog("CampusCat: messages.json has no messages")
            }
        } catch {
            NSLog("CampusCat: could not read messages.json: \(error)")
        }
    }

    /// Reads a messages.json file. Returns false (and keeps the current lines) if it's broken or empty.
    @discardableResult
    func load(_ data: Data) -> Bool {
        let lines = Self.parse(data)
        guard !lines.isEmpty else { return false }
        all = lines
        return true
    }

    static func parse(_ data: Data) -> [String] {
        // Categories are just for organising the file; every line is fair game.
        guard let groups = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [] }
        return groups.keys.sorted().flatMap { groups[$0] ?? [] }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func next() -> String? {
        guard !all.isEmpty else { return nil }
        // Avoid the last few lines (up to half the list) so nothing repeats soon.
        let avoid = min(all.count / 2, 5)
        let pool = all.filter { !recent.suffix(avoid).contains($0) }
        let pick = (pool.isEmpty ? all : pool).randomElement()!
        recent.append(pick)
        if recent.count > 10 { recent.removeFirst() }
        return pick
    }
}
