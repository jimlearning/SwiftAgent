import Foundation

/// Searches the web and returns formatted results.
/// Matches Claude Code's WebSearchTool.
public struct WebSearchTool: Tool {
    public let name = "WebSearch"
    public let description = "Search the web for current information and return results with titles, URLs, and snippets"

    public struct Arguments: Codable, Sendable {
        public var query: String
        public var allowedDomains: [String]?
        public var blockedDomains: [String]?

        enum CodingKeys: String, CodingKey {
            case query
            case allowedDomains
            case blockedDomains
        }
    }

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["query"] = JSONSchemaProperty(type: "string", description: "The search query to use")
        schema.properties?["allowedDomains"] = JSONSchemaProperty(type: "array", description: "Only include search results from these domains")
        schema.properties?["blockedDomains"] = JSONSchemaProperty(type: "array", description: "Never include search results from these domains")
        schema.required = ["query"]
        return schema
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        guard !arguments.query.isEmpty else {
            return .string("Error: Missing query")
        }

        if let allowed = arguments.allowedDomains, !allowed.isEmpty,
           let blocked = arguments.blockedDomains, !blocked.isEmpty {
            return .string("Error: Cannot specify both allowedDomains and blockedDomains in the same request")
        }

        let startTime = Date()
        let searchURL = "https://html.duckduckgo.com/html/?q=\(arguments.query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? arguments.query)"

        var request = URLRequest(url: URL(string: searchURL)!)
        request.setValue("SwiftAgent/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        var results: [[String: String]] = []

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else {
                return .string("Error: Could not decode search response")
            }

            let linkPattern = /<a[^>]*class="result__a"[^>]*href="([^"]*)"[^>]*>([^<]*)<\/a>/
            let matches = html.matches(of: linkPattern)
            for match in matches.prefix(10) {
                let url = String(match.output.1)
                let title = String(match.output.2)
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if let blocked = arguments.blockedDomains, let host = URL(string: url)?.host {
                    if blocked.contains(where: { host.contains($0) }) { continue }
                }
                if let allowed = arguments.allowedDomains, let host = URL(string: url)?.host {
                    if !allowed.contains(where: { host.contains($0) }) { continue }
                }

                results.append(["title": title, "url": url])
            }
        } catch {
            return .string("Error performing web search: \(error.localizedDescription)")
        }

        let durationSeconds = Date().timeIntervalSince(startTime)
        let formattedDuration = String(format: "%.2f", durationSeconds)

        if results.isEmpty {
            return .string("""
                Web search results for query: "\(arguments.query)"
                Duration: \(formattedDuration)s
                No results found.
                """)
        }

        var output = "Web search results for query: \"\(arguments.query)\"\nDuration: \(formattedDuration)s\n\n"
        for (i, result) in results.enumerated() {
            output += "\(i + 1). **\(result["title"] ?? "Untitled")**\n"
            output += "   URL: \(result["url"] ?? "")\n"
            if let snippet = result["snippet"] {
                output += "   \(snippet)\n"
            }
            output += "\n"
        }
        output += "\nREMINDER: You MUST include the sources above in your response to the user using markdown hyperlinks."

        return .string(output)
    }
}
