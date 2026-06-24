import SwiftUI
import ClarcCore

/// Permission mode picker (per §5.4).
/// Phase 2: stub showing 4 labels, all non-functional except selection.
public struct PermissionPickerView: View {
    @Binding var selected: PermissionMode

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("How should SwiftAgent actions be approved?")
                .font(.uiLabel)
                .foregroundColor(.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            ForEach(PermissionMode.allCases, id: \.rawValue) { mode in
                Button {
                    selected = mode
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: mode.systemImage)
                            .frame(width: 16)
                            .foregroundColor(mode == selected ? .accentPrimary : .textSecondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.rawValue)
                                .font(.uiLabel)
                                .foregroundColor(.textPrimary)
                            Text(mode.description)
                                .font(.uiCaption)
                                .foregroundColor(.textSecondary)
                        }

                        Spacer()

                        if mode == selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.accentPrimary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if mode != PermissionMode.allCases.last {
                    Divider().padding(.leading, 42)
                }
            }

            // Learn more link
            HStack {
                Spacer()
                Button("Learn more") {
                    // Stub — opens help URL in Phase 5
                }
                .font(.uiCaption)
                .foregroundColor(.accentPrimary)
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 380)
        .padding(.vertical, 4)
    }
}
