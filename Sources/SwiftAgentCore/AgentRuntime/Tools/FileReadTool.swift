import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

/// Reads a file from the local filesystem.
/// Supports text, images, PDFs, and Jupyter notebooks.
public struct FileReadTool: Tool {
    public let name = "Read"
    public let description = "Reads a file from the local filesystem. You can access any file directly by using this tool."

    private let workingDirectory: String

    public struct Arguments: Codable, Sendable {
        public var filePath: String
        public var offset: Int?
        public var limit: Int?
        public var pages: String?

        enum CodingKeys: String, CodingKey {
            case filePath = "file_path"
            case offset
            case limit
            case pages
        }
    }

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "file_path": JSONSchemaProperty(type: "string", description: "The absolute path to the file to read"),
            "offset": JSONSchemaProperty(type: "number", description: "The line number to start reading from. Only provide if the file is too large to read at once"),
            "limit": JSONSchemaProperty(type: "number", description: "The number of lines to read. Only provide if the file is too large to read at once."),
            "pages": JSONSchemaProperty(type: "string", description: "Page range for PDF files (e.g., \"1-5\", \"3\", \"10-20\"). Only applicable to PDF files. Maximum 20 pages per request."),
        ], required: ["file_path"])
    }

    public init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        let path = arguments.filePath

        if isBlockedDevicePath(path) {
            return .string("Error: cannot read device file at \(path)")
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            return .string("Error: file not found at \(path). The current working directory is \(workingDirectory).")
        }
        guard fm.isReadableFile(atPath: path) else {
            return .string("Error: cannot read file at \(path) — permission denied.")
        }

        // Validate pages parameter
        if let pages = arguments.pages {
            guard parsePageRangesIsValid(pages) else {
                return .string("Invalid pages parameter: \"\(pages)\". Use formats like \"1-5\", \"3\", or \"10-20\". Pages are 1-indexed.")
            }
            let rangeSize = pageRangeSize(pages)
            if rangeSize > 20 {
                return .string("Page range \"\(pages)\" exceeds maximum of 20 pages per request. Please use a smaller range.")
            }
        }

        // Reject known binary extensions
        let ext = (path as NSString).pathExtension.lowercased()
        if isBinaryExtension(ext) {
            return .string("This tool cannot read binary files. The file appears to be a binary .\(ext) file. Please use appropriate tools for binary file analysis.")
        }

        // Route by type
        let imageExts = Set(["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg"])
        if imageExts.contains(ext) {
            return try readImage(path: path, ext: ext)
        }
        if ext == "pdf" {
            return try readPDF(path: path, pages: arguments.pages)
        }
        if ext == "ipynb" {
            return try readNotebook(path: path)
        }
        return try readText(path: path, arguments: arguments)
    }

    // MARK: - Text Reader

    private func readText(path: String, arguments: Arguments) throws -> ToolOutputValue {
        let maxSizeBytes = 256 * 1024
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let fileSize = (attrs[.size] as? UInt64) ?? 0

        guard let rawContent = try? String(contentsOfFile: path, encoding: .utf8) else {
            return .string("Cannot display content of binary file: \(path)")
        }

        let lines = rawContent.components(separatedBy: .newlines)
        let totalLines = lines.count

        let offset = arguments.offset ?? 1
        let startLine: Int
        if offset <= 0 { startLine = 0 }
        else { startLine = min(offset - 1, max(totalLines - 1, 0)) }

        if arguments.limit == nil && fileSize > maxSizeBytes {
            return .string("""
                File is too large (\(formatBytes(fileSize))). \
                Use the offset and limit parameters to read specific portions of the file. \
                Total lines: \(totalLines). \
                Example: offset=1, limit=100 to read the first 100 lines.
                """)
        }

        let count = arguments.limit.map { min($0, totalLines - startLine) } ?? (totalLines - startLine)
        let end = min(startLine + count, totalLines)

        guard startLine < end else {
            let warning: String
            if totalLines == 0 {
                warning = "<system-reminder>Warning: the file exists but the contents are empty.</system-reminder>"
            } else {
                warning = "<system-reminder>Warning: the file exists but is shorter than the provided offset (\(offset)). The file has \(totalLines) lines.</system-reminder>"
            }
            return .string(warning)
        }

        let slice = lines[startLine..<end]
        let content = slice.joined(separator: "\n")
        let formatted = addLineNumbers(content, startLine: startLine + 1)

        let summary: String
        if count < totalLines {
            summary = "\n\n[Lines \(startLine + 1)-\(end) of \(totalLines) — use offset/limit for more]"
        } else {
            summary = ""
        }

        return .string(formatted + summary)
    }

    // MARK: - Image Reader

    private func readImage(path: String, ext: String) throws -> ToolOutputValue {
        guard let imageData = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return .string("Error: could not read image data from \(path)")
        }
        let sizeBytes = imageData.count
        let mime = mimeType(for: ext)
        let base64 = imageData.base64EncodedString()

        #if canImport(AppKit) || canImport(UIKit)
        var dimensions: (Int, Int)?
        if let imageRep = imageRepFromData(imageData) {
            dimensions = (Int(imageRep.pixelsWide), Int(imageRep.pixelsHigh))
        }
        #endif

        let sizeInfo = ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
        var desc = "[Image: \(mime), \(sizeInfo)"
        #if canImport(AppKit) || canImport(UIKit)
        if let dims = dimensions { desc += ", \(dims.0)x\(dims.1)px" }
        #endif
        desc += "]"

        return .string(desc)
    }

    // MARK: - PDF Reader

    private func readPDF(path: String, pages: String?) throws -> ToolOutputValue {
        #if canImport(PDFKit)
        guard let pdf = PDFDocument(url: URL(fileURLWithPath: path)) else {
            return .string("Error: could not open PDF at \(path) — file may be corrupted or password-protected.")
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
                return .string("[PDF: \(pageCount) page(s)]\n\n(Invalid page range — no pages matched. Use formats like \"1-5\", \"3\", or \"10-20\".)")
            }
        } else if pageCount <= 10 {
            for i in 0..<pageCount {
                guard let page = pdf.page(at: i) else { continue }
                extracted.append(PDFPage(pageNumber: i + 1, text: page.string ?? ""))
            }
        } else {
            if let page = pdf.page(at: 0) {
                extracted.append(PDFPage(pageNumber: 1, text: page.string ?? ""))
            }
            let guidance = "\n\nThis PDF has \(pageCount) pages. Use the 'pages' parameter to read specific ranges (e.g., pages: \"2-10\"). Maximum 20 pages per request."
            if extracted.isEmpty {
                return .string("[PDF: \(pageCount) page(s)]\(guidance)")
            }
            return .string(extracted.map(\.textContent).joined(separator: "\n") + guidance)
        }

        return .string(extracted.map(\.textContent).joined(separator: "\n"))
        #else
        return .string("PDF reading is not available on this platform. Build with macOS for PDFKit support.\n\nFile: \(path)\n\nTo read this PDF, use the 'pages' parameter to extract specific pages, or install poppler-utils (brew install poppler) and use the Bash tool.")
        #endif
    }

    // MARK: - Notebook Reader

    private func readNotebook(path: String) throws -> ToolOutputValue {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .string("Error: could not parse notebook at \(path)")
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

        return .string(cells.map(\.textContent).joined(separator: "\n\n"))
    }

    // MARK: - Helpers

    private func addLineNumbers(_ content: String, startLine: Int) -> String {
        let lines = content.components(separatedBy: .newlines)
        var result = ""
        for (i, line) in lines.enumerated() {
            result += String(format: "%6d\t", startLine + i) + line
            if i < lines.count - 1 { result += "\n" }
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
        if path.hasPrefix("/proc/") && (path.hasSuffix("/fd/0") || path.hasSuffix("/fd/1") || path.hasSuffix("/fd/2")) {
            return true
        }
        return false
    }

    private func parsePageRanges(_ spec: String, maxPage: Int) -> [Int] {
        var pages: Set<Int> = []
        for part in spec.split(separator: ",") {
            let trimmed = String(part).trimmingCharacters(in: .whitespaces)
            if trimmed.contains("-") {
                let bounds = trimmed.split(separator: "-", maxSplits: 1)
                if bounds.count == 2, let start = Int(bounds[0]), let end = Int(bounds[1]) {
                    let from = max(1, min(start, maxPage))
                    let to = max(1, min(end, maxPage))
                    if from <= to { pages.formUnion((from...to).map { $0 - 1 }) }
                }
            } else if let page = Int(trimmed), page >= 1, page <= maxPage {
                pages.insert(page - 1)
            }
        }
        return Array(pages).sorted()
    }

    private func parsePageRangesIsValid(_ spec: String) -> Bool {
        let parts = spec.split(separator: ",")
        guard !parts.isEmpty else { return false }
        for part in parts {
            let trimmed = String(part).trimmingCharacters(in: .whitespaces)
            if trimmed.contains("-") {
                let bounds = trimmed.split(separator: "-", maxSplits: 1)
                guard bounds.count == 2, Int(bounds[0]) != nil, Int(bounds[1]) != nil else { return false }
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
                if bounds.count == 2, let start = Int(bounds[0]), let end = Int(bounds[1]) {
                    total += max(0, end - start + 1)
                }
            } else if Int(trimmed) != nil { total += 1 }
        }
        return total
    }

    private func cellSourceArray(_ cell: [String: Any]) -> [String] {
        if let sourceStr = cell["source"] as? String { return [sourceStr] }
        if let sourceLines = cell["source"] as? [String] { return sourceLines }
        if let sourceMixed = cell["source"] as? [Any] { return sourceMixed.compactMap { $0 as? String } }
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
                if let textPlain = data["text/plain"] as? [String] { return textPlain.joined() }
                else if let textPlain = data["text/plain"] as? String { return textPlain }
                else {
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
            if let textPlain = output["text/plain"] as? [String] { return textPlain.joined() }
            return ""
        }
    }

    #if canImport(AppKit) || canImport(UIKit)
    private func imageRepFromData(_ data: Data) -> NSImageRep? {
        #if canImport(AppKit)
        if let rep = NSBitmapImageRep(data: data) { return rep }
        if let image = NSImage(data: data), let rep = image.representations.first { return rep }
        #endif
        return nil
    }
    #endif
}
