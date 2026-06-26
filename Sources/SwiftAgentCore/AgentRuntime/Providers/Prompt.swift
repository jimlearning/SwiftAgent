import Foundation

// MARK: - PromptRepresentable

/// Types that can be converted into a Prompt for a language model session.
/// Mirrors Apple's `PromptRepresentable` protocol (FoundationModels, iOS 27+).
public protocol PromptRepresentable: Sendable {
    /// Resolve this value into a Prompt.
    func resolvePrompt() -> Prompt
}

// MARK: - Prompt

/// A typed prompt abstraction wrapping a String with future support for
/// multi-modal content, file attachments, and structured generation guides.
/// Mirrors Apple's `Prompt` struct (FoundationModels, iOS 27+).
///
/// Currently String-backed; Attachment and @Guide support arrive in future phases.
public struct Prompt: Sendable, PromptRepresentable {
    /// The prompt text content.
    public let content: String

    public init(_ content: String) {
        self.content = content
    }

    public func resolvePrompt() -> Prompt { self }
}

// MARK: - String Conformance

extension String: PromptRepresentable {
    public func resolvePrompt() -> Prompt {
        Prompt(self)
    }
}

// MARK: - Prompt Conformance

extension Prompt: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.content = value
    }
}

extension Prompt: CustomStringConvertible {
    public var description: String { content }
}

// MARK: - PromptBuilder

/// Result builder for composable prompt construction.
/// Mirrors Apple's `@PromptBuilder` (FoundationModels, iOS 27+).
@resultBuilder
public enum PromptBuilder {
    public static func buildBlock(_ components: String...) -> String {
        components.joined(separator: "\n")
    }

    public static func buildBlock(_ components: PromptRepresentable...) -> Prompt {
        Prompt(components.map { $0.resolvePrompt().content }.joined(separator: "\n"))
    }

    public static func buildExpression(_ expression: String) -> String {
        expression
    }

    public static func buildExpression(_ expression: some PromptRepresentable) -> Prompt {
        expression.resolvePrompt()
    }

    public static func buildOptional(_ component: Prompt?) -> Prompt {
        component ?? Prompt("")
    }

    public static func buildEither(first: Prompt) -> Prompt {
        first
    }

    public static func buildEither(second: Prompt) -> Prompt {
        second
    }

    public static func buildArray(_ components: [Prompt]) -> Prompt {
        Prompt(components.map(\.content).joined(separator: "\n"))
    }
}

extension Prompt {
    /// Create a prompt using the `@PromptBuilder` result builder.
    public init(@PromptBuilder _ builder: () -> Prompt) {
        self = builder()
    }
}

// MARK: - ImageAttachmentContent

/// Image-specific attachment metadata for multimodal prompting.
/// Mirrors Apple's `ImageAttachmentContent` (FoundationModels, iOS 27+).
public struct ImageAttachmentContent: Sendable {
    public enum Format: String, Sendable {
        case png
        case jpeg
        case gif
        case webp
    }

    public enum ImageDetail: String, Sendable {
        case low
        case high
        case auto
    }

    /// Raw image data.
    public let data: Data
    /// Image format.
    public let format: Format
    /// Optional detail level hint for the model.
    public let detail: ImageDetail?

    public init(data: Data, format: Format, detail: ImageDetail? = nil) {
        self.data = data
        self.format = format
        self.detail = detail
    }
}

// MARK: - PromptAttachment

/// A multimodal attachment that can accompany a Prompt.
/// Mirrors Apple's `Transcript.Attachment` concept (FoundationModels, iOS 27+).
/// Renamed from `Attachment` to avoid collision with the existing `Attachment` type.
public struct PromptAttachment: Sendable {
    public enum Content: Sendable {
        case image(ImageAttachmentContent)
        case file(Data, mimeType: String, filename: String?)
        case url(URL)
    }

    public let content: Content

    public init(content: Content) {
        self.content = content
    }
}
