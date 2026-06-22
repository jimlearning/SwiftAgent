import SwiftUI

/// Horizontal drag handle that adjusts a bound height within a range.
///
/// Like `DragDivider` but for vertical resizing: 6pt invisible hit area,
/// 1pt visual line, resize-up-down cursor.
///
/// The `edge` parameter controls whether the visual line hugs the top or
/// bottom of the hit area, so it aligns with the adjacent pane junction.
struct HorizontalDragDivider: View {
    @Binding var height: CGFloat
    let range: ClosedRange<CGFloat>
    /// `.top` for dividers above the resizable pane (visual line at top of hit area).
    /// `.bottom` for dividers below the resizable pane.
    var edge: VerticalEdge = .top
    var color: Color = .borderStrong

    private let hitHeight: CGFloat = 6
    private let visualHeight: CGFloat = 1

    @State private var initialHeight: CGFloat?

    private var visualAlignment: Alignment {
        switch edge {
        case .top:    return .top
        case .bottom: return .bottom
        }
    }

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: hitHeight)
            .contentShape(Rectangle())
            .overlay(alignment: visualAlignment) {
                Rectangle()
                    .fill(color)
                    .frame(height: visualHeight)
            }
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.resizeUpDown.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = initialHeight ?? height
                        initialHeight = start
                        // Negate: dragging up (negative y delta) increases height.
                        let globalDelta = value.startLocation.y - value.location.y
                        height = max(range.lowerBound,
                                     min(range.upperBound,
                                         start + globalDelta))
                    }
                    .onEnded { _ in
                        initialHeight = nil
                    }
            )
    }
}
