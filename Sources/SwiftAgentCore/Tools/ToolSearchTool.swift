import Foundation

/// Searches for available tools by keyword.
/// Matches Claude Code's ToolSearchTool.
public struct ToolSearchTool: Tool {
    public let name = "ToolSearch"
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Search for available tools by name or description" }
    public let isReadOnly = true
    public let isConcurrencySafe = true
    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["query"] = JSONSchemaProperty(type: "string", description: "Search keywords")
        schema.properties?["maxResults"] = JSONSchemaProperty(type: "number", description: "Maximum results to return (default: 5)")
        schema.required = ["query"]
        return schema
    }()

    private let toolRegistry: ToolRegistry?

    public init(toolRegistry: ToolRegistry? = nil) {
        self.toolRegistry = toolRegistry
    }

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        guard let queryVal = input["query"], case .string(let query) = queryVal else {
            return ToolResult(content: "Error: query is required", isError: true)
        }

        let maxResults: Int
        if let m = input["maxResults"], case .number(let n) = m { maxResults = Int(n) }
        else { maxResults = 5 }

        let allTools: [any Tool]
        if let tr = toolRegistry {
            allTools = tr.allTools
        } else if let ctxTools = context.tools {
            allTools = ctxTools
        } else {
            allTools = []
        }

        let toolDefs = await withTaskGroup(of: (name: String, description: String).self) { group in
            for tool in allTools {
                group.addTask {
                    let desc = await tool.description(input: [:], options: ToolDescriptionOptions())
                    return (tool.name, desc)
                }
            }
            var results: [(name: String, description: String)] = []
            for await r in group { results.append(r) }
            return results
        }

        if query.hasPrefix("select:") {
            let toolName = String(query.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            let match = toolDefs.first { $0.name == toolName }
            if match != nil {
                return ToolResult(content: """
                    {"matches": ["\(toolName)"], "query": "\(query)", "total_deferred_tools": \(toolDefs.count)}
                    """)
            }
            return ToolResult(content: """
                {"matches": [], "query": "\(query)", "total_deferred_tools": \(toolDefs.count)}
                """)
        }

        let keywords = query.lowercased().components(separatedBy: .whitespaces)
        var scored: [(name: String, score: Int)] = []
        for tool in toolDefs {
            var score = 0
            let nameLower = tool.name.lowercased()
            let descLower = tool.description.lowercased()
            for kw in keywords where !kw.isEmpty {
                if nameLower.contains(kw) { score += 10 }
                if descLower.contains(kw) { score += 5 }
            }
            if score > 0 { scored.append((tool.name, score)) }
        }
        scored.sort { $0.score > $1.score }
        let matches = scored.prefix(maxResults).map { $0.name }

        if matches.isEmpty {
            return ToolResult(content: "No tools found matching \"\(query)\"")
        }
        return ToolResult(content: """
            {"matches": \(matches.map { "\"\($0)\"" }.joined(separator: ", ")), "query": "\(query)", "total_deferred_tools": \(toolDefs.count)}
            """)
    }
}
