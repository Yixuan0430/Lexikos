import SwiftUI
import WidgetKit

extension View {
    /// Keeps the home-screen widgets current: rewrites their snapshot whenever progress or decks change.
    func widgetFeed(decks: DeckStore, progress: ProgressStore) -> some View {
        modifier(WidgetFeedModifier(decks: decks, progress: progress))
    }
}

private struct WidgetFeedModifier: ViewModifier {
    let decks: DeckStore, progress: ProgressStore
    @Environment(\.scenePhase) private var phase
    @AppStorage("newPerDay") private var newPerDay = 20
    @AppStorage("startDeck") private var startDeck = ""
    @AppStorage("lang") private var lang = AppLanguage.zh
    @AppStorage("accent") private var accent = Accent.sage

    private var stamp: [AnyHashable] {
        [progress.events.values.map(\.count).reduce(0, +), decks.decks.count, newPerDay, startDeck, lang.rawValue, accent.rawValue]
    }

    func body(content: Content) -> some View {
        content
            .task(id: stamp) {
                try? await Task.sleep(for: .seconds(1)) // a burst of synced events writes once
                write()
            }
            .onChange(of: phase) { if phase != .active { write() } }
    }

    private func write() {
        let cal = Calendar.current, now = Date.now
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        var s = WidgetSnapshot(lang: lang.rawValue, accent: accent.rawValue)
        var days: [Date] = []
        for deck in decks.decks {
            let p = progress.plan(deck, newPerDay: newPerDay)
            s.due += p.due.count; s.new += p.new.count; s.done += p.learnedToday
            let next = progress.plan(deck, newPerDay: newPerDay, now: cal.startOfDay(for: tomorrow))
            s.dueTomorrow += next.due.count
            s.newTomorrow += min(newPerDay, p.unseenCount - p.new.count)
            days += progress.states(deck).values.flatMap { $0.reviews.map(\.date) }
        }
        let today = cal.startOfDay(for: now)
        let perDay = Dictionary(grouping: days) { cal.startOfDay(for: $0) }.mapValues(\.count)
        s.week = (0..<7).reversed().map { perDay[cal.date(byAdding: .day, value: -$0, to: today)!] ?? 0 }
        var day = perDay[today] == nil ? cal.date(byAdding: .day, value: -1, to: today)! : today
        while perDay[day] != nil { s.streak += 1; day = cal.date(byAdding: .day, value: -1, to: day)! }

        if let deck = decks.decks.first(where: { $0.id.uuidString == startDeck }) ?? decks.decks.first {
            s.deckName = deck.name.replacingOccurrences(of: "_", with: " ")
            // Words already met come first, so the widget rehearses rather than spoils new cards.
            let seen = progress.states(deck).sorted { $0.value.lastReview > $1.value.lastReview }.map(\.key)
            let pick = seen.isEmpty ? Array(deck.cards.indices.prefix(30)) : Array(seen.prefix(30))
            s.words = pick.map { CardParts(deck.cards[$0]) }.map {
                .init(front: $0.front.components(separatedBy: "\n").first ?? $0.front, back: $0.answer)
            }
        }
        s.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
