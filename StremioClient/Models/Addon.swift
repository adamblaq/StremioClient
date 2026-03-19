import Foundation

struct Addon: Identifiable, Codable, Hashable {
    var id: String { manifest.id }
    let manifest: Manifest
    let transportUrl: String

    struct Manifest: Codable, Hashable {
        let id: String
        let version: String
        let name: String
        let description: String?
        let logo: String?
        let types: [String]
        let catalogs: [Catalog]
        let resources: [ResourceValue]

        struct Catalog: Codable, Hashable {
            let type: String
            let id: String
            let name: String
            let extra: [ExtraSupported]?

            struct ExtraSupported: Codable, Hashable {
                let name: String
                let isRequired: Bool?
            }
        }

        // Resources can be either a plain string or an object
        enum ResourceValue: Codable, Hashable {
            case string(String)
            case object(ResourceObject)

            var name: String {
                switch self {
                case .string(let s): return s
                case .object(let o): return o.name
                }
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let s = try? container.decode(String.self) {
                    self = .string(s)
                } else {
                    self = .object(try container.decode(ResourceObject.self))
                }
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .string(let s): try container.encode(s)
                case .object(let o): try container.encode(o)
                }
            }
        }

        struct ResourceObject: Codable, Hashable {
            let name: String
            let types: [String]?
        }

        var supportsStream: Bool { resources.contains { $0.name == "stream" } }
        var supportsMeta: Bool { resources.contains { $0.name == "meta" } }
        var supportsCatalog: Bool { resources.contains { $0.name == "catalog" } }
    }
}

struct ManifestResponse: Codable {
    // Top-level manifest JSON has the same shape as Addon.Manifest
    let id: String
    let version: String
    let name: String
    let description: String?
    let logo: String?
    let types: [String]
    let catalogs: [Addon.Manifest.Catalog]
    let resources: [Addon.Manifest.ResourceValue]

    func toAddon(transportUrl: String) -> Addon {
        Addon(
            manifest: Addon.Manifest(
                id: id, version: version, name: name,
                description: description, logo: logo,
                types: types, catalogs: catalogs, resources: resources
            ),
            transportUrl: transportUrl
        )
    }
}
