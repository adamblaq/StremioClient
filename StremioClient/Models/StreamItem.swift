import Foundation

struct StreamItem: Identifiable, Codable, Hashable {
    var id: String { url ?? infoHash ?? name ?? UUID().uuidString }
    let name: String?
    let title: String?
    let url: String?
    let infoHash: String?
    let behaviorHints: BehaviorHints?

    struct BehaviorHints: Codable, Hashable {
        let notWebReady: Bool?
        let bingeGroup: String?
        let filename: String?
    }

    var streamURL: URL? { url.flatMap(URL.init) }
    var isTorrent: Bool { infoHash != nil }
    var isDirectPlay: Bool { url != nil && !isTorrent }

    var displayName: String { name ?? "Unknown Source" }
    var displayTitle: String { title ?? url ?? infoHash ?? "" }

    /// Quality hint parsed from name (e.g. "4K", "1080p", "720p")
    var quality: String? {
        guard let name else { return nil }
        let markers = ["4K", "2160p", "1080p", "720p", "480p", "HDR", "BluRay", "WEB-DL"]
        return markers.first { name.localizedCaseInsensitiveContains($0) }
    }
}

struct StreamsResponse: Codable {
    let streams: [StreamItem]
}
