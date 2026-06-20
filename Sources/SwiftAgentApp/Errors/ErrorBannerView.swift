import SwiftUI

/// Top banner for retryable errors (per §9.2: persistent top banner with countdown).
struct ErrorBannerView: View {
    let error: AppError
    let onDismiss: () -> Void
    let onAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: error.icon)
                .font(.system(size: 14))
                .foregroundColor(bannerColor)

            Text(error.message)
                .font(.system(size: 12))
                .foregroundColor(.textPrimary)
                .lineLimit(2)

            Spacer()

            if let action = onAction {
                Button(actionTitle) {
                    action()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.accentPrimary)
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundColor(.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(bannerBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(bannerColor)
                .frame(height: 2)
        }
        .animation(.easeInOut(duration: 0.2), value: error.id)
        .accessibilityLabel(error.title)
        .accessibilityHint(error.message)
    }

    private var bannerColor: Color {
        error.bannerColor
    }

    private var bannerBackground: Color {
        bannerColor.opacity(0.1)
    }

    private var actionTitle: String {
        error.actionTitle ?? "Retry"
    }
}
