import Foundation

extension Notification.Name {
    /// Posted by the ⌘F menu shortcut in EntryPoint. SidebarView observes
    /// this notification to focus its search field.
    static let swiftAgentFocusSearch = Notification.Name("swiftAgentFocusSearch")

    /// Posted when the user wants to open Settings (alternative to the
    /// SwiftUI openWindow environment value).
    static let swiftAgentOpenSettings = Notification.Name("swiftAgentOpenSettings")

    /// Posted by the scroll-to-bottom overlay button in ContentView.
    /// AppKitChatBridge listens and scrolls the ChatTableView to the bottom.
    static let chatScrollToBottom = Notification.Name("chatScrollToBottom")
}
