import Foundation

// MARK: - Instructions

/// System-level instructions that guide a language model's behavior.
/// Mirrors Apple's `Instructions` struct (FoundationModels, iOS 27+).
///
/// Supports both static instructions (plain string) and dynamic instructions
/// that can be resolved at runtime from context.
public struct Instructions: Sendable {
    /// The instruction content.
    public let content: String

    public init(_ content: String) {
        self.content = content
    }
}

// MARK: - String Conformance

extension Instructions: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.content = value
    }
}

extension Instructions: CustomStringConvertible {
    public var description: String { content }
}

// MARK: - InstructionsBuilder

/// Result builder for composable instructions construction.
/// Mirrors Apple's `@InstructionsBuilder` (FoundationModels, iOS 27+).
@resultBuilder
public enum InstructionsBuilder {
    public static func buildBlock(_ components: String...) -> String {
        components.joined(separator: "\n")
    }

    public static func buildBlock(_ components: Instructions...) -> Instructions {
        Instructions(components.map(\.content).joined(separator: "\n"))
    }

    public static func buildExpression(_ expression: String) -> String {
        expression
    }

    public static func buildExpression(_ expression: Instructions) -> Instructions {
        expression
    }

    public static func buildOptional(_ component: Instructions?) -> Instructions {
        component ?? Instructions("")
    }

    public static func buildEither(first: Instructions) -> Instructions {
        first
    }

    public static func buildEither(second: Instructions) -> Instructions {
        second
    }

    public static func buildArray(_ components: [Instructions]) -> Instructions {
        Instructions(components.map(\.content).joined(separator: "\n"))
    }
}

extension Instructions {
    /// Create instructions using the `@InstructionsBuilder` result builder.
    public init(@InstructionsBuilder _ builder: () -> Instructions) {
        self = builder()
    }
}
