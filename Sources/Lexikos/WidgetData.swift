import Foundation

/// What the home-screen widgets show. The app writes it to the shared App Group container
/// after every change; the widget extension only ever reads it.
struct WidgetSnapshot: Codable {
    struct Word: Codable, Hashable { var front: String; var back: String }

    var written = Date()
    var lang = "zh"
    var accent = "sage"
    var deckName = ""
    var due = 0, new = 0, done = 0
    /// Counts for the day after `written`, so the widget can roll over at midnight without the app.
    var dueTomorrow = 0, newTomorrow = 0
    /// Cards reviewed on each of the last seven days, oldest first.
    var week: [Int] = Array(repeating: 0, count: 7)
    var streak = 0
    var words: [Word] = []

    static let groupID: String = {
        #if os(macOS)
        "BGM8P5U985.com.yixuanwu.lexikos"
        #else
        "group.com.yixuanwu.lexikos"
        #endif
    }()

    private static var file: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?.appendingPathComponent("widget.json")
    }

    static func load() -> WidgetSnapshot? {
        file.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }

    func save() {
        guard let file = Self.file, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: file, options: .atomic)
    }

    /// The snapshot as it stands at `date`: after midnight the "tomorrow" counts take over.
    func at(_ date: Date) -> WidgetSnapshot {
        guard !Calendar.current.isDate(date, inSameDayAs: written), date > written else { return self }
        var s = self
        s.due = dueTomorrow; s.new = newTomorrow; s.done = 0
        if !Calendar.current.isDate(date, inSameDayAs: written.addingTimeInterval(86400)) { s.due = max(dueTomorrow, due) }
        s.week = Array(week.dropFirst()) + [0]
        if week.last == 0 { s.streak = 0 }
        return s
    }
}
