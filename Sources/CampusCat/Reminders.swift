import Foundation

/// Periodic reminders from reminders.json, each on its own interval.
final class Reminders {
    struct Reminder: Decodable {
        let text: String
        let everyMinutes: Double
        /// Optional state to play with it, e.g. "stretching".
        let animation: String?
    }

    private let items: [Reminder]
    private var nextDue: [Date] = []

    init() {
        do {
            let data = try Data(contentsOf: Resources.url("reminders.json"))
            items = try JSONDecoder().decode([Reminder].self, from: data).filter { $0.everyMinutes > 0 }
        } catch {
            NSLog("CampusCat: could not read reminders.json: \(error)")
            items = []
        }
    }

    /// Starts every reminder's clock from now.
    func restart() {
        let now = Date()
        nextDue = items.map { now.addingTimeInterval($0.everyMinutes * 60) }
    }

    /// The reminder to show now, if any. At most one fires at a time; others that are also due
    /// wait a couple of minutes so bubbles don't replace each other.
    func due(at now: Date) -> Reminder? {
        guard let index = nextDue.indices.first(where: { nextDue[$0] <= now }) else { return nil }
        nextDue[index] = now.addingTimeInterval(items[index].everyMinutes * 60)
        for other in nextDue.indices where other != index && nextDue[other] <= now.addingTimeInterval(120) {
            nextDue[other] = now.addingTimeInterval(120)
        }
        return items[index]
    }
}
