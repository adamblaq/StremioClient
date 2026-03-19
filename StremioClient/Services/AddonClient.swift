import Foundation

actor AddonClient {
    static let shared = AddonClient()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024,
                                   diskCapacity: 32 * 1024 * 1024)
        return URLSession(configuration: config)
    }()

    // Shared decoder — allocation-free across all fetch calls
    private let decoder = JSONDecoder()

    private var cache: [String: (data: Data, date: Date)] = [:]
    private let cacheTTL: TimeInterval = 300 // 5 minutes

    // MARK: - Manifest

    func fetchManifest(from transportUrl: String) async throws -> Addon {
        let base = Self.baseURL(from: transportUrl)
        let url = URL(string: base + "/manifest.json")!
        let data = try await fetch(url: url)
        let manifest = try decoder.decode(ManifestResponse.self, from: data)
        return manifest.toAddon(transportUrl: base)
    }

    // MARK: - Catalog

    func fetchCatalog(addon: Addon, type: String, id: String, skip: Int = 0) async throws -> [MetaItem] {
        var path = "\(addon.transportUrl)/catalog/\(type)/\(id)"
        if skip > 0 { path += "/skip=\(skip)" }
        path += ".json"

        guard let url = URL(string: path) else { return [] }
        let data = try await fetch(url: url)
        let response = try decoder.decode(CatalogResponse.self, from: data)
        return response.metas ?? []
    }

    // MARK: - Meta

    func fetchMeta(addon: Addon, type: String, id: String) async throws -> MetaItem? {
        let path = "\(addon.transportUrl)/meta/\(type)/\(id).json"
        guard let url = URL(string: path) else { return nil }
        let data = try await fetch(url: url)
        let response = try decoder.decode(MetaResponse.self, from: data)
        return response.meta
    }

    // MARK: - Streams

    func fetchStreams(from addons: [Addon], type: String, id: String) async throws -> [StreamItem] {
        let streamAddons = addons.filter { $0.manifest.supportsStream && $0.manifest.types.contains(type) }

        return await withTaskGroup(of: [StreamItem].self) { group in
            for addon in streamAddons {
                group.addTask {
                    let path = "\(addon.transportUrl)/stream/\(type)/\(id).json"
                    guard let url = URL(string: path),
                          let data = try? await self.fetch(url: url),
                          let response = try? self.decoder.decode(StreamsResponse.self, from: data)
                    else { return [] }
                    return response.streams
                }
            }

            var all: [StreamItem] = []
            for await streams in group { all.append(contentsOf: streams) }
            return all
        }
    }

    // MARK: - Search

    func search(addons: [Addon], type: String, query: String) async throws -> [MetaItem] {
        let searchAddons = addons.filter {
            $0.manifest.supportsCatalog &&
            $0.manifest.types.contains(type) &&
            $0.manifest.catalogs.contains { cat in
                cat.extra?.contains { $0.name == "search" } == true
            }
        }

        return await withTaskGroup(of: [MetaItem].self) { group in
            for addon in searchAddons {
                for catalog in addon.manifest.catalogs where catalog.type == type {
                    group.addTask {
                        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
                        let path = "\(addon.transportUrl)/catalog/\(type)/\(catalog.id)/search=\(encoded).json"
                        guard let url = URL(string: path),
                              let data = try? await self.fetch(url: url),
                              let response = try? self.decoder.decode(CatalogResponse.self, from: data)
                        else { return [] }
                        return response.metas ?? []
                    }
                }
            }
            var all: [MetaItem] = []
            for await items in group { all.append(contentsOf: items) }
            return all
        }
    }

    // MARK: - Private

    private func fetch(url: URL) async throws -> Data {
        let key = url.absoluteString
        if let cached = cache[key], Date().timeIntervalSince(cached.date) < cacheTTL {
            return cached.data
        }
        let (data, _) = try await session.data(from: url)
        cache[key] = (data, Date())
        return data
    }

    /// Strips trailing `/manifest.json` and `/` to get a clean base URL.
    static func baseURL(from transportUrl: String) -> String {
        var url = transportUrl
        if url.hasSuffix("/manifest.json") { url = String(url.dropLast("/manifest.json".count)) }
        if url.hasSuffix("/") { url = String(url.dropLast()) }
        return url
    }
}
