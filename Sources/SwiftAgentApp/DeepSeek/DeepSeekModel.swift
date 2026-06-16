import Foundation

public enum DeepSeekModel: String, CaseIterable, Sendable {
    case v4Pro = "deepseek-v4-pro"
    case v4Flash = "deepseek-v4-flash"

    public var displayName: String {
        switch self {
        case .v4Pro: return "DeepSeek V4 Pro"
        case .v4Flash: return "DeepSeek V4 Flash"
        }
    }

    public var supportsTemperature: Bool { true }

    public var hasReasoningContent: Bool { false }
}
