import Foundation

enum Grade: Int, Codable, CaseIterable { case forgot = 1, vague, remembered }

struct Review: Codable, Hashable { var date: Date; var grade: Grade; var stability: Double }

/// Memory state of one card.
/// Combines Anki's two-phase model (intraday learning/relearning steps + graduated SM-2/FSRS review intervals)
/// with a power forgetting curve R(t) = 1 / (1 + t / 9S), where S (days) is the 90 % retention interval.
struct CardState: Codable, Hashable {
    var stability: Double
    var due: Date
    var lapses = 0
    var reviews: [Review] = []
    var ease: Double = 2.5
    /// 0 = graduated review card; 1 = initial learning step (1 min); 2 = relearning / missed learning step (10 min).
    var step: Int = 0

    static let masteredDays = 21.0
    static let step1Seconds: TimeInterval = 60
    static let step2Seconds: TimeInterval = 600

    var lastReview: Date {
        if let last = reviews.last?.date { return last }
        if step > 0 { return due.addingTimeInterval(-Self.step1Seconds) }
        return due
    }
    var isLearning: Bool { step > 0 || stability < 1.0 }
    var mastered: Bool { step == 0 && stability >= Self.masteredDays }

    init(stability: Double, due: Date, lapses: Int = 0, reviews: [Review] = [], ease: Double = 2.5, step: Int = 0) {
        self.stability = stability
        self.due = due
        self.lapses = lapses
        self.reviews = reviews
        self.ease = ease
        self.step = step
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stability = try c.decode(Double.self, forKey: .stability)
        due = try c.decode(Date.self, forKey: .due)
        lapses = (try? c.decode(Int.self, forKey: .lapses)) ?? 0
        reviews = (try? c.decode([Review].self, forKey: .reviews)) ?? []
        ease = (try? c.decode(Double.self, forKey: .ease)) ?? 2.5
        if let decodedStep = try? c.decode(Int.self, forKey: .step) {
            step = decodedStep
        } else {
            // Migrate legacy records created before Anki learning steps existed.
            if reviews.count <= 1 && reviews.first?.grade == .forgot {
                step = 1
            } else if reviews.last?.grade == .forgot {
                step = 2
            } else {
                step = 0
                if stability < 1.0, let last = reviews.last {
                    stability = 1.0
                    due = last.date.addingTimeInterval(86400)
                }
            }
        }
    }

    func retention(at date: Date) -> Double {
        let effStability = max(0.3, stability)
        return Self.retention(days: max(0, date.timeIntervalSince(lastReview) / 86400), stability: effStability)
    }

    static func retention(days: Double, stability: Double) -> Double {
        1 / (1 + days / (9 * max(0.1, stability)))
    }

    /// Initial exposure of a brand-new card: enters Learning Step 1 (1 min) without recording a false lapse.
    static func introduce(_ s: CardState?, now: Date = .now) -> CardState {
        if let s { return s }
        return CardState(stability: 0.4, due: now.addingTimeInterval(step1Seconds), lapses: 0, reviews: [], ease: 2.5, step: 1)
    }

    /// Anki-style state transition upon grading.
    /// - New / Learning cards (`s == nil` or `s.step > 0`):
    ///   - `.forgot` (Again): stays in learning/relearning (`step = 2`, due in 1–10 min, re-queued in current group).
    ///   - `.vague` (Hard): graduates to 1 day (`step = 0`).
    ///   - `.remembered` (Good/Easy): graduates to 3 days on first-try pass, 1 day if missed in learning,
    ///     or `max(1, 0.25 * priorStability)` if re-graduating from a review lapse.
    /// - Graduated Review cards (`s.step == 0`):
    ///   - `.forgot` (Again): increments `lapses`, reduces `ease` by 0.20, enters relearning (`step = 2`, due in 10 min).
    ///   - `.vague` (Hard): reduces `ease` by 0.15, grows interval by ~1.2x (at least +1 day).
    ///   - `.remembered` (Good): grows interval by `ease` (default 2.5x) with Anki overdue bonus.
    static func next(_ s: CardState?, _ g: Grade, now: Date = .now) -> CardState {
        let priorReviews = s?.reviews ?? []
        var lapses = s?.lapses ?? 0
        var ease = s?.ease ?? 2.5

        // Phase 1: Brand-new card or card currently in intraday Learning / Relearning steps
        if s == nil || (s?.step ?? 0) > 0 {
            let priorS = s?.stability ?? 0.4
            let wasGraduatedReview = priorS >= 1.0 && priorReviews.contains(where: { $0.stability >= 1.0 })
            let hadMissInStep = (s?.step ?? 1) >= 2

            switch g {
            case .forgot:
                let wait = wasGraduatedReview ? step2Seconds : step1Seconds
                let curveS = wasGraduatedReview ? max(0.5, priorS * 0.25) : 0.3
                var out = CardState(stability: priorS, due: now.addingTimeInterval(wait),
                                    lapses: lapses, reviews: priorReviews, ease: ease, step: 2)
                out.reviews.append(Review(date: now, grade: .forgot, stability: curveS))
                return out

            case .vague:
                let st = 1.0
                var out = CardState(stability: st, due: now.addingTimeInterval(st * 86400),
                                    lapses: lapses, reviews: priorReviews, ease: ease, step: 0)
                out.reviews.append(Review(date: now, grade: .vague, stability: st))
                return out

            case .remembered:
                let st: Double
                if wasGraduatedReview {
                    st = max(1.0, (priorS * 0.25).rounded())
                } else if hadMissInStep {
                    st = 1.0
                } else {
                    st = 3.0
                }
                var out = CardState(stability: st, due: now.addingTimeInterval(st * 86400),
                                    lapses: lapses, reviews: priorReviews, ease: ease, step: 0)
                out.reviews.append(Review(date: now, grade: .remembered, stability: st))
                return out
            }
        }

        // Phase 2: Graduated Review card (or legacy sub-day card)
        let cur = s!
        let r = cur.retention(at: now)
        let elapsed = max(0, now.timeIntervalSince(cur.lastReview) / 86400)

        switch g {
        case .forgot:
            lapses += 1
            ease = max(1.3, ease - 0.20)
            let curveS = max(0.3, cur.stability * 0.25)
            // Keep cur.stability on the state while step == 2 so re-graduation knows the prior interval.
            var out = CardState(stability: max(1.0, cur.stability), due: now.addingTimeInterval(step2Seconds),
                                lapses: lapses, reviews: priorReviews, ease: ease, step: 2)
            out.reviews.append(Review(date: now, grade: .forgot, stability: curveS))
            return out

        case .vague:
            ease = max(1.3, ease - 0.15)
            let st: Double
            if cur.stability < 1.0 {
                st = 1.0
            } else {
                st = min(3650, max(cur.stability + 1.0, cur.stability * (1.2 + 0.3 * (1 - r))))
            }
            var out = CardState(stability: st, due: now.addingTimeInterval(st * 86400),
                                lapses: lapses, reviews: priorReviews, ease: ease, step: 0)
            out.reviews.append(Review(date: now, grade: .vague, stability: st))
            return out

        case .remembered:
            let st: Double
            if cur.stability < 1.0 {
                st = cur.lapses > 0 ? 1.5 : 3.0
            } else {
                // Anki overdue bonus: half of overdue days credited when recalled.
                let effectiveS = cur.stability + max(0, elapsed - cur.stability) * 0.5
                let factor = ease + max(0, (0.9 - r) * 1.5)
                st = min(3650, max(cur.stability < 2.0 ? 3.0 : cur.stability + 1.0, effectiveS * factor))
            }
            var out = CardState(stability: st, due: now.addingTimeInterval(st * 86400),
                                lapses: lapses, reviews: priorReviews, ease: ease, step: 0)
            out.reviews.append(Review(date: now, grade: .remembered, stability: st))
            return out
        }
    }
}

/// One study action. The per-deck log of these is the source of truth for progress: card states are
/// derived by replaying it, so logs from several devices merge by plain union, without conflicts.
struct ReviewEvent: Codable, Hashable, Identifiable {
    enum Kind: Codable, Hashable {
        case introduce
        case grade(Grade)
        /// Whole-deck "forget progress"; `card` is empty.
        case reset
        /// State carried over from the pre-log snapshot files.
        case seed(CardState)
    }
    var id = UUID()
    var deck: UUID
    var card: String
    var date: Date
    var kind: Kind

    /// Order of replay; the id breaks ties so every device replays identically.
    static func < (a: Self, b: Self) -> Bool { (a.date, a.id.uuidString) < (b.date, b.id.uuidString) }

    static func replay(_ events: [ReviewEvent], onto start: [String: CardState] = [:]) -> [String: CardState] {
        var out = start
        for e in events.sorted(by: <) {
            switch e.kind {
            case .introduce: out[e.card] = CardState.introduce(out[e.card], now: e.date)
            case .grade(let g): out[e.card] = CardState.next(out[e.card], g, now: e.date)
            case .reset: out = [:]
            case .seed(let s): out[e.card] = s
            }
        }
        return out
    }
}

extension Card {
    /// Content-derived identity, so progress survives re-imports that reorder cards and matches across devices.
    var key: String {
        var h: UInt64 = 0xcbf29ce484222325 // FNV-1a
        for b in (front + "\u{1F}" + back).utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(h, radix: 36)
    }
}

extension Deck {
    /// Card keys by index; repeated cards get "#2", "#3"… so each keeps its own progress.
    var keys: [String] {
        var seen: [String: Int] = [:]
        return cards.map { c in
            let k = c.key, n = seen[k, default: 0] + 1
            seen[k] = n
            return n == 1 ? k : "\(k)#\(n)"
        }
    }
}

/// Per-deck learning progress. Each deck has an append-only event log (JSON Lines) in Application Support;
/// states are replayed from it and exposed by card index for the views.
@Observable final class ProgressStore {
    private(set) var events: [UUID: [ReviewEvent]] = [:]
    private var replayed: [UUID: [String: CardState]] = [:]
    /// Called for every event recorded on this device (the sync engine uploads them).
    @ObservationIgnored var onRecord: ((ReviewEvent) -> Void)?
    private let dir: URL

    init(dir: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Lexikos/progress", isDirectory: true)) {
        self.dir = dir
        Migration.run()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Self.migrateSnapshots(in: dir)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.pathExtension == "jsonl" {
            guard let id = UUID(uuidString: f.deletingPathExtension().lastPathComponent),
                  let text = try? String(contentsOf: f, encoding: .utf8) else { continue }
            events[id] = text.split(separator: "\n").compactMap { try? JSONDecoder().decode(ReviewEvent.self, from: Data($0.utf8)) }
            replayed[id] = ReviewEvent.replay(events[id]!)
        }
    }

    func states(_ deck: Deck) -> [Int: CardState] {
        guard let raw = replayed[deck.id] else { return [:] }
        var out: [Int: CardState] = [:]
        for (i, k) in deck.keys.enumerated() { if let s = raw[k] { out[i] = s } }
        return out
    }

    func introduce(_ deck: Deck, card: Int, now: Date = .now) {
        record(ReviewEvent(deck: deck.id, card: deck.keys[card], date: now, kind: .introduce))
    }

    func grade(_ deck: Deck, card: Int, _ g: Grade, now: Date = .now) {
        record(ReviewEvent(deck: deck.id, card: deck.keys[card], date: now, kind: .grade(g)))
    }

    func forget(_ deck: Deck, now: Date = .now) {
        record(ReviewEvent(deck: deck.id, card: "", date: now, kind: .reset))
    }

    /// Adds events from another device; ones already known are ignored. Returns how many were new.
    @discardableResult func merge(_ incoming: [ReviewEvent]) -> Int {
        var added = 0
        for (deck, batch) in Dictionary(grouping: incoming, by: \.deck) {
            let known = Set((events[deck] ?? []).map(\.id))
            let fresh = batch.filter { !known.contains($0.id) }
            guard !fresh.isEmpty else { continue }
            events[deck, default: []] += fresh
            append(fresh, deck: deck)
            replayed[deck] = ReviewEvent.replay(events[deck]!)
            added += fresh.count
        }
        return added
    }

    private func record(_ e: ReviewEvent) {
        events[e.deck, default: []].append(e)
        append([e], deck: e.deck)
        // Replaying one event onto the current state equals a full replay unless it is older than the newest.
        if let last = events[e.deck]?.dropLast().max(by: <), !(last < e) {
            replayed[e.deck] = ReviewEvent.replay(events[e.deck]!)
        } else {
            replayed[e.deck] = ReviewEvent.replay([e], onto: replayed[e.deck] ?? [:])
        }
        onRecord?(e)
    }

    private func append(_ batch: [ReviewEvent], deck: UUID) {
        let url = dir.appendingPathComponent("\(deck.uuidString).jsonl")
        let lines = batch.compactMap { try? JSONEncoder().encode($0) }.map { $0 + Data("\n".utf8) }.reduce(Data(), +)
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: lines)
        } else {
            try? lines.write(to: url)
        }
    }

    /// One-time conversion of the old `<deck>.json` snapshots (card index → state) into seed events.
    /// The snapshot is kept as `<deck>.json.legacy`.
    static func migrateSnapshots(in dir: URL) {
        let fm = FileManager.default
        let decksDir = dir.deletingLastPathComponent().appendingPathComponent("decks")
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.pathExtension == "json" {
            guard let id = UUID(uuidString: f.deletingPathExtension().lastPathComponent) else { continue }
            let log = dir.appendingPathComponent("\(id.uuidString).jsonl")
            guard !fm.fileExists(atPath: log.path),
                  let old = try? JSONDecoder().decode([Int: CardState].self, from: Data(contentsOf: f)),
                  let deck = try? JSONDecoder().decode(Deck.self, from: Data(contentsOf: decksDir.appendingPathComponent(f.lastPathComponent)))
            else { continue }
            let keys = deck.keys
            let seeds = old.sorted { $0.key < $1.key }.filter { keys.indices.contains($0.key) }.map { i, s in
                ReviewEvent(deck: id, card: keys[i], date: s.lastReview, kind: .seed(s))
            }
            let data = seeds.compactMap { try? JSONEncoder().encode($0) }.map { $0 + Data("\n".utf8) }.reduce(Data(), +)
            guard (try? data.write(to: log)) != nil else { continue }
            try? fm.moveItem(at: f, to: f.appendingPathExtension("legacy"))
        }
    }

    // MARK: Daily & Group plan

    struct Plan {
        var due: [Int]
        var new: [Int]
        var groupDue: [Int]
        var groupNew: [Int]
        var unseenCount: Int
        var learnedToday: Int

        /// Next group queue: always prioritizes due review/learning cards first, then fills with new cards.
        var groupQueue: [Int] { groupDue + groupNew }
    }

    func plan(_ deck: Deck, newPerDay: Int, groupSize: Int = 10, now: Date = .now) -> Plan {
        let s = states(deck), cal = Calendar.current
        let endOfDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        // Sort due cards: intraday learning/relearning steps (step > 0) first, then due reviews by due date.
        let due = s.filter { $0.value.step > 0 || $0.value.due < endOfDay }
            .sorted { a, b in
                let aLearn = a.value.step > 0, bLearn = b.value.step > 0
                if aLearn != bLearn { return aLearn }
                return a.value.due < b.value.due
            }
            .map(\.key)

        let introducedToday = s.values.filter {
            if let first = $0.reviews.first { return cal.isDate(first.date, inSameDayAs: now) }
            return $0.step > 0 && cal.isDate($0.lastReview, inSameDayAs: now)
        }.count

        let allUnseen = deck.cards.indices.filter { s[$0] == nil }
        let freshDaily = allUnseen.prefix(max(0, newPerDay - introducedToday))

        let size = max(1, groupSize)
        let groupDue = Array(due.prefix(size))
        let groupNew = Array(allUnseen.prefix(max(0, size - groupDue.count)))

        let learnedToday = s.values.filter {
            $0.reviews.contains { cal.isDate($0.date, inSameDayAs: now) }
        }.count

        return Plan(due: due,
                    new: Array(freshDaily),
                    groupDue: groupDue,
                    groupNew: groupNew,
                    unseenCount: allUnseen.count,
                    learnedToday: learnedToday)
    }
}
