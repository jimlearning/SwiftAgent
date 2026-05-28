import Foundation

/// Standalone fuzzy string matching engine extracted from TermKit's
/// `SimpleCommandProvider.calculateFuzzyMatch`, adapted for the inline popup.
///
/// Scoring tiers:
/// - 1.0 — exact match (case-insensitive)
/// - 0.9 — prefix match
/// - 0.7 — contains match (substring anywhere)
/// - ~0.5 * coverage — ordered subsequence (all query chars appear in order)
/// - 0.0 — no match
public struct FuzzyMatcher {

    /// Result of a fuzzy match query.
    public struct MatchResult: Sendable {
        /// Relevance score from 0.0 (no match) to 1.0 (exact match).
        public let score: Float
        /// Indices within `text` where query characters matched (for highlight rendering).
        public let positions: [Int]

        public init(score: Float, positions: [Int]) {
            self.score = score
            self.positions = positions
        }

        /// Convenience for "no match".
        public static let none = MatchResult(score: 0, positions: [])
    }

    /// Calculate a fuzzy match score and highlight positions for `query` against `text`.
    ///
    /// The search is case-insensitive. Returns `.none` if there is no match.
    public static func match(query: String, text: String) -> MatchResult {
        if query.isEmpty { return MatchResult(score: 1.0, positions: []) }
        if text.isEmpty { return .none }

        let queryLower = query.lowercased()
        let textLower = text.lowercased()

        // Exact match — highest possible score
        if textLower == queryLower {
            let positions = Array(0..<text.count)
            return MatchResult(score: 1.0, positions: positions)
        }

        // Prefix match — high score
        if textLower.hasPrefix(queryLower) {
            let positions = Array(0..<queryLower.count)
            return MatchResult(score: 0.9, positions: positions)
        }

        // Contains (substring) match — medium score
        if let range = textLower.range(of: queryLower) {
            let start = textLower.distance(from: textLower.startIndex, to: range.lowerBound)
            let positions = Array(start..<(start + queryLower.count))
            return MatchResult(score: 0.7, positions: positions)
        }

        // Ordered-subsequence fuzzy match — all query characters appear in text in order
        var queryIdx = queryLower.startIndex
        var matchPositions: [Int] = []
        var textPos = 0

        for char in textLower {
            if queryIdx < queryLower.endIndex, char == queryLower[queryIdx] {
                matchPositions.append(textPos)
                queryIdx = queryLower.index(after: queryIdx)
            }
            textPos += 1
        }

        if matchPositions.count == queryLower.count {
            // Scale by coverage ratio — fewer gaps = higher score
            let score = Float(matchPositions.count) / Float(text.count) * 0.5
            return MatchResult(score: score, positions: matchPositions)
        }

        return .none
    }
}
