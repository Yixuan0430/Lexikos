import SwiftUI
import Charts

/// A deck's home: today's plan, memory stats, forgetting curves and per-word retention.
struct OverviewView: View {
    let deck: Deck
    @Binding var route: Route?
    @Environment(ProgressStore.self) private var progress
    @AppStorage("lang") private var lang = AppLanguage.zh
    @AppStorage("accent") private var accent = Accent.sage
    @AppStorage("newPerDay") private var newPerDay = 20
    @State private var selected: Int?
    @Environment(\.windowSize) private var size

    private var l: L { L(lang: lang) }
    private var states: [Int: CardState] { progress.states(deck) }
    private var plan: ProgressStore.Plan { progress.plan(deck, newPerDay: newPerDay) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { route = nil } label: { Label(l["back"], systemImage: "chevron.left").font(.system(size: 13)) }
                    .buttonStyle(.plain).focusable(false).foregroundStyle(Color.muted)
                Spacer()
            }
            .padding(.bottom, 18)

            PageScroll {
                VStack(alignment: .leading, spacing: 22) {
                    today
                    stats
                    let layout = size.compact ? AnyLayout(VStackLayout(spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                    layout {
                        panel(l["curve.title"], l["curve.sub"]) { curve }
                        panel(l["forecast.title"], l["forecast.sub"]) { forecast }
                    }
                    panel(l["words.title"], l["words.sub"]) { words }
                }
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: 1200)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, size.gutter).padding(.top, 40)
        .sheet(item: Binding(get: { selected.map { IdentifiedInt(id: $0) } }, set: { selected = $0?.id })) { item in
            WordCurveSheet(card: deck.cards[item.id], state: states[item.id]!, accent: accent, l: l)
        }
    }

    // MARK: Today

    private var today: some View {
        let p = plan
        let layout = size.compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 24))
        return layout {
            VStack(alignment: .leading, spacing: 6) {
                Text(deck.name.replacingOccurrences(of: "_", with: " "))
                    .font(.system(size: 26, weight: .medium, design: .serif)).foregroundStyle(Color.ink).lineLimit(2)
                Text(p.due.isEmpty && p.new.isEmpty ? l["today.clear"]
                     : "\(l["today.plan"]) · \(l["review"]) \(p.due.count) · \(l["new"]) \(p.new.count)")
                    .font(.system(size: 13)).foregroundStyle(Color.muted)
            }
            if !size.compact { Spacer() }
            HStack(spacing: 10) {
            Button { route = .free(deck) } label: {
                Label(l["free"], systemImage: "shuffle").font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Capsule().strokeBorder(Color.line)).foregroundStyle(Color.ink)
            }
            .buttonStyle(.plain).focusable(false)
            Button { route = .study(deck) } label: {
                Label(l["start"], systemImage: "play.fill").font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(Capsule().fill(accent.color)).foregroundStyle(Color.bg)
            }
            .buttonStyle(.plain).focusable(false)
            .disabled(p.due.isEmpty && p.new.isEmpty).opacity(p.due.isEmpty && p.new.isEmpty ? 0.4 : 1)
            }
        }
    }

    private var stats: some View {
        let s = states.values
        let items: [(String, Int, Color)] = [
            (l["stat.due"], plan.due.count, gradeColor(.forgot)),
            (l["stat.learning"], s.filter { !$0.mastered }.count, gradeColor(.vague)),
            (l["stat.mastered"], s.filter(\.mastered).count, gradeColor(.remembered)),
            (l["stat.unseen"], deck.cards.count - s.count, Color.muted),
            (l["stat.today"], plan.learnedToday, accent.color),
        ]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
            ForEach(items, id: \.0) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle().fill(item.2).frame(width: 7, height: 7)
                        Text(item.0).font(.system(size: 12)).foregroundStyle(Color.muted)
                    }
                    Text("\(item.1)").font(.system(size: 26, weight: .medium, design: .serif)).foregroundStyle(Color.ink)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.panel))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.line))
            }
        }
    }

    private func panel<C: View>(_ title: String, _ sub: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.ink)
            Text(sub).font(.system(size: 12)).foregroundStyle(Color.muted).padding(.bottom, 10)
            c()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.panel))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.line))
    }

    // MARK: Charts

    /// Ebbinghaus (1885) savings data: hours since learning → % retained.
    private static let ebbinghaus: [(Double, Double)] = [(0, 100), (0.33, 58.2), (1, 44.2), (8.8, 35.8),
                                                         (24, 33.7), (48, 27.8), (144, 25.4), (744, 21.1)]

    private struct CurvePoint: Identifiable { let id = UUID(); let day: Double; let value: Double; let series: String }

    private var curvePoints: [CurvePoint] {
        let now = Date.now, learned = Array(states.values)
        var pts = Self.ebbinghaus.map { CurvePoint(day: $0.0 / 24, value: $0.1, series: l["curve.ebbinghaus"]) }
        if !learned.isEmpty {
            for step in 0...60 {
                let d = Double(step) / 2, at = now.addingTimeInterval(d * 86400)
                let avg = learned.map { $0.retention(at: at) }.reduce(0, +) / Double(learned.count)
                pts.append(CurvePoint(day: d, value: avg * 100, series: l["curve.yours"]))
            }
        }
        return pts
    }

    private var curve: some View {
        Chart(curvePoints) { p in
            LineMark(x: .value("day", p.day), y: .value("%", p.value))
                .foregroundStyle(by: .value("series", p.series))
                .lineStyle(StrokeStyle(lineWidth: 2, dash: p.series == l["curve.ebbinghaus"] ? [4, 4] : []))
                .interpolationMethod(.monotone)
        }
        .chartForegroundStyleScale([l["curve.ebbinghaus"]: Color.muted, l["curve.yours"]: accent.color])
        .chartXScale(domain: 0...30)
        .chartYScale(domain: 0...100)
        .chartXAxis { AxisMarks(values: [0, 7, 14, 21, 30]) { v in
            AxisGridLine().foregroundStyle(Color.line)
            AxisValueLabel { Text("\(v.as(Int.self) ?? 0)\(l["unit.d"])").foregroundStyle(Color.muted) }
        } }
        .chartYAxis { AxisMarks(values: [0, 50, 90, 100]) { v in
            AxisGridLine().foregroundStyle(Color.line)
            AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%").foregroundStyle(Color.muted) }
        } }
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 200)
    }

    private var forecast: some View {
        let cal = Calendar.current, start = cal.startOfDay(for: .now)
        let counts = (0..<14).map { d in
            states.values.filter {
                let day = cal.dateComponents([.day], from: start, to: cal.startOfDay(for: $0.due)).day ?? 0
                return d == 0 ? day <= 0 : day == d
            }.count
        }
        return Chart(Array(counts.enumerated()), id: \.offset) { d, n in
            BarMark(x: .value("day", d), y: .value("n", n), width: 12)
                .foregroundStyle(d == 0 ? accent.color : accent.color.opacity(0.45))
                .cornerRadius(3)
        }
        .chartXScale(domain: -0.6...13.6)
        .chartXAxis { AxisMarks(values: [0, 4, 8, 12]) { v in
            AxisValueLabel {
                let d = v.as(Int.self) ?? 0
                Text(d == 0 ? l["today"] : "+\(d)\(l["unit.d"])").foregroundStyle(Color.muted)
            }
        } }
        .chartYAxis { AxisMarks { v in
            AxisGridLine().foregroundStyle(Color.line)
            AxisValueLabel { Text("\(v.as(Int.self) ?? 0)").foregroundStyle(Color.muted) }
        } }
        .frame(height: 200)
    }

    // MARK: Words

    private var words: some View {
        let now = Date.now
        let rows = states.map { ($0.key, $0.value, $0.value.retention(at: now)) }.sorted { $0.2 < $1.2 }
        return VStack(spacing: 0) {
            if rows.isEmpty {
                Text(l["words.empty"]).font(.system(size: 13)).foregroundStyle(Color.muted).padding(.vertical, 8)
            }
            ForEach(rows, id: \.0) { i, st, r in
                Button { selected = i } label: {
                    HStack(spacing: 14) {
                        Text(CardParts.splitGloss(deck.cards[i].front).0.replacingOccurrences(of: "\n", with: " / "))
                            .font(.system(size: 14)).foregroundStyle(Color.ink).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.line)
                            Capsule().fill(r < 0.8 ? gradeColor(.forgot) : r < 0.9 ? gradeColor(.vague) : gradeColor(.remembered))
                                .frame(width: 120 * r)
                        }
                        .frame(width: 120, height: 6)
                        Text("\(Int(r * 100))%").font(.system(size: 12)).monospacedDigit().foregroundStyle(Color.muted)
                            .frame(width: 38, alignment: .trailing)
                        Text(st.due <= now ? l["due.now"] : PracticeView.interval(st.due.timeIntervalSince(now) / 86400, l))
                            .font(.system(size: 12)).foregroundStyle(Color.muted).frame(width: 70, alignment: .trailing)
                        Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Color.muted.opacity(0.6))
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).focusable(false)
                Rectangle().fill(Color.line).frame(height: 1)
            }
        }
    }
}

private struct IdentifiedInt: Identifiable { let id: Int }

/// One word's full memory history: the sawtooth of forgetting and each review that reset it.
struct WordCurveSheet: View {
    let card: Card, state: CardState, accent: Accent, l: L
    @Environment(\.dismiss) private var dismiss

    private struct Pt: Identifiable { let id = UUID(); let date: Date; let value: Double; let segment: Int }

    private var points: [Pt] {
        let reviews = state.reviews
        let end = max(Date.now, state.due).addingTimeInterval(7 * 86400)
        var out: [Pt] = []
        for (k, r) in reviews.enumerated() {
            let stop = k + 1 < reviews.count ? reviews[k + 1].date : end
            let span = stop.timeIntervalSince(r.date)
            for step in 0...40 {
                let t = r.date.addingTimeInterval(span * Double(step) / 40)
                out.append(Pt(date: t, value: CardState.retention(days: t.timeIntervalSince(r.date) / 86400, stability: r.stability) * 100, segment: k))
            }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(CardParts.splitGloss(card.front).0).font(.system(size: 26, weight: .medium, design: .serif)).foregroundStyle(Color.ink)
                Text(CardParts(card).answer).font(.system(size: 15)).foregroundStyle(Color.muted).lineLimit(1)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).focusable(false).foregroundStyle(Color.muted).keyboardShortcut(.cancelAction)
            }
            Text(l["word.sub"]).font(.system(size: 12)).foregroundStyle(Color.muted).padding(.bottom, 8)
            Chart {
                ForEach(points) { p in
                    AreaMark(x: .value("t", p.date), y: .value("%", p.value), series: .value("s", p.segment))
                        .foregroundStyle(accent.color.opacity(0.10))
                    LineMark(x: .value("t", p.date), y: .value("%", p.value), series: .value("s", p.segment))
                        .foregroundStyle(accent.color)
                }
                ForEach(state.reviews, id: \.date) { r in
                    PointMark(x: .value("t", r.date), y: .value("%", 100))
                        .foregroundStyle(gradeColor(r.grade)).symbolSize(60)
                }
                RuleMark(x: .value("now", Date.now)).foregroundStyle(Color.muted.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .bottom, alignment: .leading) { Text(l["now"]).font(.system(size: 10)).foregroundStyle(Color.muted) }
                RuleMark(y: .value("90", 90)).foregroundStyle(Color.line)
            }
            .chartYScale(domain: 0...105)
            .chartYAxis { AxisMarks(values: [0, 50, 90]) { v in
                AxisGridLine().foregroundStyle(Color.line)
                AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%").foregroundStyle(Color.muted) }
            } }
            .chartXAxis { AxisMarks { _ in AxisValueLabel(format: .dateTime.month().day()).foregroundStyle(Color.muted) } }
            .frame(height: 220)

            HStack(spacing: 18) {
                fact(l["word.retention"], "\(Int(state.retention(at: .now) * 100))%")
                fact(l["word.stability"], PracticeView.interval(state.stability, l, later: false))
                fact(l["word.reviews"], "\(state.reviews.count)")
                fact(l["word.lapses"], "\(state.lapses)")
                fact(l["word.next"], state.due.formatted(.dateTime.month().day().hour().minute()))
            }
            PageScroll {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(state.reviews.reversed(), id: \.date) { r in
                        HStack(spacing: 8) {
                            Circle().fill(gradeColor(r.grade)).frame(width: 7, height: 7)
                            Text(l["grade.\(r.grade)"]).font(.system(size: 12)).foregroundStyle(Color.ink).frame(width: 70, alignment: .leading)
                            Text(r.date.formatted(.dateTime.year().month().day().hour().minute()))
                                .font(.system(size: 12)).foregroundStyle(Color.muted)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 110)
        }
        .padding(24)
        .frame(width: 620)
        .background(Color.bg)
    }

    private func fact(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(k).font(.system(size: 11)).foregroundStyle(Color.muted)
            Text(v).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.ink).monospacedDigit()
        }
    }
}
