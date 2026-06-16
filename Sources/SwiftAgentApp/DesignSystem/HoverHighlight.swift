import SwiftUI

/// Adds a hover highlight to any view: when the pointer enters the
/// view's rectangle, the background switches to `hoverBackground` and
/// (optionally) the foreground color changes. Pointer exit restores
/// the original colors.
///
/// Crucially, this modifier also calls `.contentShape(Rectangle())`
/// on the underlying view, which is what fixes the "click on the
/// blank padding area doesn't respond" bug — without contentShape,
/// SwiftUI's hit-test region is the rendered opaque pixels only, so
/// padded cells have dead zones around their labels.
///
/// Apply to any view that should feel like a button or selectable
/// row:
/// ```swift
/// Text("New chat")
///     .hoverHighlight()           // default look
/// Text("Submit")
///     .hoverHighlight(cornerRadius: 6, padding: .horizontal)
/// ```
public struct HoverHighlight: ViewModifier {
    @State private var isHovering: Bool = false

    public var hoverBackground: Color
    public var hoverForeground: Color?
    public var cornerRadius: CGFloat
    public var padding: EdgeInsets

    public init(
        hoverBackground: Color = Color.white.opacity(0.06),
        hoverForeground: Color? = nil,
        cornerRadius: CGFloat = 4,
        padding: EdgeInsets = EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
    ) {
        self.hoverBackground = hoverBackground
        self.hoverForeground = hoverForeground
        self.cornerRadius = cornerRadius
        self.padding = padding
    }

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isHovering ? hoverBackground : Color.clear)
            )
            .foregroundColor(hoverForeground)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.1), value: isHovering)
    }
}

public extension View {
    /// Apply a hover highlight (background fade + full-row hit region).
    func hoverHighlight(
        background: Color = Color.white.opacity(0.06),
        foreground: Color? = nil,
        cornerRadius: CGFloat = 4,
        padding: EdgeInsets = EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
    ) -> some View {
        modifier(HoverHighlight(
            hoverBackground: background,
            hoverForeground: foreground,
            cornerRadius: cornerRadius,
            padding: padding
        ))
    }
}
