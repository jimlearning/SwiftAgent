import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

/// Reads a file from the local filesystem.
/// Supports text, images (PNG/JPG/GIF/WebP/BMP/SVG), PDFs, and Jupyter notebooks.
/// Mirrors Claude Code's FileReadTool.
public struct FileReadTool: Tool {
    public init() {}

    // MARK: - Tool Protocol Basics

    public let name = "Read"
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Reads a file from the local filesystem. You can access any file directly by using this tool." }
    public var isReadOnly: Bool { true }
    public var isConcurrencySafe: Bool { true }
    public var maxResultSizeChars: Int { Int.max }
    public var searchHint: String? { "read files, images, PDFs, notebooks" }

    // MARK: - Input Schema

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "file_path": JSONSchemaProperty(type: "string", description: "The absolute path to the file to read"),
            "offset": JSONSchemaProperty(type: "number", description: "The line number to start reading from. Only provide if the file is too large to read at once"),
            "limit": JSONSchemaProperty(type: "number", description: "The number of lines to read. Only provide if the file is too large to read at once."),
            "pages": JSONSchemaProperty(type: "string", description: "Page range for PDF files (e.g., \"1-5\", \"3\", \"10-20\"). Only applicable to PDF files. Maximum 20 pages per request."),
        ], required: ["file_path"])
    }

    // MARK: - Protocol Overrides

    public func getToolUseSummary(_ input: [String: JSONValue]) -> String? {
        input.stringValue("file_path")
    }

    public func getActivityDescription(_ input: [String: JSONValue]) -> String? {
        if let path = input.stringValue("file_path") {
            let filename = (path as NSString).lastPathComponent
            return "Reading \(filename)"
        }
        return "Reading file"
    }

    public func interruptBehavior() -> InterruptBehavior { .cancel }

    public func isSearchOrReadCommand(_ input: [String: JSONValue]) -> SearchOrReadResult {
        SearchOrReadResult(isSearch: false, isRead: true)
    }

    public func getPath(_ input: [String: JSONValue]) -> String? {
        input.stringValue("file_path")
    }

    public func toAutoClassifierInput(_ input: [String: JSONValue]) -> String {
        input.stringValue("file_path") ?? ""
    }

    // MARK: - Validate Input

    public func validateInput(_ input: [String: JSONValue], context: ToolUseContext) async -> ValidationResult {
        guard let path = input.stringValue("file_path"), !path.isEmpty else {
            return .failure(message: "file_path is required and must be a non-empty string", errorCode: 1)
        }

        // Validate pages parameter
        if let pages = input.stringValue("pages") {
            guard parsePageRangesIsValid(pages) else {
                return .failure(message: """
                    Invalid pages parameter: "\(pages)". Use formats like "1-5", "3", or "10-20". Pages are 1-indexed.
                    """, errorCode: 7)
            }
            let rangeSize = pageRangeSize(pages)
            if rangeSize > 20 {
                return .failure(message: """
                    Page range "\(pages)" exceeds maximum of 20 pages per request. Please use a smaller range.
                    """, errorCode: 8)
            }
        }

        // Reject known binary extensions (before any I/O)
        let ext = (path as NSString).pathExtension.lowercased()
        if isBinaryExtension(ext) {
            return .failure(message: """
                This tool cannot read binary files. The file appears to be a binary .\(ext) file. \
                Please use appropriate tools for binary file analysis.
                """, errorCode: 4)
        }

        // Block device files (path-based, no I/O)
        if isBlockedDevicePath(path) {
            return .failure(message: "Cannot read '\(path)': this device file would block or produce infinite output.", errorCode: 9)
        }

        return .success
    }

    // MARK: - Execute

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        guard case .string(let path) = input["file_path"] else {
            return ToolResult(content: "Error: file_path is required", isError: true)
        }

        // Block device paths (defense-in-depth)
        if isBlockedDevicePath(path) {
            return ToolResult(content: "Error: cannot read device file at \(path)", isError: true)
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            let cwd = context.workingDirectory
            return ToolResult(content: "Error: file not found at \(path). The current working directory is \(cwd).", isError: true)
        }
        guard fm.isReadableFile(atPath: path) else {
            return ToolResult(content: "Error: cannot read file at \(path) — permission denied.", isError: true)
        }

        let ext = (path as NSString).pathExtension.lowercased()

        // Images
        let imageExts = Set(["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg"])
        if imageExts.contains(ext) {
            return try readImage(path: path, ext: ext)
        }

        // PDFs
        if ext == "pdf" {
            let pages = input.stringValue("pages")
            return try readPDF(path: path, pages: pages)
        }

        // Jupyter notebooks
        if ext == "ipynb" {
            return try readNotebook(path: path)
        }

        // Text file (default)
        return try readText(path: path, input: input)
    }

    // MARK: - Private: Text Reader

    private func readText(path: String, input: [String: JSONValue]) throws -> ToolResult {
        let maxSizeBytes = 256 * 1024 // 256KB

        // Check file size
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let fileSize = (attrs[.size] as? UInt64) ?? 0

        guard let rawContent = try? String(contentsOfFile: path, encoding: .utf8) else {
            // Not valid UTF-8 — treat as binary
            return ToolResult(content: "Cannot display content of binary file: \(path)", isError: true)
        }

        let lines = rawContent.components(separatedBy: .newlines)
        let totalLines = lines.count

        // Parse offset (1-indexed, matching CC)
        let offset = input.intValue("offset") ?? 1
        let startLine: Int
        if offset <= 0 {
            startLine = 0
        } else {
            startLine = min(offset - 1, max(totalLines - 1, 0))
        }

        let limit = input.intValue("limit")

        // Enforce 256KB limit for full reads (when no limit specified)
        if limit == nil && fileSize > maxSizeBytes {
            return ToolResult(content: """
                File is too large (\(formatBytes(fileSize))). \
                Use the offset and limit parameters to read specific portions of the file. \
                Total lines: \(totalLines). \
                Example: offset=1, limit=100 to read the first 100 lines.
                """, isError: true)
        }

        let count = limit.map { min($0, totalLines - startLine) } ?? (totalLines - startLine)
        let end = min(startLine + count, totalLines)

        // Guard against empty result
        guard startLine < end else {
            let warning: String
            if totalLines == 0 {
                warning = "<system-reminder>Warning: the file exists but the contents are empty.</system-reminder>"
            } else {
                warning = "<system-reminder>Warning: the file exists but is shorter than the provided offset (\(offset)). The file has \(totalLines) lines.</system-reminder>"
            }
            return ToolResult(content: warning)
        }

        let slice = lines[startLine..<end]
        let content = slice.joined(separator: "\n")
        let formatted = addLineNumbers(content, startLine: startLine + 1)

        // Add range summary when only part of file is shown
        let summary: String
        if count < totalLines {
            summary = "\n\n[Lines \(startLine + 1)-\(end) of \(totalLines) — use offset/limit for more]"
        } else {
            summary = ""
        }

        return ToolResult(content: formatted + summary)
    }

    // MARK: - Private: Image Reader

    private func readImage(path: String, ext: String) throws -> ToolResult {
        guard let imageData = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return ToolResult(content: "Error: could not read image data from \(path)", isError: true)
        }
        let sizeBytes = imageData.count
        let mime = mimeType(for: ext)
        let base64 = imageData.base64EncodedString()

        // Try to get image dimensions on Apple platforms
        var dimensions: (Int, Int)?
        #if canImport(AppKit) || canImport(UIKit)
        if let imageRep = imageRepFromData(imageData) {
            dimensions = (Int(imageRep.pixelsWide), Int(imageRep.pixelsHigh))
        }
        #endif

        return ToolResult(data: .image(type: mime, data: base64, size: sizeBytes, dimensions: dimensions))
    }

    // MARK: - Private: PDF Reader

    private func readPDF(path: String, pages: String?) throws -> ToolResult {
        #if canImport(PDFKit)
        guard let pdf = PDFDocument(url: URL(fileURLWithPath: path)) else {
            return ToolResult(content: "Error: could not open PDF at \(path) — file may be corrupted or password-protected.", isError: true)
        }

        let pageCount = pdf.pageCount
        var extracted: [PDFPage] = []

        if let pagesStr = pages {
            let ranges = parsePageRanges(pagesStr, maxPage: pageCount)
            for i in ranges.prefix(20) {
                guard let page = pdf.page(at: i) else { continue }
                extracted.append(PDFPage(pageNumber: i + 1, text: page.string ?? ""))
            }
            if ranges.isEmpty {
                return ToolResult(content: "[PDF: \(pageCount) page(s)]\n\n(Invalid page range — no pages matched. Use formats like \"1-5\", \"3\", or \"10-20\".)", isError: true)
            }
        } else if pageCount <= 10 {
            for i in 0..<pageCount {
                guard let page = pdf.page(at: i) else { continue }
                extracted.append(PDFPage(pageNumber: i + 1, text: page.string ?? ""))
            }
        } else {
            // Show first page + guidance for larger PDFs
            if let page = pdf.page(at: 0) {
                extracted.append(PDFPage(pageNumber: 1, text: page.string ?? ""))
            }
            // Use content fallback for the guidance message since it's not a real page
            let guidance = "\n\nThis PDF has \(pageCount) pages. Use the 'pages' parameter to read specific ranges (e.g., pages: \"2-10\"). Maximum 20 pages per request."
            if extracted.isEmpty {
                return ToolResult(content: "[PDF: \(pageCount) page(s)]\(guidance)")
            }
            // Append guidance as a synthetic page (unconventional but preserves structured output)
            return ToolResult(content: extracted.map(\.textContent).joined(separator: "\n") + guidance)
        }

        return ToolResult(data: .pdf(pages: extracted))
        #else
        return ToolResult(content: "PDF reading is not available on this platform. Build with macOS for PDFKit support.\n\nFile: \(path)\n\nTo read this PDF, use the 'pages' parameter to extract specific pages, or install poppler-utils (brew install poppler) and use the Bash tool.")
        #endif
    }

    // MARK: - Private: Notebook Reader

    private func readNotebook(path: String) throws -> ToolResult {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ToolResult(content: "Error: could not parse notebook at \(path)", isError: true)
        }

        let rawCells = json["cells"] as? [[String: Any]] ?? []

        var cells: [NotebookCell] = []
        for rawCell in rawCells {
            let cellType = rawCell["cell_type"] as? String ?? "unknown"
            let sourceArr = cellSourceArray(rawCell)

            var outputs: [String]?
            if cellType == "code", let cellOutputs = rawCell["outputs"] as? [[String: Any]], !cellOutputs.isEmpty {
                outputs = cellOutputs.map(formatSingleOutput)
            }

            cells.append(NotebookCell(cellType: cellType, source: sourceArr, outputs: outputs))
        }

        return ToolResult(data: .notebook(cells: cells))
    }

    // MARK: - Private: Binary Detection

    private func isBinaryExtension(_ ext: String) -> Bool {
        let binaryExts: Set<String> = [
            "exe", "dll", "dylib", "so", "a", "o", "obj", "lib",
            "class", "jar", "war", "ear",
            "zip", "tar", "gz", "bz2", "xz", "zst", "7z", "rar",
            "dmg", "iso", "img",
            "ico", "tiff", "tif", "heic", "heif",
            "mp3", "mp4", "avi", "mov", "mkv", "wmv", "flv", "webm",
            "ogg", "oga", "ogv", "wav", "aac", "flac", "m4a",
            "ttf", "otf", "woff", "woff2", "eot",
            "wasm", "bc", "ll",
            "pyc", "pyo", "class",
            "db", "sqlite", "sqlite3", "mdb",
            "bin", "dat", "pak", "asset",
            "app", "framework", "bundle", "xcarchive",
            "pkg", "deb", "rpm",
        ]
        return binaryExts.contains(ext)
    }

    private func isBlockedDevicePath(_ path: String) -> Bool {
        let blocked: Set<String> = [
            "/dev/zero", "/dev/random", "/dev/urandom", "/dev/full",
            "/dev/stdin", "/dev/tty", "/dev/console",
            "/dev/stdout", "/dev/stderr",
            "/dev/fd/0", "/dev/fd/1", "/dev/fd/2",
        ]
        if blocked.contains(path) { return true }
        // /proc/self/fd/0-2 and /proc/<pid>/fd/0-2 Linux aliases
        if path.hasPrefix("/proc/") && (path.hasSuffix("/fd/0") || path.hasSuffix("/fd/1") || path.hasSuffix("/fd/2")) {
            return true
        }
        return false
    }

    // MARK: - Private: Notebook Helpers

    private func cellSourceArray(_ cell: [String: Any]) -> [String] {
        if let sourceStr = cell["source"] as? String {
            return [sourceStr]
        }
        if let sourceLines = cell["source"] as? [String] {
            return sourceLines
        }
        if let sourceMixed = cell["source"] as? [Any] {
            return sourceMixed.compactMap { $0 as? String }
        }
        return []
    }

    private func formatSingleOutput(_ output: [String: Any]) -> String {
        let outputType = output["output_type"] as? String ?? "unknown"
        switch outputType {
        case "stream":
            let name = output["name"] as? String ?? "stdout"
            let text = (output["text"] as? [String])?.joined() ?? ""
            return "[\(name)]: \(text)"
        case "execute_result", "display_data":
            if let data = output["data"] as? [String: Any] {
                if let textPlain = data["text/plain"] as? [String] {
                    return textPlain.joined()
                } else if let textPlain = data["text/plain"] as? String {
                    return textPlain
                } else {
                    let keys = data.keys.sorted().joined(separator: ", ")
                    return "[\(outputType): \(keys)]"
                }
            }
            return ""
        case "error":
            let ename = output["ename"] as? String ?? "Error"
            let evalue = output["evalue"] as? String ?? ""
            let traceback = (output["traceback"] as? [String])?.joined() ?? ""
            return "[ERROR: \(ename)] \(evalue)\n\(traceback)"
        default:
            if let textPlain = output["text/plain"] as? [String] {
                return textPlain.joined()
            }
            return ""
        }
    }

    // MARK: - Private: PDF Page Range Parsing

    private func parsePageRanges(_ spec: String, maxPage: Int) -> [Int] {
        var pages: Set<Int> = []
        for part in spec.split(separator: ",") {
            let trimmed = String(part).trimmingCharacters(in: .whitespaces)
            if trimmed.contains("-") {
                let bounds = trimmed.split(separator: "-", maxSplits: 1)
                if bounds.count == 2,
                   let start = Int(bounds[0]), let end = Int(bounds[1]) {
                    let from = max(1, min(start, maxPage))
                    let to = max(1, min(end, maxPage))
                    if from <= to {
                        pages.formUnion((from...to).map { $0 - 1 }) // 0-indexed internally
                    }
                }
            } else if let page = Int(trimmed), page >= 1, page <= maxPage {
                pages.insert(page - 1)
            }
        }
        return Array(pages).sorted()
    }

    /// Validates that the pages string has a plausible format, without knowing maxPage.
    private func parsePageRangesIsValid(_ spec: String) -> Bool {
        let parts = spec.split(separator: ",")
        guard !parts.isEmpty else { return false }
        for part in parts {
            let trimmed = String(part).trimmingCharacters(in: .whitespaces)
            if trimmed.contains("-") {
                let bounds = trimmed.split(separator: "-", maxSplits: 1)
                guard bounds.count == 2,
                      Int(bounds[0]) != nil,
                      Int(bounds[1]) != nil else { return false }
            } else {
                guard Int(trimmed) != nil else { return false }
            }
        }
        return true
    }

    private func pageRangeSize(_ spec: String) -> Int {
        var total = 0
        for part in spec.split(separator: ",") {
            let trimmed = String(part).trimmingCharacters(in: .whitespaces)
            if trimmed.contains("-") {
                let bounds = trimmed.split(separator: "-", maxSplits: 1)
                if bounds.count == 2,
                   let start = Int(bounds[0]), let end = Int(bounds[1]) {
                    total += max(0, end - start + 1)
                }
            } else if Int(trimmed) != nil {
                total += 1
            }
        }
        return total
    }

    // MARK: - Private: Helpers

    /// Format lines with cat -n style line numbers: 6-char right-aligned + tab + content.
    private func addLineNumbers(_ content: String, startLine: Int) -> String {
        let lines = content.components(separatedBy: .newlines)
        var result = ""
        for (i, line) in lines.enumerated() {
            let lineNum = startLine + i
            result += String(format: "%6d\t", lineNum) + line
            if i < lines.count - 1 {
                result += "\n"
            }
        }
        return result
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        if bytes < 1024 { return "\(bytes)B" }
        if bytes < 1024 * 1024 { return String(format: "%.1fKB", Double(bytes) / 1024) }
        return String(format: "%.1fMB", Double(bytes) / (1024 * 1024))
    }

    private func mimeType(for ext: String) -> String {
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "bmp": return "image/bmp"
        case "svg": return "image/svg+xml"
        default: return "application/octet-stream"
        }
    }

    #if canImport(AppKit) || canImport(UIKit)
    private func imageRepFromData(_ data: Data) -> NSImageRep? {
        #if canImport(AppKit)
        if let rep = NSBitmapImageRep(data: data) {
            return rep
        }
        if let image = NSImage(data: data),
           let rep = image.representations.first {
            return rep
        }
        #endif
        return nil
    }
    #endif
}
