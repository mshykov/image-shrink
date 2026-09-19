import Foundation

/// What was converted lately, so the menu bar panel can show it without the window.
struct Batch: Codable, Identifiable, Sendable {
    var id = UUID()
    var date = Date()
    var count: Int
    var before: Int
    var after: Int
}

enum History {
    private static let key = "history"
    private static let limit = 12

    static var recent: [Batch] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let batches = try? JSONDecoder().decode([Batch].self, from: data) else { return [] }
        return batches
    }

    static func add(count: Int, before: Int, after: Int) {
        guard count > 0 else { return }
        var batches = [Batch(count: count, before: before, after: after)] + recent
        batches = Array(batches.prefix(limit))
        guard let data = try? JSONEncoder().encode(batches) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// "Today" / "Yesterday" / a date, matching how Finder groups its own lists.
    static func groupTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
