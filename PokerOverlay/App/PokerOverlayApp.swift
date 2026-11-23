import SwiftUI

@main
struct PokerOverlayApp: App {
    @StateObject private var store = AppStore()

    init() {
        DebugLog.installCrashHandler()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .onAppear { store.boot() }
        }
    }
}
