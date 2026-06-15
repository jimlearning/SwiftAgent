import SwiftUI

// MARK: - Accessibility Label Modifier

extension View {
    /// Apply an accessibility label with a hint for activation.
    func a11yLabel(_ text: String) -> some View {
        self.accessibilityLabel(text)
            .accessibilityHint(Text("Press Enter to activate"))
    }

    /// Mark this element as a keyboard-interactive key.
    func a11yKeyboardKey() -> some View {
        self.accessibilityAddTraits(.isKeyboardKey)
    }

    /// Apply increased contrast when the system setting is active.
    func a11yHighContrast(enabled: Bool) -> some View {
        self.modifier(HighContrastModifier(enabled: enabled))
    }

    /// Add textual status for screen readers that supplements visual indicators.
    func a11yStatusDot(_ status: String) -> some View {
        self.accessibilityLabel("Status: \(status)")
            .accessibilityAddTraits(.updatesFrequently)
    }

    /// Make this element focusable and keyboard-navigable.
    func a11yFocusable() -> some View {
        self.accessibilityAddTraits(.isButton)
            .focusable()
    }
}

// MARK: - High Contrast Modifier

private struct HighContrastModifier: ViewModifier {
    let enabled: Bool
    @Environment(\.colorSchemeContrast) var colorSchemeContrast

    func body(content: Content) -> some View {
        if enabled || colorSchemeContrast == .increased {
            content
                .border(Color.borderStrong, width: 1.5)
        } else {
            content
        }
    }
}

// MARK: - Dynamic Type Support

extension View {
    /// Scale font sizes based on Dynamic Type setting.
    func a11yDynamicType() -> some View {
        self.modifier(DynamicTypeModifier())
    }
}

private struct DynamicTypeModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    func body(content: Content) -> some View {
        content
            // SwiftUI automatically handles Dynamic Type when using system fonts.
            // This modifier serves as documentation anchor for a11y compliance.
    }
}

// MARK: - Reduce Motion Detection

extension View {
    /// Apply a modifier that checks for the Reduce Motion accessibility setting.
    func a11yReduceMotionAware<Value: Equatable>(
        animation: Animation? = .default,
        value: Value
    ) -> some View {
        modifier(A11yReduceMotionModifier(animation: animation, value: value))
    }
}

private struct A11yReduceMotionModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    let animation: Animation?
    let value: Value

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.animation(animation, value: value)
        }
    }
}

// MARK: - VoiceOver Groups

extension View {
    /// Group related elements for VoiceOver navigation.
    func a11yGroup(label: String) -> some View {
        self.accessibilityElement(children: .combine)
            .accessibilityLabel(label)
    }
}

// MARK: - Semantic Color Check

extension View {
    /// Ensures that color-based information is also conveyed via text/icon.
    func a11ySemanticColor(label: String) -> some View {
        self.accessibilityLabel(label)
    }
}
