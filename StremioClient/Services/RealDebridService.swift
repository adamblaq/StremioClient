import Foundation

actor RealDebridService {
    static let shared = RealDebridService()
    private let base = URL(string: "https://api.real-debrid.com/rest/1.0")!

    struct UserInfo: Codable {
        let id: Int
        let username: String
        let email: String
        let type: String?       // "premium", "free", etc.
        let premium: Int?       // unix timestamp of expiry (0 if not premium)
        let points: Int?
        let locale: String?
        let avatar: String?
        let expiration: String?

        var isPremium: Bool {
            if let t = type { return t == "premium" }
            if let p = premium { return p > 0 }
            return false
        }
    }

    func validateKey(_ key: String) async throws -> UserInfo {
        var request = URLRequest(url: base.appendingPathComponent("user"))
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)

        if let raw = String(data: data, encoding: .utf8) {
            print("[RealDebrid] /user response: \(raw)")
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw RDError.invalidKey
        }
        return try JSONDecoder().decode(UserInfo.self, from: data)
    }

    enum RDError: LocalizedError {
        case invalidKey
        var errorDescription: String? { "Invalid Real-Debrid API key. Check your key and try again." }
    }
}
