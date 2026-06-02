import Foundation

/// Searches for available tools by keyword or loads deferred tool schemas by name.
/// Matches Claude Code's ToolSearchTool.
///
/// CC's ToolSearch returns `tool_reference` blocks which the API server expands into
/// full function definitions. SA replicates this by returning the actual JSON Schema
/// for `select:` queries inside a `<functions>` block — the model sees the full
/// schema and can call the tool on the next turn.
public struct ToolSearchTool: Tool {
    public let name = "ToolSearch"
    public var searchHint: String? { "load deferred tool schemas by name or keyword" }

    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String {
        """
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
    }

    public let isReadOnly = true
    public let isConcurrencySafe = true
    public func isEnabled() -> Bool { FeatureFlags.isToolSearchEnabled() }
    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["query"] = JSONSchemaProperty(type: "string", description: "Query to find deferred tools. Use \"select:<tool_name>[,<tool_name>...]\" for direct selection, or keywords to search.")
        schema.properties?["max_results"] = JSONSchemaProperty(type: "number", description: "Maximum number of results to return (default: 5)")
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
        if let m = input["max_results"], case .number(let n) = m { maxResults = Int(n) }
        else if let m = input["maxResults"], case .number(let n) = m { maxResults = Int(n) }
        else { maxResults = 5 }

        // Collect all tools: use registry if available, fall back to context
        let allTools: [any Tool]
        if let tr = toolRegistry {
            allTools = tr.allTools
        } else if let ctxTools = context.tools {
            allTools = ctxTools
        } else {
            allTools = []
        }

        // Only search deferred tools
        let deferredTools = allTools.filter { $0.shouldDefer && !$0.alwaysLoad }

        // Build tool descriptions for keyword scoring
        let toolDefs = await withTaskGroup(of: (name: String, description: String, tool: (any Tool)?).self) { group in
            for tool in deferredTools {
                group.addTask {
                    let desc = await tool.description(input: [:], options: ToolDescriptionOptions())
                    return (tool.name, desc, tool)
                }
            }
            var results: [(name: String, description: String, tool: (any Tool)?)] = []
            for await r in group { results.append(r) }
            return results
        }

        // Handle select: prefix — load full schemas for named tools
        if query.hasPrefix("select:") {
            let raw = String(query.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            let requestedNames = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

            var foundSchemas: [(name: String, schemaJSON: String)] = []
            for toolName in requestedNames {
                // Search deferred tools first, then fall back to all tools
                let match = deferredTools.first(where: { $0.name == toolName })
                    ?? allTools.first(where: { $0.name == toolName })
                if let tool = match {
                    let schemaJSON = schemaToFunctionJSON(name: tool.name, description: await tool.description(input: [:], options: ToolDescriptionOptions()), inputSchema: tool.inputSchema)
                    foundSchemas.append((tool.name, schemaJSON))
                }
            }

            if foundSchemas.isEmpty {
                return ToolResult(content: """
                    {"matches": [], "query": "\(query)", "total_deferred_tools": \(deferredTools.count)}
                    """)
            }

            let functionsBlock = foundSchemas.map { $0.schemaJSON }.joined(separator: "\n")
            return ToolResult(content: """
                <functions>
                \(functionsBlock)
                </functions>
                """)
        }

        // Keyword search
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
            return ToolResult(content: "No matching deferred tools found. Query: \"\(query)\"")
        }
        return ToolResult(content: """
            {"matches": [\(matches.map { "\"\($0)\"" }.joined(separator: ", "))], "query": "\(query)", "total_deferred_tools": \(deferredTools.count)}
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

// MARK: - Discovered Tool Extraction

/// Extract tool names from ToolSearch `<function>` results in message history.
///
/// When ToolSearch returns schemas inside `<functions>` blocks, this function scans
/// the conversation history to find all tool names that have been loaded. These
/// tools should be undeferred (sent with full schema) on subsequent API calls.
///
/// Matches Claude Code's `extractDiscoveredToolNames()` in toolSearch.ts.
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
            // Look for <function>{"name":"...","description":"...","parameters":{...}}</function>
            guard text.contains("<function>") else { continue }
            // Extract all tool names from <function> blocks
            let pattern = /<function>\{"name":"([^"]+)"/
            for match in text.matches(of: pattern) {
                discovered.insert(String(match.1))
            }
        }
    }
    return discovered
}

/// Adjust a ToolDefinition list for deferred tool loading, matching CC's
/// claude.ts:1154-1167.
///
/// - Non-deferred tools: always included
/// - ToolSearch: always included (the model needs it to discover more)
/// - Deferred + discovered: included with `deferLoading: false` (full schema)
/// - Deferred + NOT discovered: **removed** (model cannot call them)
public func filterDeferredTools(_ defs: [ToolDefinition], discovered: Set<String>) -> [ToolDefinition] {
    return defs.filter { def in
        if !def.deferLoading { return true }  // non-deferred: always keep
        if def.name == "ToolSearch" { return true }  // ToolSearch itself: always keep
        return discovered.contains(def.name)  // only keep discovered deferred tools
    }.map { def in
        // Undefer discovered tools so their full schema is sent inline
        if discovered.contains(def.name) && def.deferLoading {
            return ToolDefinition(name: def.name, description: def.description, inputSchema: def.inputSchema, deferLoading: false)
        }
        return def
    }
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
