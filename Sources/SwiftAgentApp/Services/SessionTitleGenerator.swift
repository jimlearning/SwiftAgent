import Foundation

// MARK: - Session Title Generator

/// Generates intelligent session titles matching Claude Code's approach:
/// 1. Instant regex placeholder (first sentence, max 50 chars)
/// 2. Fire-and-forget LLM call for a 3-7 word sentence-case title
public struct SessionTitleGenerator: Sendable {
    private let apiKey: String
    private let baseURL: URL
    private let modelID: String

    public init(apiKey: String, baseURL: URL, modelID: String = "deepseek-chat") {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.modelID = modelID
    }

    // MARK: - Placeholder (instant, no network)

    /// Extract an instant placeholder title from the user's first message.
    /// Returns the first sentence (up to 50 chars), or nil if the text is empty.
    ///
    /// Matches CC's `deriveTitle` in initReplBridge.ts:555-569.
    public func derivePlaceholder(from text: String) -> String? {
        // Strip display/system tags like <system-reminder>, <ide_opened_file>, etc.
        var cleaned = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        // Collapse whitespace
        cleaned = cleaned.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return nil }

        // Extract first sentence via regex (match ., !, or ? followed by whitespace or end)
        let pattern = "^(.*?[.!?])(?:\\s|$)"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
        if let match = regex?.firstMatch(in: cleaned, options: [], range: range),
           let captureRange = Range(match.range(at: 1), in: cleaned) {
            let sentence = String(cleaned[captureRange])
            return truncate(sentence, maxLength: 50)
        }

        // No sentence-ending punctuation found — use the whole text, truncated
        return truncate(cleaned, maxLength: 50)
    }

    private func truncate(_ text: String, maxLength: Int) -> String {
        if text.count <= maxLength { return text }
        let endIndex = text.index(text.startIndex, offsetBy: maxLength)
        return String(text[..<endIndex]) + "\u{2026}" // ellipsis character
    }

    // MARK: - AI Title Generation (fire-and-forget)

    /// Generate a smart title via LLM call.
    /// Returns nil on any failure (designed for fire-and-forget use).
    ///
    /// Uses the Anthropic-compatible Messages API with `deepseek-chat`
    /// for fast, cheap title generation. Timeout: 15 seconds.
    ///
    /// Matches CC's `generateSessionTitle` in utils/sessionTitle.ts.
    public func generateTitle(from conversationText: String) async -> String? {
        let systemPrompt = """
        Generate a concise, sentence-case title (3-7 words) that captures the main \
        topic or goal of this coding session. The title should be clear enough that \
        the user recognizes the session in a list. Use sentence case: capitalize only \
        the first word and proper nouns.

        Return JSON with a single "title" field.

        Good examples:
        {"title": "Fix login button on mobile"}
        {"title": "Add OAuth authentication"}
        {"title": "Debug failing CI tests"}
        {"title": "Refactor API client error handling"}

        Bad (too vague): {"title": "Code changes"}
        Bad (too long): {"title": "Investigate and fix the issue where the login button does not respond on mobile devices"}
        Bad (wrong case): {"title": "Fix Login Button On Mobile"}
        """

        // Tail-slice to last 1000 chars so recent context wins (matching CC)
        let input = String(conversationText.suffix(1000))

        let body: [String: Any] = [
            "model": modelID,
            "max_tokens": 50,
            "stream": false,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": input]
            ]
        ]

        let url = baseURL.appendingPathComponent("anthropic/v1/messages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-06-01", forHTTPHeaderField: "anthropic-version")

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body, options: .sortedKeys) else {
            return nil
        }
        request.httpBody = bodyData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("[SessionTitleGenerator] AI title generation failed: non-200 status")
                return nil
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = (json["content"] as? [[String: Any]])?.first,
                  let text = content["text"] as? String else {
                print("[SessionTitleGenerator] AI title generation failed: unexpected response format")
                return nil
            }

            // Parse the JSON title from the response text
            guard let titleData = text.data(using: .utf8),
                  let titleJSON = try? JSONSerialization.jsonObject(with: titleData) as? [String: String],
                  let title = titleJSON["title"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else {
                print("[SessionTitleGenerator] AI title generation failed: couldn't parse title from response")
                return nil
            }

            return title
        } catch {
            print("[SessionTitleGenerator] AI title generation failed: \(error.localizedDescription)")
            return nil
        }
    }

}
