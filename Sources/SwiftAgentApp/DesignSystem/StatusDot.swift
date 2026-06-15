import SwiftUI

/// A small colored dot used for status indicators (per §4.7).
public struct StatusDot: View {
    public enum Style {
        case idle      // gray
        case active    // blue, pulsing
        case done      // blue, solid
        case failed    // red
        case cancelled // gray

        var color: Color {
            switch self {
            case .idle: return .textTertiary
            case .active: return .accentPrimary
            case .done: return .accentPrimary
            case .failed: return .danger
            case .cancelled: return .textTertiary
            }
        }
    }

    let style: Style
    let size: CGFloat

    public init(style: Style = .idle, size: CGFloat = 8) {
        self.style = style
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(style.color)
            .frame(width: size, height: size)
    }
}
