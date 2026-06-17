import SwiftUI

/// Three-pane workspace with independent sidebar / right-pane /
/// focus-mode toggles.
///
/// Layout rules:
/// - Left toggle → sidebar slides in/out from the left edge
/// - Right toggle → right tabs slides in/out from the right edge
/// - Focus toggle → ContentView slides out, RightTabsView expands to
///   fill the freed space (toggle only available when right is visible)
///
/// Why HStack (not HSplitView):
/// HSplitView wraps NSSplitView, which manages its own AppKit layout.
/// NSSplitView does not participate in SwiftUI's animation system for
/// column show/hide — frame changes and view insertions/removals snap
/// instead of animating. Plain HStack gives SwiftUI full control over
/// layout, so `.transition` and `.animation` work as expected for
/// smooth slide-in/slide-out of entire columns.
///
/// Sidebar is always pinned to the leading edge regardless of which
/// other panes are visible. ContentView and RightTabsView must never
/// both be hidden — this is enforced by AppViewModel's didSet guards.
struct MainContentView: View {
    @EnvironmentObject var appViewModel: AppViewModel

    private let sidebarWidth: CGFloat = 260
    private let rightNormalWidth: CGFloat = 420
    private let rightMinWidth: CGFloat = 380

    var body: some View {
        HStack(spacing: 0) {
            // Left: sidebar — fixed width, pinned to leading edge.
            if appViewModel.sidebarVisible {
                SidebarView()
                    .frame(width: sidebarWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .zIndex(1)
            }

            // Center: content — flexible, fills the space between
            // sidebar and right pane. Hidden in focus mode.
            if !appViewModel.focusMode {
                ContentView()
                    .frame(maxWidth: .infinity)
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }

            // Thin divider between center and right — hidden when
            // either side is collapsed to avoid a floating line.
            if !appViewModel.focusMode && appViewModel.rightVisible {
                Rectangle()
                    .fill(Color.borderStrong)
                    .frame(width: 1)
            }

            // Right: multi-tab workspace. Fixed ~420pt in normal mode;
            // expands to fill all remaining space in focus mode.
            if appViewModel.rightVisible {
                RightTabsView()
                    .frame(minWidth: appViewModel.focusMode ? 480 : rightMinWidth,
                           idealWidth: appViewModel.focusMode ? nil : rightNormalWidth,
                           maxWidth: .infinity)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(Color.bgContent)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        appViewModel.sidebarVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help(appViewModel.sidebarVisible
                      ? "Hide left sidebar (⌘B)"
                      : "Show left sidebar (⌘B)")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if appViewModel.rightVisible {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            appViewModel.focusMode.toggle()
                        }
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
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        appViewModel.rightVisible.toggle()
                    }
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
        .animation(.easeInOut(duration: 0.22), value: appViewModel.sidebarVisible)
        .animation(.easeInOut(duration: 0.22), value: appViewModel.rightVisible)
        .animation(.easeInOut(duration: 0.22), value: appViewModel.focusMode)
    }
}
