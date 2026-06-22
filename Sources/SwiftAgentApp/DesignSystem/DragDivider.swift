import SwiftUI

/// A thin vertical drag handle that adjusts a bound width within a range.
///
/// Uses a 6pt invisible hit area so the divider is easy to grab, with a
/// 1pt visual line. Shows the resize-left-right cursor on hover and
/// applies a DragGesture that clamps output to the given range.
///
/// When `inverted` is true, the drag translation is negated so dragging
/// left increases the width. Use this for dividers that sit at the
/// leading edge of the pane they resize (e.g. right pane): pulling the
/// divider into the content area widens the adjacent panel.
///
/// Uses `.global` coordinate space so the cursor delta is measured in
/// screen-absolute coordinates and isn't affected by layout changes that
/// reposition the divider mid-drag (avoids the feedback loop).
struct DragDivider: View {
    @Binding var width: CGFloat
    let range: ClosedRange<CGFloat>
    var inverted: Bool = false
    /// Which edge the visual line hugs (the junction between panes).
    /// `.leading` for dividers after the left pane, `.trailing` for
    /// dividers before the right pane.
    var edge: HorizontalEdge = .leading
    var color: Color = .clear

    private let hitWidth: CGFloat = 6
    private let visualWidth: CGFloat = 1

    @State private var initialWidth: CGFloat?

    private var visualAlignment: Alignment {
        switch edge {
        case .leading:  return .leading
        case .trailing: return .trailing
        }
    }

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: hitWidth)
            .contentShape(Rectangle())
            .overlay(alignment: visualAlignment) {
                Rectangle()
                    .fill(color)
                    .frame(width: visualWidth)
            }
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.resizeLeftRight.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = initialWidth ?? width
                        initialWidth = start
                        let globalDelta = value.location.x - value.startLocation.x
                        let delta = inverted ? -globalDelta : globalDelta
                        width = max(range.lowerBound,
                                    min(range.upperBound,
                                        start + delta))
                    }
                    .onEnded { _ in
                        initialWidth = nil
                    }
            )
    }
}
