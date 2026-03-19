import Foundation

actor StremioAPI {
    static let shared = StremioAPI()
    private let base = URL(string: "https://api.strem.io/api")!
    private let session = URLSession.shared

    // MARK: - Auth

    func login(email: String, password: String) async throws -> (user: StremioUser, authKey: String) {
        struct Body: Encodable {
            let email: String
            let password: String
            let type = "Auth"
        }
        struct Response: Decodable {
            struct Result: Decodable {
                let user: StremioUser
                let authKey: String
            }
            let result: Result?
            let error: String?
        }

        let response: Response = try await post(path: "login", body: Body(email: email, password: password))
        guard let result = response.result else {
            throw APIError.serverError(response.error ?? "Login failed")
        }
        return (result.user, result.authKey)
    }

    func logout(authKey: String) async throws {
        struct Body: Encodable {
            let authKey: String
            let type = "Logout"
        }
        struct Response: Decodable { let result: Bool? }
        let _: Response = try await post(path: "logout", body: Body(authKey: authKey))
    }

    // MARK: - Addon Collection

    func getAddonCollection(authKey: String) async throws -> [String] {
        struct Body: Encodable {
            let authKey: String
            let type = "AddonCollectionGet"
            let addons: [String] = []
        }
        struct AddonEntry: Decodable {
            let transportUrl: String?
        }
        struct Response: Decodable {
            let result: [AddonEntry]?
            let error: String?
        }

        let response: Response = try await post(path: "addonCollectionGet", body: Body(authKey: authKey))
        return response.result?.compactMap(\.transportUrl) ?? []
    }

    func setAddonCollection(authKey: String, transportUrls: [String]) async throws {
        struct AddonEntry: Encodable {
            let transportUrl: String
        }
        struct Body: Encodable {
            let authKey: String
            let type = "AddonCollectionSet"
            let addons: [AddonEntry]
        }
        struct Response: Decodable { let result: Bool? }
        let body = Body(authKey: authKey, addons: transportUrls.map(AddonEntry.init))
        let _: Response = try await post(path: "addonCollectionSet", body: body)
    }

    // MARK: - Private helpers

    private func post<Body: Encodable, Response: Decodable>(path: String, body: Body) async throws -> Response {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await session.data(for: request)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.httpError((resp as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    enum APIError: LocalizedError {
        case serverError(String)
        case httpError(Int)

        var errorDescription: String? {
            switch self {
            case .serverError(let msg): return msg
            case .httpError(let code): return "HTTP error \(code)"
            }
        }
    }
}
