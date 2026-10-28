import SwiftUI
import AVFoundation
import NaturalLanguage

struct PracticeView: View {
    enum Source { case numbers, free(Deck), study(Deck) }
    let source: Source
    @Binding var route: Route?

    @AppStorage("lang") private var lang = AppLanguage.zh
    @AppStorage("accent") private var accent = Accent.sage
    @AppStorage("level") private var level = Level.units
    @AppStorage("showDetails") private var showDetails = false
    @State private var card = Card(front: "", back: "")
    @State private var parts = CardParts(Card(front: "", back: ""))
    @State private var section = ""
    @State private var revealed = false
    @State private var seen = 0
    @State private var order: [Int] = []
    @FocusState private var focused: Bool
    @State private var speaker = Speaker()
    @AppStorage("autoSpeak") private var autoSpeak = true
    @State private var learning = false // first sight of a new word: shown with its answer, counted as not yet known
    @State private var newLearned = 0
    @Environment(\.windowSize) private var size
    private var k: CGFloat { size.cardScale }
    @Environment(ProgressStore.self) private var progress
    @AppStorage("newPerDay") private var newPerDay = 20
    // Study session: remaining queue, current card index, cards already scheduled this session.
    @State private var queue: [Int] = []
    @State private var current: Int?
    @State private var scheduled: Set<Int> = []
    @State private var tally: [Grade: Int] = [:]
    @State private var finished = false

    private var l: L { L(lang: lang) }
    private var isNumbers: Bool { if case .numbers = source { true } else { false } }
    private var isStudy: Bool { if case .study = source { true } else { false } }
    private var deck: Deck? {
        switch source { case .numbers: nil; case .free(let d), .study(let d): d }
    }
    private var detailsOpen: Bool { revealed && showDetails && !parts.sections.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 16)
            if finished { doneView } else { cardView }
            Spacer(minLength: 16)
            if isStudy && revealed && !finished { Group { if learning { learnBar } else { gradeBar } }.padding(.bottom, 14) }
            footer
        }
        .padding(.horizontal, size.gutter).padding(.top, 40).padding(.bottom, 24)
        .focusable().focused($focused).focusEffectDisabled()
        .onAppear {
            focused = true
            if case .study(let d) = source {
                let plan = progress.plan(d, newPerDay: newPerDay)
                queue = plan.due + plan.new
            }
            next()
        }
        .onKeyPress("1") { grade(.forgot); return .handled }
        .onKeyPress("2") { grade(.vague); return .handled }
        .onKeyPress("3") { grade(.remembered); return .handled }
        .onKeyPress("a") { speak(slow: true); return .handled }
        .onKeyPress(.space) { advance(); return .handled }
        .onKeyPress(.return) { advance(); return .handled }
        .onKeyPress(.rightArrow) { next(); return .handled }
        .onKeyPress(.escape) { goBack(); return .handled }
        .onKeyPress("s") { speak(); return .handled }
        .onKeyPress("d") { toggleDetails(); return .handled }
    }

    private var header: some View {
        HStack {
            Button(action: goBack) {
                Label(l["back"], systemImage: "chevron.left").font(.system(size: 13))
            }
            .buttonStyle(.plain).focusable(false).foregroundStyle(Color.muted)
            Spacer()
            if isNumbers {
                Picker("", selection: $level) { ForEach(Level.allCases) { Text($0.label).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .onChange(of: level) { next() }
            } else if let d = deck {
                Text(d.name.replacingOccurrences(of: "_", with: " "))
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.muted).lineLimit(1)
                if isStudy && !finished {
                    Text("· \(l["remaining"]) \(queue.count + (current == nil ? 0 : 1))")
                        .font(.system(size: 13)).foregroundStyle(Color.muted).monospacedDigit()
                }
            }
        }
    }

    // MARK: Card

    private var cardView: some View {
        VStack(spacing: detailsOpen ? 14 : 22) {
            VStack(spacing: 10) {
                Text(parts.front)
                    .font(frontFont)
                    .monospacedDigit()
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                if let tag = parts.tag {
                    Text(tag).font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(accent.soft)).foregroundStyle(accent.color)
                }
            }

            VStack(spacing: 10) {
                Text(parts.answer)
                    .font(.system(size: (isNumbers ? 34 : 28) * k, design: .serif))
                    .foregroundStyle(Color.ink.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 640 * k)
                if let note = parts.answerNote {
                    Text(note).font(.system(size: 15)).foregroundStyle(Color.muted)
                        .multilineTextAlignment(.center).frame(maxWidth: 560)
                }
                if !parts.hint.isEmpty {
                    Text(parts.hint)
                        .font(.system(size: 19 * k, design: .serif))
                        .foregroundStyle(Color.muted)
                        .textSelection(.enabled)
                }
                HStack(spacing: 10) {
                    pill(l["listen"], "speaker.wave.2") { speak() }
                    pill(l["slow"], "tortoise") { speak(slow: true) }
                    if !parts.sections.isEmpty {
                        pill(showDetails ? l["details.hide"] : l["details.show"],
                             showDetails ? "chevron.up" : "text.alignleft") { toggleDetails() }
                    }
                }
                .padding(.top, 4)
                if detailsOpen { details.transition(.opacity.combined(with: .move(edge: .bottom))) }
            }
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 6)
            .frame(minHeight: 150, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { advance() }
    }

    private var frontFont: Font {
        if isNumbers { return .custom("Didot", size: (parts.front.count > 3 ? 128 : 148) * k) }
        let n = parts.front.count, pt: CGFloat = detailsOpen ? (n < 16 ? 44 : 32) : (n < 16 ? 64 : n < 32 ? 46 : 32)
        return .system(size: pt * k, weight: .medium, design: .serif)
    }

    private func pill(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(accent.soft))
                .foregroundStyle(accent.color)
        }
        .buttonStyle(.plain).focusable(false)
    }

    // MARK: Notes panel

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(parts.sections) { s in
                        let on = s.id == (currentSection?.id ?? "")
                        Button { section = s.id } label: {
                            Text(s.category == .other ? s.title : l["cat.\(s.category.rawValue)"])
                                .font(.system(size: 12, weight: on ? .semibold : .regular))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(on ? accent.soft : .clear))
                                .foregroundStyle(on ? accent.color : Color.muted)
                        }
                        .buttonStyle(.plain).focusable(false)
                    }
                }
                .padding(10)
            }
            .scrollIndicators(.never)
            Rectangle().fill(Color.line).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array((currentSection?.items ?? []).enumerated()), id: \.offset) { _, item in noteLine(item) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .frame(maxHeight: max(140, size.height * 0.36))
        }
        .frame(maxWidth: 640 * k)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.panel))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.line))
        .padding(.top, 6)
        .onTapGesture {} // keep clicks inside the panel from advancing the card
    }

    private var currentSection: CardParts.Section? {
        parts.sections.first { $0.id == section } ?? parts.sections.first
    }

    /// French phrase (speakable, French only) with its translation underneath, or a plain note.
    private func noteLine(_ item: CardParts.Item) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let fr = item.fr {
                Button { speaker.say(fr, language: "fr-FR") } label: { Image(systemName: "speaker.wave.1").font(.system(size: 11)) }
                    .buttonStyle(.plain).focusable(false).foregroundStyle(Color.muted.opacity(0.7))
                    .simultaneousGesture(TapGesture().modifiers(.option).onEnded { speaker.say(fr, language: "fr-FR", slow: true) })
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.fr ?? item.text).font(.system(size: item.fr == nil ? 14 : 15))
                    .foregroundStyle(item.fr == nil ? Color.ink.opacity(0.85) : Color.ink)
                    .lineSpacing(3)
                if let g = item.gloss { Text(g).font(.system(size: 13)).foregroundStyle(Color.muted) }
            }
            .textSelection(.enabled)
        }
    }

    // MARK: Footer & actions

    private var footer: some View {
        HStack {
            Text(learning ? l["tap.learn"] : revealed ? (isStudy ? l["tap.grade"] : l["tap.next"]) : l["tap.reveal"])
            Spacer()
            if !size.compact {
                Text(isNumbers ? l["keys"] : isStudy ? l["keys.study"] : l["keys.deck"]).lineLimit(1)
                Spacer()
            }
            Text("\(seen) \(l["seen"])").monospacedDigit()
        }
        .font(.system(size: 11)).foregroundStyle(Color.muted)
        .padding(.top, 14)
        .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: 1) }
    }

    private func toggleDetails() {
        guard revealed, !parts.sections.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.22)) { showDetails.toggle() }
    }

    private func advance() {
        if finished { return }
        if learning { return continueLearning() }
        if !revealed { reveal() } else if !isStudy { next() }
    }

    private func goBack() {
        if let d = deck { route = .overview(d) } else { route = nil }
    }

    private func grade(_ g: Grade) {
        guard isStudy, revealed, !learning, let d = deck, let i = current else { return }
        // Only the first answer of a session moves the schedule; repeats are in-session drilling.
        if !scheduled.contains(i) {
            progress.grade(d, card: i, g)
            scheduled.insert(i)
            tally[g, default: 0] += 1
        }
        if g == .forgot { queue.insert(i, at: min(4, queue.count)) }
        next()
    }

    /// New word seen once: record it as not yet known and bring it back later this session as a real test.
    private func continueLearning() {
        guard let d = deck, let i = current else { return }
        progress.grade(d, card: i, .forgot)
        newLearned += 1
        queue.insert(i, at: min(5, queue.count))
        next()
    }

    private var learnBar: some View {
        HStack(spacing: 14) {
            Label(l["learn.badge"], systemImage: "sparkles").font(.system(size: 13, weight: .medium)).foregroundStyle(accent.color)
            Spacer()
            Button(action: continueLearning) {
                Text(l["learn.continue"]).font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 22).padding(.vertical, 10)
                    .background(Capsule().fill(accent.color)).foregroundStyle(Color.bg)
            }
            .buttonStyle(.plain).focusable(false)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(maxWidth: 560)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.line))
    }

    // MARK: Grading

    private var gradeBar: some View {
        HStack(spacing: 12) {
            ForEach(Grade.allCases, id: \.self) { g in
                Button { grade(g) } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Circle().fill(gradeColor(g)).frame(width: 8, height: 8)
                            Text(l["grade.\(g)"]).font(.system(size: 14, weight: .medium)).foregroundStyle(Color.ink)
                            Text("\(g.rawValue)").font(.system(size: 11)).foregroundStyle(Color.muted)
                        }
                        Text(preview(g)).font(.system(size: 11)).foregroundStyle(Color.muted)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.panel))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.line))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).focusable(false)
            }
        }
        .frame(maxWidth: 560)
    }

    /// When the card would come back after this grade, e.g. "4 天后".
    private func preview(_ g: Grade) -> String {
        guard let d = deck, let i = current else { return "" }
        if scheduled.contains(i) { return g == .forgot ? l["again.soon"] : "" }
        let s = CardState.next(progress.states(d)[i], g)
        return Self.interval(s.stability, l)
    }

    /// "3 天后" (later = true) or "3 天" (a duration).
    static func interval(_ days: Double, _ l: L, later: Bool = true) -> String {
        let p = later ? "unit" : "dur"
        return days < 1 ? "\(max(1, Int((days * 24).rounded()))) \(l["\(p).hours"])"
            : days < 60 ? "\(Int(days.rounded())) \(l["\(p).days"])"
            : "\(Int((days / 30).rounded())) \(l["\(p).months"])"
    }

    private var doneView: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle").font(.system(size: 44, weight: .light)).foregroundStyle(accent.color)
            Text(l["done.title"]).font(.system(size: 28, weight: .medium, design: .serif)).foregroundStyle(Color.ink)
            HStack(spacing: 22) {
                if newLearned > 0 {
                    Text("\(l["new"]) \(newLearned)").font(.system(size: 13)).foregroundStyle(Color.muted)
                }
                ForEach(Grade.allCases, id: \.self) { g in
                    HStack(spacing: 6) {
                        Circle().fill(gradeColor(g)).frame(width: 8, height: 8)
                        Text("\(l["grade.\(g)"]) \(tally[g] ?? 0)").font(.system(size: 13)).foregroundStyle(Color.muted)
                    }
                }
            }
            HStack(spacing: 10) {
                pill(l["back.overview"], "chart.xyaxis.line") { goBack() }
                if let d = deck { pill(l["free"], "shuffle") { route = .free(d) } }
            }
            .padding(.top, 6)
        }
    }

    private func reveal() {
        withAnimation(.easeOut(duration: 0.28)) { revealed = true }
        seen += 1
        if autoSpeak { speak() }
    }

    private func next() {
        let c: Card
        switch source {
        case .numbers:
            var n = Int.random(in: level.range)
            while "\(n)" == card.front { n = Int.random(in: level.range) }
            let e = FrenchNumbers.entry(n)
            c = Card(front: "\(n)", back: e.word, hint: "/\(e.ipa)/")
        case .free(let d):
            // Shuffled pass through the deck, reshuffled when exhausted.
            if order.isEmpty { order = Array(d.cards.indices).shuffled() }
            c = d.cards[order.removeLast()]
        case .study(let d):
            guard !queue.isEmpty else {
                learning = false
                withAnimation { finished = true; current = nil }
                return
            }
            let i = queue.removeFirst()
            current = i
            c = d.cards[i]
        }
        var isNew = false
        if case .study(let d) = source, let i = current { isNew = progress.states(d)[i] == nil }
        speaker.stop()
        withAnimation(.snappy(duration: 0.25)) {
            learning = isNew
            revealed = isNew
            card = c
            parts = CardParts(c)
            section = parts.sections.first?.id ?? ""
        }
        if isNew { seen += 1; if autoSpeak { speak() } }
    }

    private func speak(slow: Bool = false) {
        // Numbers: read the French word. Decks: read whichever side is French, else the front.
        if isNumbers { return speaker.say(card.back, language: "fr-FR", slow: slow) }
        let text = CardParts.lang(parts.front) != .english ? parts.front
            : CardParts.lang(parts.answer) == .french ? parts.answer : parts.front
        speaker.say(text, language: "fr-FR", slow: slow)
    }
}

func gradeColor(_ g: Grade) -> Color {
    switch g {
    case .forgot: Color.dyn(0xC25B52, 0xE08A82)
    case .vague: Color.dyn(0xB08A23, 0xD9B75A)
    case .remembered: Color.dyn(0x4F8A6E, 0x8CC4A4)
    }
}
