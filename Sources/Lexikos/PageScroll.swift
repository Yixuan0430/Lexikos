import SwiftUI

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
        if snapshotting { VStack { content; Spacer(minLength: 0) }.frame(maxHeight: .infinity, alignment: .top).clipped() }
        else { ScrollView { content }.scrollIndicators(.never) }
    }
}
