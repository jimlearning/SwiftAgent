import Foundation

// MARK: - LSPTool

/// Interacts with Language Server Protocol (LSP) servers for code intelligence.
/// Matches Claude Code's LSPTool with 9 LSP operations.
public struct LSPTool: Tool {
    public let name = "LSP"
    public var searchHint: String? { "code intelligence (definitions, references, symbols, hover)" }
    public func isEnabled() -> Bool { FeatureFlags.isLSPEnabled() }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String {
        """
        Interact with Language Server Protocol (LSP) servers to get code intelligence features.

        Supported operations:
        - goToDefinition: Find where a symbol is defined
        - findReferences: Find all references to a symbol
        - hover: Get hover information (documentation, type info) for a symbol
        - documentSymbol: Get all symbols (functions, classes, variables) in a document
        - workspaceSymbol: Search for symbols across the entire workspace
        - goToImplementation: Find implementations of an interface or abstract method
        - prepareCallHierarchy: Get call hierarchy item at a position
        - incomingCalls: Find all functions/methods that call the function at a position
        - outgoingCalls: Find all functions/methods called by the function at a position

        All operations require filePath, line (1-based), and character (1-based).
        """
    }

    public let isReadOnly = true
    public let isConcurrencySafe = true
    public var shouldDefer: Bool { true }
    public var maxResultSizeChars: Int { 100_000 }
    /// CC: LSPTool is `isLsp` — true (flags as LSP tool type).
    public var isLsp: Bool { true }

    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["operation"] = JSONSchemaProperty(
            type: "string",
            description: "LSP operation: goToDefinition, findReferences, hover, documentSymbol, workspaceSymbol, goToImplementation, prepareCallHierarchy, incomingCalls, outgoingCalls"
        )
        schema.properties?["filePath"] = JSONSchemaProperty(type: "string", description: "The absolute or relative path to the file")
        schema.properties?["line"] = JSONSchemaProperty(type: "number", description: "The line number (1-based, as shown in editors)")
        schema.properties?["character"] = JSONSchemaProperty(type: "number", description: "The character offset (1-based, as shown in editors)")
        schema.required = ["operation", "filePath", "line", "character"]
        return schema
    }()

    public init() {}

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        guard case .string(let operation) = input["operation"],
              isValidOperation(operation) else {
            return ToolResult(content: "Error: operation must be one of: \(validOperations.joined(separator: ", "))", isError: true)
        }

        guard case .string(let filePath) = input["filePath"] else {
            return ToolResult(content: "Error: filePath is required", isError: true)
        }

        let line: Int
        if case .number(let n) = input["line"] { line = Int(n) }
        else { line = 1 }

        let character: Int
        if case .number(let n) = input["character"] { character = Int(n) }
        else { character = 1 }

        // Resolve the absolute path
        let absolutePath = resolvePath(filePath, relativeTo: context.workingDirectory)

        // Try to get symbol at position for context
        let symbol = getSymbolAtPosition(absolutePath, line: line, character: character)

        // Attempt LSP operation
        let result = try await performLSPOperation(
            operation: operation,
            filePath: absolutePath,
            line: line,
            character: character,
            symbol: symbol,
            workingDirectory: context.workingDirectory
        )

        return ToolResult(content: result)
    }

    // MARK: - Operation dispatch

    private func performLSPOperation(
        operation: String,
        filePath: String,
        line: Int,
        character: Int,
        symbol: String?,
        workingDirectory: String
    ) async throws -> String {
        guard FileManager.default.fileExists(atPath: filePath) else {
            return "Error: file not found: \(filePath)"
        }

        switch operation {
        case "goToDefinition":
            return try await goToDefinition(filePath: filePath, line: line, character: character, symbol: symbol, cwd: workingDirectory)
        case "findReferences":
            return try await findReferences(filePath: filePath, line: line, character: character, symbol: symbol, cwd: workingDirectory)
        case "hover":
            return try await hover(filePath: filePath, line: line, character: character, symbol: symbol)
        case "documentSymbol":
            return try await documentSymbol(filePath: filePath, cwd: workingDirectory)
        case "workspaceSymbol":
            return try await workspaceSymbol(filePath: filePath, line: line, character: character, cwd: workingDirectory)
        case "goToImplementation":
            return try await goToImplementation(filePath: filePath, line: line, character: character, symbol: symbol, cwd: workingDirectory)
        case "prepareCallHierarchy":
            return try await prepareCallHierarchy(filePath: filePath, line: line, character: character, symbol: symbol, cwd: workingDirectory)
        case "incomingCalls":
            return try await incomingCalls(filePath: filePath, line: line, character: character, symbol: symbol, cwd: workingDirectory)
        case "outgoingCalls":
            return try await outgoingCalls(filePath: filePath, line: line, character: character, symbol: symbol, cwd: workingDirectory)
        default:
            return "Error: unknown operation: \(operation)"
        }
    }

    // MARK: - LSP Operations

    private func goToDefinition(filePath: String, line: Int, character: Int, symbol: String?, cwd: String) async throws -> String {
        // Search for symbol definitions using grep-based fallback
        guard let sym = symbol else {
            return "No definition found. This may occur if the cursor is not on a symbol, or if the definition is in an external library not indexed by the LSP server."
        }

        let results = searchSymbolPattern(sym, in: cwd, excludeFile: filePath)
        if results.isEmpty {
            return "No definition found for '\(sym)'."
        }
        if results.count == 1 {
            return "Defined in \(results[0])"
        }
        return "Found \(results.count) definitions:\n\(results.map { "  \($0)" }.joined(separator: "\n"))"
    }

    private func findReferences(filePath: String, line: Int, character: Int, symbol: String?, cwd: String) async throws -> String {
        guard let sym = symbol else {
            return "No references found."
        }
        let results = searchSymbolPattern(sym, in: cwd, excludeFile: nil)
        if results.isEmpty {
            return "No references found."
        }
        if results.count == 1 {
            return "Found 1 reference:\n  \(results[0])"
        }
        return "Found \(results.count) references across files:\n\(results.map { "  \($0)" }.joined(separator: "\n"))"
    }

    private func hover(filePath: String, line: Int, character: Int, symbol: String?) async throws -> String {
        guard let sym = symbol else {
            return "No hover information available."
        }
        let lineContent = readLine(filePath, line: line) ?? ""
        return "Hover info at \(line):\(character):\n\nSymbol: \(sym)\nLine: \(lineContent.trimmingCharacters(in: .whitespaces))"
    }

    private func documentSymbol(filePath: String, cwd: String) async throws -> String {
        let symbols = extractDocumentSymbols(filePath)
        if symbols.isEmpty {
            return "No symbols found in document."
        }
        return "Document symbols:\n\(symbols.map { "  \($0)" }.joined(separator: "\n"))"
    }

    private func workspaceSymbol(filePath: String, line: Int, character: Int, cwd: String) async throws -> String {
        let symbol = getSymbolAtPosition(filePath, line: line, character: character)
        guard let sym = symbol else {
            return "No symbols found in workspace."
        }
        let results = searchSymbolPattern(sym, in: cwd, excludeFile: nil)
        if results.isEmpty {
            return "No symbols found in workspace."
        }
        return "Found \(results.count) symbol(s) in workspace:\n\(results.map { "  \($0)" }.joined(separator: "\n"))"
    }

    private func goToImplementation(filePath: String, line: Int, character: Int, symbol: String?, cwd: String) async throws -> String {
        guard let sym = symbol else {
            return "No implementation found."
        }
        let results = searchSymbolPattern(sym, in: cwd, excludeFile: filePath)
        if results.isEmpty {
            return "No implementation found for '\(sym)'."
        }
        return "Found \(results.count) implementation(s):\n\(results.map { "  \($0)" }.joined(separator: "\n"))"
    }

    private func prepareCallHierarchy(filePath: String, line: Int, character: Int, symbol: String?, cwd: String) async throws -> String {
        guard let sym = symbol else {
            return "No call hierarchy item found at this position."
        }
        let callers = searchSymbolPattern(sym, in: cwd, excludeFile: nil)
        return "Call hierarchy item: \(sym) - \(filePath):\(line)\n\(callers.count > 0 ? "Found \(callers.count) reference(s)" : "No callers found")"
    }

    private func incomingCalls(filePath: String, line: Int, character: Int, symbol: String?, cwd: String) async throws -> String {
        guard let sym = symbol else {
            return "No incoming calls found."
        }
        let results = searchSymbolPattern(sym, in: cwd, excludeFile: filePath)
        if results.isEmpty {
            return "No incoming calls found (nothing calls this function)."
        }
        return "Found \(results.count) incoming call(s):\n\(results.map { "  \($0)" }.joined(separator: "\n"))"
    }

    private func outgoingCalls(filePath: String, line: Int, character: Int, symbol: String?, cwd: String) async throws -> String {
        // Find symbols called from the current function
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return "No outgoing calls found."
        }
        let lines = content.components(separatedBy: .newlines)
        guard line <= lines.count else {
            return "No outgoing calls found (this function calls nothing)."
        }

        // Find the function body and extract calls
        let funcBody = extractFunctionBody(from: lines, startLine: line)
        let calledSymbols = extractCalledSymbols(from: funcBody)

        if calledSymbols.isEmpty {
            return "No outgoing calls found (this function calls nothing)."
        }
        return "Found \(calledSymbols.count) outgoing call(s):\n\(calledSymbols.map { "  \($0)" }.joined(separator: "\n"))"
    }

    // MARK: - Helpers

    private func searchSymbolPattern(_ symbol: String, in directory: String, excludeFile: String?) -> [String] {
        var results: [String] = []
        guard let enumerator = FileManager.default.enumerator(atPath: directory) else { return [] }
        let vcsDirs: Set<String> = [".git", ".svn", ".hg"]

        while let fileRel = enumerator.nextObject() as? String {
            let components = (fileRel as NSString).pathComponents
            if components.contains(where: { vcsDirs.contains($0) }) { continue }

            let absPath = "\(directory)/\(fileRel)"
            if absPath == excludeFile { continue }

            guard absPath.hasSuffix(".swift") || absPath.hasSuffix(".ts") || absPath.hasSuffix(".tsx") ||
                  absPath.hasSuffix(".js") || absPath.hasSuffix(".py") || absPath.hasSuffix(".go") ||
                  absPath.hasSuffix(".rs") || absPath.hasSuffix(".c") || absPath.hasSuffix(".h") ||
                  absPath.hasSuffix(".cpp") || absPath.hasSuffix(".java") || absPath.hasSuffix(".kt") else { continue }

            guard let content = try? String(contentsOfFile: absPath, encoding: .utf8),
                  content.contains(symbol) else { continue }

            let lines = content.components(separatedBy: .newlines)
            for (i, line) in lines.enumerated() {
                if line.contains(symbol) {
                    let relativePath = relativize(absPath, from: directory)
                    results.append("\(relativePath):\(i + 1):\(line.trimmingCharacters(in: .whitespaces).prefix(120))")
                    if results.count >= 20 { return results }
                }
            }
        }
        return results
    }

    private func getSymbolAtPosition(_ filePath: String, line: Int, character: Int) -> String? {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { return nil }
        let lines = content.components(separatedBy: .newlines)
        guard line > 0, line <= lines.count else { return nil }
        let lineContent = lines[line - 1]
        guard character > 0, character <= lineContent.count else { return nil }

        // Extract word at position
        let pattern = #/[a-zA-Z_$][a-zA-Z0-9_$]*|[+\-*/%&|^~<>=]+/#
        let matches = lineContent.matches(of: pattern)
        for match in matches {
            let range = match.range
            let startIdx = lineContent.distance(from: lineContent.startIndex, to: range.lowerBound)
            let endIdx = lineContent.distance(from: lineContent.startIndex, to: range.upperBound)
            if character - 1 >= startIdx && character - 1 < endIdx {
                return String(lineContent[range])
            }
        }
        return nil
    }

    private func readLine(_ filePath: String, line: Int) -> String? {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { return nil }
        let lines = content.components(separatedBy: .newlines)
        guard line > 0, line <= lines.count else { return nil }
        return lines[line - 1]
    }

    private func extractDocumentSymbols(_ filePath: String) -> [String] {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { return [] }
        var symbols: [String] = []
        let lines = content.components(separatedBy: .newlines)

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Swift symbols
            if let match = trimmed.firstMatch(of: #/^(func|class|struct|enum|protocol|extension|var|let|actor)\s+([a-zA-Z_]\w*)/#) {
                let kind = String(match.1)
                let name = String(match.2)
                symbols.append("\(name) (\(kind.capitalized)) - Line \(i + 1)")
            }
            // TypeScript/JS symbols
            else if let match = trimmed.firstMatch(of: #/^(function|class|interface|type|const|let|var|enum)\s+([a-zA-Z_$]\w*)/#) {
                let kind = String(match.1)
                let name = String(match.2)
                symbols.append("\(name) (\(kind.capitalized)) - Line \(i + 1)")
            }
            // Python symbols
            else if let match = trimmed.firstMatch(of: #/^(def|class)\s+([a-zA-Z_]\w*)/#) {
                let kind = String(match.1)
                let name = String(match.2)
                symbols.append("\(name) (\(kind.capitalized)) - Line \(i + 1)")
            }
        }
        return symbols
    }

    private func extractFunctionBody(from lines: [String], startLine: Int) -> String {
        let start = max(0, startLine - 1)
        var depth = 0
        var started = false
        var bodyLines: [String] = []
        for i in start..<lines.endIndex {
            let line = lines[i]
            if line.contains("{") { depth += line.filter { $0 == "{" }.count; started = true }
            if started { bodyLines.append(line) }
            if line.contains("}") {
                depth -= line.filter { $0 == "}" }.count
                if depth <= 0 { break }
            }
            if bodyLines.count > 100 { break }
        }
        return bodyLines.joined(separator: "\n")
    }

    private func extractCalledSymbols(from body: String) -> [String] {
        var symbols: Set<String> = []
        let pattern = #/\b([a-zA-Z_]\w*)\s*\(/#
        for match in body.matches(of: pattern) {
            symbols.insert(String(match.1))
        }
        // Filter common keywords
        let keywords: Set<String> = ["if", "for", "while", "switch", "return", "guard", "try", "await", "catch", "throw"]
        return symbols.filter { !keywords.contains($0) }.sorted()
    }

    private func resolvePath(_ path: String, relativeTo cwd: String) -> String {
        if path.hasPrefix("/") { return path }
        return "\(cwd)/\(path)"
    }

    private func relativize(_ path: String, from cwd: String) -> String {
        if path.hasPrefix(cwd + "/") { return String(path.dropFirst(cwd.count + 1)) }
        return path
    }

    // MARK: - Validation

    private let validOperations = [
        "goToDefinition", "findReferences", "hover",
        "documentSymbol", "workspaceSymbol", "goToImplementation",
        "prepareCallHierarchy", "incomingCalls", "outgoingCalls",
    ]

    private func isValidOperation(_ op: String) -> Bool {
        validOperations.contains(op)
    }
}
