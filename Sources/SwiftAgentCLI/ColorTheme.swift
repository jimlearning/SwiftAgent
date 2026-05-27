/// ANSI color theme for terminal output.
public struct ColorTheme: Sendable {
    public let name: String

    public var primary: ANSIColor
    public var secondary: ANSIColor
    public var success: ANSIColor
    public var warning: ANSIColor
    public var error: ANSIColor
    public var dim: ANSIColor
    public var bold: ANIStyle

    public static let `default` = ColorTheme(
        name: "default",
        primary: .blue,
        secondary: .cyan,
        success: .green,
        warning: .yellow,
        error: .red,
        dim: .brightBlack,
        bold: .bold
    )

    public static let monochrome = ColorTheme(
        name: "monochrome",
        primary: .white,
        secondary: .brightBlack,
        success: .white,
        warning: .white,
        error: .white,
        dim: .brightBlack,
        bold: .bold
    )
}

public enum ANSIColor: Sendable {
    case black
    case red
    case green
    case yellow
    case blue
    case magenta
    case cyan
    case white
    case brightBlack
    case brightRed
    case brightGreen
    case brightYellow
    case brightBlue
    case brightMagenta
    case brightCyan
    case brightWhite
    case trueColor(r: UInt8, g: UInt8, b: UInt8)

    public func foreground() -> String {
        switch self {
        case .trueColor(let r, let g, let b):
            return "\u{001B}[38;2;\(r);\(g);\(b)m"
        default:
            return "\u{001B}[\(ansiCode)m"
        }
    }

    public func background() -> String {
        switch self {
        case .trueColor(let r, let g, let b):
            return "\u{001B}[48;2;\(r);\(g);\(b)m"
        default:
            return "\u{001B}[\(ansiCode + 10)m"
        }
    }

    private var ansiCode: Int {
        switch self {
        case .black: 30
        case .red: 31
        case .green: 32
        case .yellow: 33
        case .blue: 34
        case .magenta: 35
        case .cyan: 36
        case .white: 37
        case .brightBlack: 90
        case .brightRed: 91
        case .brightGreen: 92
        case .brightYellow: 93
        case .brightBlue: 94
        case .brightMagenta: 95
        case .brightCyan: 96
        case .brightWhite: 97
        case .trueColor: 0 // unreachable
        }
    }
}

public enum ANIStyle: String, Sendable {
    case reset = "0"
    case bold = "1"
    case dim = "2"
    case italic = "3"
    case underline = "4"
    case blink = "5"

    public var code: String { "\u{001B}[\(rawValue)m" }
    public static var resetCode: String { "\u{001B}[0m" }
}

/// Convenience: colorize a string with a color and/or style.
public func ansi(_ text: String, color: ANSIColor? = nil, style: ANIStyle? = nil) -> String {
    var prefix = ""
    if let c = color { prefix += c.foreground() }
    if let s = style { prefix += s.code }
    guard !prefix.isEmpty else { return text }
    return prefix + text + "\u{001B}[0m"
}
