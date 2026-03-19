import SwiftUI

@main
struct StremioClientApp: App {
    @State private var appState = AppState()
    @State private var addonManager = AddonManager()
    @State private var downloadManager = DownloadManager()

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isLoggedIn {
                    MainTabView()
                } else {
                    LoginView()
                }
            }
            .environment(appState)
            .environment(addonManager)
            .environment(downloadManager)
        }
    }
}
