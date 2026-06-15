import SwiftUI
import UniformTypeIdentifiers

/// The `+` button menu with the full 6 items (per §5.7).
/// Items: Add photos & files | Create (submenu) | Plan mode (toggle) |
/// Pursue goal (toggle) | Plugins (submenu) | Appshot (camera).
public struct AddMenuView: View {
    var onFilePick: (() -> Void)?
    var onCreateNewFile: (() -> Void)?
    var onCreateNewProject: (() -> Void)?
    var onTogglePlanMode: (() -> Void)?
    var onToggleGoalMode: (() -> Void)?
    var onTriggerAppshot: (() -> Void)?

    var planModeOn: Bool = false
    var goalModeOn: Bool = false
    var mcpServerCount: Int = 0
    var skillsCount: Int = 0

    @State private var showCreateSubmenu: Bool = false
    @State private var showPluginsSubmenu: Bool = false

    public init(
        onFilePick: (() -> Void)? = nil,
        onCreateNewFile: (() -> Void)? = nil,
        onCreateNewProject: (() -> Void)? = nil,
        onTogglePlanMode: (() -> Void)? = nil,
        onToggleGoalMode: (() -> Void)? = nil,
        onTriggerAppshot: (() -> Void)? = nil,
        planModeOn: Bool = false,
        goalModeOn: Bool = false,
        mcpServerCount: Int = 0,
        skillsCount: Int = 0
    ) {
        self.onFilePick = onFilePick
        self.onCreateNewFile = onCreateNewFile
        self.onCreateNewProject = onCreateNewProject
        self.onTogglePlanMode = onTogglePlanMode
        self.onToggleGoalMode = onToggleGoalMode
        self.onTriggerAppshot = onTriggerAppshot
        self.planModeOn = planModeOn
        self.goalModeOn = goalModeOn
        self.mcpServerCount = mcpServerCount
        self.skillsCount = skillsCount
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. Add photos & files
            menuItem(icon: "paperclip", label: "Add photos & files", action: { onFilePick?() })

            // 2. Create → submenu
            createMenuItem

            Divider().padding(.horizontal, 12)

            // 3. Plan mode (toggle)
            toggleMenuItem(
                icon: "doc.text.magnifyingglass",
                label: "Plan mode",
                isOn: planModeOn,
                action: { onTogglePlanMode?() }
            )

            // 4. Pursue goal (toggle)
            toggleMenuItem(
                icon: "target",
                label: "Pursue goal",
                isOn: goalModeOn,
                action: { onToggleGoalMode?() }
            )

            // 5. Plugins → submenu
            pluginsMenuItem

            Divider().padding(.horizontal, 12)

            // 6. Appshot (camera)
            menuItem(icon: "camera", label: "Appshot (Cmd+Cmd)", action: { onTriggerAppshot?() })
        }
        .frame(width: 220)
        .padding(.vertical, 4)
    }

    // MARK: - Menu Items

    private func menuItem(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(label)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private var createMenuItem: some View {
        Menu {
            Button(action: { onCreateNewFile?() }) {
                Label("New File", systemImage: "doc.badge.plus")
            }
            Button(action: { onCreateNewProject?() }) {
                Label("New Project", systemImage: "folder.badge.plus")
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.square")
                    .frame(width: 16)
                Text("Create")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .menuStyle(.borderlessButton)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleMenuItem(icon: String, label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(label)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.accentPrimary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private var pluginsMenuItem: some View {
        Menu {
            PluginsSubmenu(mcpServerCount: mcpServerCount, skillsCount: skillsCount)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "puzzlepiece.extension")
                    .frame(width: 16)
                Text("Plugins")
                Spacer()
                Text("\(mcpServerCount + skillsCount) installed")
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .menuStyle(.borderlessButton)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
