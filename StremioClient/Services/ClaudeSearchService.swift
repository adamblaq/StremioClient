import Foundation

/// Handles multi-turn conversational search powered by Claude.
/// The view owns message state; this actor just provides the API call.
actor ClaudeSearchService {
    static let shared = ClaudeSearchService()

    private let session = URLSession.shared

    private let systemPrompt = """
    You are a friendly, knowledgeable movie and TV show discovery assistant. \
    Help users find what they want to watch through natural conversation.

    You MUST respond with ONLY valid JSON — no markdown, no preamble, no explanation outside the JSON:
    {
      "message": "Your conversational response here",
      "suggestions": [
        {"title": "Exact Title", "year": "2023", "type": "movie", "reason": "One-sentence reason"}
      ]
    }

    Rules:
    - "type" must be exactly "movie" or "series"
    - Include 3–6 suggestions when the user's request is clear; 0 when you need to ask a clarifying question
    - Only suggest real titles with a strong reputation (IMDB 6.5+)
    - "reason" should explain specifically why this title matches what the user asked for
    - "message" should be warm, enthusiastic, and reference the user's exact words
    - If the user wants to refine (e.g. "more recent", "something darker"), adjust accordingly
    - Do not repeat suggestions already mentioned in the conversation
    """

    // MARK: - Public

    struct Response {
        let text: String
        let suggestions: [ClaudeRecommendation]
    }

    /// Send a conversation to Claude and get a response with optional title suggestions.
    /// - Parameter history: Full conversation so far as (role, text) pairs.
    func respond(
        to history: [(role: String, text: String)],
        claudeKey: String
    ) async throws -> Response {
        guard !claudeKey.isEmpty else { throw ClaudeSearchError.missingKey }
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw ClaudeSearchError.badURL
        }

        let apiMessages = history.map { ["role": $0.role, "content": $0.text] }
        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": apiMessages
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            throw ClaudeSearchError.encodingFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(claudeKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = bodyData
        request.timeoutInterval = 30

        let (data, _) = try await session.data(for: request)

        struct ClaudeEnvelope: Codable {
            struct Content: Codable { let type: String; let text: String }
            let content: [Content]
        }

        guard let envelope = try? JSONDecoder().decode(ClaudeEnvelope.self, from: data),
              let rawText = envelope.content.first?.text
        else {
            throw ClaudeSearchError.badResponse
        }

        return parse(rawText)
    }

    // MARK: - TMDB resolution

    /// Resolves suggestion titles to MetaItems in parallel via TMDB.
    func resolve(
        suggestions: [ClaudeRecommendation],
        tmdbKey: String
    ) async -> [ClaudeRecommendation] {
        guard !tmdbKey.isEmpty else { return suggestions }
        return await withTaskGroup(of: ClaudeRecommendation.self) { group in
            for rec in suggestions {
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
            return out.sorted { a, b in
                // Preserve original order
                let ai = suggestions.firstIndex(where: { $0.id == a.id }) ?? 0
                let bi = suggestions.firstIndex(where: { $0.id == b.id }) ?? 0
                return ai < bi
            }
        }
    }

    // MARK: - Parsing

    private func parse(_ text: String) -> Response {
        var json = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip code fences
        if json.hasPrefix("```") {
            json = json.components(separatedBy: "\n")
                .dropFirst().dropLast().joined(separator: "\n")
        }

        // Extract first JSON object
        guard let start = json.firstIndex(of: "{"),
              let end = json.lastIndex(of: "}")
        else {
            return Response(text: text, suggestions: [])
        }
        let objStr = String(json[start...end])

        struct Raw: Codable {
            let message: String
            let suggestions: [RawSuggestion]?

            struct RawSuggestion: Codable {
                let title: String
                let year: String?
                let type: String?
                let reason: String
            }
        }

        guard let raw = try? JSONDecoder().decode(Raw.self, from: Data(objStr.utf8)) else {
            return Response(text: text, suggestions: [])
        }

        let suggestions = (raw.suggestions ?? []).map {
            ClaudeRecommendation(
                id: UUID(),
                title: $0.title,
                year: $0.year,
                type: $0.type ?? "movie",
                reason: $0.reason,
                resolvedItem: nil
            )
        }

        return Response(text: raw.message, suggestions: suggestions)
    }
}

enum ClaudeSearchError: LocalizedError {
    case missingKey, badURL, encodingFailed, badResponse

    var errorDescription: String? {
        switch self {
        case .missingKey:      return "No Claude API key configured."
        case .badURL:          return "Invalid API endpoint."
        case .encodingFailed:  return "Failed to encode request."
        case .badResponse:     return "Unexpected response from Claude."
        }
    }
}
