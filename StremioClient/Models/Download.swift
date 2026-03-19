import Foundation

struct Download: Identifiable, Codable {
    let id: UUID
    let metaId: String
    let metaType: String
    let title: String
    let posterURL: String?
    let sourceURL: String       // Pre-resolved CDN URL
    var status: Status
    var progress: Double
    var localPath: String?
    let createdAt: Date
    // Series-only — nil for movies
    let season: Int?
    let episode: Int?
    let episodeTitle: String?
    // Progress detail
    var downloadedBytes: Int64
    var totalBytes: Int64
    var speedBytesPerSecond: Double

    enum Status: String, Codable {
        case queued, downloading, paused, completed, failed
    }

    init(meta: MetaItem, resolvedURL: URL, episode: MetaItem.Video? = nil) {
        self.id = UUID()
        self.metaId = meta.id
        self.metaType = meta.type ?? "movie"
        self.title = meta.name
        self.posterURL = meta.poster
        self.sourceURL = resolvedURL.absoluteString
        self.status = .queued
        self.progress = 0
        self.localPath = nil
        self.createdAt = Date()
        self.season = episode?.season
        self.episode = episode?.episode
        self.episodeTitle = episode.flatMap { $0.name ?? $0.title }
        self.downloadedBytes = 0
        self.totalBytes = 0
        self.speedBytesPerSecond = 0
    }

    /// Creates a fresh download record re-using the same CDN URL, for retry.
    init(retrying other: Download) {
        self.id = UUID()
        self.metaId = other.metaId
        self.metaType = other.metaType
        self.title = other.title
        self.posterURL = other.posterURL
        self.sourceURL = other.sourceURL
        self.status = .queued
        self.progress = 0
        self.localPath = nil
        self.createdAt = Date()
        self.season = other.season
        self.episode = other.episode
        self.episodeTitle = other.episodeTitle
        self.downloadedBytes = 0
        self.totalBytes = 0
        self.speedBytesPerSecond = 0
    }

    var displayTitle: String {
        guard let s = season, let e = episode else { return title }
        let ep = episodeTitle.map { " — \($0)" } ?? ""
        return "\(title) S\(s)E\(e)\(ep)"
    }

    var downloadedMB: Double { Double(downloadedBytes) / 1_048_576 }
    var totalMB: Double { Double(totalBytes) / 1_048_576 }
    var speedMBps: Double { speedBytesPerSecond / 1_048_576 }

    var localFileURL: URL? {
        guard let path = localPath else { return nil }
        return URL(fileURLWithPath: path)
    }

    var isPlayable: Bool { status == .completed && localFileURL != nil }
}
