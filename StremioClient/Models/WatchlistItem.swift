import Foundation

struct WatchlistItem: Identifiable, Codable {
    let id: String      // metaId
    let type: String
    let name: String
    let poster: String?
    let year: String?
    let savedAt: Date

    var posterURL: URL? { poster.flatMap(URL.init) }

    /// Thin MetaItem stub — enough for NavigationLink → DetailView to load full metadata.
    var metaItem: MetaItem {
        MetaItem(
            id: id, type: type, name: name, poster: poster,
            background: nil, description: nil, releaseInfo: year,
            imdbRating: nil, genre: nil, genres: nil, runtime: nil,
            cast: nil, director: nil, year: year, videos: nil, trailers: nil
        )
    }
}
