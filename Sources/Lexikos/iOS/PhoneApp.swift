import SwiftUI

@main
struct LexikosApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
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
                .cloudSync(decks: store, progress: progress)
                .widgetFeed(decks: store, progress: progress)
        }
    }
}

/// CloudKit announces changes from other devices with silent pushes.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }
}
