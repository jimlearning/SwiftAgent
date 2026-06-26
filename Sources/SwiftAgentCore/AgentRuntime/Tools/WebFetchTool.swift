import Foundation

/// Fetches and extracts content from a URL.
/// Matches Claude Code's WebFetchTool.
public struct WebFetchTool: Tool {
    public let name = "WebFetch"
    public let description = "Fetches content from a specified URL and processes into markdown."

    public struct Arguments: Codable, Sendable {
        public var url: String
        public var prompt: String

        enum CodingKeys: String, CodingKey {
            case url
            case prompt
        }
    }

    public var inputSchema: JSONSchema {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["url"] = JSONSchemaProperty(type: "string", description: "The URL to fetch content from")
        schema.properties?["prompt"] = JSONSchemaProperty(type: "string", description: "The prompt to answer based on the fetched content")
        schema.required = ["url", "prompt"]
        return schema
    }

    public init() {}

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        guard let url = URL(string: arguments.url) else {
            return .string("Error: URL is required")
        }

        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return .string("Error: Only HTTP and HTTPS URLs are supported")
        }

        var request = URLRequest(url: url)
        request.setValue("SwiftAgent/1.0 (markdown-fetcher)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html, application/json, text/plain", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .string("Error: Invalid response")
            }

            guard httpResponse.statusCode == 200 else {
                return .string("Error: HTTP \(httpResponse.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))")
            }

            let contentType = (httpResponse.allHeaderFields["Content-Type"] as? String) ?? "unknown"
            let content = extractContent(from: data, contentType: contentType)

            let maxContentSize = 100_000
            let truncated = content.count > maxContentSize
                ? String(content.prefix(maxContentSize)) + "\n\n[Content truncated at \(maxContentSize) chars. Total: \(content.count)]"
                : content

            return .string("""
                ## WebFetch Result
                **Prompt:** \(arguments.prompt)
                **URL:** \(url.absoluteString)
                **Content-Type:** \(contentType)
                **Size:** \(data.count) bytes

                ## Content
                \(truncated)
                """)
        } catch {
            return .string("Error fetching URL: \(error.localizedDescription)")
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

    private func stripHTML(_ html: String) -> String {
        var text = html
        text = regexReplace(text, pattern: "<script[^>]*>[\\s\\S]*?</script>", with: "")
        text = regexReplace(text, pattern: "<style[^>]*>[\\s\\S]*?</style>", with: "")
        text = regexReplace(text, pattern: "<!--[\\s\\S]*?-->", with: "")
        text = regexReplace(text, pattern: "</?(?:br|p|div|h[1-6]|li|tr)[^>]*>", with: "\n")
        text = regexReplace(text, pattern: "<[^>]+>", with: "")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
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
}
