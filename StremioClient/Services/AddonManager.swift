import Foundation
import Observation

@Observable
class AddonManager {
    var addons: [Addon] = []
    var isLoading = false

    private let defaultTransportUrls = [
        "https://v3-cinemeta.strem.io/manifest.json"
    ]

    private let storageKey = "installed_addons"

    init() {
        loadFromDisk()
        if addons.isEmpty {
            Task { await installDefaults() }
        }
    }

    // MARK: - Install / Remove

    func install(transportUrl: String) async throws {
        let base = AddonClient.baseURL(from: transportUrl)
        guard !addons.contains(where: { $0.transportUrl == base }) else { return }
        let addon = try await AddonClient.shared.fetchManifest(from: base)
        addons.append(addon)
        saveToDisk()
    }

    func remove(_ addon: Addon) {
        addons.removeAll { $0.id == addon.id }
        saveToDisk()
    }

    func removeTorrentio() {
        addons.removeAll { $0.transportUrl.contains("torrentio.strem.fun") }
        saveToDisk()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        var refreshed: [Addon] = []
        for addon in addons {
            if let updated = try? await AddonClient.shared.fetchManifest(from: addon.transportUrl) {
                refreshed.append(updated)
            } else {
                refreshed.append(addon)
            }
        }
        addons = refreshed
    }

    // MARK: - Sync with Stremio account

    func syncFromAccount(authKey: String) async throws {
        let urls = try await StremioAPI.shared.getAddonCollection(authKey: authKey)
        for url in urls {
            try? await install(transportUrl: url)
        }
    }

    func syncToAccount(authKey: String) async throws {
        let urls = addons.map(\.transportUrl)
        try await StremioAPI.shared.setAddonCollection(authKey: authKey, transportUrls: urls)
    }

    // MARK: - Persistence

    private func installDefaults() async {
        for url in defaultTransportUrls {
            try? await install(transportUrl: url)
        }
    }

    private func saveToDisk() {
        guard let data = try? JSONEncoder().encode(addons) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([Addon].self, from: data)
        else { return }
        addons = saved
    }
}
