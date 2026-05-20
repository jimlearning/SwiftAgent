import Foundation

/// Detects terminal capabilities: TTY, color support, dimensions.
public struct TerminalCapability: Sendable {
    public let isTTY: Bool
    public let supportsColor: Bool
    public let columns: Int
    public let rows: Int

    public init() {
        self.isTTY = isatty(STDIN_FILENO) != 0 && isatty(STDOUT_FILENO) != 0
        self.supportsColor = Self.detectColorSupport()
        (self.columns, self.rows) = Self.detectSize()
    }

    /// Create with forced values for testing.
    public init(isTTY: Bool, supportsColor: Bool, columns: Int, rows: Int) {
        self.isTTY = isTTY
        self.supportsColor = supportsColor
        self.columns = columns
        self.rows = rows
    }

    private static func detectColorSupport() -> Bool {
        // Check TERM and COLORTERM environment variables
        if let colorTerm = ProcessInfo.processInfo.environment["COLORTERM"], !colorTerm.isEmpty {
            return true
        }
        if let term = ProcessInfo.processInfo.environment["TERM"] {
            return term.contains("color") || term.contains("256") || term == "xterm"
        }
        return false
    }

    private static func detectSize() -> (columns: Int, rows: Int) {
        var size = winsize()
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &size) == 0 {
            let cols = Int(size.ws_col)
            let rows = Int(size.ws_row)
            if cols > 0, rows > 0 {
                return (cols, rows)
            }
        }
        // Fallback to environment or defaults
        let cols = Int(ProcessInfo.processInfo.environment["COLUMNS"] ?? "80") ?? 80
        let rows = Int(ProcessInfo.processInfo.environment["LINES"] ?? "24") ?? 24
        return (cols, rows)
    }

    /// Emit ANSI codes only if color is supported.
    public func color(_ text: String, color: ANSIColor, style: ANIStyle? = nil) -> String {
        guard supportsColor else { return text }
        return ansi(text, color: color, style: style)
    }

    /// Scrub ANSI codes for non-TTY output.
    public func scrubANSICodes(_ text: String) -> String {
        if isTTY { return text }
        let pattern = "\u{001B}\\[[0-9;]*[a-zA-Z]"
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }
}
