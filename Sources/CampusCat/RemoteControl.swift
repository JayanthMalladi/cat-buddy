import Foundation

/// Reads the "Control" tab of the messages sheet (CatController asks every minute), so Jayanth can nudge her
/// from anywhere and change when the cat checks on her list.
///
/// The tab has a name in column A and a value in column B:
///
///     Nudge           | Go finish that lab report! I believe in you.
///     Check-in times  | 11:00, 15:00, 19:00
///
/// Typing a new nudge makes the cat say it once (changing the text sends it again). The check-in
/// times replace the defaults; an empty cell goes back to 11:00, 15:00 and 19:00.
/// It uses the same share link as the messages, so nothing extra is set up on her Mac.
@MainActor
final class RemoteControl: NSObject {
    static let tabName = "Control"
    private static let lastNudgeKey = "lastNudge"

    /// Called with a new nudge from the sheet.
    var onNudge: ((String) -> Void)?

    /// Where the tab is read from: the hidden `controlFeed` default (used by CI), or the Control
    /// tab of the pasted messages sheet. Nil when no sheet link is set.
    nonisolated static var source: URL? {
        if let feed = UserDefaults.standard.string(forKey: "controlFeed"), let url = URL(string: feed) {
            return url
        }
        guard let link = URL(string: RemoteMessages.link), link.host == "docs.google.com" else { return nil }
        let parts = link.pathComponents   // ["/", "spreadsheets", "d", "<id>", "edit"]
        guard parts.contains("spreadsheets"), let d = parts.firstIndex(of: "d"), d + 1 < parts.count else { return nil }
        var components = URLComponents(string: "https://docs.google.com/spreadsheets/d/\(parts[d + 1])/gviz/tq")
        components?.queryItems = [
            URLQueryItem(name: "tqx", value: "out:csv"),
            URLQueryItem(name: "headers", value: "0"),
            URLQueryItem(name: "sheet", value: tabName),
        ]
        return components?.url
    }

    func refresh() {
        guard let url = Self.source else { return }
        Task { await fetch(url) }
    }

    private func fetch(_ url: URL) async {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { return }
            guard let text = String(data: data, encoding: .utf8) else { return }
            apply(Self.parse(text))
        } catch {
            NSLog("CampusCat: could not read the Control tab: \(error.localizedDescription)")
        }
    }

    /// Picks the Nudge and Check-in times rows out of the tab. If the sheet has no Control tab,
    /// Google sends the first tab instead, which has neither row, so nothing changes.
    nonisolated static func parse(_ text: String) -> (nudge: String?, times: String?) {
        guard !text.prefix(200).lowercased().contains("<html") else { return (nil, nil) }
        var nudge: String?
        var times: String?
        for row in Messages.csvRows(text) where row.count >= 2 {
            let name = row[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = row[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if name == "nudge" {
                nudge = value
            } else if name.hasPrefix("check-in") || name.hasPrefix("check in") || name.hasPrefix("checkin") {
                times = value
            }
        }
        return (nudge, times)
    }

    private func apply(_ control: (nudge: String?, times: String?)) {
        if let times = control.times {
            if CheckIns.parse(times).isEmpty {
                UserDefaults.standard.removeObject(forKey: CheckIns.timesKey)
            } else {
                UserDefaults.standard.set(times, forKey: CheckIns.timesKey)
            }
        }
        if let nudge = control.nudge, !nudge.isEmpty,
           nudge != UserDefaults.standard.string(forKey: Self.lastNudgeKey) {
            UserDefaults.standard.set(nudge, forKey: Self.lastNudgeKey)
            onNudge?(nudge)
        }
    }
}
