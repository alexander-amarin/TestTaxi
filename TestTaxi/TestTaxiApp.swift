import SwiftUI
import GoogleMaps

@main
struct TestTaxiApp: App {
    init() {
        GoogleMapsBootstrap.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
