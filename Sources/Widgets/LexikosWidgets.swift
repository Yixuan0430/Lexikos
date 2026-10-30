import SwiftUI
import WidgetKit

@main
struct LexikosWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        WordWidget()
        StreakWidget()
    }
}

// MARK: Timeline

struct Entry: TimelineEntry {
    var date: Date
    var s: WidgetSnapshot
    /// Which word the word widget shows; advances every half hour.
    var turn = 0
}

private let sample = WidgetSnapshot(deckName: "French 5000", due: 23, new: 10, done: 14, week: [12, 30, 0, 18, 25, 40, 14], streak: 4,
                                    words: [.init(front: "la mémoire", back: "memory"), .init(front: "apprendre", back: "to learn"),
                                            .init(front: "le souvenir", back: "remembrance"), .init(front: "réviser", back: "to review")])

struct Provider: TimelineProvider {
    func placeholder(in _: Context) -> Entry { Entry(date: .now, s: sample) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, s: context.isPreview ? sample : WidgetSnapshot.load() ?? sample))
    }
    func getTimeline(in _: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let s = WidgetSnapshot.load() ?? WidgetSnapshot()
        let start = Date.now, base = Int(start.timeIntervalSince1970 / 1800)
        // Half-hourly entries for a day; each re-derives the counts so midnight rolls over on its own.
        let entries = (0..<48).map { i in
            let d = start.addingTimeInterval(Double(i) * 1800)
            return Entry(date: d, s: s.at(d), turn: base + i)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: Strings & style

private struct T {
    let lang: String
    subscript(_ k: String) -> String { Self.table[k]?[lang] ?? Self.table[k]?["en"] ?? k }
    private static let table: [String: [String: String]] = [
        "review": ["zh": "待复习", "en": "Review", "fr": "À revoir"],
        "new": ["zh": "新词", "en": "New", "fr": "Nouveaux"],
        "done": ["zh": "今日已学", "en": "Today", "fr": "Aujourd’hui"],
        "clear": ["zh": "今天完成了", "en": "All done today", "fr": "Terminé pour aujourd’hui"],
        "start": ["zh": "开始学习", "en": "Study", "fr": "Étudier"],
        "left": ["zh": "剩余", "en": "left", "fr": "restants"],
        "streak": ["zh": "连续学习", "en": "Streak", "fr": "Série"],
        "days": ["zh": "天", "en": "days", "fr": "jours"],
        "week": ["zh": "最近 7 天", "en": "Last 7 days", "fr": "7 derniers jours"],
        "word": ["zh": "每日一词", "en": "Word", "fr": "Le mot"],
        "words": ["zh": "最近学过的词", "en": "Recent words", "fr": "Mots récents"],
        "empty": ["zh": "先在 Lexikos 里导入词库", "en": "Import a deck in Lexikos", "fr": "Importez un paquet dans Lexikos"],
        "today.name": ["zh": "今日学习", "en": "Today", "fr": "Aujourd’hui"],
        "today.desc": ["zh": "今天要复习和学习的数量。", "en": "What is due and new today.", "fr": "Révisions et nouveautés du jour."],
        "word.desc": ["zh": "轮流显示你学过的单词。", "en": "Cycles through words you have learned.", "fr": "Fait défiler les mots appris."],
        "streak.desc": ["zh": "连续学习天数和最近一周。", "en": "Your streak and the past week.", "fr": "Votre série et la semaine passée."],
    ]
}

private var deviceLang: String {
    let l = String(Locale.preferredLanguages.first?.prefix(2) ?? "en")
    return ["zh", "en", "fr"].contains(l) ? l : "en"
}

extension WidgetSnapshot {
    fileprivate var t: T { T(lang: lang) }
    fileprivate var tint: Color { (Accent(rawValue: accent) ?? .sage).color }
    fileprivate var soft: Color { (Accent(rawValue: accent) ?? .sage).soft }
    fileprivate var left: Int { due + new }
    /// Share of today's work already done, for the rings.
    fileprivate var progress: Double { done + left == 0 ? 1 : Double(done) / Double(done + left) }
}

private let serif = Font.system(.title, design: .serif)

private struct Ring: View {
    let value: Double, tint: Color, width: CGFloat
    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: width)
            Circle().trim(from: 0, to: value).stroke(tint, style: StrokeStyle(lineWidth: width, lineCap: .round)).rotationEffect(.degrees(-90))
        }
    }
}

private struct Stat: View {
    let value: Int, label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)").font(.system(size: 24, weight: .medium, design: .serif)).monospacedDigit().foregroundStyle(Color.ink)
            Text(label).font(.system(size: 11)).foregroundStyle(Color.muted).lineLimit(1)
        }
    }
}

private struct WeekBars: View {
    let s: WidgetSnapshot
    var body: some View {
        let top = max(1, s.week.max() ?? 1), cal = Calendar.current
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(s.week.enumerated()), id: \.offset) { i, n in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(n == 0 ? s.tint.opacity(0.15) : s.tint.opacity(i == 6 ? 1 : 0.55))
                        .frame(height: max(4, CGFloat(n) / CGFloat(top) * 56))
                    Text(cal.date(byAdding: .day, value: i - 6, to: s.written)!.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 9)).foregroundStyle(Color.muted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 72, alignment: .bottom)
    }
}

private struct Panel: ViewModifier {
    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) { Color.panel }
    }
}

// MARK: Today

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "today", provider: Provider()) { TodayView(e: $0) }
            .configurationDisplayName(T(lang: deviceLang)["today.name"])
            .description(T(lang: deviceLang)["today.desc"])
            .supportedFamilies(Self.families)
    }
    static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        #else
        [.systemSmall, .systemMedium, .systemLarge]
        #endif
    }
}

struct TodayView: View {
    let e: Entry
    @Environment(\.widgetFamily) private var family
    private var s: WidgetSnapshot { e.s }

    var body: some View {
        content.widgetURL(URL(string: "lexikos://study"))
    }

    @ViewBuilder private var content: some View {
        switch family {
        #if os(iOS)
        case .accessoryCircular:
            Gauge(value: s.progress) { Text("Lx") } currentValueLabel: { Text("\(s.left)") }
                .gaugeStyle(.accessoryCircular).containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("Lexikos").font(.headline).widgetAccentable()
                Text("\(s.t["review"]) \(s.due) · \(s.t["new"]) \(s.new)")
                Text(s.left == 0 ? s.t["clear"] : "\(s.t["done"]) \(s.done)").foregroundStyle(.secondary)
            }
            .containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            Text(s.left == 0 ? "Lexikos · \(s.t["clear"])" : "Lexikos · \(s.t["review"]) \(s.due) · \(s.t["new"]) \(s.new)")
                .containerBackground(for: .widget) { Color.clear }
        #endif
        case .systemMedium: medium.modifier(Panel())
        case .systemLarge: large.modifier(Panel())
        default: small.modifier(Panel())
        }
    }

    private var header: some View {
        HStack {
            Text("Lexikos").font(.custom("Didot", size: 15)).foregroundStyle(s.tint)
            Spacer()
            Text(s.written.formatted(.dateTime.weekday(.abbreviated).day())).font(.system(size: 11)).foregroundStyle(Color.muted)
        }
    }

    private var bigRing: some View {
        ZStack {
            Ring(value: s.progress, tint: s.tint, width: 9)
            VStack(spacing: 0) {
                if s.left == 0 {
                    Image(systemName: "checkmark").font(.system(size: 26, weight: .medium)).foregroundStyle(s.tint)
                } else {
                    Text("\(s.left)").font(.system(size: 30, weight: .medium, design: .serif)).monospacedDigit().foregroundStyle(Color.ink)
                    Text(s.t["left"]).font(.system(size: 10)).foregroundStyle(Color.muted)
                }
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lexikos").font(.custom("Didot", size: 14)).foregroundStyle(s.tint)
            bigRing.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 6)
            Text("\(s.t["review"]) \(s.due) · \(s.t["new"]) \(s.new)").font(.system(size: 11)).foregroundStyle(Color.muted)
                .frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private var medium: some View {
        HStack(spacing: 18) {
            bigRing.frame(width: 104)
            VStack(alignment: .leading, spacing: 10) {
                Text(s.deckName.isEmpty ? "Lexikos" : s.deckName).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.ink).lineLimit(1)
                HStack(spacing: 16) {
                    Stat(value: s.due, label: s.t["review"])
                    Stat(value: s.new, label: s.t["new"])
                    Stat(value: s.done, label: s.t["done"])
                }
                startPill
            }
        }
    }

    private var startPill: some View {
        Label(s.left == 0 ? s.t["clear"] : s.t["start"], systemImage: s.left == 0 ? "checkmark" : "play.fill")
            .font(.system(size: 12, weight: .semibold)).foregroundStyle(s.left == 0 ? s.tint : Color.bg)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(s.left == 0 ? s.soft : s.tint))
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HStack(spacing: 18) {
                bigRing.frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 16) {
                        Stat(value: s.due, label: s.t["review"])
                        Stat(value: s.new, label: s.t["new"])
                        Stat(value: s.done, label: s.t["done"])
                    }
                    startPill
                }
            }
            Divider().overlay(Color.line)
            HStack {
                Text(s.t["week"]).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.muted)
                Spacer()
                Label("\(s.streak) \(s.t["days"])", systemImage: "flame").font(.system(size: 11, weight: .medium)).foregroundStyle(s.tint)
            }
            WeekBars(s: s)
            if let w = s.words.first {
                HStack(alignment: .firstTextBaseline) {
                    Text(w.front).font(.system(size: 15, weight: .medium, design: .serif)).foregroundStyle(Color.ink)
                    Text(w.back).font(.system(size: 12)).foregroundStyle(Color.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: Word

struct WordWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "word", provider: Provider()) { WordView(e: $0) }
            .configurationDisplayName(T(lang: deviceLang)["word"])
            .description(T(lang: deviceLang)["word.desc"])
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct WordView: View {
    let e: Entry
    @Environment(\.widgetFamily) private var family
    private var s: WidgetSnapshot { e.s }

    var body: some View {
        Group {
            if s.words.isEmpty {
                Text(s.t["empty"]).font(.system(size: 13)).foregroundStyle(Color.muted).multilineTextAlignment(.center)
            } else if family == .systemLarge {
                list
            } else {
                single
            }
        }
        .modifier(Panel())
        .widgetURL(URL(string: "lexikos://study"))
    }

    private func word(_ offset: Int) -> WidgetSnapshot.Word { s.words[(e.turn + offset) % s.words.count] }

    private var single: some View {
        let w = word(0), small = family == .systemSmall
        return VStack(alignment: .leading, spacing: small ? 6 : 8) {
            Text(s.t["word"].uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(s.tint)
            Spacer(minLength: 0)
            Text(w.front).font(.system(size: small ? 22 : 30, weight: .medium, design: .serif)).foregroundStyle(Color.ink)
                .lineLimit(2).minimumScaleFactor(0.6)
            Text(w.back).font(.system(size: small ? 12 : 14)).foregroundStyle(Color.muted).lineLimit(small ? 3 : 2)
            Spacer(minLength: 0)
            if !small, !s.deckName.isEmpty {
                Text(s.deckName).font(.system(size: 10)).foregroundStyle(Color.muted.opacity(0.7)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(s.t["words"].uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(s.tint)
                Spacer()
                Text(s.deckName).font(.system(size: 10)).foregroundStyle(Color.muted).lineLimit(1)
            }
            .padding(.bottom, 8)
            ForEach(0..<min(6, s.words.count), id: \.self) { i in
                let w = word(i)
                VStack(alignment: .leading, spacing: 2) {
                    Text(w.front).font(.system(size: 16, weight: .medium, design: .serif)).foregroundStyle(Color.ink).lineLimit(1)
                    Text(w.back).font(.system(size: 12)).foregroundStyle(Color.muted).lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                if i < min(6, s.words.count) - 1 { Divider().overlay(Color.line) }
            }
        }
    }
}

// MARK: Streak

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "streak", provider: Provider()) { StreakView(e: $0) }
            .configurationDisplayName(T(lang: deviceLang)["streak"])
            .description(T(lang: deviceLang)["streak.desc"])
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct StreakView: View {
    let e: Entry
    @Environment(\.widgetFamily) private var family
    private var s: WidgetSnapshot { e.s }

    var body: some View {
        Group {
            if family == .systemMedium {
                HStack(spacing: 20) { count; WeekBars(s: s) }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    count
                    Spacer(minLength: 0)
                    dots
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .modifier(Panel())
        .widgetURL(URL(string: "lexikos://study"))
    }

    private var count: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(s.t["streak"], systemImage: "flame.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(s.tint)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(s.streak)").font(.system(size: 40, weight: .medium, design: .serif)).monospacedDigit().foregroundStyle(Color.ink)
                Text(s.t["days"]).font(.system(size: 13)).foregroundStyle(Color.muted)
            }
            Text("\(s.t["done"]) \(s.done)").font(.system(size: 11)).foregroundStyle(Color.muted)
        }
    }

    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(Array(s.week.enumerated()), id: \.offset) { i, n in
                Circle().fill(n > 0 ? s.tint : s.tint.opacity(0.15))
                    .overlay(Circle().strokeBorder(i == 6 ? s.tint : .clear, lineWidth: 1.5).padding(-2.5))
                    .frame(width: 12, height: 12)
            }
        }
    }
}
