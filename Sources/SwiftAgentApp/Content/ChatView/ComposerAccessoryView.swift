import SwiftUI

/// Composer accessory controls: Permission Mode, Model Picker, Effort Picker.
/// Passed as the `accessory` view to InputBarView, appearing in the action row.
struct ComposerAccessoryView: View {
    @EnvironmentObject private var appViewModel: AppViewModel

    var body: some View {
        HStack(spacing: 8) {
            permissionModeControl
            modelPickerControl
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Permission Mode

    private var permissionModeControl: some View {
        Menu {
            ForEach(PermissionModeOption.allCases, id: \.self) { mode in
                Button {
                    appViewModel.selectedPermissionMode = mode
                } label: {
                    Text(mode.displayName)
                    if appViewModel.selectedPermissionMode == mode {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            composerLabel(title: appViewModel.selectedPermissionMode.displayName)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Model Picker

    private var modelPickerControl: some View {
        Menu {
            ForEach(availableModels, id: \.self) { model in
                Button {
                    appViewModel.selectedModel = model
                } label: {
                    Text(modelDisplayName(model))
                    if appViewModel.selectedModel == model {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            composerLabel(title: modelDisplayName(appViewModel.selectedModel))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Helpers

    private var availableModels: [String] {
        ["auto", "deepseek-chat", "deepseek-reasoner"]
    }

    private func modelDisplayName(_ id: String) -> String {
        switch id {
        case "deepseek-chat": return "DeepSeek Chat"
        case "deepseek-reasoner": return "DeepSeek Reasoner"
        default: return "Auto"
        }
    }

    @ViewBuilder
    private func composerLabel(title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: ChatTheme.size(13), weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(ChatTheme.textSecondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .contentShape(RoundedRectangle(cornerRadius: ChatTheme.cornerRadiusSmall))
    }
}

// MARK: - Permission Mode Options

enum PermissionModeOption: String, CaseIterable {
    case `default`
    case acceptEdits
    case plan
    case bypassPermissions

    var displayName: String {
        switch self {
        case .default: return "Default"
        case .acceptEdits: return "Accept Edits"
        case .plan: return "Plan Mode"
        case .bypassPermissions: return "Bypass"
        }
    }
}
