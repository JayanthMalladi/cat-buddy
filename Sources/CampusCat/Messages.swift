import Foundation

/// Picks preset lines from messages.json without repeating recent ones.
/// The newest online copy (see RemoteMessages) wins over the one built into the app.
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

    /// Accepts messages.json (categories of lines) or a CSV export of a sheet (first column,
    /// one message per row; a first row that just says "message" or "messages" is a header).
    static func parse(_ data: Data) -> [String] {
        let lines: [String]
        if let groups = try? JSONDecoder().decode([String: [String]].self, from: data) {
            // Categories are just for organising the file; every line is fair game.
            lines = groups.keys.sorted().flatMap { groups[$0] ?? [] }
        } else if let text = String(data: data, encoding: .utf8), !looksLikeHTML(text),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {   // broken JSON
            var rows = csvFirstColumn(text)
            if let first = rows.first?.lowercased(), first == "message" || first == "messages" {
                rows.removeFirst()
            }
            lines = rows
        } else {
            lines = []
        }
        return lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Google answers with a sign-in page when a file isn't shared; that's not a list of messages.
    private static func looksLikeHTML(_ text: String) -> Bool {
        let start = text.prefix(200).lowercased()
        return start.contains("<!doctype html") || start.contains("<html")
    }

    /// The first field of every CSV row.
    static func csvFirstColumn(_ text: String) -> [String] {
        csvRows(text).map { $0.first ?? "" }
    }

    /// Every CSV row's fields, handling quoted fields with commas, quotes and line breaks.
    static func csvRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
        if chars.first == "\u{FEFF}" { chars.removeFirst() }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
            } else if c == "," {
                row.append(field)
                field = ""
            } else if c == "\n" || c == "\r" {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(c)
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
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
