import SwiftUI

/// Sheet shown when creating a thread to pick execution environment.
struct WorktreePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedEnv: ExecutionEnvironment = .local
    @State private var repoPath: String = ""
    @State private var isCreating: Bool = false
    @State private var error: String?

    var onConfirm: ((ExecutionEnvironment) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select Execution Environment")
                .font(.uiHeadline)
                .foregroundColor(.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(ExecutionEnvironment.allCases, id: \.rawValue) { env in
                    Button {
                        selectedEnv = env
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: env.icon)
                                .frame(width: 16)
                                .foregroundColor(selectedEnv == env ? .accentPrimary : .textSecondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(env.label)
                                    .font(.uiLabel)
                                    .foregroundColor(.textPrimary)
                                Text(env.description)
                                    .font(.uiCaption)
                                    .foregroundColor(.textSecondary)
                            }
                            Spacer()
                            if selectedEnv == env {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.accentPrimary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedEnv == env ? Color.accentPrimary.opacity(0.08) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if let error {
                Text(error)
                    .font(.uiCaption)
                    .foregroundColor(.danger)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Button(selectedEnv == .worktree ? "Create & Continue" : "Continue") {
                    onConfirm?(selectedEnv)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCreating)
            }
        }
        .padding(24)
        .frame(width: 420, height: 340)
    }
}

// MARK: - ExecutionEnvironment

public enum ExecutionEnvironment: String, CaseIterable, Sendable {
    case local = "local"
    case worktree = "worktree"
    case cloud = "cloud"

    public var label: String {
        switch self {
        case .local: return "Local"
        case .worktree: return "Worktree"
        case .cloud: return "Cloud (Coming Soon)"
        }
    }

    public var icon: String {
        switch self {
        case .local: return "desktopcomputer"
        case .worktree: return "tree"
        case .cloud: return "cloud"
        }
    }

    public var description: String {
        switch self {
        case .local:
            return "Run directly in your current working directory"
        case .worktree:
            return "Run in an isolated git worktree (auto-created)"
        case .cloud:
            return "Run on a remote machine (deferred to Phase 5)"
        }
    }
}
