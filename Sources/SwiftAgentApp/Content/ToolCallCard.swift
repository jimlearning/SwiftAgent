import SwiftUI

/// Card shown in the conversation stream when the agent invokes a tool.
/// Shows tool name, args (collapsed by default), result (collapsed by default).
struct ToolCallCard: View {
    let toolName: String
    let args: String
    let result: String?
    let isPending: Bool

    @State private var argsExpanded: Bool = false
    @State private var resultExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Tool name header
            HStack(spacing: 6) {
                if isPending {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: "wrench")
                        .font(.system(size: 10))
                        .foregroundColor(.textSecondary)
                }
                Text(toolName)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.textPrimary)
                Spacer()
                if result != nil {
                    Image(systemName: resultExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(.textTertiary)
                        .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { resultExpanded.toggle() } }
                }
            }

            // Args (collapsed)
            if !args.isEmpty {
                Button(action: { withAnimation(.easeOut(duration: 0.15)) { argsExpanded.toggle() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: argsExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8))
                        Text("Args")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.textTertiary)
                }
                .buttonStyle(.plain)

                if argsExpanded {
                    Text(args)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.textSecondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.bgInput)
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.borderStrong, lineWidth: 1)
                        )
                }
            }

            // Result (collapsed)
            if let result = result, !isPending {
                if resultExpanded {
                    Text(result)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.textSecondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.bgInput)
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.borderStrong, lineWidth: 1)
                        )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.bgSidebar.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
    }
}

/// Card shown when agent edits N files. Has Undo + Review buttons.
struct EditSummaryCard: View {
    let filesEdited: Int
    let linesAdded: Int
    let linesRemoved: Int
    let fileNames: [String]
    let onUndo: () -> Void
    let onReview: () -> Void

    @State private var filesExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top row: summary + buttons
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "plus.square")
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Edited \(filesEdited) files")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.textPrimary)
                        Text("+\(linesAdded) \u{2212}\(linesRemoved)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(
                                linesAdded > linesRemoved ? .success : .danger
                            )
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    Button(action: onUndo) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 10))
                            Text("Undo")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.textSecondary)
                    }
                    .buttonStyle(.plain)

                    Button(action: onReview) {
                        HStack(spacing: 4) {
                            Text("Review")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.accentPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.accentPrimary, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // File list (collapsible)
            if !fileNames.isEmpty {
                Button(action: { withAnimation(.easeOut(duration: 0.15)) { filesExpanded.toggle() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: filesExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8))
                        Text(filesExpanded ? "Hide files" : "Show \(fileNames.count) files")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.textTertiary)
                }
                .buttonStyle(.plain)

                if filesExpanded {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(fileNames, id: \.self) { name in
                            HStack(spacing: 6) {
                                Image(systemName: "doc")
                                    .font(.system(size: 10))
                                Text(name)
                                    .font(.system(size: 11, design: .monospaced))
                            }
                            .foregroundColor(.textSecondary)
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.bgElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.borderStrong, lineWidth: 1)
        )
    }
}
