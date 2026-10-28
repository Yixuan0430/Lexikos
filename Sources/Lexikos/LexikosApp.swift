import SwiftUI
import AVFoundation
import NaturalLanguage
import UniformTypeIdentifiers

enum Level: Int, CaseIterable, Identifiable {
    case units, tens, hundreds, thousands
    var id: Int { rawValue }
    var range: ClosedRange<Int> { [0...10, 11...99, 100...999, 1000...9999][rawValue] }
    var label: String { "\(range.lowerBound)–\(range.upperBound)" }
}

enum Route: Hashable { case numbers, overview(Deck), study(Deck), free(Deck) }

@main
struct LexikosApp: App {
    @State private var store = DeckStore()
    @State private var progress = ProgressStore()
    @State private var updater = Updater()
    @AppStorage("lang") private var lang = AppLanguage.zh
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue

    init() {
        if CommandLine.arguments.contains("--dump") {
            for n in 0...9999 { let e = FrenchNumbers.entry(n); print("\(n)\t\(e.word)\t/\(e.ipa)/") }
            exit(0)
        }
        if CommandLine.arguments.contains("--parse") {
            for d in DeckStore().decks { for c in d.cards {
                let p = CardParts(c)
                print("\(p.front) [\(p.tag ?? "")] → \(p.answer) | \(p.sections.map { "\($0.id)(\($0.items.count))" }.joined(separator: ", "))")
                for sec in p.sections { for it in sec.items { print("   \(sec.id): \(it.fr.map { "FR[\($0)] EN[\(it.gloss ?? "")]" } ?? "TXT[\(it.text)]")") } }
            } }
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            Snapshot.run(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--verify-signature"), i + 1 < CommandLine.arguments.count {
            print(MainActor.assumeIsolated { Updater.signedByUs(URL(fileURLWithPath: CommandLine.arguments[i + 1])) } ? "trusted" : "rejected")
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--preview"), i + 1 < CommandLine.arguments.count {
            let cards = (try? Importer.anki(URL(fileURLWithPath: CommandLine.arguments[i + 1]))) ?? []
            print(cards.count, "cards")
            for c in cards.prefix(Int(CommandLine.arguments.last!) ?? 4) {
                let p = CardParts(c)
                print("── \(p.front) [\(p.tag ?? "")] /\(p.hint)/ → \(p.answer)")
                for s in p.sections { for it in s.items { print("     \(s.id): \(it.fr ?? it.text)  ⟶ \(it.gloss ?? "")") } }
            }
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--reimport"), i + 2 < CommandLine.arguments.count {
            do {
                try DeckStore().reimport(UUID(uuidString: CommandLine.arguments[i + 1])!, from: URL(fileURLWithPath: CommandLine.arguments[i + 2]))
                print("reimported")
            } catch { print("failed: \(error)") }
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--import"), i + 1 < CommandLine.arguments.count {
            do { try DeckStore().importFile(URL(fileURLWithPath: CommandLine.arguments[i + 1])); print("imported") }
            catch { print("failed: \(error)") }
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup("Lexikos") {
            RootView()
                .environment(\.locale, Locale(identifier: lang.rawValue))
                .environment(store)
                .environment(progress)
                .environment(updater)
                .task { await updater.checkIfDue() }
                .frame(minWidth: 480, minHeight: 520)
                .onAppear { (Appearance(rawValue: appearance) ?? .system).apply() }
                .onChange(of: appearance) { (Appearance(rawValue: appearance) ?? .system).apply() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 820, height: 600)

        Settings { SettingsView().environment(updater).padding(24).frame(width: 460) }
    }
}

struct RootView: View {
    @State private var route: Route?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.bg.ignoresSafeArea()
                content
            }
            .environment(\.windowSize, geo.size)
        }
        .animation(.easeOut(duration: 0.2), value: route)
    }

    @ViewBuilder private var content: some View {
            switch route {
            case nil: HomeView(route: $route)
            case .numbers: PracticeView(source: .numbers, route: $route)
            case .overview(let d): OverviewView(deck: d, route: $route)
            case .study(let d): PracticeView(source: .study(d), route: $route).id("study-\(d.id)")
            case .free(let d): PracticeView(source: .free(d), route: $route).id("free-\(d.id)")
            }
    }
}

// MARK: - Home

struct HomeView: View {
    @Binding var route: Route?
    @Environment(DeckStore.self) private var store
    @Environment(ProgressStore.self) private var progress
    @Environment(Updater.self) private var updater
    @AppStorage("newPerDay") private var newPerDay = 20
    @AppStorage("startDeck") private var startDeck = ""
    @Environment(\.windowSize) private var size
    @AppStorage("lang") private var lang = AppLanguage.zh
    @AppStorage("accent") private var accent = Accent.sage
    @State private var importing = false
    @State private var reimportTarget: UUID?
    @State private var showSettings = false
    @State private var error: String?

    private var l: L { L(lang: lang) }
    private let cols = [GridItem(.adaptive(minimum: 220), spacing: 16)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Lexikos").font(.custom("Didot", size: 30)).foregroundStyle(Color.ink)
                Text(l["home.subtitle"]).font(.system(size: 13)).foregroundStyle(Color.muted)
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape").font(.system(size: 15))
                }
                .buttonStyle(.plain).foregroundStyle(Color.muted).help(l["settings"])
            }
            .padding(.bottom, 28)

            PageScroll {
                VStack(alignment: .leading, spacing: 24) {
                    UpdateBanner(l: l, accent: accent)
                    todaySummary
                    section(l["builtin"]) {
                        DeckTile(title: l["numbers.name"], detail: l["numbers.desc"], glyph: "123", accent: accent) {
                            route = .numbers
                        }
                    }
                    section(l["imported"]) {
                        ForEach(store.decks) { deck in
                            let p = progress.plan(deck, newPerDay: newPerDay)
                            DeckTile(title: deck.name.replacingOccurrences(of: "_", with: " "),
                                     detail: p.due.isEmpty && p.new.isEmpty ? "\(deck.cards.count) \(l["cards"]) · \(l["today.clear"])"
                                         : "\(l["review"]) \(p.due.count) · \(l["new"]) \(p.new.count)",
                                     glyph: deck.glyph, accent: accent) {
                                route = .overview(deck)
                            }
                            .contextMenu {
                                Button(l["reimport"]) { reimportTarget = deck.id; importing = true }
                                Button(l["delete"], role: .destructive) { progress.forget(deck); store.delete(deck) }
                            }
                        }
                        ImportTile(title: l["import"], detail: l["import.desc"], accent: accent) { importing = true }
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: 1200)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, size.gutter).padding(.top, 40)
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "apkg") ?? .data,
                                                                     .commaSeparatedText, .tabSeparatedText, .plainText]) { result in
            guard case .success(let url) = result else { return }
            let target = reimportTarget
            reimportTarget = nil
            do {
                if let target {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    try store.reimport(target, from: url)
                } else { try store.importFile(url) }
            } catch let e as ImportError {
                error = l[["anki21b": "err.anki21b", "empty": "err.empty"]["\(e)"] ?? "err.unreadable"]
            } catch { self.error = l["err.unreadable"] }
        }
        .alert(l["import.failed"], isPresented: .constant(error != nil)) {
            Button(l["ok"]) { error = nil }
        } message: { Text(error ?? "") }
        .sheet(isPresented: $showSettings) {
            SettingsView().environment(updater).padding(28).frame(width: 460)
                .overlay(alignment: .topTrailing) {
                    Button { showSettings = false } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundStyle(Color.muted).padding(16)
                        .keyboardShortcut(.cancelAction)
                }
        }
    }

    private var todaySummary: some View {
        let plans = store.decks.map { progress.plan($0, newPerDay: newPerDay) }
        let due = plans.map(\.due.count).reduce(0, +), new = plans.map(\.new.count).reduce(0, +)
        let done = plans.map(\.learnedToday).reduce(0, +)
        let heading = VStack(alignment: .leading, spacing: 4) {
            Text(Date.now.formatted(.dateTime.month(.wide).day().weekday(.wide)).uppercased())
                .font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(Color.muted)
            Text(due + new == 0 ? l["today.clear"] : l["today.plan"])
                .font(.system(size: 22, weight: .medium, design: .serif)).foregroundStyle(Color.ink)
        }
        let numbers = HStack(spacing: 24) {
            ForEach([(l["review"], due), (l["new"], new), (l["stat.today"], done)], id: \.0) { k, v in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(v)").font(.system(size: 26, weight: .medium, design: .serif)).foregroundStyle(Color.ink).monospacedDigit()
                    Text(k).font(.system(size: 11)).foregroundStyle(Color.muted)
                }
            }
        }
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 28) {
                heading
                Spacer(minLength: 12)
                numbers
                startPanel.frame(width: 280)
            }
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) { heading; Spacer(minLength: 12); numbers }
                startPanel
            }
            VStack(alignment: .leading, spacing: 16) { heading; numbers; startPanel }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16).fill(accent.soft))
    }

    /// Deck chooser + start button. The chooser is a menu dressed as a deck row, not a system pop-up.
    @ViewBuilder private var startPanel: some View {
        if let chosen = store.decks.first(where: { $0.id.uuidString == startDeck }) ?? store.decks.first {
            let p = progress.plan(chosen, newPerDay: newPerDay)
            VStack(spacing: 10) {
                Menu {
                    ForEach(store.decks) { d in
                        Button { startDeck = d.id.uuidString } label: {
                            if d.id == chosen.id { Label(d.name.replacingOccurrences(of: "_", with: " "), systemImage: "checkmark") }
                            else { Text(d.name.replacingOccurrences(of: "_", with: " ")) }
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text(chosen.glyph)
                            .font(.custom("Didot", size: 16)).foregroundStyle(accent.color)
                            .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 7).fill(accent.soft))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(chosen.name.replacingOccurrences(of: "_", with: " "))
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.ink).lineLimit(1).truncationMode(.middle)
                            Text("\(l["review"]) \(p.due.count) · \(l["new"]) \(p.new.count)")
                                .font(.system(size: 11)).foregroundStyle(Color.muted)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.muted)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.panel))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.line))
                    .contentShape(Rectangle())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).focusable(false)
                .help(l["start.from"])

                Button { route = .study(chosen) } label: {
                    Label(l["start.go"], systemImage: "play.fill").font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10).fill(accent.color)).foregroundStyle(Color.bg)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).focusable(false)
            }
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(Color.muted)
            LazyVGrid(columns: cols, alignment: .leading, spacing: 16) { content() }
        }
    }
}

struct DeckTile: View {
    let title: String, detail: String, glyph: String, accent: Accent
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(glyph).font(.custom("Didot", size: 22)).foregroundStyle(accent.color)
                    .frame(width: 48, height: 48).background(RoundedRectangle(cornerRadius: 10).fill(accent.soft))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.ink).lineLimit(1)
                    Text(detail).font(.system(size: 12)).foregroundStyle(Color.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.panel))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(hover ? accent.color.opacity(0.5) : Color.line))
            .shadow(color: .black.opacity(hover ? 0.08 : 0.03), radius: hover ? 12 : 4, y: hover ? 6 : 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}

struct ImportTile: View {
    let title: String, detail: String, accent: Accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "plus").font(.system(size: 18, weight: .light)).foregroundStyle(Color.muted)
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.ink)
                    Text(detail).font(.system(size: 12)).foregroundStyle(Color.muted).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @AppStorage("lang") private var lang = AppLanguage.zh
    @AppStorage("appearance") private var appearance = Appearance.system
    @AppStorage("accent") private var accent = Accent.sage
    @AppStorage("newPerDay") private var newPerDay = 20
    @AppStorage("autoSpeak") private var autoSpeak = true
    private static let presets = [5, 10, 20, 30, 50]
    private var l: L { L(lang: lang) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(l["settings"]).font(.custom("Didot", size: 24)).foregroundStyle(Color.ink)
            row(l["language"]) {
                Picker("", selection: $lang) { ForEach(AppLanguage.allCases) { Text($0.label).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden()
            }
            row(l["appearance"]) {
                Picker("", selection: $appearance) { ForEach(Appearance.allCases) { Text(l[$0.rawValue]).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden()
            }
            row(l["autoSpeak"]) {
                Picker("", selection: $autoSpeak) { Text(l["on"]).tag(true); Text(l["off"]).tag(false) }
                    .pickerStyle(.segmented).labelsHidden()
            }
            row(l["newPerDay"]) {
                HStack(spacing: 12) {
                    Picker("", selection: Binding(get: { Self.presets.contains(newPerDay) ? newPerDay : -1 },
                                                  set: { if $0 > 0 { newPerDay = $0 } })) {
                        ForEach(Self.presets, id: \.self) { Text("\($0)").tag($0) }
                        Text(l["custom"]).tag(-1)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    HStack(spacing: 4) {
                        TextField("", value: Binding(get: { newPerDay }, set: { newPerDay = min(500, max(1, $0)) }), format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 52).multilineTextAlignment(.trailing)
                        Stepper("", value: $newPerDay, in: 1...500).labelsHidden()
                    }
                }
            }
            row(l["update"]) { UpdateSettings(l: l) }
            row(l["accent"]) {
                HStack(spacing: 12) {
                    ForEach(Accent.allCases) { a in
                        Button { accent = a } label: {
                            Circle().fill(a.color).frame(width: 24, height: 24)
                                .overlay(Circle().strokeBorder(Color.bg, lineWidth: 2).padding(-1))
                                .overlay(Circle().strokeBorder(a == accent ? a.color : .clear, lineWidth: 2).padding(-4))
                        }
                        .buttonStyle(.plain).help(l["accent.\(a.rawValue)"])
                    }
                }
                .padding(.leading, 4)
            }
        }
    }

    private func row<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.muted)
            c()
        }
    }
}

