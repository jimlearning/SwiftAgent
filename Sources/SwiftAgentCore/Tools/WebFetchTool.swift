import Foundation

/// Fetches and extracts content from a URL.
/// Matches Claude Code's WebFetchTool.
public struct WebFetchTool: Tool {
    public let name = "WebFetch"
    public var searchHint: String? { "fetch and extract content from a URL" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Fetches content from a specified URL and processes into markdown." }
    public let isReadOnly = true
    public let isConcurrencySafe = true
    public var shouldDefer: Bool { true }
    public let interruptBehavior = InterruptBehavior.cancel

    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["url"] = JSONSchemaProperty(
            type: "string",
            description: "The URL to fetch content from"
        )
        schema.properties?["prompt"] = JSONSchemaProperty(
            type: "string",
            description: "The prompt to answer based on the fetched content"
        )
        schema.required = ["url", "prompt"]
        return schema
    }()

    public init() {}

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        guard let urlVal = input["url"],
              case .string(let urlStr) = urlVal,
              let url = URL(string: urlStr) else {
            return ToolResult(content: "Error: URL is required", isError: true)
        }

        let userPrompt: String
        if let p = input["prompt"], case .string(let s) = p { userPrompt = s }
        else { userPrompt = "Summarize the content" }

        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return ToolResult(content: "Error: Only HTTP and HTTPS URLs are supported", isError: true)
        }

        var request = URLRequest(url: url)
        request.setValue("SwiftAgent/1.0 (markdown-fetcher)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html, application/json, text/plain", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return ToolResult(content: "Error: Invalid response", isError: true)
            }

            guard httpResponse.statusCode == 200 else {
                return ToolResult(content: "Error: HTTP \(httpResponse.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))", isError: true)
            }

            let contentType = (httpResponse.allHeaderFields["Content-Type"] as? String) ?? "unknown"
            let content = extractContent(from: data, contentType: contentType)

            let maxContentSize = 100_000
            let truncated = content.count > maxContentSize
                ? String(content.prefix(maxContentSize)) + "\n\n[Content truncated at \(maxContentSize) chars. Total: \(content.count)]"
                : content

            return ToolResult(content: """
                ## WebFetch Result
                **Prompt:** \(userPrompt)
                **URL:** \(url.absoluteString)
                **Content-Type:** \(contentType)
                **Size:** \(data.count) bytes

                ## Content
                \(truncated)
                """)
        } catch {
            return ToolResult(content: "Error fetching URL: \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: - Helpers

    private func extractContent(from data: Data, contentType: String) -> String {
        if contentType.contains("text/html") || contentType.contains("application/xhtml") {
            return stripHTML(String(data: data, encoding: .utf8) ?? "[binary HTML, \(data.count) bytes]")
        }
        if contentType.contains("application/json") {
            if let obj = try? JSONSerialization.jsonObject(with: data),
               let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
               let str = String(data: pretty, encoding: .utf8) {
                return str
            }
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii)
            ?? "[binary content, \(data.count) bytes]"
    }

    /// Strip HTML tags and extract readable text.
    private func stripHTML(_ html: String) -> String {
        var text = html
        // Remove scripts and styles
        text = regexReplace(text, pattern: "<script[^>]*>[\\s\\S]*?</script>", with: "")
        text = regexReplace(text, pattern: "<style[^>]*>[\\s\\S]*?</style>", with: "")
        // Remove HTML comments
        text = regexReplace(text, pattern: "<!--[\\s\\S]*?-->", with: "")
        // Replace block elements with newlines
        text = regexReplace(text, pattern: "</?(?:br|p|div|h[1-6]|li|tr)[^>]*>", with: "\n")
        // Strip remaining tags
        text = regexReplace(text, pattern: "<[^>]+>", with: "")
        // Decode HTML entities
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        // Collapse multiple blank lines
        text = regexReplace(text, pattern: "\\n{3,}", with: "\n\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func regexReplace(_ text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }

    public func getToolUseSummary(_ input: [String: JSONValue]) -> String? {
        if case .string(let url) = input["url"] ?? input["url"] {
            return "Fetching \(url.prefix(80))"
        }
        return nil
    }

    public func getActivityDescription(_ input: [String: JSONValue]) -> String? {
        if case .string(let url) = input["url"] ?? input["url"] {
            return "Fetching \(url.prefix(60))"
        }
        return "Fetching URL"
    }
}
