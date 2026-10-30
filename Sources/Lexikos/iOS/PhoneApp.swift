import SwiftUI

@main
struct LexikosApp: App {
    @State private var store = DeckStore()
    @State private var progress = ProgressStore()
    @AppStorage("lang") private var lang = AppLanguage.zh
    @AppStorage("appearance") private var appearance = Appearance.system

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.locale, Locale(identifier: lang.rawValue))
                .environment(store)
                .environment(progress)
                .preferredColorScheme(appearance.scheme)
        }
    }
}
