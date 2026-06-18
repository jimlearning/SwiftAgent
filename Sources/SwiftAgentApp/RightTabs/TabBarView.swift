import SwiftUI

/// Horizontal tab bar showing all open right-pane tabs + a `+` button
/// that opens a native NSMenu listing the 5 right-pane panel types.
///
/// Why a SwiftUI `Menu` and not a custom popover (AddTabMenu.swift)?
/// SwiftUI's `Menu` on macOS renders as a real NSMenu — every row gets
/// system-level padding, spacing, hover highlight, and shortcut column.
/// A hand-rolled popover of Buttons can only approximate that and ends
/// up visibly off (different row height, different highlight color, no
/// system shortcut glyph). Using `Menu` makes the picker identical to
/// any other menu in the app and to the macOS system menus.
struct TabBarView: View {
    @ObservedObject var tabsStore: RightTabsStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tabsStore.tabs) { tab in
                    TabLabel(
                        tab: tab,
                        isActive: tabsStore.activeTabID == tab.id,
                        onTap: { tabsStore.activate(tab.id) },
                        onClose: { tabsStore.close(tab.id) }
                    )
                }

                addButton
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 36)
        .background(Color.bgRightPanel)
    }

    /// + button rendered as a SwiftUI `Menu` so the dropdown is a real
    /// NSMenu. Each row uses `Label(title, systemImage: icon)` so the
    /// system icon column and title column line up exactly like other
    /// menus. `.keyboardShortcut` is attached so the system renders the
    /// shortcut glyph on the right and the keystroke works globally
    /// (EntryPoint's CommandGroup mirrors the same shortcuts so they
    /// also appear under View in the main menu bar).
    private var addButton: some View {
        Menu {
            ForEach(RightTabType.allCases) { type in
                Button {
                    tabsStore.openTab(type: type)
                } label: {
                    Label(type.title, systemImage: type.icon)
                }
                .modifier(MenuShortcutModifier(type: type))
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        // Hover region expanded past the 28pt icon to match the rest
        // of the toolbar (≈36×36 hit area + 6pt corners), so the user
        // doesn't have to land on the icon glyph itself. Same standard
        // as the composer + button.
        .hoverHighlight(
            background: Color.white.opacity(0.08),
            cornerRadius: 6,
            padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        )
        .help("Open a new right-pane tab")
    }
}

/// Attaches a `.keyboardShortcut` to a Menu Button so the system renders
/// the shortcut on the right edge of the menu item and registers the
/// keystroke. Each `RightTabType` maps to the same shortcuts declared in
/// `EntryPoint`'s `CommandGroup(after: .windowArrangement)`, so users
/// see them both in the View menu bar and in this + menu.
private struct MenuShortcutModifier: ViewModifier {
    let type: RightTabType

    func body(content: Content) -> some View {
        switch type {
        case .review:
            content.keyboardShortcut("g", modifiers: [.control, .shift])
        case .terminal:
            content.keyboardShortcut("`", modifiers: .control)
        case .browser:
            content.keyboardShortcut("t", modifiers: .command)
        case .files:
            content.keyboardShortcut("p", modifiers: .command)
        case .sideChat:
            content.keyboardShortcut("s", modifiers: [.command, .option])
        case .debug:
            content.keyboardShortcut("d", modifiers: [.control, .shift])
        }
    }
}
