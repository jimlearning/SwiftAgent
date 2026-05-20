import Foundation

/// Extended thinking configuration for Claude models.
/// Mirrors Claude Code's thinking config at utils/thinking.ts:10-13.
public enum ThinkingConfig: Sendable, Equatable {
    /// Adaptive thinking — the model decides how much to think.
    case adaptive
    /// Fixed thinking token budget.
    case enabled(budgetTokens: Int)
    /// No extended thinking.
    case disabled
}

extension ThinkingConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case budgetTokens
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "adaptive": self = .adaptive
        case "enabled":
            let budget = try container.decodeIfPresent(Int.self, forKey: .budgetTokens)
            self = .enabled(budgetTokens: budget ?? 0)
        case "disabled": self = .disabled
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown thinking type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .adaptive:
            try container.encode("adaptive", forKey: .type)
        case .enabled(let budgetTokens):
            try container.encode("enabled", forKey: .type)
            try container.encode(budgetTokens, forKey: .budgetTokens)
        case .disabled:
            try container.encode("disabled", forKey: .type)
        }
    }
}
