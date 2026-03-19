import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Discover", systemImage: "film.stack") }
                .tag(0)

            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(1)

            DownloadsView()
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
                .tag(2)

            AddonsView()
                .tabItem { Label("Addons", systemImage: "puzzlepiece.extension") }
                .tag(3)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(4)
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(AddonManager.self) private var addonManager

    @State private var showRDSetup = false
    @State private var tmdbKeyDraft = ""
    @State private var showTMDBField = false
    @State private var claudeKeyDraft = ""
    @State private var showClaudeField = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                List {
                    // Account
                    Section {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(Theme.accent)
                            VStack(alignment: .leading) {
                                Text(appState.user?.fullname ?? appState.user?.email ?? "Guest")
                                    .font(.headline)
                                    .foregroundStyle(Theme.textPrimary)
                                if let email = appState.user?.email {
                                    Text(email).font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }
                    .listRowBackground(Theme.surface)

                    // Real-Debrid
                    Section {
                        if appState.isRealDebridConnected {
                            HStack {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Real-Debrid Connected")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(Theme.textPrimary)
                                    if let u = appState.realDebridUser {
                                        Text(u.username)
                                            .font(.caption)
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                }
                                Spacer()
                                Button("Disconnect") {
                                    appState.disconnectRealDebrid()
                                    addonManager.removeTorrentio()
                                }
                                .font(.caption)
                                .foregroundStyle(.red)
                            }
                        } else {
                            Button {
                                showRDSetup = true
                            } label: {
                                HStack {
                                    Image(systemName: "bolt.fill")
                                        .foregroundStyle(Theme.accent)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Connect Real-Debrid")
                                            .font(.subheadline.bold())
                                            .foregroundStyle(Theme.textPrimary)
                                        Text("Enable Smart Play with 1-click streaming")
                                            .font(.caption)
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    } header: {
                        Text("Streaming").foregroundStyle(Theme.textSecondary)
                    }
                    .listRowBackground(Theme.surface)

                    // TMDB recommendations
                    Section {
                        if appState.tmdbApiKey.isEmpty || showTMDBField {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("TMDB API Key (v3 auth)", text: $tmdbKeyDraft)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .padding()
                                    .background(Theme.background)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("Free at themoviedb.org → Settings → API")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                                Button("Save Key") {
                                    appState.tmdbApiKey = tmdbKeyDraft.trimmingCharacters(in: .whitespaces)
                                    appState.saveTmdbKey()
                                    showTMDBField = false
                                }
                                .font(.caption.bold())
                                .foregroundStyle(Theme.accent)
                                .disabled(tmdbKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        } else {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(Theme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("TMDB Connected")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("\"Because You Watched\" recommendations enabled")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                Button("Change") {
                                    tmdbKeyDraft = appState.tmdbApiKey
                                    showTMDBField = true
                                }
                                .font(.caption)
                                .foregroundStyle(Theme.accent)
                            }
                        }
                    } header: {
                        Text("Recommendations").foregroundStyle(Theme.textSecondary)
                    }
                    .listRowBackground(Theme.surface)
                    .onAppear { tmdbKeyDraft = appState.tmdbApiKey }

                    // Claude AI recommendations
                    Section {
                        if appState.claudeApiKey.isEmpty || showClaudeField {
                            VStack(alignment: .leading, spacing: 8) {
                                SecureField("Claude API Key (sk-ant-...)", text: $claudeKeyDraft)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .padding()
                                    .background(Theme.background)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("Free at console.anthropic.com — uses Claude Haiku (very low cost)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                                Button("Save Key") {
                                    appState.claudeApiKey = claudeKeyDraft.trimmingCharacters(in: .whitespaces)
                                    appState.saveClaudeKey()
                                    showClaudeField = false
                                }
                                .font(.caption.bold())
                                .foregroundStyle(Theme.accent)
                                .disabled(claudeKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        } else {
                            HStack {
                                Image(systemName: "brain")
                                    .foregroundStyle(Theme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("AI Recommendations On")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("\"Curated For You\" shelf powered by Claude")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                Button("Change") {
                                    claudeKeyDraft = ""
                                    showClaudeField = true
                                }
                                .font(.caption)
                                .foregroundStyle(Theme.accent)
                            }
                        }
                    } header: {
                        Text("AI Recommendations").foregroundStyle(Theme.textSecondary)
                    }
                    .listRowBackground(Theme.surface)
                    .onAppear { claudeKeyDraft = "" }

                    // Sign out
                    Section {
                        Button(role: .destructive) {
                            Task { await appState.logout() }
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .foregroundStyle(.red)
                    }
                    .listRowBackground(Theme.surface)
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showRDSetup) {
                RealDebridSetupView()
            }
        }
    }
}

struct RealDebridSetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(AddonManager.self) private var addonManager
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 24) {
                    // Icon
                    Image(systemName: "bolt.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(Theme.accent)

                    VStack(spacing: 8) {
                        Text("Connect Real-Debrid")
                            .font(.title2.bold())
                            .foregroundStyle(Theme.textPrimary)
                        Text("Real-Debrid converts torrents into high-speed direct streams. Smart Play will automatically pick the best 1080p+ stream under 15 GB.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("API Key")
                            .font(.caption.bold())
                            .foregroundStyle(Theme.textSecondary)
                        SecureField("Paste your Real-Debrid API key", text: $apiKey)
                            .padding()
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Find your key at real-debrid.com → Account → API Keys")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    if let error = errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }

                    Button {
                        Task { await connect() }
                    } label: {
                        Group {
                            if isConnecting {
                                ProgressView().tint(.white)
                            } else {
                                Text("Connect").font(.headline).foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(apiKey.isEmpty ? Theme.surface : Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isConnecting || apiKey.isEmpty)

                    Spacer()
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.accent)
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private func connect() async {
        isConnecting = true
        errorMessage = nil
        do {
            try await appState.connectRealDebrid(key: apiKey.trimmingCharacters(in: .whitespaces))
            // Install Torrentio with RD key automatically
            if let url = appState.torrentioTransportUrl {
                try? await addonManager.install(transportUrl: url)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isConnecting = false
    }
}
