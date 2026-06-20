import Foundation
import SwiftAgentCore

// MARK: - Provider Registry

/// Discovers, validates, and provides access to all configured LLM providers.
///
/// The registry scans the environment for API keys and creates the
/// appropriate provider instances. It is the single source of truth
/// for which providers are available at runtime.
///
/// Usage:
/// ```swift
/// let registry = ProviderRegistry()
/// let provider = registry.provider(for: "deepseek-v4-pro")
/// let allModels = registry.allModels  // Flat list for UI pickers
/// ```
@MainActor
public final class ProviderRegistry: ObservableObject {

    /// All configured providers, keyed by provider ID.
    @Published public private(set) var providers: [String: any LLMProvider] = [:]

    /// The default provider (first configured provider found).
    @Published public private(set) var defaultProvider: (any LLMProvider)?

    /// Flat list of all available models across all providers.
    @Published public private(set) var allModels: [ResolvedModel] = []

    // MARK: - Init

    /// Discover providers from the environment. Non-fatal — providers
    /// without credentials are silently skipped.
    public init() {
        discover()
    }

    // MARK: - Discovery

    /// Scan for all supported providers in priority order.
    private func discover() {
        var discovered: [String: any LLMProvider] = [:]

        // 1. Anthropic (native)
        if let anthropic = AnthropicProvider() {
            discovered[anthropic.providerID] = anthropic
        }

        // 2. DeepSeek (Anthropic-compatible)
        if let deepseek = DeepSeekProvider() {
            discovered[deepseek.providerID] = deepseek
        }

        // 3. OpenAI (stub — only if key present)
        if let openai = OpenAIProvider() {
            discovered[openai.providerID] = openai
        }

        self.providers = discovered
        self.defaultProvider = discovered.first?.value

        // Build flat model list
        self.allModels = buildModelList(from: discovered)
    }

    // MARK: - Lookup

    /// Find the provider that serves the given model ID.
    /// Returns `nil` if no configured provider supports this model.
    public func provider(for modelID: String) -> (any LLMProvider)? {
        for (_, provider) in providers {
            if provider.availableModels.contains(where: { $0.id == modelID }) {
                return provider
            }
        }
        // Fallback: if the modelID matches a provider ID, return that provider
        return providers[modelID]
    }

    /// Find the provider by its ID (e.g. `"anthropic"`, `"deepseek"`).
    public func provider(byID providerID: String) -> (any LLMProvider)? {
        providers[providerID]
    }

    /// Get `ModelInfo` for a given model ID, or `nil`.
    public func modelInfo(for modelID: String) -> ModelInfo? {
        for (_, provider) in providers {
            if let info = provider.availableModels.first(where: { $0.id == modelID }) {
                return info
            }
        }
        return nil
    }

    // MARK: - All Models

    /// Build a flat, deduplicated list of all available models.
    private func buildModelList(from providers: [String: any LLMProvider]) -> [ResolvedModel] {
        var seen: Set<String> = []
        var result: [ResolvedModel] = []

        for (_, provider) in providers {
            for model in provider.availableModels {
                guard !seen.contains(model.id) else { continue }
                seen.insert(model.id)
                result.append(ResolvedModel(
                    modelInfo: model,
                    providerID: provider.providerID,
                    providerName: provider.displayName
                ))
            }
        }

        return result.sorted { $0.modelInfo.displayName < $1.modelInfo.displayName }
    }
}

// MARK: - Resolved Model

/// A model resolved to its provider — suitable for UI pickers and model selection.
public struct ResolvedModel: Identifiable, Sendable, Equatable {
    public var id: String { modelInfo.id }
    public let modelInfo: ModelInfo
    public let providerID: String
    public let providerName: String

    public init(modelInfo: ModelInfo, providerID: String, providerName: String) {
        self.modelInfo = modelInfo
        self.providerID = providerID
        self.providerName = providerName
    }

    /// Display string: "Claude Sonnet 4.6 (Anthropic)"
    public var displayLabel: String {
        "\(modelInfo.displayName) (\(providerName))"
    }
}
