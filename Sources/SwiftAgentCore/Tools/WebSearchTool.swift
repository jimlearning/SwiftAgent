import Foundation

// MARK: - WebSearchTool

/// Searches the web and returns formatted results.
/// Matches Claude Code's WebSearchTool.
public struct WebSearchTool: Tool {
    public let name = "WebSearch"
    public var searchHint: String? { "search the web for current information" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Search the web for current information and return results with titles, URLs, and snippets" }
    public let isReadOnly = true
    public let isConcurrencySafe = true
    public var shouldDefer: Bool { true }
    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["query"] = JSONSchemaProperty(type: "string", description: "The search query to use")
        schema.properties?["allowedDomains"] = JSONSchemaProperty(type: "array", description: "Only include search results from these domains")
        schema.properties?["blockedDomains"] = JSONSchemaProperty(type: "array", description: "Never include search results from these domains")
        schema.required = ["query"]
        return schema
    }()

    public init() {}

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        guard let queryVal = input["query"], case .string(let query) = queryVal, !query.isEmpty else {
            return ToolResult(content: "Error: Missing query", isError: true)
        }

        let allowedDomains: [String]?
        if let a = input["allowedDomains"], case .array(let arr) = a {
            allowedDomains = arr.compactMap { if case .string(let s) = $0 { return s }; return nil }
        } else { allowedDomains = nil }

        let blockedDomains: [String]?
        if let b = input["blockedDomains"], case .array(let arr) = b {
            blockedDomains = arr.compactMap { if case .string(let s) = $0 { return s }; return nil }
        } else { blockedDomains = nil }

        if let allowed = allowedDomains, !allowed.isEmpty,
           let blocked = blockedDomains, !blocked.isEmpty {
            return ToolResult(content: "Error: Cannot specify both allowedDomains and blockedDomains in the same request", isError: true)
        }

        let startTime = Date()

        // Build search URL — uses DuckDuckGo's HTML search endpoint by default.
        let searchURL = "https://html.duckduckgo.com/html/?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)"

        var request = URLRequest(url: URL(string: searchURL)!)
        request.setValue("SwiftAgent/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        // Extract search results from DuckDuckGo HTML response
        var results: [[String: String]] = []

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else {
                return ToolResult(content: "Error: Could not decode search response", isError: true)
            }

            // Parse DuckDuckGo HTML results — each result has a link with class "result__a"
            let linkPattern = /<a[^>]*class="result__a"[^>]*href="([^"]*)"[^>]*>([^<]*)<\/a>/

            let matches = html.matches(of: linkPattern)
            for match in matches.prefix(10) {
                let url = String(match.output.1)
                let title = String(match.output.2)
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // Filter by domains
                if let blocked = blockedDomains, let host = URL(string: url)?.host {
                    if blocked.contains(where: { host.contains($0) }) { continue }
                }
                if let allowed = allowedDomains, let host = URL(string: url)?.host {
                    if !allowed.contains(where: { host.contains($0) }) { continue }
                }

                results.append(["title": title, "url": url])
            }
        } catch {
            return ToolResult(content: "Error performing web search: \(error.localizedDescription)", isError: true)
        }

        let durationSeconds = Date().timeIntervalSince(startTime)
        let formattedDuration = String(format: "%.2f", durationSeconds)

        if results.isEmpty {
            return ToolResult(content: """
                Web search results for query: "\(query)"
                Duration: \(formattedDuration)s
                No results found.
                """)
        }

        var output = "Web search results for query: \"\(query)\"\nDuration: \(formattedDuration)s\n\n"
        for (i, result) in results.enumerated() {
            output += "\(i + 1). **\(result["title"] ?? "Untitled")**\n"
            output += "   URL: \(result["url"] ?? "")\n"
            if let snippet = result["snippet"] {
                output += "   \(snippet)\n"
            }
            output += "\n"
        }
        output += "\nREMINDER: You MUST include the sources above in your response to the user using markdown hyperlinks."

        return ToolResult(content: output)
    }
}
