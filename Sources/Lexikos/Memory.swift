import Foundation

enum Grade: Int, Codable, CaseIterable { case forgot = 1, vague, remembered }

struct Review: Codable, Hashable { var date: Date; var grade: Grade; var stability: Double }

/// Memory state of one card. Retention follows a power forgetting curve R(t) = 1 / (1 + t / 9S),
/// so the stability S (days) is exactly the gap after which recall drops to 90 %. Reviews are due then.
struct CardState: Codable, Hashable {
    var stability: Double
    var due: Date
    var lapses = 0
    var reviews: [Review] = []

    static let masteredDays = 21.0

    var lastReview: Date { reviews.last?.date ?? due }
    var mastered: Bool { stability >= Self.masteredDays }

    func retention(at date: Date) -> Double {
        Self.retention(days: max(0, date.timeIntervalSince(lastReview) / 86400), stability: stability)
    }

    static func retention(days: Double, stability: Double) -> Double { 1 / (1 + days / (9 * stability)) }

    /// Next state after grading. Reviewing when recall has faded (low R) grows stability more: the spacing effect.
    static func next(_ s: CardState?, _ g: Grade, now: Date = .now) -> CardState {
        var st: Double, lapses = s?.lapses ?? 0
        if let s {
            let r = s.retention(at: now)
            switch g {
            case .remembered: st = s.stability * (1.5 + 8 * (1 - r))
            case .vague: st = s.stability * (1.1 + 2 * (1 - r))
            case .forgot: st = max(0.3, s.stability * 0.3); lapses += 1
            }
        } else {
            st = [Grade.forgot: 0.3, .vague: 1, .remembered: 2.5][g]!
        }
        st = min(st, 3650)
        var out = CardState(stability: st, due: now.addingTimeInterval(st * 86400), lapses: lapses, reviews: s?.reviews ?? [])
        out.reviews.append(Review(date: now, grade: g, stability: st))
        return out
    }
}

/// Per-deck learning progress, keyed by card index, one JSON file per deck.
@Observable final class ProgressStore {
    private(set) var states: [UUID: [Int: CardState]] = [:]
    private let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Lexikos/progress", isDirectory: true)

    init() {
        Migration.run()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.pathExtension == "json" {
            guard let id = UUID(uuidString: f.deletingPathExtension().lastPathComponent),
                  let s = try? JSONDecoder().decode([Int: CardState].self, from: Data(contentsOf: f)) else { continue }
            states[id] = s
        }
    }

    func states(_ deck: Deck) -> [Int: CardState] { states[deck.id] ?? [:] }

    func grade(_ deck: Deck, card: Int, _ g: Grade, now: Date = .now) {
        states[deck.id, default: [:]][card] = CardState.next(states[deck.id]?[card], g, now: now)
        try? JSONEncoder().encode(states[deck.id]).write(to: dir.appendingPathComponent("\(deck.id.uuidString).json"))
    }

    func forget(_ deck: Deck) {
        states[deck.id] = nil
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(deck.id.uuidString).json"))
    }

    // MARK: Daily plan

    struct Plan { var due: [Int]; var new: [Int]; var learnedToday: Int }

    func plan(_ deck: Deck, newPerDay: Int, now: Date = .now) -> Plan {
        let s = states(deck), cal = Calendar.current
        let endOfDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        let due = s.filter { $0.value.due < endOfDay }.sorted { $0.value.due < $1.value.due }.map(\.key)
        let introducedToday = s.values.filter { $0.reviews.first.map { cal.isDate($0.date, inSameDayAs: now) } ?? false }.count
        let fresh = deck.cards.indices.filter { s[$0] == nil }.prefix(max(0, newPerDay - introducedToday))
        let learnedToday = s.values.filter { $0.reviews.contains { cal.isDate($0.date, inSameDayAs: now) } }.count
        return Plan(due: due, new: Array(fresh), learnedToday: learnedToday)
    }
}
