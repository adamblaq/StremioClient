import Foundation

// MARK: - Data models

struct ClaudeRecommendation: Identifiable, Codable {
    let id: UUID
    let title: String
    let year: String?
    let type: String        // "movie" or "series"
    let reason: String
    var resolvedItem: MetaItem?   // populated after TMDB resolution
}

struct ClaudeCache: Codable {
    let recommendations: [ClaudeRecommendation]
    let generatedAt: Date
    var isExpired: Bool { Date().timeIntervalSince(generatedAt) > 7 * 86_400 }  // 7 days
}

// MARK: - Service

actor ClaudeRecommendationService {
    static let shared = ClaudeRecommendationService()

    private let cacheKey = "claudeRecCache"
    private let session  = URLSession.shared

    // MARK: - Public

    /// Returns cached recommendations if fresh, otherwise generates new ones.
    func recommendations(
        history: WatchHistoryManager,
        claudeKey: String,
        tmdbKey: String
    ) async -> [ClaudeRecommendation] {
        guard !claudeKey.isEmpty else { return [] }

        // Return cache if still fresh
        if let cache = loadCache(), !cache.isExpired {
            return cache.recommendations
        }

        return await generate(history: history, claudeKey: claudeKey, tmdbKey: tmdbKey)
    }

    /// Force-regenerates recommendations (ignores cache).
    func refresh(
        history: WatchHistoryManager,
        claudeKey: String,
        tmdbKey: String
    ) async -> [ClaudeRecommendation] {
        guard !claudeKey.isEmpty else { return [] }
        return await generate(history: history, claudeKey: claudeKey, tmdbKey: tmdbKey)
    }

    // MARK: - Generation

    private func generate(
        history: WatchHistoryManager,
        claudeKey: String,
        tmdbKey: String
    ) async -> [ClaudeRecommendation] {
        let prompt = buildPrompt(history: history)

        guard let rawRecs = await callClaude(prompt: prompt, apiKey: claudeKey) else {
            return []
        }

        // Resolve IMDB IDs via TMDB if key available
        var resolved = rawRecs
        if !tmdbKey.isEmpty {
            resolved = await withTaskGroup(of: ClaudeRecommendation.self) { group in
                for rec in rawRecs {
                    group.addTask {
                        var r = rec
                        r.resolvedItem = await TMDBService.shared.searchMetaItem(
                            title: rec.title, year: rec.year, type: rec.type, apiKey: tmdbKey
                        )
                        return r
                    }
                }
                var out: [ClaudeRecommendation] = []
                for await r in group { out.append(r) }
                return out
            }
        }

        // Filter out items user has already watched
        let watched = history.watchedIds
        resolved = resolved.filter { rec in
            guard let item = rec.resolvedItem else { return true }  // keep unresolved
            return !watched.contains(item.id)
        }

        let cache = ClaudeCache(recommendations: resolved, generatedAt: Date())
        saveCache(cache)
        return resolved
    }

    // MARK: - Prompt

    private func buildPrompt(history: WatchHistoryManager) -> String {
        let recents = history.recentTitles.prefix(20)
        guard !recents.isEmpty else { return "" }

        let historyLines = recents.map { event -> String in
            var line = "- \(event.name)"
            if let s = event.season, let e = event.episode {
                line += " (S\(s)E\(e))"
            }
            if !event.genres.isEmpty {
                line += " [\(event.genres.prefix(3).joined(separator: ", "))]"
            }
            let completion = history.completionPercent(metaId: event.metaId, season: event.season, episode: event.episode)
            if completion > 0 {
                line += " — watched \(Int(completion * 100))%"
            }
            switch history.feedback[event.metaId] {
            case .liked:    line += " 👍"
            case .disliked: line += " 👎"
            case nil: break
            }
            return line
        }.joined(separator: "\n")

        let likedGenres = history.genreWeights
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map(\.key)
            .joined(separator: ", ")

        return """
        You are a world-class film and TV recommendation engine with deep knowledge of cinema.

        This user's watch history (most recent first):
        \(historyLines)

        Their top genres by affinity: \(likedGenres)

        Recommend exactly 15 titles they haven't seen yet that they would love. Be specific about WHY based on their actual history — reference titles they've watched.

        Rules:
        - Only titles with IMDB rating 7.0+ (or critically acclaimed)
        - Mix movies and series proportionally to their history
        - Include some variety — don't just recommend the same genre 15 times
        - Reasons must reference their specific watch history, not be generic

        Respond with ONLY a valid JSON array, no other text:
        [
          {
            "title": "Exact Title",
            "year": "2019",
            "type": "movie",
            "reason": "Because you loved X, this shares..."
          }
        ]
        """
    }

    // MARK: - Claude API call

    private func callClaude(prompt: String, apiKey: String) async -> [ClaudeRecommendation]? {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return nil }

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 2048,
            "messages": [["role": "user", "content": prompt]]
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        print("[Claude] ===== PROMPT =====\n\(prompt)\n===================")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = bodyData
        request.timeoutInterval = 30

        guard let (data, _) = try? await session.data(for: request) else { return nil }

        // Parse Claude response envelope
        struct ClaudeResponse: Codable {
            struct Content: Codable { let type: String; let text: String }
            let content: [Content]
        }
        guard let response = try? JSONDecoder().decode(ClaudeResponse.self, from: data),
              let text = response.content.first?.text
        else {
            print("[Claude] Failed to decode response: \(String(data: data, encoding: .utf8) ?? "?")")
            return nil
        }
        print("[Claude] ===== RESPONSE =====\n\(text)\n=====================")

        return parseRecommendations(from: text)
    }

    // MARK: - JSON parsing

    private func parseRecommendations(from text: String) -> [ClaudeRecommendation]? {
        // Strip markdown code fences if present
        var json = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if json.hasPrefix("```") {
            json = json
                .components(separatedBy: "\n")
                .dropFirst()          // drop ```json line
                .dropLast()           // drop closing ```
                .joined(separator: "\n")
        }

        // Extract first JSON array
        guard let start = json.firstIndex(of: "["),
              let end = json.lastIndex(of: "]")
        else { return nil }
        let arrayStr = String(json[start...end])

        struct Raw: Codable {
            let title: String
            let year: String?
            let type: String?
            let reason: String
        }
        guard let raws = try? JSONDecoder().decode([Raw].self, from: Data(arrayStr.utf8))
        else { return nil }

        return raws.map {
            ClaudeRecommendation(
                id: UUID(),
                title: $0.title,
                year: $0.year,
                type: $0.type ?? "movie",
                reason: $0.reason,
                resolvedItem: nil
            )
        }
    }

    // MARK: - Cache persistence

    private func saveCache(_ cache: ClaudeCache) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    private func loadCache() -> ClaudeCache? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(ClaudeCache.self, from: data)
    }
}
