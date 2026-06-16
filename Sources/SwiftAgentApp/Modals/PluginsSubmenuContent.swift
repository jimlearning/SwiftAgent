import SwiftUI

/// Submenu content for the Composer's `+` → Plugins menu item.
/// Renders inside a SwiftUI `Menu` (NOT a `popover`), so each child is a
/// native `Button` with built-in hit-testing, hover highlight, and
/// keyboard navigation. Popover-based menus were the cause of the
/// "click only on text/icon, blank cell doesn't respond" bug.
struct PluginsSubmenuContent: View {
    let mcpServerCount: Int
    let skillsCount: Int

    var body: some View {
        if mcpServerCount == 0 && skillsCount == 0 {
            Text("No plugins installed")
        } else {
            if mcpServerCount > 0 {
                Button("MCP servers (\(mcpServerCount))") {
                    // Open settings page to MCP servers tab — wired via
                    // OpenSettingsIntent / URL scheme in a future pass.
                }
            }
            if skillsCount > 0 {
                Button("Skills (\(skillsCount))") {
                    // Open settings page to Skills tab.
                }
            }
        }
    }
}
