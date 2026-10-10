import SwiftUI

@main
struct WeatherUVApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        PulseboardBackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { PulseboardBackgroundRefresh.schedule() }
        }
    }
}
