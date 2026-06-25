import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Constructs URLRequest objects for the Anthropic Messages API.
/// Combines Transcript translation, tool translation, and header assembly
/// into a single POST /v1/messages request.
struct AnthropicRequestBuilder: Sendable {

    /// Build a URLRequest for the Anthropic Messages API streaming endpoint.
    ///
    /// - Parameters:
    ///   - transcript: Conversation history to include.
    ///   - tools: Available tool definitions.
    ///   - options: Generation configuration.
    ///   - systemPrompt: External system prompt string.
    ///   - apiKey: Anthropic API key.
    ///   - baseURL: Anthropic API base URL.
    ///   - modelID: Model identifier for the API.
    /// - Returns: A configured URLRequest ready to execute.
    /// - Throws: `AgentRuntimeError.invalidResponse` if the body cannot be JSON-encoded.
    static func build(
        transcript: Transcript,
        tools: [RuntimeToolDefinition],
        options: GenerationOptions,
        systemPrompt: String?,
        apiKey: String,
        baseURL: URL,
        modelID: String
    ) throws -> URLRequest {
        let (messages, system) = AnthropicTranscriptTranslator.translate(transcript, systemPrompt: systemPrompt)
        let toolDefs = tools.isEmpty ? nil : AnthropicToolTranslator.translate(tools)

        // Build request body
        var body: [String: Any] = [
            "model": modelID,
            "max_tokens": options.maxTokens ?? 8_192,
            "stream": true,
            "messages": messages,
        ]

        if let system {
            body["system"] = system
        }

        if let toolDefs {
            body["tools"] = toolDefs
        }

        // Thinking budget
        if let budget = options.reasoningBudget, budget > 0 {
            body["thinking"] = ["type": "enabled", "budget_tokens": budget]
        }

        // Metadata
        body["metadata"] = ["user_id": claudeCodeMetadataUserID()]

        // Construct URL
        let url = baseURL.appendingPathComponent("v1/messages")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 600

        // Headers
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("fine-grained-tool-streaming-2025-05-14", forHTTPHeaderField: "anthropic-beta")
        request.setValue("true", forHTTPHeaderField: "anthropic-dangerous-direct-browser-access")
        request.setValue("arm64", forHTTPHeaderField: "x-stainless-arch")
        request.setValue("js", forHTTPHeaderField: "x-stainless-lang")
        request.setValue("MacOS", forHTTPHeaderField: "x-stainless-os")
        request.setValue("0.94.0", forHTTPHeaderField: "x-stainless-package-version")
        request.setValue("0", forHTTPHeaderField: "x-stainless-retry-count")
        request.setValue("node", forHTTPHeaderField: "x-stainless-runtime")
        request.setValue("v24.3.0", forHTTPHeaderField: "x-stainless-runtime-version")

        // Encode body — surface failure instead of silently sending nil body
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body, options: .sortedKeys) else {
            throw AgentRuntimeError.invalidResponse(reason: "Failed to encode request body to JSON")
        }
        request.httpBody = bodyData

        return request
    }

    // MARK: - Private Helpers

    private static func claudeCodeMetadataUserID() -> String {
        let deviceID = stableDeviceID()
        let sessionID = UUID().uuidString
        return "{\"device_id\":\"\(deviceID)\",\"account_uuid\":\"\",\"session_id\":\"\(sessionID)\"}"
    }

    private static func stableDeviceID() -> String {
        let raw = [
            NSUserName(),
            Host.current().localizedName ?? "",
            FileManager.default.homeDirectoryForCurrentUser.path,
        ].joined(separator: "|")
        let data = Data(raw.utf8)
        #if canImport(CryptoKit)
        let digest = CryptoKit.SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
        #else
        var hash: UInt64 = 14695981039346656037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(format: "%016llx", hash)
        #endif
    }
}
