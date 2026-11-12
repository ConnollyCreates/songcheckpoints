import SwiftUI

enum AppTab: Hashable {
    case nowPlaying, library, log, settings
}

struct RootView: View {
    @State private var tab: AppTab = .library

    var body: some View {
        TabView(selection: $tab) {
            NowPlayingView()
                .tabItem { Label("Now Playing", systemImage: "play.circle.fill") }
                .tag(AppTab.nowPlaying)

            LibraryView(onStartPlayback: { tab = .nowPlaying })
                .tabItem { Label("Library", systemImage: "music.note.list") }
                .tag(AppTab.library)

            LogView()
                .tabItem { Label("Test Log", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.log)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
    }
}
