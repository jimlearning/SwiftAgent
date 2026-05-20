import Foundation

/// Binary file extensions and detection utilities matching Claude Code's constants/files.ts.
/// These extensions are skipped for text-based operations (diff, edit, etc.).

public let BINARY_EXTENSIONS: Set<String> = [
    // Images
    ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".ico", ".webp", ".tiff", ".tif",
    // Videos
    ".mp4", ".mov", ".avi", ".mkv", ".webm", ".wmv", ".flv", ".m4v", ".mpeg", ".mpg",
    // Audio
    ".mp3", ".wav", ".ogg", ".flac", ".aac", ".m4a", ".wma", ".aiff", ".opus",
    // Archives
    ".zip", ".tar", ".gz", ".bz2", ".7z", ".rar", ".xz", ".z", ".tgz", ".iso",
    // Executables/binaries
    ".exe", ".dll", ".so", ".dylib", ".bin", ".o", ".a", ".obj", ".lib",
    ".app", ".msi", ".deb", ".rpm",
    // Documents
    ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx", ".odt", ".ods", ".odp",
    // Fonts
    ".ttf", ".otf", ".woff", ".woff2", ".eot",
    // Bytecode
    ".pyc", ".pyo", ".class", ".jar", ".war", ".ear", ".node", ".wasm", ".rlib",
    // Database
    ".sqlite", ".sqlite3", ".db", ".mdb", ".idx",
    // Design / 3D
    ".psd", ".ai", ".eps", ".sketch", ".fig", ".xd", ".blend", ".3ds", ".max",
    // Flash
    ".swf", ".fla",
    // Lock/profiling data
    ".lockb", ".dat", ".data",
]

/// Number of bytes to read for binary content detection. CC: BINARY_CHECK_SIZE = 8192
public let BINARY_CHECK_SIZE = 8192

/// Check if a file path has a binary extension. CC: hasBinaryExtension()
public func hasBinaryExtension(_ filePath: String) -> Bool {
    guard let ext = filePath.lastIndex(of: ".").map({ filePath[$0...].lowercased() }) else { return false }
    return BINARY_EXTENSIONS.contains(String(ext))
}

/// Check if data contains binary content (null bytes or >10% non-printable chars).
/// CC: isBinaryContent(buffer)
public func isBinaryContent(_ data: Data) -> Bool {
    let checkSize = min(data.count, BINARY_CHECK_SIZE)
    var nonPrintable = 0
    for i in 0..<checkSize {
        let byte = data[i]
        if byte == 0 { return true }
        if byte < 32 && byte != 9 && byte != 10 && byte != 13 {
            nonPrintable += 1
        }
    }
    return Double(nonPrintable) / Double(checkSize) > 0.1
}
