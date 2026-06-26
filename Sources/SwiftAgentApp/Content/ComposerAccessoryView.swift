import SwiftUI
import ClarcCore
import SwiftAgentCore

/// Composer-row controls: Permission Picker, Model Picker.
/// Rendered as the input accessory inside `ChatView`.
struct ComposerAccessoryView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(WindowState.self) private var windowState

    @State private var permissionMode: ClarcCore.PermissionMode = .default
    @State private var selectedModel: String = "deepseek-v4-pro"

    private let availableModels: [(id: String, displayName: String)] = [
        ("deepseek-v4-pro", "DeepSeek V4 Pro"),
        ("deepseek-v4-flash", "DeepSeek V4 Flash"),
    ]

    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 12)

            // Permission Picker
            Menu {
                Section("Permission Mode") {
                    ForEach(ClarcCore.PermissionMode.allCases, id: \.self) { mode in
                        Button {
                            permissionMode = mode
                            setPermissionMode(mode)
                        } label: {
                            Text(LocalizedStringKey(mode.displayName))
                            if permissionMode == mode { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                controlLabel(
                    title: permissionMode.displayName,
                    isAccent: true
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Permission mode: \(permissionMode.displayName)")

            // Model Picker
            Menu {
                Section("Model") {
                    ForEach(availableModels, id: \.id) { model in
                        Button {
                            selectedModel = model.id
                            appViewModel.selectedThread?.selectedModel = model.id
                            appViewModel.selectedThread?.persistState()
                        } label: {
                            Text(model.displayName)
                            if selectedModel == model.id { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                controlLabel(
                    title: modelDisplayName(selectedModel),
                    isAccent: false
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Model: \(modelDisplayName(selectedModel))")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            permissionMode = mapPermissionMode(appViewModel.permissionMode)
            if let model = appViewModel.selectedThread?.selectedModel {
                selectedModel = model
            }
        }
        .onChange(of: appViewModel.selectedThread?.id) { _, _ in
            if let model = appViewModel.selectedThread?.selectedModel {
                selectedModel = model
            }
            permissionMode = mapPermissionMode(appViewModel.permissionMode)
        }
    }

    private func setPermissionMode(_ mode: ClarcCore.PermissionMode) {
        appViewModel.permissionMode = mapToSwiftAgentPermission(mode)
    }

    private func modelDisplayName(_ id: String) -> String {
        availableModels.first(where: { $0.id == id })?.displayName ?? id
    }

    @ViewBuilder
    private func controlLabel(title: String, isAccent: Bool) -> some View {
        HStack(spacing: 6) {
            Text(LocalizedStringKey(title))
                .font(.system(size: ClaudeTheme.size(13), weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(isAccent ? ClaudeTheme.accent : ClaudeTheme.textSecondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall)
                .fill(Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: ClaudeTheme.cornerRadiusSmall))
    }
}

// MARK: - Permission Mode Mapping

private func mapPermissionMode(_ sa: SwiftAgentCore.PermissionMode) -> ClarcCore.PermissionMode {
    switch sa {
    case .default: return .default
    case .acceptEdits: return .acceptEdits
    case .plan: return .plan
    case .auto, .dontAsk: return .auto
    case .bypassPermissions: return .bypassPermissions
    case .bubble: return .default
    }
}

private func mapToSwiftAgentPermission(_ clarc: ClarcCore.PermissionMode) -> SwiftAgentCore.PermissionMode {
    switch clarc {
    case .default: return .default
    case .acceptEdits: return .acceptEdits
    case .plan: return .plan
    case .auto: return .auto
    case .bypassPermissions: return .bypassPermissions
    }
}
