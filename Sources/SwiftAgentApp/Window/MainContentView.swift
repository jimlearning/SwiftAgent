import SwiftUI

/// Three-pane workspace with independent sidebar / right-pane /
/// focus-mode toggles.
///
/// Why HSplitView (not NavigationSplitView):
/// We tried NavigationSplitView first because it offers the macOS
/// "modern navigation" look. But it has two real problems for our
/// pane-toggle model:
///   1. `.navigationSplitViewColumnWidth(min: 0, ideal: 0, max: 0)`
///      collapses a column to 0 width, but `NavigationSplitView`
///      still reserves the collapsed column's layout slot, so the
///      neighboring columns don't expand to fill the gap. Focus
///      mode (collapse content) leaves an empty band where content
///      used to be, and the right pane doesn't grow.
///   2. `NavigationSplitViewVisibility` has only 4 cases — there is
///      no value that means "sidebar + detail, hide content", which
///      is exactly focus mode. Mapping our 3 independent toggles
///      through the 4-case enum is lossy.
///
/// `HSplitView` (the SwiftUI wrapper around AppKit's `NSSplitView`)
/// has fixed-order columns with flex widths. Collapse a column to
/// 0pt and the remaining columns naturally expand to fill the
/// freed space. No reserved layout slots, no enum-mapping hell.
///
/// Why focus mode uses `if !focusMode { ContentView() }` (not width 0):
/// With `.frame(minWidth: 0, idealWidth: 0, maxWidth: 0)`, HSplitView
/// still keeps `ContentView` in the layout tree and gives it a
/// `layoutPriority: 1` slot — which means ContentView still claims
/// the leading portion of the window and pushes `SidebarView` into
/// the middle. Removing ContentView from the tree entirely (when
/// focus mode is on) lets HSplitView relayout sidebar + detail to
/// fill the freed space, with sidebar back at the leading edge.
///
/// Toolbar:
/// `.toolbar` works on any SwiftUI view inside a `Window` scene —
/// HSplitView is a perfectly fine host. We render the three pane
/// toggles into the native macOS toolbar using `ToolbarItem` so
/// they get the system look-and-feel (title-bar integration,
/// accessibility, hover affordances, ⌘ shortcut hints) without any
/// custom chrome.
struct MainContentView: View {
    @EnvironmentObject var appViewModel: AppViewModel

    /// Minimum width reserved for the center pane when not in focus
    /// mode. Below this, content readability collapses. The user can
    /// always collapse a side pane explicitly via the toolbar
    /// toggles.
    private let centerMinWidth: CGFloat = 480

    var body: some View {
        HSplitView {
            // Left: sidebar. Width is 0 (effectively gone) when
            // sidebarVisible is false; the divider automatically
            // closes up. layoutPriority keeps sidebar above detail
            // when both are competing for space — i.e. when the user
            // drags the center column's right edge, detail yields
            // before sidebar does.
            SidebarView()
                .frame(minWidth: appViewModel.sidebarVisible ? 240 : 0,
                       idealWidth: appViewModel.sidebarVisible ? 260 : 0,
                       maxWidth: appViewModel.sidebarVisible ? 320 : 0)
                .layoutPriority(0.5)

            // Center: content. Removed from the tree entirely in
            // focus mode (not collapsed to width 0) so HSplitView
            // relayouts sidebar + detail to fill the freed space
            // with sidebar back at the leading edge. See the doc
            // comment for the layoutPriority pitfall.
            if !appViewModel.focusMode {
                ContentView()
                    .frame(minWidth: centerMinWidth,
                           idealWidth: 720,
                           maxWidth: .infinity)
                    .layoutPriority(1)
            }

            // Right: multi-tab workspace. Always pinned to the
            // trailing edge; HSplitView gives it whatever width
            // remains after sidebar and content take their share.
            RightTabsView()
                .frame(minWidth: appViewModel.rightVisible ? 380 : 0,
                       idealWidth: appViewModel.rightVisible ? 420 : 0,
                       maxWidth: appViewModel.rightVisible ? 520 : 0)
                .layoutPriority(appViewModel.focusMode ? 0.5 : 0.5)
        }
        .background(Color.bgContent)
        .toolbar {
            // Sidebar toggle at .navigation placement: SwiftUI gives
            // this the standard "sidebar" appearance on macOS (the
            // system sidebar collapse button). We provide a Button
            // here so the user has a visible affordance to toggle
            // the sidebar; SwiftUI applies the system styling.
            ToolbarItem(placement: .navigation) {
                Button {
                    appViewModel.sidebarVisible.toggle()
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help(appViewModel.sidebarVisible
                      ? "Hide left sidebar (⌘B)"
                      : "Show left sidebar (⌘B)")
            }

            // Focus + right toggles at .primaryAction placement
            // (trailing edge of the toolbar). Cluster them on the
            // right side so the focus action — the most prominent
            // layout control — sits at the user's natural eye line.
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appViewModel.focusMode.toggle()
                } label: {
                    Image(systemName: appViewModel.focusMode
                          ? "arrow.down.right.and.arrow.up.left"
                          : "arrow.up.left.and.arrow.down.right")
                }
                .help(appViewModel.focusMode
                      ? "Exit focus mode (restore center column)"
                      : "Focus mode (hide center, expand right)")
                .foregroundStyle(appViewModel.focusMode
                                 ? AnyShapeStyle(.tint)
                                 : AnyShapeStyle(.primary))

                Button {
                    appViewModel.rightVisible.toggle()
                } label: {
                    Image(systemName: appViewModel.rightVisible
                          ? "sidebar.squares.right"
                          : "sidebar.right")
                }
                .help(appViewModel.rightVisible
                      ? "Hide right panel (⌘⇧B)"
                      : "Show right panel (⌘⇧B)")
            }
        }
        .preferredColorScheme(.dark)
        // Animate width transitions so the columns collapse/expand
        // smoothly instead of snapping.
        .animation(.easeInOut(duration: 0.18), value: appViewModel.sidebarVisible)
        .animation(.easeInOut(duration: 0.18), value: appViewModel.rightVisible)
        .animation(.easeInOut(duration: 0.18), value: appViewModel.focusMode)
    }
}