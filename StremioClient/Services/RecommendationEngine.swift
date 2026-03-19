import Foundation

struct RecommendationEngine {

    // MARK: - Scoring

    /// Score a single item against the user's taste profile (0–1+).
    static func score(_ item: MetaItem, history: WatchHistoryManager) -> Double {
        // Watchlist = strongest positive signal (user explicitly saved it)
        if history.isInWatchlist(item.id) { return 1.8 }

        // Explicit feedback overrides scoring
        switch history.feedback[item.id] {
        case .liked:    return 1.5
        case .disliked: return 0.0
        case nil: break
        }

        // Already fully watched — suppress unless liked
        let completion = history.completionPercent(metaId: item.id)
        if completion >= 0.92 { return 0.02 }

        var score = 0.0

        // Genre match (0–0.60)
        let genreW = history.genreWeights
        let genres = item.allGenres ?? []
        if !genres.isEmpty {
            let g = genres.compactMap { genreW[$0] }.reduce(0, +) / Double(genres.count)
            score += g * 0.60
        }

        // Director match (0–0.25)
        let dirW = history.directorWeights
        if let dirs = item.director, !dirs.isEmpty {
            score += (dirs.compactMap { dirW[$0] }.max() ?? 0) * 0.25
        }

        // Cast match (0–0.15)
        let castW = history.castWeights
        if let cast = item.cast, !cast.isEmpty {
            score += (cast.prefix(5).compactMap { castW[$0] }.max() ?? 0) * 0.15
        }

        // Freshness bonus: items released within 2 years get a small lift
        if let year = item.year.flatMap(Int.init) {
            let currentYear = Calendar.current.component(.year, from: Date())
            if currentYear - year <= 2 { score += 0.05 }
        }

        // Suppress already-seen (but not fully — it might be a rewatch candidate)
        if history.watchedIds.contains(item.id) { score *= 0.08 }

        return score
    }

    // MARK: - Ranking with diversity

    /// Returns top matches with per-genre diversity cap so results don't
    /// collapse into a single genre even if that's the user's #1 preference.
    static func topMatches(
        from items: [MetaItem],
        history: WatchHistoryManager,
        minScore: Double = 0.04,
        limit: Int = 20,
        maxPerGenre: Int = 3
    ) -> [MetaItem] {
        guard !history.events.isEmpty else { return [] }

        let scored = items
            .map { ($0, score($0, history: history)) }
            .filter { $0.1 >= minScore }
            .sorted { $0.1 > $1.1 }

        // Diversity pass — track first-genre counts
        var genreCounts: [String: Int] = [:]
        var result: [MetaItem] = []

        for (item, _) in scored {
            let primaryGenre = item.allGenres?.first ?? "_none"
            let count = genreCounts[primaryGenre, default: 0]
            if count < maxPerGenre {
                result.append(item)
                genreCounts[primaryGenre] = count + 1
            }
            if result.count >= limit { break }
        }
        return result
    }

    /// Simple sort without diversity — used when diversity already handled externally.
    static func rank(_ items: [MetaItem], history: WatchHistoryManager) -> [MetaItem] {
        guard !history.events.isEmpty else { return items }
        return items
            .map { ($0, score($0, history: history)) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }
}
