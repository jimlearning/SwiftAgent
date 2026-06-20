import SwiftUI

/// Modal overlay for fatal errors (per §9.2: modal + red icon + clear action).
struct ErrorModalView: View {
    let error: AppError
    let onDismiss: () -> Void
    let onAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: error.icon)
                .font(.system(size: 40))
                .foregroundColor(.danger)

            Text(error.title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.textPrimary)

            Text(error.message)
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            HStack(spacing: 12) {
                Button("Cancel") {
                    onDismiss()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .foregroundColor(.textSecondary)

                if let action = onAction {
                    Button(actionTitle) {
                        action()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(actionColor)
                }
            }
        }
        .padding(32)
        .background(Color.bgElevated)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.5), radius: 20)
        .accessibilityLabel(error.title)
        .accessibilityHint(error.message)
    }

    private var actionTitle: String {
        error.actionTitle ?? "OK"
    }

    private var actionColor: Color {
        error.actionColor
    }
}
