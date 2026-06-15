import SwiftUI

/// Central animation token definitions per §8 of the product spec.
enum AnimationTokens {
    // MARK: - Duration

    /// Appshot success animation: 1.2s scale + opacity
    static let appshotSuccess: Double = 1.2

    /// Thread list add/remove: 200-300ms ease-in-out
    static let threadList: Double = 0.25

    /// Diff row expand/collapse: 150-200ms ease-out
    static let diffRow: Double = 0.18

    /// Button hover feedback: 100ms linear
    static let buttonHover: Double = 0.1

    /// Composer focus: 150ms linear
    static let composerFocus: Double = 0.15

    /// Status "Thought for Xs": 200ms opacity + move from top
    static let statusThought: Double = 0.2

    /// Modal popup: 250ms spring
    static let modalPopup: Double = 0.25

    /// Toast enter: 200ms
    static let toastEnter: Double = 0.2

    /// Toast exit: 300ms
    static let toastExit: Double = 0.3

    // MARK: - Easings

    static let easeInOut = Animation.easeInOut(duration: threadList)
    static let easeOut = Animation.easeOut(duration: diffRow)
    static let linear = Animation.linear(duration: buttonHover)
    static let spring = Animation.spring(response: modalPopup, dampingFraction: 0.8)
}

// MARK: - View extensions for common animations

extension View {
    /// Fade in/out transition.
    func swiftuiFade(duration: Double = 0.2) -> some View {
        self.transition(.opacity.animation(.easeInOut(duration: duration)))
    }

    /// Slide from bottom + fade.
    func swiftuiSlideFromBottom(duration: Double = 0.2) -> some View {
        self.transition(.move(edge: .bottom).combined(with: .opacity)
            .animation(.easeOut(duration: duration)))
    }

    /// Slide from top + fade.
    func swiftuiSlideFromTop(duration: Double = 0.2) -> some View {
        self.transition(.move(edge: .top).combined(with: .opacity)
            .animation(.easeInOut(duration: duration)))
    }

    /// Scale + opacity (used for appshot success).
    func swiftuiScalePop(duration: Double = 0.3) -> some View {
        self.transition(.scale.combined(with: .opacity)
            .animation(.spring(response: duration, dampingFraction: 0.7)))
    }

    /// Applies reduce-motion aware animation.
    func withReduceMotionAwareAnimation(
        _ animation: Animation? = .default,
        value: some Equatable
    ) -> some View {
        modifier(ReduceMotionAnimationModifier(animation: animation, value: value))
    }

    /// Honors macOS Reduce Motion accessibility setting.
    func swiftuiAccessibleAnimation(
        _ animation: Animation? = .default,
        value: some Equatable
    ) -> some View {
        self.animation(animation, value: value)
    }
}

/// View modifier that respects the Reduce Motion accessibility setting.
private struct ReduceMotionAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    let animation: Animation?
    let value: V

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.animation(animation, value: value)
        }
    }
}
