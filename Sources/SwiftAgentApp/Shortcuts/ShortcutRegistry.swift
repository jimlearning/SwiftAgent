import SwiftUI

/// Single source of truth for all keyboard shortcuts (per §6 of the product spec).
enum ShortcutRegistry {
    /// All 25+ shortcut entries for the Settings table and app-wide binding.
    static let allEntries: [ShortcutEntry] = threads + navigation + rightTabs + panels + environment + global

    // MARK: - Thread Management (8)

    static let threads: [ShortcutEntry] = [
        .init(id: "newChat", category: "Thread Management", action: "New chat", shortcut: "⌘N", alternate: "⇧⌘O"),
        .init(id: "quickChat", category: "Thread Management", action: "New quick chat", shortcut: "⌥⌘N", alternate: nil),
        .init(id: "openSideChat", category: "Thread Management", action: "Open side chat", shortcut: "⌥⌘S", alternate: nil),
        .init(id: "pinChat", category: "Thread Management", action: "Pin chat", shortcut: "⌥⌘P", alternate: nil),
        .init(id: "renameChat", category: "Thread Management", action: "Rename chat", shortcut: "⌥⌘R", alternate: nil),
        .init(id: "archiveChat", category: "Thread Management", action: "Archive chat", shortcut: "⇧⌘A", alternate: nil),
        .init(id: "find", category: "Thread Management", action: "Find", shortcut: "⌘F", alternate: nil),
    ]

    // MARK: - Navigation (6)

    static let navigation: [ShortcutEntry] = [
        .init(id: "focusBrowser", category: "Navigation", action: "Focus browser address bar", shortcut: "⌘L", alternate: nil),
        .init(id: "back", category: "Navigation", action: "Back", shortcut: "⌘[", alternate: nil),
        .init(id: "forward", category: "Navigation", action: "Forward", shortcut: "⌘]", alternate: nil),
        .init(id: "nextRecent", category: "Navigation", action: "Next recently viewed", shortcut: "^Tab", alternate: nil),
        .init(id: "nextTab", category: "Navigation", action: "Next chat or tab", shortcut: "⇧⌘]", alternate: "⌥⌘→"),
        .init(id: "prevRecent", category: "Navigation", action: "Previous recently viewed", shortcut: "^⇧Tab", alternate: nil),
        .init(id: "prevTab", category: "Navigation", action: "Previous chat or tab", shortcut: "⇧⌘[", alternate: "⌥⌘←"),
    ]

    // MARK: - Right Multi-Tab Panel (11)

    static let rightTabs: [ShortcutEntry] = [
        .init(id: "newReview", category: "Right Tabs", action: "New Review tab", shortcut: "^⇧G", alternate: nil),
        .init(id: "newTerminal", category: "Right Tabs", action: "New Terminal tab", shortcut: "^`", alternate: nil),
        .init(id: "newBrowser", category: "Right Tabs", action: "New Browser tab", shortcut: "⌘T", alternate: nil),
        .init(id: "newFiles", category: "Right Tabs", action: "New Files tab", shortcut: "⌘P", alternate: nil),
        .init(id: "newSideChat", category: "Right Tabs", action: "New Side chat tab", shortcut: "⌥⌘S", alternate: nil),
        .init(id: "closeTab", category: "Right Tabs", action: "Close current tab", shortcut: "⌘W", alternate: nil),
        .init(id: "nextRightTab", category: "Right Tabs", action: "Next tab", shortcut: "^⇧}", alternate: "⌥⌘→"),
        .init(id: "prevRightTab", category: "Right Tabs", action: "Previous tab", shortcut: "^⇧{", alternate: "⌥⌘←"),
        .init(id: "moveTabRight", category: "Right Tabs", action: "Move tab right", shortcut: "^⇧⌘→", alternate: nil),
        .init(id: "moveTabLeft", category: "Right Tabs", action: "Move tab left", shortcut: "^⇧⌘←", alternate: nil),
    ]

    // MARK: - Panels (3)

    static let panels: [ShortcutEntry] = [
        .init(id: "toggleComposer", category: "Panels", action: "Toggle Composer", shortcut: "⌘J", alternate: nil),
        .init(id: "toggleRightPanel", category: "Panels", action: "Toggle right panel", shortcut: "⇧⌘B", alternate: nil),
        .init(id: "toggleLeftSidebar", category: "Panels", action: "Toggle left sidebar", shortcut: "⌘B", alternate: nil),
    ]

    // MARK: - Environment (2)

    static let environment: [ShortcutEntry] = [
        .init(id: "envAction1", category: "Environment", action: "Environment action 1", shortcut: "⇧⌘D", alternate: nil),
    ]

    // MARK: - Global / Appshots (5)

    static let global: [ShortcutEntry] = [
        .init(id: "appshots", category: "Global", action: "Appshots (capture screen)", shortcut: "Cmd+Cmd", alternate: nil),
        .init(id: "sendMessage", category: "Global", action: "Send message", shortcut: "Enter", alternate: "⌘Enter"),
        .init(id: "newLine", category: "Global", action: "New line", shortcut: "Shift+Enter", alternate: nil),
        .init(id: "editLast", category: "Global", action: "Edit last message", shortcut: "Esc+Esc", alternate: nil),
        .init(id: "voiceInput", category: "Global", action: "Voice input", shortcut: "^M", alternate: nil),
    ]
}

// MARK: - App-wide keyboard shortcut commands

/// Attach keyboard shortcuts to any Scene using the .commands modifier.
struct AppShortcutsModifier: ViewModifier {
    @ObservedObject var appViewModel: AppViewModel
    @ObservedObject var rightTabsStore: RightTabsStore

    func body(content: Content) -> some View {
        content
    }
}
