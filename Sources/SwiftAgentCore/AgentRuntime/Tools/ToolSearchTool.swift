import Foundation

/// Searches for available tools by keyword or loads deferred tool schemas by name.
/// Matches Claude Code's ToolSearchTool.
public struct ToolSearchTool: Tool {
    public let name = "ToolSearch"
    public let description = """
        Fetches full schema definitions for deferred tools so they can be called.

        Deferred tools appear by name in <system-reminder> messages. Until fetched, \
        only the name is known — there is no parameter schema, so the tool cannot be \
        invoked. This tool takes a query, matches it against the deferred tool list, \
        and returns the matched tools' complete JSONSchema definitions inside a \
        <functions> block. Once a tool's schema appears in that result, it is \
        callable exactly like any tool defined at the top of the prompt.

        Result format: each matched tool appears as one \
        <function>{"description": "...", "name": "...", "parameters": {...}}</function> \
        line inside the <functions> block — the same encoding as the tool list at the \
        top of this prompt.

        Query forms:
        - "select:Read,Edit,Grep" — fetch these exact tools by name
        - "notebook jupyter" — keyword search, up to max_results best matches
        - "+slack send" — require "slack" in the name, rank by remaining terms
        """

    private let availableTools: [SessionToolDefinition]

    public struct Arguments: Codable, Sendable {
        public var query: String
        public var maxResults: Int?

        enum CodingKeys: String, CodingKey {
            case query
            case maxResults
        }
    }

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["query"] = JSONSchemaProperty(type: "string", description: "Query to find deferred tools. Use \"select:<tool_name>[,<tool_name>...]\" for direct selection, or keywords to search.")
        schema.properties?["max_results"] = JSONSchemaProperty(type: "number", description: "Maximum number of results to return (default: 5)")
        schema.required = ["query"]
        return schema
    }

    public init(availableTools: [SessionToolDefinition] = []) {
        self.availableTools = availableTools
    }

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        let maxResults = arguments.maxResults ?? 5

        if arguments.query.hasPrefix("select:") {
            let raw = String(arguments.query.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            let requestedNames = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

            var foundSchemas: [(name: String, schemaJSON: String)] = []
            for toolName in requestedNames {
                if let tool = availableTools.first(where: { $0.name == toolName }) {
                    let schemaJSON = schemaToFunctionJSON(name: tool.name, description: tool.description, inputSchema: tool.parameters)
                    foundSchemas.append((tool.name, schemaJSON))
                }
            }

            if foundSchemas.isEmpty {
                return .string("""
                    {"matches": [], "query": "\(arguments.query)", "total_deferred_tools": \(availableTools.count)}
                    """)
            }

            let functionsBlock = foundSchemas.map { $0.schemaJSON }.joined(separator: "\n")
            return .string("""
                <functions>
                \(functionsBlock)
                </functions>
                """)
        }

        // Keyword search
        let keywords = arguments.query.lowercased().components(separatedBy: .whitespaces)
        var scored: [(name: String, score: Int)] = []
        for tool in availableTools {
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
            return .string("No matching deferred tools found. Query: \"\(arguments.query)\"")
        }
        return .string("""
            {"matches": [\(matches.map { "\"\($0)\"" }.joined(separator: ", "))], "query": "\(arguments.query)", "total_deferred_tools": \(availableTools.count)}
            """)
    }
}

/// Serialize a tool's schema into a `<function>` JSON line matching the API format.
private func schemaToFunctionJSON(name: String, description: String, inputSchema: JSONSchema) -> String {
    let funcDict: [String: Any] = [
        "name": name,
        "description": description,
        "parameters": schemaToDict(inputSchema),
    ]
    guard let jsonData = try? JSONSerialization.data(withJSONObject: funcDict, options: []),
          let jsonStr = String(data: jsonData, encoding: .utf8) else {
        return "<function>{\"name\": \"\(name)\", \"description\": \"\(description)\", \"parameters\": {}}</function>"
    }
    return "<function>\(jsonStr)</function>"
}

/// Convert JSONSchema to a serializable dictionary.
private func schemaToDict(_ schema: JSONSchema) -> [String: Any] {
    var dict: [String: Any] = ["type": schema.type]
    if let props = schema.properties {
        var propsDict: [String: Any] = [:]
        for (key, prop) in props {
            var propDict: [String: Any] = ["type": prop.type]
            if let desc = prop.description { propDict["description"] = desc }
            if let enm = prop.enum { propDict["enum"] = enm }
            if let items = prop.items {
                var itemsDict: [String: Any] = ["type": items.type]
                if let itemDesc = items.description { itemsDict["description"] = itemDesc }
                propDict["items"] = itemsDict
            }
            propsDict[key] = propDict
        }
        dict["properties"] = propsDict
    }
    if let required = schema.required { dict["required"] = required }
    if let desc = schema.description { dict["description"] = desc }
    if let additional = schema.additionalProperties { dict["additionalProperties"] = additional }
    return dict
}

// MARK: - Discovered Tool Extraction

/// Extract tool names from ToolSearch `<function>` results in message history.
public func extractDiscoveredToolNames(messages: [Message]) -> Set<String> {
    var discovered = Set<String>()
    for msg in messages {
        guard msg.type == .user else { continue }
        for block in msg.content {
            guard case .toolResult(_, let content, _) = block else { continue }
            let text: String
            switch content {
            case .string(let s): text = s
            case .blocks: continue
            }
            guard text.contains("<function>") else { continue }
            let pattern = /<function>\{"name":"([^"]+)"/
            for match in text.matches(of: pattern) {
                discovered.insert(String(match.1))
            }
        }
    }
    return discovered
}

/// Adjust a ToolDefinition list for deferred tool loading.
public func filterDeferredTools(_ defs: [ToolDefinition], discovered: Set<String>) -> [ToolDefinition] {
    return defs.filter { def in
        if !def.deferLoading { return true }
        if def.name == "ToolSearch" { return true }
        return discovered.contains(def.name)
    }.map { def in
        if discovered.contains(def.name) && def.deferLoading {
            return ToolDefinition(name: def.name, description: def.description, parameters: def.parameters, deferLoading: false)
        }
        return def
    }
}
