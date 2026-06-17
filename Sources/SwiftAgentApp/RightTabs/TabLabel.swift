import SwiftUI

/// Codex-style right-pane tab label.
///
/// Layout invariants:
/// - Tab width follows its content (title text length + icon slot +
///   padding). NOT pinned to a fixed min/max — short titles produce
///   short tabs, long titles produce long tabs.
/// - The tab NEVER resizes based on hover state. The type icon and the
///   close icon render at the SAME point size (11pt) so glyph widths
///   match; the title text column stays put across the icon swap.
/// - Resting state: leading slot shows the tab-type icon
///   (checklist / terminal / globe / folder / plus.circle).
/// - Hovering the tab (but not the icon): same slot swaps to `xmark`
///   in the resting close color (`textPrimary`, near-white).
/// - Hovering the close icon itself: xmark stays put but brightens
///   to pure `.white` as a "this is the action target" cue.
/// - Hover background across the full tab cell; active tab has its
///   own background plus a 2pt accent stripe at the bottom.
/// - Clicking the title area activates the tab; clicking the close
///   icon closes it.
///
/// Why the close button lives in the HStack (not `.overlay`):
/// Every prior version of this view used `.overlay(alignment: .leading)`
/// to mount the close button on top of the tab. SwiftUI's overlay hit
/// testing is unstable on macOS — the overlay's hit area can flicker in
/// and out of the parent's hit region during state changes, which made
/// `isTabHovering` flap between true/false at ~10Hz, which made the
/// `if isTabHovering { Icon(...) }` swap in `iconSlotView` flap with it,
/// which made the icon's opacity/color/visibility visibly flicker.
/// Putting the close button in the HStack as a real sibling means its
/// hit area is part of the tab's normal layout, no overlay z-order to
/// fight, no feedback loop. The icon-slot view is replaced by a
/// dedicated `iconSlot` ZStack that holds both the type icon and the
/// close icon in the same coordinate space.
///
/// Why NO `.animation()` on this view at all:
/// SwiftUI's animation interpolates state changes over multiple frames.
/// During that interpolation, hit testing re-runs against intermediate
/// layout values. Combined with SwiftUI's overlay/z-order behavior this
/// produced the render loop. The 1-frame color change from `textPrimary`
/// → `white` on close-hover is invisible to the user anyway.
struct TabLabel: View {
    let tab: RightTab
    let isActive: Bool
    let onTap: () -> Void
    let onClose: () -> Void

    @State private var isTabHovering: Bool = false
    @State private var isCloseHovering: Bool = false

    /// Slot reserved for the leading icon. Both the type icon and the
    /// close icon render at `iconFontSize` so glyph widths match.
    private let iconFontSize: CGFloat = 11
    /// Hit area for the close button — slightly larger than the glyph
    /// so the user has a comfortable target.
    private let closeHitSize: CGFloat = 16
    /// Horizontal padding inside the tab cell.
    private let cellPaddingH: CGFloat = 10
    /// Vertical padding inside the tab cell.
    private let cellPaddingV: CGFloat = 6

    var body: some View {
        HStack(spacing: 6) {
            // Leading icon slot — always present in the HStack, so its
            // hit area is part of the tab's normal layout (not an overlay).
            // The ZStack inside holds:
            //   layer 1 (bottom): Rectangle().fill(.clear) — stable hit
            //     area, owns .onHover (drives isCloseHovering) and
            //     .onTapGesture (fires onClose).
            //   layer 2 (top): Image — visual only, .allowsHitTesting(false)
            //     so its foregroundColor changes never perturb hit testing.
            iconSlot

            // Title — its own .onTapGesture activates the tab.
            Text(tab.title)
                .font(.uiLabel)
                .foregroundColor(isActive ? .textPrimary : .textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .onTapGesture(perform: onTap)
        }
        .padding(.horizontal, cellPaddingH)
        .padding(.vertical, cellPaddingV)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundFill)
        )
        .overlay(alignment: .bottom) {
            // Active tab indicator: 2pt accent stripe at the bottom edge,
            // inset 8pt from the sides. Pure visual, no hit testing.
            if isActive {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentPrimary)
                    .frame(height: 2)
                    .padding(.horizontal, 8)
                    .offset(y: 1)
                    .allowsHitTesting(false)
            }
        }
        .onHover { hovering in
            isTabHovering = hovering
            // Reset the close-hover when the pointer leaves the tab
            // entirely — otherwise the next time the user hovers in,
            // isCloseHovering could be stuck true from a previous pass.
            if !hovering {
                isCloseHovering = false
            }
        }
        // NO .animation() anywhere in this view.
    }

    /// The leading icon slot. Two layers stacked:
    /// - Bottom: `Rectangle().fill(.clear)` — stable hit surface,
    ///   fixed 16×16 frame, owns `.onHover` + `.onTapGesture`.
    /// - Top: `Image` — visual only, `.allowsHitTesting(false)`,
    ///   swaps between type icon and xmark based on `isTabHovering`.
    ///
    /// Both layers share the same 16×16 frame, so the slot occupies
    /// exactly the same pixels whether hovered or not — the title
    /// column never shifts.
    private var iconSlot: some View {
        ZStack {
            // Hit area. Explicit Rectangle view (not Color.clear) for
            // predictable hit-testing across SwiftUI versions.
            //
            // `.contentShape(Rectangle())` is REQUIRED here even though
            // the Rectangle already has a frame. SwiftUI treats
            // `Color.clear` fills as transparent for hit-testing — the
            // .onHover and .onTapGesture would never fire without this
            // modifier forcing the rectangle's full bounds into the hit
            // region. (We hit this bug after switching from `Color.clear`
            // to `Rectangle().fill(.clear)` — the modifier-less version
            // silently swallows all hits.)
            //
            // Click logic — gated on `isCloseHovering`, not just
            // `isTabHovering`, so the user has to be pointing AT the
            // close icon (not just somewhere inside the tab) for the
            // close to fire:
            // - Cursor on type icon (not hovering tab): tap does nothing
            // - Cursor on tab body, not on close icon: tap does nothing
            // - Cursor on close icon: tap closes
            Rectangle()
                .fill(Color.clear)
                .frame(width: closeHitSize, height: closeHitSize)
                .contentShape(Rectangle())
                .onHover { hovering in
                    isCloseHovering = hovering
                }
                .onTapGesture {
                    if isCloseHovering {
                        onClose()
                    }
                }
                .help(isCloseHovering ? "Close \(tab.title)" : tab.title)

            // Visual. .allowsHitTesting(false) so this layer is pure
            // render — its foregroundColor / systemName changes cannot
            // feed back into hit testing.
            Image(systemName: isTabHovering ? "xmark" : tab.type.icon)
                .font(.system(size: iconFontSize, weight: isTabHovering ? .bold : .regular))
                .foregroundColor(iconForeground)
                .allowsHitTesting(false)
        }
        .frame(width: closeHitSize, height: closeHitSize)
    }

    /// Color of the leading icon. The color stays the same across the
    /// type→close icon swap so the swap feels like a content change,
    /// not a state change:
    /// - Not hovering: type icon in its normal color
    /// - Hovering tab (icon now xmark): SAME color as the type icon
    /// - Hovering close icon specifically: `.white` as an action cue
    private var iconForeground: Color {
        let baseColor = isActive ? Color.textPrimary : Color.textSecondary
        return isCloseHovering ? .white : baseColor
    }

    /// Background fill for the tab. Order of precedence (lowest first):
    /// - inactive + not hovered: transparent
    /// - inactive + hovered: 8% white hover tint
    /// - active: elevated background, slightly stronger than the hover tint
    private var backgroundFill: Color {
        if isActive { return Color.bgElevated }
        if isTabHovering { return Color.white.opacity(0.08) }
        return Color.clear
    }
}