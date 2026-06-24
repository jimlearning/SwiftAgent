import SwiftUI
import ClarcCore

/// The full 4-tier permission modal shown when ⚙️ Custom⌄ is clicked.
/// Per §5.4: "How should SwiftAgent actions be approved?" with 4 options.
public struct PermissionModal: View {
    @Binding var selectedMode: PermissionMode
    @Environment(\.dismiss) private var dismiss

    public init(selectedMode: Binding<PermissionMode>) {
        self._selectedMode = selectedMode
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("How should SwiftAgent actions be approved?")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Button("Learn more") {
                    // Open help URL
                    if let url = URL(string: "https://github.com/jimlearning/SwiftAgent/blob/main/docs/permissions.md") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.uiCaption)
                .foregroundColor(.accentPrimary)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // 4 options
            ForEach(PermissionMode.allCases, id: \.rawValue) { mode in
                optionRow(mode: mode)
                if mode != PermissionMode.allCases.last {
                    Divider().padding(.leading, 42)
                }
            }
        }
        .frame(width: 420)
        .padding(.vertical, 4)
    }

    private func optionRow(mode: PermissionMode) -> some View {
        Button {
            selectedMode = mode
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 16))
                    .frame(width: 18)
                    .foregroundColor(mode == selectedMode ? .accentPrimary : .textSecondary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.rawValue)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.textPrimary)
                    Text(mode.description)
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if mode == selectedMode {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.accentPrimary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension PermissionMode: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .default: return "Ask for approval before each action. Use when you want to review every step."
        case .acceptEdits: return "Auto-accept edits, confirm other actions. Best for pair-programming."
        case .plan: return "Explore and plan only — no execution. Safe review mode."
        case .auto: return "Auto-approve all actions. Use only in trusted workspaces."
        case .bypassPermissions: return "Skip all permission checks. Everything runs automatically."
        }
    }
}