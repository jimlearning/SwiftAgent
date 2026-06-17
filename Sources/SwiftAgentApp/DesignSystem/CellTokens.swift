import SwiftUI

/// Single source of truth for selectable-row visuals: sidebar entries,
/// thread rows, project rows, menu rows, settings links. Every cell in
/// the app should look identical at the same density — same padding,
/// same hover background, same corner radius.
///
/// Why this exists:
/// - Previously every call site wrote its own `.padding(...)` AND its
///   own `.hoverHighlight(... padding: ...)` — those two paddings
///   stacked, making hover regions visually larger than the resting
///   row, which looked broken.
/// - Hover background opacity also drifted: 0.06 here, 0.08 there, 0.04
///   for selected rows. Hard to scan which row you're on.
/// - Corner radii varied between 4, 6, and 12 for what should be the
///   same kind of row.
///
/// Rules:
/// - Apply ONLY via `hoverHighlight(cell:)` — never add your own
///   `.padding(...)` outside the modifier; doing so produces a "ghost
///   hover area" outside the visible cell.
/// - `cornerRadius` is fixed at 6 (matches Menu rows on macOS).
/// - `padding` is fixed at (h: 12, v: 7) — matches native Menu rows.
/// - Hover background is 8% white — readable on every background the
///   app uses (sidebar, content, right panel).
public enum CellTokens {
    /// Default cell padding — matches macOS native Menu rows.
    public static let padding = EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12)

    /// Default cell corner radius — softer than a hard rectangle but
    /// still clearly a cell.
    public static let cornerRadius: CGFloat = 6

    /// Hover background — readable on bgSidebar, bgContent, bgRightPanel.
    public static let hoverBackground = Color.white.opacity(0.08)

    /// Selected-row hover background — slightly weaker than the resting
    /// selected background so it doesn't feel "double-tinted".
    public static let selectedHoverBackground = Color.white.opacity(0.04)

    /// Tight cell padding for compact toolbar-style rows (env picker,
    /// model picker, control row buttons). Same horizontal hit area,
    /// shorter vertical so 28pt icon buttons don't look squished.
    public static let tightPadding = EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)

    /// Tight cell corner radius — same as default since these are still
    /// "row-shaped" cells, just smaller.
    public static let tightCornerRadius: CGFloat = 6
}

public extension View {
    /// Standard cell hover highlight. Use this for any selectable row:
    /// sidebar entries, thread rows, project rows, menu items.
    ///
    /// Do NOT also call `.padding(...)` outside this modifier — the
    /// padding is built in.
    func cellHoverHighlight() -> some View {
        hoverHighlight(
            background: CellTokens.hoverBackground,
            cornerRadius: CellTokens.cornerRadius,
            padding: CellTokens.padding
        )
    }

    /// Cell hover highlight for the already-selected row — weaker
    /// background so the selected accent stays the dominant cue.
    func cellHoverHighlightSelected() -> some View {
        hoverHighlight(
            background: CellTokens.selectedHoverBackground,
            cornerRadius: CellTokens.cornerRadius,
            padding: CellTokens.padding
        )
    }

    /// Tight variant for compact toolbar rows (env picker, control row).
    func cellHoverHighlightTight() -> some View {
        hoverHighlight(
            background: CellTokens.hoverBackground,
            cornerRadius: CellTokens.tightCornerRadius,
            padding: CellTokens.tightPadding
        )
    }
}