import Foundation
import Observation

@Observable
class AppState {
    var user: StremioUser?
    var authKey: String?
    var realDebridKey: String?
    var realDebridUser: RealDebridService.UserInfo?

    var isLoggedIn: Bool { authKey != nil }
    var isRealDebridConnected: Bool { realDebridKey != nil && realDebridUser?.isPremium == true }

    var torrentioTransportUrl: String? {
        guard let key = realDebridKey else { return nil }
        return "https://torrentio.strem.fun/sort=qualitysize|realdebrid=\(key)"
    }

    var tmdbApiKey: String = ""
    var claudeApiKey: String = ""
    var trailerAutoplaySound: Bool = false

    private let authKeyStorageKey      = "authKey"
    private let userStorageKey         = "user"
    private let rdKeyStorageKey        = "rdKey"
    private let rdUserStorageKey       = "rdUser"
    private let tmdbKeyStorageKey      = "tmdbApiKey"
    private let claudeKeyStorageKey    = "claudeApiKey"
    private let trailerSoundStorageKey = "trailerAutoplaySound"

    init() {
        authKey              = UserDefaults.standard.string(forKey: authKeyStorageKey)
        realDebridKey        = UserDefaults.standard.string(forKey: rdKeyStorageKey)
        tmdbApiKey           = UserDefaults.standard.string(forKey: tmdbKeyStorageKey) ?? ""
        claudeApiKey         = UserDefaults.standard.string(forKey: claudeKeyStorageKey) ?? ""
        trailerAutoplaySound = UserDefaults.standard.bool(forKey: trailerSoundStorageKey)
        if let data = UserDefaults.standard.data(forKey: userStorageKey) {
            user = try? JSONDecoder().decode(StremioUser.self, from: data)
        }
        if let data = UserDefaults.standard.data(forKey: rdUserStorageKey) {
            realDebridUser = try? JSONDecoder().decode(RealDebridService.UserInfo.self, from: data)
        }
    }

    // MARK: - Stremio auth

    func login(email: String, password: String) async throws {
        let (user, authKey) = try await StremioAPI.shared.login(email: email, password: password)
        self.user = user
        self.authKey = authKey
        persist()
    }

    func logout() async {
        if let key = authKey { try? await StremioAPI.shared.logout(authKey: key) }
        user = nil
        authKey = nil
        UserDefaults.standard.removeObject(forKey: authKeyStorageKey)
        UserDefaults.standard.removeObject(forKey: userStorageKey)
    }

    // MARK: - Real-Debrid

    func connectRealDebrid(key: String) async throws {
        let info = try await RealDebridService.shared.validateKey(key)
        realDebridKey  = key
        realDebridUser = info
        UserDefaults.standard.set(key, forKey: rdKeyStorageKey)
        if let data = try? JSONEncoder().encode(info) {
            UserDefaults.standard.set(data, forKey: rdUserStorageKey)
        }
    }

    func disconnectRealDebrid() {
        realDebridKey  = nil
        realDebridUser = nil
        UserDefaults.standard.removeObject(forKey: rdKeyStorageKey)
        UserDefaults.standard.removeObject(forKey: rdUserStorageKey)
    }

    // MARK: - Persistence

    func saveTmdbKey() {
        UserDefaults.standard.set(tmdbApiKey, forKey: tmdbKeyStorageKey)
    }

    func saveClaudeKey() {
        UserDefaults.standard.set(claudeApiKey, forKey: claudeKeyStorageKey)
    }

    func saveTrailerAutoplaySound() {
        UserDefaults.standard.set(trailerAutoplaySound, forKey: trailerSoundStorageKey)
    }

    private func persist() {
        UserDefaults.standard.set(authKey, forKey: authKeyStorageKey)
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: userStorageKey)
        }
    }
}
