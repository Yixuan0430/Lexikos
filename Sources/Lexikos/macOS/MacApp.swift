import SwiftUI

@main
struct LexikosApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
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
                .cloudSync(decks: store, progress: progress)
                .frame(minWidth: 480, minHeight: 520)
                .onAppear { (Appearance(rawValue: appearance) ?? .system).apply() }
                .onChange(of: appearance) { (Appearance(rawValue: appearance) ?? .system).apply() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 820, height: 600)

        Settings { SettingsView().environment(updater).padding(24).frame(width: 460) }
    }
}

/// CloudKit announces changes from other devices with silent pushes.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        NSApplication.shared.registerForRemoteNotifications()
    }
}
