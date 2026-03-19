import Foundation
import Observation

@Observable
class WatchHistoryManager {
    private(set) var events: [WatchEvent] = []
    private(set) var progressMap: [String: PlaybackProgress] = [:]
    private(set) var feedback: [String: WatchFeedback] = [:]

    private let eventsKey   = "watchHistory"
    private let progressKey = "watchProgress"
    private let feedbackKey = "watchFeedback"

    init() {
        loadFromDisk()
    }

    // MARK: - Watch events

    func record(_ item: MetaItem, season: Int? = nil, episode: Int? = nil) {
        let today = Calendar.current.startOfDay(for: Date())
        let alreadyToday = events.contains {
            $0.metaId == item.id &&
            $0.season == season &&
            $0.episode == episode &&
            Calendar.current.startOfDay(for: $0.watchedAt) == today
        }
        guard !alreadyToday else { return }

        let event = WatchEvent(
            id: UUID(),
            metaId: item.id,
            type: item.type ?? "movie",
            name: item.name,
            poster: item.poster,
            genres: item.allGenres ?? [],
            cast: Array((item.cast ?? []).prefix(5)),
            director: item.director ?? [],
            season: season,
            episode: episode,
            watchedAt: Date()
        )
        events.insert(event, at: 0)
        if events.count > 200 { events = Array(events.prefix(200)) }
        save(events, key: eventsKey)
    }

    // MARK: - Playback progress

    func updateProgress(
        for item: MetaItem,
        season: Int?,
        episode: Int?,
        episodeName: String?,
        seconds: Double,
        duration: Double
    ) {
        guard seconds.isFinite, duration.isFinite, duration > 0 else { return }
        let pid = PlaybackProgress.id(metaId: item.id, season: season, episode: episode)
        let pct = seconds / duration

        // If finished (>92%) remove from continue-watching
        if pct >= 0.92 {
            progressMap.removeValue(forKey: pid)
        } else {
            progressMap[pid] = PlaybackProgress(
                id: pid,
                metaId: item.id,
                name: item.name,
                poster: item.poster,
                type: item.type ?? "movie",
                season: season,
                episode: episode,
                episodeName: episodeName,
                resumeSeconds: seconds,
                durationSeconds: duration,
                updatedAt: Date()
            )
        }
        save(progressMap, key: progressKey)
    }

    func completionPercent(metaId: String, season: Int? = nil, episode: Int? = nil) -> Double {
        let pid = PlaybackProgress.id(metaId: metaId, season: season, episode: episode)
        return progressMap[pid]?.completionPercent ?? 0
    }

    /// Items with 5–92% completion, sorted by most recently updated.
    var continueWatching: [PlaybackProgress] {
        progressMap.values
            .filter(\.isInProgress)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Explicit feedback

    func setFeedback(_ value: WatchFeedback, for metaId: String) {
        feedback[metaId] = value
        save(feedback, key: feedbackKey)
    }

    func clearFeedback(for metaId: String) {
        feedback.removeValue(forKey: metaId)
        save(feedback, key: feedbackKey)
    }

    // MARK: - Preference profile (used by RecommendationEngine)

    /// Genre affinity weights (0–1), recency-decayed and completion-weighted.
    var genreWeights: [String: Double] {
        var raw: [String: Double] = [:]
        let now = Date()
        for event in events {
            let age = now.timeIntervalSince(event.watchedAt)
            let decay = exp(-age / (30 * 86_400) * 0.693)   // 30-day half-life
            let pid = PlaybackProgress.id(metaId: event.metaId, season: event.season, episode: event.episode)
            let completion = progressMap[pid]?.completionPercent ?? 0.6  // assume 60% if no data
            let qualityW = 0.4 + completion * 0.6   // 0.4–1.0 based on how much they watched
            for genre in event.genres {
                raw[genre, default: 0] += decay * qualityW
            }
        }
        return normalized(raw)
    }

    var directorWeights: [String: Double] {
        weightedNames(events.flatMap(\.director))
    }

    var castWeights: [String: Double] {
        weightedNames(events.flatMap(\.cast))
    }

    var watchedIds: Set<String> {
        Set(events.map(\.metaId))
    }

    /// Recent distinct titles — seeds for "Because You Watched" shelves.
    var recentTitles: [WatchEvent] {
        var seen = Set<String>()
        return events.filter { seen.insert($0.metaId).inserted }.prefix(5).map { $0 }
    }

    // MARK: - Helpers

    private func weightedNames(_ names: [String]) -> [String: Double] {
        var counts: [String: Double] = [:]
        for n in names { counts[n, default: 0] += 1 }
        return normalized(counts)
    }

    private func normalized(_ dict: [String: Double]) -> [String: Double] {
        guard let max = dict.values.max(), max > 0 else { return dict }
        return dict.mapValues { $0 / max }
    }

    // MARK: - Persistence

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func loadFromDisk() {
        if let data = UserDefaults.standard.data(forKey: eventsKey),
           let saved = try? JSONDecoder().decode([WatchEvent].self, from: data) {
            events = saved
        }
        if let data = UserDefaults.standard.data(forKey: progressKey),
           let saved = try? JSONDecoder().decode([String: PlaybackProgress].self, from: data) {
            progressMap = saved
        }
        if let data = UserDefaults.standard.data(forKey: feedbackKey),
           let saved = try? JSONDecoder().decode([String: WatchFeedback].self, from: data) {
            feedback = saved
        }
    }
}
