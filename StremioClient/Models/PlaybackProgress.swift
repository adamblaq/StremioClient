import Foundation

/// Tracks where a user is in a piece of content — used for Continue Watching
/// and as a quality signal for the recommendation engine.
struct PlaybackProgress: Identifiable, Codable {
    /// Composite key: metaId for movies, "metaId:season:episode" for episodes.
    let id: String
    let metaId: String
    let name: String
    let poster: String?
    let type: String        // "movie" or "series"
    let season: Int?
    let episode: Int?
    let episodeName: String?
    var resumeSeconds: Double
    var durationSeconds: Double
    var updatedAt: Date

    var completionPercent: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(1.0, resumeSeconds / durationSeconds)
    }

    /// True when between 5% and 92% complete — means "in progress, worth resuming".
    var isInProgress: Bool {
        let p = completionPercent
        return p >= 0.05 && p < 0.92
    }

    var episodeLabel: String? {
        guard let s = season, let e = episode else { return nil }
        return "S\(s)E\(e)"
    }

    static func id(metaId: String, season: Int?, episode: Int?) -> String {
        if let s = season, let e = episode { return "\(metaId):\(s):\(e)" }
        return metaId
    }
}

enum WatchFeedback: String, Codable {
    case liked
    case disliked
}
