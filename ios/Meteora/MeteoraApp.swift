import SwiftUI

@main
struct MeteoraApp: App {
    @State private var app = AppModel()
    @Environment(\.scenePhase) private var phase

    init() {
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 256 << 20)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(app.settings.colorScheme)
                .tint(app.weather.mood.color)
        }
        .onChange(of: phase) { _, p in
            switch p {
            case .active: app.becameActive()
            case .background: app.player.stopPolling()
            default: break
            }
        }
    }
}
