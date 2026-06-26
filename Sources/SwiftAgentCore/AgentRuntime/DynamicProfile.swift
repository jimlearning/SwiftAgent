import Foundation

// MARK: - ReasoningLevel

/// Reasoning budget for model generation.
/// Mirrors Apple's FoundationModels reasoning levels (WWDC26).
public enum ReasoningLevel: Sendable, Equatable {
    /// Fast, low-token reasoning for simple tasks.
    case shallow
    /// Balanced reasoning for typical tasks.
    case medium
    /// Deep reasoning for complex multi-step problems.
    case deep
}

// MARK: - Profile Component

/// A single profile definition within a DynamicProfile body.
/// Each case represents a set of instructions and tools for a specific mode.
public struct ProfileComponent: Sendable {
    public var instructions: String?
    public var tools: [any Tool]
    public var model: (any LanguageModel)?
    public var reasoningLevel: ReasoningLevel?

    public init(
        instructions: String? = nil,
        tools: [any Tool] = [],
        model: (any LanguageModel)? = nil,
        reasoningLevel: ReasoningLevel? = nil
    ) {
        self.instructions = instructions
        self.tools = tools
        self.model = model
        self.reasoningLevel = reasoningLevel
    }
}

// MARK: - ProfileBuilder

/// Result builder for declarative profile construction.
/// Mirrors Apple's FoundationModels `DynamicProfile` DSL (WWDC26).
///
/// TYPE-SLOT — placeholder implementation. Full implementation with
/// mode-switching and per-branch model selection arrives when
/// `DynamicProfile` gains runtime support.
@resultBuilder
public enum ProfileBuilder {
    public static func buildBlock(_ components: ProfileComponent...) -> [ProfileComponent] {
        components
    }

    public static func buildEither(first component: ProfileComponent) -> ProfileComponent {
        component
    }

    public static func buildEither(second component: ProfileComponent) -> ProfileComponent {
        component
    }

    public static func buildOptional(_ component: ProfileComponent?) -> ProfileComponent? {
        component
    }
}

// MARK: - DynamicProfile

/// Declarative agent profile with mode-switching support.
/// Mirrors Apple's FoundationModels `DynamicProfile` (WWDC26).
///
/// TYPE-SLOT — the result builder DSL is wired but runtime mode-switching
/// is not yet implemented. Currently resolves to a single `AgentProfile`.
///
/// ```swift
/// let profile = DynamicProfile {
///     ProfileComponent(instructions: "You are a coding assistant.", reasoningLevel: .deep)
/// }
/// ```
public struct DynamicProfile: Sendable {
    public var components: [ProfileComponent]

    public init(@ProfileBuilder components: () -> [ProfileComponent]) {
        self.components = components()
    }

    /// Resolve to a concrete AgentProfile for session initialization.
    /// Currently returns the first component — mode-switching arrives
    /// when DynamicProfile gains runtime support.
    public func resolve() -> AgentProfile? {
        guard let first = components.first else { return nil }
        return AgentProfile(
            name: "Dynamic",
            instructions: first.instructions ?? "",
            tools: first.tools,
            model: first.model,
            permissionMode: .readFiles(paths: []),
            memoryScope: .session
        )
    }
}
