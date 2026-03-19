import SwiftUI

@main
struct StremioClientApp: App {
    @State private var appState = AppState()
    @State private var addonManager = AddonManager()
    @State private var downloadManager = DownloadManager()
    @State private var watchHistory = WatchHistoryManager()
    @State private var showSplash = true

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
            .environment(watchHistory)
            .overlay {
                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                withAnimation(.easeOut(duration: 0.5)) {
                                    showSplash = false
                                }
                            }
                        }
                }
            }
        }
    }
}
