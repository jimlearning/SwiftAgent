import SwiftUI

/// Bottom toast for warning errors (per §9.2: bottom toast + auto-dismiss 2-3s).
struct ErrorToastView: View {
    let error: AppError
    let onDismiss: () -> Void

    @State private var opacity: Double = 0

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: error.icon)
                .font(.system(size: 12))
                .foregroundColor(.warning)

            Text(error.message)
                .font(.system(size: 12))
                .foregroundColor(.textPrimary)

            Spacer()

            Button {
                onDismiss()
            } label: {
                // Action button if applicable
                if error == .appshotPermissionDenied {
                    Text("Open Settings")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.bgElevated)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.3), radius: 8)
        .padding(.horizontal, 16)
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeOut(duration: AnimationTokens.toastEnter)) {
                opacity = 1
            }
            // Auto-dismiss after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeIn(duration: AnimationTokens.toastExit)) {
                    opacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + AnimationTokens.toastExit) {
                    onDismiss()
                }
            }
        }
    }
}
