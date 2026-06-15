import SwiftUI

/// Toast overlay shown after an appshot capture (success/error).
struct AppshotToastView: View {
    let success: Bool
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundColor(success ? .success : .danger)
            Text(message)
                .font(.uiLabel)
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.bgElevated)
                .shadow(color: .black.opacity(0.3), radius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.borderStrong, lineWidth: 1)
        )
    }
}

/// One-time prompt shown on first launch.
struct AppshotPermissionPrompt: View {
    var onRequestPermission: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 32))
                .foregroundColor(.accentPrimary)

            Text("Screen Recording Permission")
                .font(.uiHeadline)
                .foregroundColor(.textPrimary)

            Text("SwiftAgent needs screen recording permission to capture your active window when you double-tap the Command key.")
                .font(.uiBody)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Not Now") { onDismiss() }
                    .buttonStyle(.bordered)
                Button("Open System Settings") {
                    onRequestPermission()
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(width: 400)
        .background(Color.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.4), radius: 20)
    }
}
