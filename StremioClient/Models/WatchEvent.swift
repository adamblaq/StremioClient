import Foundation

/// A single playback event — recorded whenever the user starts watching something.
struct WatchEvent: Identifiable, Codable {
    let id: UUID
    let metaId: String       // IMDB ID (tt...)
    let type: String         // "movie" or "series"
    let name: String
    let poster: String?
    let genres: [String]
    let cast: [String]       // top 5 actors
    let director: [String]
    let season: Int?
    let episode: Int?
    let watchedAt: Date
}
