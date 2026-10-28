import SwiftUI

/// Dev aid: renders the home and overview pages at several window sizes into PNGs.
@MainActor enum Snapshot {
    static func run(to dir: URL) {
        let store = DeckStore(), progress = ProgressStore()
        for size in [CGSize(width: 520, height: 640), CGSize(width: 820, height: 600), CGSize(width: 1400, height: 900)] {
            let pages: [(String, AnyView)] = [
                ("home", AnyView(HomeView(route: .constant(nil)))),
            ] + store.decks.prefix(1).map { ("overview", AnyView(OverviewView(deck: $0, route: .constant(nil)))) }
            for (name, page) in pages {
                let view = ZStack { Color.bg; page }
                    .environment(\.windowSize, size).environment(\.snapshotting, true).environment(store).environment(progress).environment(Updater())
                    .frame(width: size.width, height: size.height)
                let r = ImageRenderer(content: view)
                r.scale = 1
                if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: dir.appendingPathComponent("\(name)-\(Int(size.width)).png"))
                }
            }
        }
    }
}

private struct SnapshotKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var snapshotting: Bool {
        get { self[SnapshotKey.self] }
        set { self[SnapshotKey.self] = newValue }
    }
}

/// A vertical ScrollView, except while snapshotting (ImageRenderer cannot draw scroll views).
struct PageScroll<Content: View>: View {
    @Environment(\.snapshotting) private var snapshotting
    @ViewBuilder var content: Content
    var body: some View {
        if snapshotting { VStack { content; Spacer(minLength: 0) } }
        else { ScrollView { content }.scrollIndicators(.never) }
    }
}
