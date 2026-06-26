import Foundation

// MARK: - Tool Progress Types

/// Progress data emitted during tool execution.
/// Matches Claude Code's ToolProgressData.
public protocol ToolProgressData: Sendable {
    var type: String { get }
}

/// A progress event for a specific tool call, pairing data with the tool use ID.
/// Matches Claude Code's ToolProgress<P>.
public struct ToolProgress: Sendable {
    public let toolUseID: String
    public let data: any ToolProgressData

    public init(toolUseID: String, data: any ToolProgressData) {
        self.toolUseID = toolUseID
        self.data = data
    }
}

/// Progress stream continuation for tool call progress.
/// Matches Claude Code's ToolCallProgress<P>.
public typealias ToolCallProgress = @Sendable (ToolProgress) -> Void
