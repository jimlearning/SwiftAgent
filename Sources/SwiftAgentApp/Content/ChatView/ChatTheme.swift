import SwiftUI

/// Design tokens mapped from ClaudeTheme to SwiftAgent's DesignSystem.
/// ClarcChatKit views reference `ClaudeTheme.xxx` — this enum provides the same
/// interface using SwiftAgent's existing Color/Font/Spacing/Radius extensions.
enum ChatTheme {
    // MARK: - Backgrounds
    static let background = Color.bgContent
    static let surfacePrimary = Color.bgElevated
    static let surfaceSecondary = Color.bgSidebar
    static let surfaceTertiary = Color.bgElevated.opacity(0.5)
    static let inputBackground = Color.bgInput

    // MARK: - Text
    static let textPrimary = Color.textPrimary
    static let textSecondary = Color.textSecondary
    static let textTertiary = Color.textTertiary

    // MARK: - Accent & Status
    static let accent = Color.accentPrimary
    static let accentSubtle = Color.accentPrimary.opacity(0.15)
    static let statusSuccess = Color.success
    static let statusError = Color.danger
    static let statusWarning = Color.warning

    // MARK: - Borders
    static let border = Color.borderStrong
    static let borderSubtle = Color.borderSubtle

    // MARK: - Bubbles
    static let userBubble = Color.accentPrimary
    static let userBubbleText = Color.white
    static let assistantBubble = Color.bgElevated

    // MARK: - Code
    static let codeBackground = Color.bgInput
    static let codeHeaderBackground = Color.bgSidebar

    // MARK: - Sizes (Clarc uses `ClaudeTheme.size(_:)` for relative sizing)
    static func size(_ pt: CGFloat) -> CGFloat { pt }
    static func messageSize(_ pt: CGFloat) -> CGFloat { pt }

    // MARK: - Corner Radii
    static let cornerRadiusSmall: CGFloat = .radiusSmall
    static let cornerRadiusMedium: CGFloat = .radiusCard
    static let cornerRadiusLarge: CGFloat = .radiusContainer
    static let cornerRadiusPill: CGFloat = .radiusPopup  // 20pt — matches Clarc's pill radius (not a full capsule)

    // MARK: - Divider
    struct ChatThemeDivider: View {
        var body: some View {
            Rectangle().fill(ChatTheme.border).frame(height: 1)
        }
    }
}

/// Convenience divider matching `ClaudeThemeDivider()` calls in ported views.
typealias ClaudeThemeDivider = ChatTheme.ChatThemeDivider

/// Theme change notification — ported views observe this for cache invalidation.
extension Notification.Name {
    static let clarcThemeDidChange = Notification.Name("ChatThemeDidChange")
}

// MARK: - Localization stub

/// Stub for `String(localized:bundle:)` — ClarcChatKit uses `.module` bundle.
/// In SwiftAgent, localizations live in the main bundle.
extension String {
    init(localized key: String.LocalizationValue, bundle: Bundle) {
        self.init(localized: key)
    }
}

// MARK: - Clipboard helper

import AppKit

func copyToClipboard(_ text: String, feedback: Binding<Bool>) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    feedback.wrappedValue = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        feedback.wrappedValue = false
    }
}
