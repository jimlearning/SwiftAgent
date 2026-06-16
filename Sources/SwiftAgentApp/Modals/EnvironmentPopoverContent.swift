import SwiftUI

/// Popover content shown when the user clicks the ⚙️ button in the
/// center-pane toolbar (per product doc §3.5). Five fields:
/// + Changes, Local ⌄, branch ⌄, Commit or push, Pull request status.
public struct EnvironmentPopoverContent: View {
    @State private var localSelected: Bool = true
    @State private var branch: String = "main"
    @State private var sources: [String] = []

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            popRow(icon: "plus.square", label: "Changes")
            popRow(icon: "laptopcomputer", label: localSelected ? "Local" : "Local ⌄", trailing: "Local")
            popRow(icon: "arrow.triangle.branch", label: branch, trailing: "main ⌄")
            popRow(icon: "arrow.up.doc", label: "Commit or push")
            popRow(icon: "tortoise", label: "Pull request status unavailable", accent: .warning)

            Divider().padding(.vertical, 4)

            Text("Sources")
                .font(.uiCaption)
                .foregroundColor(.textTertiary)
            if sources.isEmpty {
                Text("No sources yet")
                    .font(.uiCaption)
                    .foregroundColor(.textTertiary)
                    .padding(.vertical, 2)
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    @ViewBuilder
    private func popRow(icon: String, label: String, trailing: String? = nil, accent: Color = .textPrimary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .frame(width: 16)
                .foregroundColor(accent)
            Text(label)
                .font(.uiBody)
                .foregroundColor(accent)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.uiCaption)
                    .foregroundColor(.textTertiary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .hoverHighlight(cornerRadius: 4, padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
    }
}
