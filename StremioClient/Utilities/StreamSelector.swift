import Foundation

/// Parses Torrentio stream metadata and selects the best stream automatically.
struct StreamSelector {

    struct ParsedStream {
        let stream: StreamItem
        let qualityP: Int       // 480 / 720 / 1080 / 2160
        let sizeGB: Double?
        let seeders: Int?
        let isRDCached: Bool    // [RD+] = cached on Real-Debrid, plays instantly
        let isMp4: Bool         // MP4 streams support HTTP progressive playback; MKV does not
    }

    /// Returns the best playable stream using a tiered fallback strategy.
    ///
    /// Tier 1 (ideal):   RD cached · MP4 · ≥ minQualityP · ≤ maxSizeGB
    /// Tier 2 (fallback): RD cached · MP4 · any quality   · ≤ maxSizeGB   (covers shows where MP4 has no "1080p" label)
    /// Tier 3 (last resort): RD cached · any format · ≥ minQualityP · ≤ maxSizeGB  (MKV only — will likely fail for HTTP streaming)
    static func selectBest(from streams: [StreamItem],
                           minQualityP: Int = 1080,
                           maxSizeGB: Double = 15.0) -> StreamItem? {
        let parsed = streams.compactMap { parse($0) }

        func best(_ candidates: [ParsedStream]) -> StreamItem? {
            candidates.sorted { a, b in
                if a.isRDCached != b.isRDCached { return a.isRDCached }
                if a.isMp4 != b.isMp4 { return a.isMp4 }
                let aScore = qualityScore(a.qualityP)
                let bScore = qualityScore(b.qualityP)
                if aScore != bScore { return aScore > bScore }
                return (a.seeders ?? 0) > (b.seeders ?? 0)
            }.first?.stream
        }

        let underSize: (ParsedStream) -> Bool = { $0.sizeGB == nil || $0.sizeGB! <= maxSizeGB }

        // Tier 1: MP4 + quality threshold (the happy path)
        if let t1 = best(parsed.filter { $0.isRDCached && $0.isMp4 && $0.qualityP >= minQualityP && underSize($0) }) {
            return t1
        }
        // Tier 2: MP4 at any quality (handles shows where MP4 streams lack a "1080p" label)
        if let t2 = best(parsed.filter { $0.isRDCached && $0.isMp4 && underSize($0) }) {
            return t2
        }
        // Tier 3: Non-MP4 (MKV etc.) — may fail for HTTP streaming but better than nothing
        if let t3 = best(parsed.filter { $0.isRDCached && $0.qualityP >= minQualityP && underSize($0) }) {
            return t3
        }
        // Tier 4: Any RD-cached stream regardless of size — user has large files and wants to play
        if let t4 = best(parsed.filter { $0.isRDCached }) {
            return t4
        }
        return nil
    }

    /// All streams parsed with metadata, useful for displaying the stream picker.
    static func parseAll(_ streams: [StreamItem]) -> [ParsedStream] {
        streams.compactMap { parse($0) }
    }

    // MARK: - Private

    private static func qualityScore(_ p: Int) -> Int {
        switch p {
        case 1080: return 3   // preferred — great quality, manageable size
        case 2160: return 2   // 4K is fine but deprioritised to stay under size limit
        case 720:  return 1
        default:   return 0
        }
    }

    static func parse(_ stream: StreamItem) -> ParsedStream? {
        guard stream.isDirectPlay else { return nil }

        let name  = stream.name  ?? ""
        let title = stream.title ?? ""
        let combined = name + " " + title

        // Quality
        let qualityP: Int
        if combined.contains("2160p") || combined.lowercased().contains("4k") { qualityP = 2160 }
        else if combined.contains("1080p") { qualityP = 1080 }
        else if combined.contains("720p")  { qualityP = 720  }
        else if combined.contains("480p")  { qualityP = 480  }
        else { qualityP = 0 }

        // File size — Torrentio embeds "💾 X.XX GB" or "💾 XXX MB" in title
        let sizeGB = parseSize(from: title)

        // Seeders — Torrentio embeds "👥 NNNN" in title
        let seeders = parseNumber(emoji: "👥", from: title)

        // [RD+] = cached on Real-Debrid (plays immediately without wait)
        let isRDCached = combined.contains("[RD+]")

        // MP4 streams work with AVPlayer HTTP streaming; MKV is file-local only on iOS
        let isMp4 = stream.url?.lowercased().hasSuffix(".mp4") == true

        return ParsedStream(
            stream: stream,
            qualityP: qualityP,
            sizeGB: sizeGB,
            seeders: seeders,
            isRDCached: isRDCached,
            isMp4: isMp4
        )
    }

    private static func parseSize(from text: String) -> Double? {
        // Match "💾 8.73 GB"
        if let m = text.firstMatch(pattern: #"💾\s*([\d.]+)\s*GB"#),
           let n = Double(m) { return n }
        // Match "💾 897 MB"
        if let m = text.firstMatch(pattern: #"💾\s*([\d.]+)\s*MB"#),
           let n = Double(m) { return n / 1024 }
        return nil
    }

    private static func parseNumber(emoji: String, from text: String) -> Int? {
        guard let m = text.firstMatch(pattern: "\(emoji)\\s*(\\d+)"),
              let n = Int(m) else { return nil }
        return n
    }
}

private extension String {
    /// Returns the content of the first capture group of a regex match.
    func firstMatch(pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: self, range: NSRange(self.startIndex..., in: self)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: self)
        else { return nil }
        return String(self[range])
    }
}
