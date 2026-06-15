import Foundation

/// DeepSeek model identifiers for the app UI.
/// Only four fixed models are supported — no custom model names allowed (anti-pattern #22).
public enum DeepSeekModel: String, CaseIterable, Sendable {
    case v3 = "deepseek-chat"
    case r1 = "deepseek-reasoner"
    case v3_0324 = "deepseek-chat-0324"
    case coderV2 = "deepseek-coder-v2"

    /// Display name shown in the model picker menu.
    public var displayName: String {
        switch self {
        case .v3: return "DeepSeek-V3"
        case .r1: return "DeepSeek-R1"
        case .v3_0324: return "DeepSeek-V3-0324"
        case .coderV2: return "DeepSeek-Coder-V2"
        }
    }

    /// Whether this model supports the `temperature` parameter.
    /// R1 (reasoner) does not support temperature (per §11.3).
    public var supportsTemperature: Bool {
        switch self {
        case .r1: return false
        case .v3, .v3_0324, .coderV2: return true
        }
    }

    /// Whether this model returns `reasoning_content` (thinking chain).
    public var hasReasoningContent: Bool {
        switch self {
        case .r1: return true
        case .v3, .v3_0324, .coderV2: return false
        }
    }
}
