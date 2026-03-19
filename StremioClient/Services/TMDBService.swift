import Foundation

/// Fetches "Because You Watched X" recommendations from TMDB.
///
/// Flow per seed title:
///   1. `/find/{imdb_id}?external_source=imdb_id`  → TMDB ID + media type
///   2. `/movie|tv/{tmdb_id}/recommendations`       → up to 6 TMDB result IDs
///   3. Parallel `/movie|tv/{id}/external_ids`      → IMDB IDs
///   4. Assemble lightweight MetaItems (poster via TMDB CDN, id = IMDB ID)
actor TMDBService {
    static let shared = TMDBService()

    private let base = "https://api.themoviedb.org/3"
    private let imageBase = "https://image.tmdb.org/t/p/w500"
    private let session = URLSession.shared

    // MARK: - Public

    /// Full pipeline: IMDB ID → [MetaItem] recommendations.
    /// Returns [] on any error or when apiKey is empty.
    func recommendations(
        forImdbId imdbId: String,
        apiKey: String
    ) async -> [MetaItem] {
        guard !apiKey.isEmpty else { return [] }

        guard let (tmdbId, mediaType) = await findTMDB(imdbId: imdbId, apiKey: apiKey)
        else { return [] }

        let results = await fetchRecommendations(tmdbId: tmdbId, mediaType: mediaType, apiKey: apiKey)
        guard !results.isEmpty else { return [] }

        // Resolve IMDB IDs in parallel (cap at 8 to limit calls)
        let capped = Array(results.prefix(8))
        return await withTaskGroup(of: MetaItem?.self) { group in
            for result in capped {
                group.addTask {
                    await self.resolveToMetaItem(result: result, mediaType: mediaType, apiKey: apiKey)
                }
            }
            var items: [MetaItem] = []
            for await item in group {
                if let item { items.append(item) }
            }
            return items
        }
    }

    // MARK: - Private steps

    private func findTMDB(imdbId: String, apiKey: String) async -> (Int, String)? {
        guard let url = URL(string: "\(base)/find/\(imdbId)?external_source=imdb_id&api_key=\(apiKey)")
        else { return nil }
        guard let data = try? await session.data(from: url).0,
              let resp = try? JSONDecoder().decode(FindResponse.self, from: data)
        else { return nil }

        if let movie = resp.movie_results.first { return (movie.id, "movie") }
        if let tv = resp.tv_results.first { return (tv.id, "tv") }
        return nil
    }

    private func fetchRecommendations(
        tmdbId: Int,
        mediaType: String,
        apiKey: String
    ) async -> [RecommendationResult] {
        guard let url = URL(string: "\(base)/\(mediaType)/\(tmdbId)/recommendations?api_key=\(apiKey)")
        else { return [] }
        guard let data = try? await session.data(from: url).0,
              let resp = try? JSONDecoder().decode(RecommendationsResponse.self, from: data)
        else { return [] }
        return resp.results
    }

    private func resolveToMetaItem(
        result: RecommendationResult,
        mediaType: String,
        apiKey: String
    ) async -> MetaItem? {
        guard let url = URL(string: "\(base)/\(mediaType)/\(result.id)/external_ids?api_key=\(apiKey)")
        else { return nil }
        guard let data = try? await session.data(from: url).0,
              let ext = try? JSONDecoder().decode(ExternalIds.self, from: data),
              let imdbId = ext.imdb_id, !imdbId.isEmpty
        else { return nil }

        let posterURL = result.poster_path.map { "\(imageBase)\($0)" }
        let year = (result.release_date ?? result.first_air_date).flatMap { String($0.prefix(4)) }
        let title = result.title ?? result.name ?? "Unknown"
        let stremioType = mediaType == "tv" ? "series" : "movie"

        return MetaItem(
            id: imdbId,
            type: stremioType,
            name: title,
            poster: posterURL,
            background: nil,
            description: result.overview,
            releaseInfo: year,
            imdbRating: result.vote_average.map { String(format: "%.1f", $0) },
            genre: nil,
            genres: nil,
            runtime: nil,
            cast: nil,
            director: nil,
            year: year,
            videos: nil
        )
    }

    // MARK: - Search by title (for Claude resolution)

    /// Search TMDB by title + year, resolve to IMDB ID, return a lightweight MetaItem.
    func searchMetaItem(title: String, year: String?, type: String, apiKey: String) async -> MetaItem? {
        guard !apiKey.isEmpty else { return nil }
        let endpoint = type == "series" ? "tv" : "movie"
        var components = URLComponents(string: "\(base)/search/\(endpoint)")!
        components.queryItems = [
            .init(name: "query", value: title),
            .init(name: "api_key", value: apiKey)
        ]
        if let y = year {
            let key = type == "series" ? "first_air_date_year" : "year"
            components.queryItems?.append(.init(name: key, value: y))
        }
        guard let url = components.url,
              let data = try? await session.data(from: url).0,
              let resp = try? JSONDecoder().decode(SearchResponse.self, from: data),
              let first = resp.results.first
        else { return nil }

        return await resolveToMetaItem(result: first, mediaType: endpoint, apiKey: apiKey)
    }

    private struct SearchResponse: Codable {
        let results: [RecommendationResult]
    }

    // MARK: - Response models

    private struct FindResponse: Codable {
        struct Entry: Codable { let id: Int }
        let movie_results: [Entry]
        let tv_results: [Entry]
    }

    private struct RecommendationsResponse: Codable {
        let results: [RecommendationResult]
    }

    private struct RecommendationResult: Codable {
        let id: Int
        let title: String?
        let name: String?
        let poster_path: String?
        let release_date: String?
        let first_air_date: String?
        let vote_average: Double?
        let overview: String?
    }

    private struct ExternalIds: Codable {
        let imdb_id: String?
    }
}
