import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            toolbarView

            Spacer()

            VStack(spacing: 16) {
                Spacer()
                Text("Hello, SwiftAgent")
                    .font(.uiTitle)
                    .foregroundColor(.textPrimary)
                Spacer()
            }

            composerPlaceholder
        }
        .background(Color.bgContent)
    }

    private var toolbarView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Untitled")
                    .font(.uiHeadline)
                    .foregroundColor(.textPrimary)
                Text("No project selected")
                    .font(.uiCaption)
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            HStack(spacing: 12) {
                Button {} label: {
                    HStack(spacing: 4) {
                        Text("Z")
                            .font(.system(size: 11, weight: .bold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .foregroundColor(.textSecondary)
                }
                .buttonStyle(.plain)

                Button {} label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 12))
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 48)
        .padding(.horizontal, 16)
    }

    private var composerPlaceholder: some View {
        VStack(spacing: 0) {
            Divider().background(Color.borderSubtle)

            HStack {
                Button {} label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundColor(.textSecondary)

                Button {} label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                        Text("Custom")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .font(.uiCaption)
                    .foregroundColor(.textSecondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {} label: {
                    HStack(spacing: 4) {
                        Text("5.5 High")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .font(.uiCaption)
                    .foregroundColor(.textSecondary)
                }
                .buttonStyle(.plain)

                Button {} label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .padding(8)
                        .background(Circle().fill(Color.bgElevated))
                }
                .buttonStyle(.plain)
                .foregroundColor(.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(minHeight: 80)
        .background(Color.bgContent)
    }
}
