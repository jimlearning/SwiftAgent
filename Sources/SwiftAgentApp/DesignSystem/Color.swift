import SwiftUI

extension Color {
    // Dark mode backgrounds
    static let bgSidebar      = Color(red: 0.165, green: 0.165, blue: 0.165)  // #2A2A2A
    static let bgContent      = Color(red: 0.110, green: 0.110, blue: 0.110)  // #1C1C1C
    static let bgRightPanel   = Color(red: 0.000, green: 0.000, blue: 0.000)  // #000000
    static let bgElevated     = Color(red: 0.165, green: 0.165, blue: 0.165)  // #2A2A2A
    static let bgInput        = Color(red: 0.122, green: 0.122, blue: 0.122)  // #1F1F1F

    // Text
    static let textPrimary    = Color(red: 0.961, green: 0.961, blue: 0.961)  // #F5F5F5
    static let textSecondary  = Color(red: 0.600, green: 0.600, blue: 0.600)  // #999999
    static let textTertiary   = Color(red: 0.400, green: 0.400, blue: 0.400)  // #666666

    // Accent & status
    static let accentPrimary  = Color(red: 0.200, green: 0.612, blue: 1.000)  // #339CFF
    static let success        = Color(red: 0.247, green: 0.725, blue: 0.314)  // #3FB950
    static let danger         = Color(red: 0.973, green: 0.318, blue: 0.286)  // #F85149
    static let warning        = Color(red: 0.890, green: 0.702, blue: 0.255)  // #E3B341

    // Borders
    static let borderSubtle   = Color(red: 0.165, green: 0.165, blue: 0.165)  // #2A2A2A
    static let borderStrong   = Color(red: 0.227, green: 0.227, blue: 0.227)  // #3A3A3A

    /// Initialize from a hex string (e.g. "#339CFF" or "339CFF").
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}
