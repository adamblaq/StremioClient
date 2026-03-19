import SwiftUI

struct AddonsView: View {
    @Environment(AddonManager.self) private var addonManager
    @Environment(AppState.self) private var appState

    @State private var showingAddAddon = false
    @State private var newAddonURL = ""
    @State private var isInstalling = false
    @State private var installError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                List {
                    if addonManager.addons.isEmpty {
                        Text("No addons installed")
                            .foregroundStyle(Theme.textSecondary)
                            .listRowBackground(Theme.surface)
                    } else {
                        ForEach(addonManager.addons) { addon in
                            AddonRowView(addon: addon)
                                .listRowBackground(Theme.surface)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        addonManager.remove(addon)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
                .refreshable { await addonManager.refresh() }
            }
            .navigationTitle("Addons")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAddAddon = true } label: {
                        Image(systemName: "plus")
                    }
                    .foregroundStyle(Theme.accent)
                }
            }
            .sheet(isPresented: $showingAddAddon) {
                addAddonSheet
            }
        }
    }

    private var addAddonSheet: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Addon Manifest URL")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        TextField("https://example.com/manifest.json", text: $newAddonURL)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .padding()
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(Theme.textPrimary)
                    }

                    if let error = installError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await installAddon() }
                    } label: {
                        Group {
                            if isInstalling { ProgressView().tint(.white) }
                            else { Text("Install Addon").font(.headline).foregroundStyle(.white) }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(newAddonURL.isEmpty ? Theme.surface : Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isInstalling || newAddonURL.isEmpty)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Add Addon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingAddAddon = false }
                        .foregroundStyle(Theme.accent)
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private func installAddon() async {
        isInstalling = true
        installError = nil
        do {
            try await addonManager.install(transportUrl: newAddonURL)
            showingAddAddon = false
            newAddonURL = ""
        } catch {
            installError = error.localizedDescription
        }
        isInstalling = false
    }
}

struct AddonRowView: View {
    let addon: Addon

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: addon.manifest.logo.flatMap(URL.init)) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFit()
                } else {
                    Image(systemName: "puzzlepiece.extension.fill")
                        .foregroundStyle(Theme.accent)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(addon.manifest.name)
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.textPrimary)
                if let desc = addon.manifest.description {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
                Text(addon.manifest.types.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 4)
    }
}
