import SwiftUI
import SwiftData

@main
struct SongCheckpointsApp: App {
    init() {
        AppSettings.register()
        PlayerService.shared.ensureStarted()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(PlayerService.shared)
                .environmentObject(DiagnosticsLog.shared)
        }
        .modelContainer(Persistence.container)
    }
}
