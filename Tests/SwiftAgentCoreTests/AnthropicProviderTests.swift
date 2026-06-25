import Foundation
import XCTest
@testable import SwiftAgentCore

/// Integration tests for AnthropicProvider, its translators, SSE parser,
/// content accumulator, request builder, and retry policy.
///
/// Tests use fixture data and mock channels — no live API calls.
final class AnthropicProviderTests: XCTestCase {

    // MARK: - Helpers

    func makeProvider(modelID: String = "claude-sonnet-4-6") -> AnthropicProvider {
        AnthropicProvider(apiKey: "test-key", modelID: modelID)
    }

    func makeJSON(_ input: some Encodable) -> Data {
        try! JSONEncoder().encode(input)
    }

    func dictFromJSON(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

// MARK: - Task 1: Provider Skeleton & Translation Tests

extension AnthropicProviderTests {

    // MARK: Test 1: Provider initialization and capabilities

    func test_providerInit_storesConfigurationAndReturnsCorrectCapabilities() {
        let provider = AnthropicProvider(
            apiKey: "sk-ant-test",
            baseURL: URL(string: "https://custom.api.com")!,
            modelID: "claude-opus-4-6",
            displayName: "Custom Opus"
        )

        XCTAssertEqual(provider.displayName, "Custom Opus")
        XCTAssertEqual(provider.capabilities.contextWindow, 200_000)
        XCTAssertEqual(provider.capabilities.maxOutputTokens, 32_768)
        XCTAssertTrue(provider.capabilities.supportsStreaming)
        XCTAssertTrue(provider.capabilities.supportsToolUse)
        XCTAssertTrue(provider.capabilities.supportsThinking)

        let executor = provider.makeExecutor()
        XCTAssertNotNil(executor)
        // makeExecutor() returns self — executor's model is the provider
        XCTAssertTrue(executor.model is AnthropicProvider)
    }

    func test_providerInit_unknownModelID_getsDefaultCapabilities() {
        let provider = AnthropicProvider(
            apiKey: "sk-test",
            modelID: "some-custom-model-v7"
        )
        // Falls back to defaults with providerDisplayName set to modelID
        XCTAssertEqual(provider.displayName, "some-custom-model-v7")
        XCTAssertEqual(provider.capabilities.providerDisplayName, "some-custom-model-v7")
        XCTAssertTrue(provider.capabilities.supportsStreaming)
        XCTAssertTrue(provider.capabilities.supportsToolUse)
        XCTAssertFalse(provider.capabilities.supportsThinking)
    }

    func test_providerInit_haikuHasThinkingDisabled() {
        let provider = AnthropicProvider(apiKey: "test-key", modelID: "claude-haiku-4-6")
        XCTAssertFalse(provider.capabilities.supportsThinking)
        XCTAssertEqual(provider.capabilities.maxOutputTokens, 4_096)
    }

    // MARK: Test 2: Transcript translation — basic prompt/response

    func test_transcriptTranslator_basicPromptResponse() throws {
        let transcript = Transcript(entries: [
            .prompt("Hello"),
            .response("Hi there"),
        ])

        let result = AnthropicTranscriptTranslator.translate(transcript, systemPrompt: nil)
        let messages = result.messages

        XCTAssertEqual(messages.count, 2, "Expected 2 messages, got \(messages.count)")
        XCTAssertEqual(result.system as? String, nil)

        // First message: user
        let userMsg = messages[0]
        XCTAssertEqual(userMsg["role"] as? String, "user")
        let userContent = userMsg["content"] as? [[String: Any]]
        XCTAssertEqual(userContent?.count, 1)
        XCTAssertEqual(userContent?[0]["type"] as? String, "text")
        XCTAssertEqual(userContent?[0]["text"] as? String, "Hello")

        // Second message: assistant
        let asstMsg = messages[1]
        XCTAssertEqual(asstMsg["role"] as? String, "assistant")
        let asstContent = asstMsg["content"] as? [[String: Any]]
        XCTAssertEqual(asstContent?.count, 1)
        XCTAssertEqual(asstContent?[0]["type"] as? String, "text")
        XCTAssertEqual(asstContent?[0]["text"] as? String, "Hi there")
    }

    // MARK: Test 3: Transcript translation — tool call

    func test_transcriptTranslator_toolCall() {
        let inputDict: [String: Any] = ["command": "ls", "description": "List files"]
        let inputData = try! JSONSerialization.data(withJSONObject: inputDict)
        let transcript = Transcript(entries: [
            .prompt("List files"),
            .toolCall(id: "toolu_01", name: "Bash", input: inputData),
        ])

        let result = AnthropicTranscriptTranslator.translate(transcript, systemPrompt: nil)
        let messages = result.messages

        XCTAssertEqual(messages.count, 2)

        let toolMsg = messages[1]
        XCTAssertEqual(toolMsg["role"] as? String, "assistant")
        let content = toolMsg["content"] as? [[String: Any]]
        XCTAssertEqual(content?.count, 1)
        let block = content?[0]
        XCTAssertEqual(block?["type"] as? String, "tool_use")
        XCTAssertEqual(block?["id"] as? String, "toolu_01")
        XCTAssertEqual(block?["name"] as? String, "Bash")
        let input = block?["input"] as? [String: Any]
        XCTAssertEqual(input?["command"] as? String, "ls")
        XCTAssertEqual(input?["description"] as? String, "List files")
    }

    // MARK: Test 4: Transcript translation — tool output

    func test_transcriptTranslator_toolOutput() {
        let transcript = Transcript(entries: [
            .prompt("Run command"),
            .toolCall(id: "toolu_02", name: "Bash", input: Data()),
            .toolOutput(id: "toolu_02", output: "result output", isError: false),
        ])

        let result = AnthropicTranscriptTranslator.translate(transcript, systemPrompt: nil)
        let messages = result.messages

        XCTAssertEqual(messages.count, 3)

        let outputMsg = messages[2]
        XCTAssertEqual(outputMsg["role"] as? String, "user")
        let content = outputMsg["content"] as? [[String: Any]]
        XCTAssertEqual(content?.count, 1)
        let block = content?[0]
        XCTAssertEqual(block?["type"] as? String, "tool_result")
        XCTAssertEqual(block?["tool_use_id"] as? String, "toolu_02")
        XCTAssertEqual(block?["content"] as? String, "result output")
        XCTAssertEqual(block?["is_error"] as? Bool, false)
    }

    func test_transcriptTranslator_toolOutputWithError() {
        let transcript = Transcript(entries: [
            .prompt("Run bad command"),
            .toolCall(id: "toolu_03", name: "Bash", input: Data()),
            .toolOutput(id: "toolu_03", output: "command not found", isError: true),
        ])

        let result = AnthropicTranscriptTranslator.translate(transcript, systemPrompt: nil)
        let messages = result.messages

        let outputMsg = messages[2]
        let content = outputMsg["content"] as? [[String: Any]]
        let block = content?[0]
        XCTAssertEqual(block?["is_error"] as? Bool, true)
    }

    // MARK: Test 5: Transcript translation — thinking

    func test_transcriptTranslator_thinking() {
        let transcript = Transcript(entries: [
            .prompt("Think about this"),
            .thinking("Let me reason about this carefully..."),
        ])

        let result = AnthropicTranscriptTranslator.translate(transcript, systemPrompt: nil)
        let messages = result.messages

        XCTAssertEqual(messages.count, 2)

        let thinkingMsg = messages[1]
        XCTAssertEqual(thinkingMsg["role"] as? String, "assistant")
        let content = thinkingMsg["content"] as? [[String: Any]]
        let block = content?[0]
        XCTAssertEqual(block?["type"] as? String, "thinking")
        XCTAssertEqual(block?["thinking"] as? String, "Let me reason about this carefully...")
    }

    // MARK: Test 6: Transcript translation — instruction goes to system, not messages

    func test_transcriptTranslator_instructionBecomesSystem() {
        let transcript = Transcript(entries: [
            .instruction("You are a helpful assistant."),
            .prompt("Hello"),
        ])

        let result = AnthropicTranscriptTranslator.translate(transcript, systemPrompt: nil)
        let messages = result.messages

        // Instruction should NOT be in the messages array
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")

        // system parameter should contain the instruction
        let systemStr = result.system as? String
        XCTAssertEqual(systemStr, "You are a helpful assistant.")
    }

    func test_transcriptTranslator_systemPromptPlusInstruction() {
        let transcript = Transcript(entries: [
            .instruction("Be concise."),
            .prompt("Hello"),
        ])

        let result = AnthropicTranscriptTranslator.translate(
            transcript,
            systemPrompt: "You are Claude."
        )
        let messages = result.messages

        XCTAssertEqual(messages.count, 1)
        // When both external systemPrompt and transcript instructions exist,
        // the system should combine both
        let systemStr = result.system as? String
        XCTAssertNotNil(systemStr)
        XCTAssertTrue(systemStr?.contains("You are Claude.") ?? false)
        XCTAssertTrue(systemStr?.contains("Be concise.") ?? false)
    }

    // MARK: Test 7: Tool translation — basic

    func test_toolTranslator_basicTool() {
        let schema = JSONSchema(
            type: "object",
            properties: [
                "command": JSONSchemaProperty(type: "string", description: "The command"),
                "timeout": JSONSchemaProperty(type: "number", description: "Timeout in seconds"),
            ],
            required: ["command"]
        )
        let tools = [
            RuntimeToolDefinition(name: "Bash", description: "Run a shell command", inputSchema: schema),
        ]

        let result = AnthropicToolTranslator.translate(tools)
        XCTAssertEqual(result.count, 1)

        let toolDict = result[0]
        XCTAssertEqual(toolDict["name"] as? String, "Bash")
        XCTAssertEqual(toolDict["description"] as? String, "Run a shell command")

        let inputSchema = toolDict["input_schema"] as? [String: Any]
        XCTAssertEqual(inputSchema?["type"] as? String, "object")

        let props = inputSchema?["properties"] as? [String: [String: Any]]
        XCTAssertEqual(props?["command"]?["type"] as? String, "string")
        XCTAssertEqual(props?["command"]?["description"] as? String, "The command")
        XCTAssertEqual(props?["timeout"]?["type"] as? String, "number")

        let required = inputSchema?["required"] as? [String]
        XCTAssertEqual(required, ["command"])
    }

    // MARK: Test 8: Tool translation — array items and enum values

    func test_toolTranslator_arrayAndEnumSchemas() {
        let schema = JSONSchema(
            type: "object",
            properties: [
                "filter": JSONSchemaProperty(
                    type: "string",
                    description: "Filter type",
                    enum: ["include", "exclude"]
                ),
                "paths": JSONSchemaProperty(
                    type: "array",
                    description: "File paths",
                    items: JSONSchemaItems(type: "string", description: "A file path")
                ),
            ],
            required: ["filter"],
            additionalProperties: false
        )

        let tools = [
            RuntimeToolDefinition(name: "Search", description: "Search files", inputSchema: schema),
        ]

        let result = AnthropicToolTranslator.translate(tools)
        let inputSchema = result[0]["input_schema"] as? [String: Any]

        // Check top-level schema properties
        XCTAssertEqual(inputSchema?["type"] as? String, "object")
        XCTAssertEqual(inputSchema?["additionalProperties"] as? Bool, false)

        let props = inputSchema?["properties"] as? [String: [String: Any]]

        // Enum property
        let filterProp = props?["filter"]
        XCTAssertEqual(filterProp?["type"] as? String, "string")
        XCTAssertEqual(filterProp?["description"] as? String, "Filter type")
        let enumValues = filterProp?["enum"] as? [String]
        XCTAssertEqual(enumValues, ["include", "exclude"])

        // Array items property
        let pathsProp = props?["paths"]
        XCTAssertEqual(pathsProp?["type"] as? String, "array")
        XCTAssertEqual(pathsProp?["description"] as? String, "File paths")
        let items = pathsProp?["items"] as? [String: Any]
        XCTAssertEqual(items?["type"] as? String, "string")
        XCTAssertEqual(items?["description"] as? String, "A file path")

        let required = inputSchema?["required"] as? [String]
        XCTAssertEqual(required, ["filter"])
    }
}
