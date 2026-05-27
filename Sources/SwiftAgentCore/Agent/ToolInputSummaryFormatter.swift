import Foundation

public enum ToolInputSummaryFormatter {
    private static let sensitiveKeyFragments = ["key", "token", "secret", "password", "authorization", "cookie"]

    public static func summarize(
        toolName: String,
        input: [String: JSONValue],
        registry: ToolRegistry? = nil
    ) -> String? {
        let keys = preferredKeys(for: toolName, input: input)
        let parts = keys.compactMap { key -> String? in
            guard let value = input[key] else { return nil }
            return "\(key)=\(format(value, key: key))"
        }
        if !parts.isEmpty {
            return singleLine(parts.joined(separator: " "))
        }

        if let tool = registry?.tool(named: toolName),
           let summary = tool.getActivityDescription(input) ?? tool.getToolUseSummary(input),
           !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return singleLine(summary)
        }

        return nil
    }

    private static func preferredKeys(for toolName: String, input: [String: JSONValue]) -> [String] {
        switch toolName {
        case "Grep":
            return ["pattern", "path", "glob", "type", "output_mode", "head_limit"].filter { input[$0] != nil }
        case "Read":
            return ["file_path", "offset", "limit", "pages"].filter { input[$0] != nil }
        case "Glob":
            return ["pattern", "path"].filter { input[$0] != nil }
        case "Bash":
            return ["command", "description", "run_in_background", "timeout"].filter { input[$0] != nil }
        default:
            return Array(input.keys.sorted().prefix(4))
        }
    }

    private static func format(_ value: JSONValue, key: String) -> String {
        if sensitiveKeyFragments.contains(where: { key.lowercased().contains($0) }) {
            return "<redacted>"
        }

        switch value {
        case .string(let string):
            return quoteIfNeeded(singleLine(string))
        case .number(let number):
            if number.rounded() == number {
                return String(Int(number))
            }
            return String(number)
        case .bool(let bool):
            return bool ? "true" : "false"
        case .array(let values):
            return "[\(values.count) items]"
        case .object(let object):
            return "{\(object.count) keys}"
        case .null:
            return "null"
        }
    }

    private static func quoteIfNeeded(_ value: String) -> String {
        if value.contains(" ") || value.contains("\t") {
            return "\"\(value)\""
        }
        return value
    }

    private static func singleLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
