import Testing
import Foundation
@testable import SwiftAgentCore

struct MCPMessageCoderTests {
    @Test
    func encodeDecodeRequest() throws {
        let msg = MCPMessage.request(id: 1, method: "tools/list", params: nil)
        let data = try MessageCoder.encode(msg)
        let decoded = try MessageCoder.decode(data)
        switch decoded {
        case .request(let id, let method, let params):
            #expect(id == 1)
            #expect(method == "tools/list")
            #expect(params == nil)
        default:
            #expect(Bool(false), "Expected request")
        }
    }

    @Test
    func encodeDecodeResponse() throws {
        let msg = MCPMessage.response(id: 2, result: ["name": .string("test")])
        let data = try MessageCoder.encode(msg)
        let decoded = try MessageCoder.decode(data)
        switch decoded {
        case .response(let id, let result):
            #expect(id == 2)
            #expect(result?["name"] == .string("test"))
        default:
            #expect(Bool(false), "Expected response")
        }
    }

    @Test
    func encodeDecodeError() throws {
        let msg = MCPMessage.error(id: 3, code: -32601, message: "Method not found")
        let data = try MessageCoder.encode(msg)
        let decoded = try MessageCoder.decode(data)
        switch decoded {
        case .error(let id, let code, let message):
            #expect(id == 3)
            #expect(code == -32601)
            #expect(message == "Method not found")
        default:
            #expect(Bool(false), "Expected error")
        }
    }

    @Test
    func encodeDecodeNotification() throws {
        let msg = MCPMessage.notification(method: "notifications/initialized", params: nil)
        let data = try MessageCoder.encode(msg)
        let decoded = try MessageCoder.decode(data)
        switch decoded {
        case .notification(let method, let params):
            #expect(method == "notifications/initialized")
            #expect(params == nil)
        default:
            #expect(Bool(false), "Expected notification")
        }
    }
}

struct MCPToolBridgeTests {
    @Test
    func buildToolDefinitions() {
        let tools = [
            MCPToolDescription(name: "View", description: "Read a file"),
            MCPToolDescription(name: "Replace", description: "Write a file")
        ]
        let defs = MCPToolBridge.buildToolDefinitions(from: tools)
        #expect(defs.count == 2)
        #expect(defs[0].name == "View")
        #expect(defs[0].description == "Read a file")
        #expect(defs[1].name == "Replace")
    }

    @Test
    func buildToolDefinitionsEmptyArray() {
        let defs = MCPToolBridge.buildToolDefinitions(from: [])
        #expect(defs.isEmpty)
    }

    @Test
    func buildToolResult() {
        let result = MCPToolResult(content: "hello", isError: false)
        let toolResult = MCPToolBridge.buildToolResult(result)
        #expect(toolResult.content == "hello")
        #expect(!toolResult.isError)
    }

    @Test
    func buildToolResultError() {
        let result = MCPToolResult(content: "something went wrong", isError: true)
        let toolResult = MCPToolBridge.buildToolResult(result)
        #expect(toolResult.content == "something went wrong")
        #expect(toolResult.isError)
    }
}

struct MCPToolDescriptionTests {
    @Test
    func createsToolDescription() {
        let tool = MCPToolDescription(
            name: "echo",
            description: "Echoes input",
            inputSchema: JSONSchema(type: "object", properties: [:])
        )
        #expect(tool.name == "echo")
        #expect(tool.description == "Echoes input")
    }
}

struct MCPErrorTests {
    @Test
    func transportNotConnected() {
        let error = MCPError.transportNotConnected
        switch error {
        case .transportNotConnected: break // expected
        default: #expect(Bool(false), "Expected transportNotConnected")
        }
    }

    @Test
    func serverErrorCarriesDetails() {
        let error = MCPError.serverError(code: 500, message: "boom")
        switch error {
        case .serverError(let code, let message):
            #expect(code == 500)
            #expect(message == "boom")
        default:
            #expect(Bool(false), "Expected serverError")
        }
    }

    @Test
    func toolNotFoundCarriesName() {
        let error = MCPError.toolNotFound("missing_tool")
        switch error {
        case .toolNotFound(let name):
            #expect(name == "missing_tool")
        default:
            #expect(Bool(false), "Expected toolNotFound")
        }
    }
}
