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

public enum ANSIColor: String, Sendable {
    case black = "30"
    case red = "31"
    case green = "32"
    case yellow = "33"
    case blue = "34"
    case magenta = "35"
    case cyan = "36"
    case white = "37"
    case brightBlack = "90"
    case brightRed = "91"
    case brightGreen = "92"
    case brightYellow = "93"
    case brightBlue = "94"
    case brightMagenta = "95"
    case brightCyan = "96"
    case brightWhite = "97"

    public func foreground() -> String { "\u{001B}[\(rawValue)m" }
    public func background() -> String { "\u{001B}[\(Int(rawValue)! + 10)m" }
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
    var codes: [String] = []
    if let c = color { codes.append(c.rawValue) }
    if let s = style { codes.append(s.rawValue) }
    guard !codes.isEmpty else { return text }
    return "\u{001B}[\(codes.joined(separator: ";"))m\(text)\u{001B}[0m"
}
