import Foundation

struct MetaItem: Identifiable, Codable, Hashable {
    let id: String
    let type: String?
    let name: String
    let poster: String?
    let background: String?
    let description: String?
    let releaseInfo: String?
    let imdbRating: String?
    let genre: [String]?
    let genres: [String]?
    let runtime: String?
    let cast: [String]?
    let director: [String]?
    let year: String?
    let videos: [Video]?
    let trailers: [Trailer]?

    var allGenres: [String]? { genre ?? genres }

    struct Video: Identifiable, Codable, Hashable {
        let id: String
        let title: String?
        let name: String?   // Cinemeta uses "name" for episode titles
        let released: String?
        let season: Int?
        let episode: Int?
        let overview: String?
        let thumbnail: String?

        var displayName: String { name ?? title ?? "Episode" }
    }

    var posterURL: URL? { poster.flatMap(URL.init) }
    var backgroundURL: URL? { background.flatMap(URL.init) }
    var displayYear: String { releaseInfo ?? year ?? "" }

    struct Trailer: Codable, Hashable {
        let source: String   // YouTube video ID
        let type: String?    // "Trailer", "Teaser", etc.
    }
}

struct CatalogResponse: Codable {
    let metas: [MetaItem]?
}

struct MetaResponse: Codable {
    let meta: MetaItem?
}
