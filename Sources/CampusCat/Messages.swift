import Foundation

/// Picks preset lines from messages.json without repeating recent ones.
final class Messages {
    private let all: [String]
    private var recent: [String] = []

    init() {
        var lines: [String] = []
        do {
            let data = try Data(contentsOf: Resources.url("messages.json"))
            // Categories are just for organising the file; every line is fair game.
            let groups = try JSONDecoder().decode([String: [String]].self, from: data)
            lines = groups.keys.sorted().flatMap { groups[$0] ?? [] }
        } catch {
            NSLog("CampusCat: could not read messages.json: \(error)")
        }
        all = lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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
