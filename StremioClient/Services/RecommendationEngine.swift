import Foundation

struct RecommendationEngine {

    // MARK: - Precomputed context

    /// All history-derived weights computed once per scoring batch.
    /// Avoids recomputing O(events) decay math for every item in the pool.
    /// Sendable so it can be passed into Task.detached for off-actor scoring.
    struct ScoringContext: Sendable {
        let genreW: [String: Double]
        let dirW: [String: Double]
        let castW: [String: Double]
        let watchedIds: Set<String>
        let watchlistIds: Set<String>
        let feedback: [String: WatchFeedback]
        let progressMap: [String: PlaybackProgress]
        let currentYear: Int

        init(history: WatchHistoryManager) {
            genreW = history.genreWeights
            dirW = history.directorWeights
            castW = history.castWeights
            watchedIds = history.watchedIds
            watchlistIds = history.watchlistIds
            feedback = history.feedback
            progressMap = history.progressMap
            currentYear = Calendar.current.component(.year, from: Date())
        }
    }

    // MARK: - Scoring

    /// Score a single item against the user's taste profile (0–1+).
    /// Accepts a precomputed context so weights are only derived once per batch.
    private static func score(_ item: MetaItem, ctx: ScoringContext) -> Double {
        if ctx.watchlistIds.contains(item.id) { return 1.8 }

        switch ctx.feedback[item.id] {
        case .liked:    return 1.5
        case .disliked: return 0.0
        case nil: break
        }

        let pid = PlaybackProgress.id(metaId: item.id, season: nil, episode: nil)
        let completion = ctx.progressMap[pid]?.completionPercent ?? 0
        if completion >= 0.92 { return 0.02 }

        var s = 0.0

        let genres = item.allGenres ?? []
        if !genres.isEmpty {
            let g = genres.compactMap { ctx.genreW[$0] }.reduce(0, +) / Double(genres.count)
            s += g * 0.60
        }

        if let dirs = item.director, !dirs.isEmpty {
            s += (dirs.compactMap { ctx.dirW[$0] }.max() ?? 0) * 0.25
        }

        if let cast = item.cast, !cast.isEmpty {
            s += (cast.prefix(5).compactMap { ctx.castW[$0] }.max() ?? 0) * 0.15
        }

        if let year = item.year.flatMap(Int.init), ctx.currentYear - year <= 2 {
            s += 0.05
        }

        if ctx.watchedIds.contains(item.id) { s *= 0.08 }

        return s
    }

    /// Convenience overload for single-item scoring (builds its own context).
    static func score(_ item: MetaItem, history: WatchHistoryManager) -> Double {
        score(item, ctx: ScoringContext(history: history))
    }

    // MARK: - Ranking with diversity

    /// Returns top matches with per-genre diversity cap so results don't
    /// collapse into a single genre even if that's the user's #1 preference.
    /// Weights are computed ONCE and reused — no O(items × events) blowup.
    static func topMatches(
        from items: [MetaItem],
        history: WatchHistoryManager,
        minScore: Double = 0.04,
        limit: Int = 20,
        maxPerGenre: Int = 3
    ) -> [MetaItem] {
        guard !history.events.isEmpty else { return [] }
        return topMatchesWithContext(
            from: items,
            ctx: ScoringContext(history: history),
            minScore: minScore, limit: limit, maxPerGenre: maxPerGenre
        )
    }

    /// Off-actor entry point: accepts a pre-built ScoringContext (Sendable) so
    /// scoring can run inside Task.detached without touching @Observable state.
    static func topMatchesWithContext(
        from items: [MetaItem],
        ctx: ScoringContext,
        minScore: Double = 0.04,
        limit: Int = 20,
        maxPerGenre: Int = 3
    ) -> [MetaItem] {
        let scored = items
            .map { ($0, score($0, ctx: ctx)) }
            .filter { $0.1 >= minScore }
            .sorted { $0.1 > $1.1 }

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
        let ctx = ScoringContext(history: history)
        return items
            .map { ($0, score($0, ctx: ctx)) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }
}
