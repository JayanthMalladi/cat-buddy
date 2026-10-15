import Foundation

/// One task on her to-do note.
struct TodoItem: Codable, Equatable {
    var id = UUID()
    var text: String
    var done = false
}

/// Today's tasks, saved in Application Support so they survive restarts and updates.
///
/// Tasks can be added at any time of day. When a new day starts, finished tasks are cleared and
/// unfinished ones carry over.
@MainActor
final class TodoList {
    static let maxItems = 10

    private struct Saved: Codable {
        var day: String
        var items: [TodoItem]
    }

    nonisolated static var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Vrinda's Cat/todos.json")
    }

    private(set) var items: [TodoItem] = []
    private var day = ""
    /// Called whenever the list changes.
    var onChange: (() -> Void)?

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            items = saved.items
            day = saved.day
        }
        rollOverIfNewDay()
    }

    var open: [TodoItem] { items.filter { !$0.done } }
    var doneCount: Int { items.filter(\.done).count }

    /// Adds a task. Returns false if it's empty or the note is full.
    @discardableResult
    func add(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, items.count < Self.maxItems else { return false }
        items.append(TodoItem(text: trimmed))
        changed()
        return true
    }

    /// Ticks or unticks a task and returns its new state.
    func toggle(_ id: UUID) -> Bool? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        items[index].done.toggle()
        changed()
        return items[index].done
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        changed()
    }

    /// On a new day, clears what she finished and keeps what's left.
    func rollOverIfNewDay() {
        let today = Self.dayString(Date())
        guard today != day else { return }
        day = today
        items.removeAll(where: \.done)
        changed()
    }

    private func changed() {
        save()
        onChange?()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(Saved(day: day, items: items))
            try FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            NSLog("CampusCat: could not save the to-do list: \(error.localizedDescription)")
        }
    }

    private static func dayString(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// The times of day she checks on the list (11:00, 15:00 and 19:00 unless the sheet says otherwise).
enum CheckIns {
    static let timesKey = "checkInTimes"
    static let lastKey = "lastCheckIn"
    static let defaultTimes = [11 * 60, 15 * 60, 19 * 60]
    /// A check-in missed by more than this (the Mac was asleep) is skipped.
    static let lateness: TimeInterval = 2 * 60 * 60

    /// Minutes after midnight, earliest first.
    static var times: [Int] {
        let saved = parse(UserDefaults.standard.string(forKey: timesKey) ?? "")
        return saved.isEmpty ? defaultTimes : saved
    }

    /// Reads "11:00, 15:00, 19:00", "11am, 3pm, 7pm", "3:30 pm" or "14" (also with seconds,
    /// which is how Sheets writes a cell it took for a time).
    static func parse(_ text: String) -> [Int] {
        let minutes = text.lowercased()
            .split(whereSeparator: { ",;\n".contains($0) })
            .compactMap { raw -> Int? in
                var s = raw.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ".", with: "")
                var half: String?
                for suffix in ["am", "pm"] where s.hasSuffix(suffix) {
                    half = suffix
                    s.removeLast(2)
                }
                let parts = s.split(separator: ":", omittingEmptySubsequences: false)
                guard (1...3).contains(parts.count), var hour = Int(parts[0]) else { return nil }
                let minute = parts.count >= 2 ? Int(parts[1]) : 0
                guard let minute, (0..<60).contains(minute) else { return nil }
                if let half {
                    guard (1...12).contains(hour) else { return nil }
                    hour = hour % 12 + (half == "pm" ? 12 : 0)
                }
                guard (0..<24).contains(hour) else { return nil }
                return hour * 60 + minute
            }
        return Array(Set(minutes)).sorted()
    }

    /// Whether a check-in has come due since the last one: nil if not, true if it's the day's last.
    static func due(at now: Date) -> Bool? {
        let times = self.times
        let startOfDay = Calendar.current.startOfDay(for: now)
        let last = UserDefaults.standard.object(forKey: lastKey) as? Date ?? .distantPast
        guard let index = times.lastIndex(where: { startOfDay.addingTimeInterval(TimeInterval($0 * 60)) <= now }) else {
            return nil
        }
        let slot = startOfDay.addingTimeInterval(TimeInterval(times[index] * 60))
        guard last < slot else { return nil }
        UserDefaults.standard.set(now, forKey: lastKey)
        guard now.timeIntervalSince(slot) < lateness else { return nil }
        return index == times.count - 1
    }
}
