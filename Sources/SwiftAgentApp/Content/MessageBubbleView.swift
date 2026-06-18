import SwiftUI

/// Renders a single message bubble with native AgentMessageBlock support.
/// - User messages: rounded bubble, right-aligned
/// - Assistant messages: text + thinking + tool_use + tool_result blocks
/// - System messages: small gray text
public struct MessageBubbleView: View {
    let message: AgentMessage
    let thoughtTimeString: String?
    let reasoningExpanded: Bool
    let onToggleReasoning: () -> Void

    public var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            if message.role == .assistant, let thoughtTime = thoughtTimeString, message.isStreaming {
                statusRow(thoughtTime)
            }

            ForEach(Array(message.blocks.enumerated()), id: \.offset) { _, block in
                blockView(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // MARK: - Block rendering

    @ViewBuilder
    private func blockView(for block: AgentMessageBlock) -> some View {
        switch block {
        case .text(let text):
            if message.role == .user {
                userBubble(text)
            } else {
                assistantText(text)
            }
        case .thinking(let text, let isExpanded):
            thinkingBlock(text, isExpanded: isExpanded)
        case .toolUse(let toolUse):
            toolUseCard(toolUse)
        case .toolResult(let result):
            toolResultCard(result)
        case .systemReminder(let text):
            systemReminder(text)
        }
    }

    // MARK: - User Bubble

    private func userBubble(_ text: String) -> some View {
        Text(text)
            .font(.uiBody)
            .foregroundColor(.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: .radiusSmall)
                    .fill(Color.bgElevated)
            )
            .frame(maxWidth: 320, alignment: .trailing)
    }

    // MARK: - Assistant Text

    private func assistantText(_ text: String) -> some View {
        Group {
            if text.isEmpty && message.isStreaming {
                Text(" ")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(text)
                    .font(.uiBody)
                    .foregroundColor(.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Thinking Block

    private func thinkingBlock(_ content: String, isExpanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onToggleReasoning) {
                HStack(spacing: 4) {
                    Image(systemName: reasoningExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("Thinking\(message.isStreaming ? "..." : "")")
                        .font(.uiCaption)
                }
                .foregroundColor(.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if reasoningExpanded && !content.isEmpty {
                Text(content)
                    .font(.uiCaption)
                    .foregroundColor(.textTertiary)
                    .padding(.leading, 16)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Tool Use Card

    private func toolUseCard(_ toolUse: ToolUseBlock) -> some View {
        HStack(spacing: 8) {
            Image(systemName: toolIcon(for: toolUse.toolName))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.textSecondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(toolUse.toolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textSecondary)
                Text(toolUse.inputSummary)
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            toolStatusBadge(toolUse.status)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.bgElevated.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.borderSubtle, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func toolStatusBadge(_ status: ToolUseStatus) -> some View {
        switch status {
        case .pending:
            Circle()
                .fill(Color.textTertiary)
                .frame(width: 6, height: 6)
        case .executing:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 14, height: 14)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.success)
        case .error(let msg):
            HStack(spacing: 2) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.danger)
                Text(msg.truncated(to: 40))
                    .font(.system(size: 9))
                    .foregroundColor(.danger)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Tool Result Card

    private func toolResultCard(_ result: ToolResultBlock) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: result.isError ? "xmark.circle" : "arrow.turn.down.left")
                    .font(.system(size: 10))
                    .foregroundColor(result.isError ? .danger : .textTertiary)
                Text(result.isError ? "Error" : "Result")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(result.isError ? .danger : .textTertiary)
            }

            Text(result.content.truncated(to: 500))
                .font(.system(size: 10))
                .foregroundColor(.textTertiary)
                .lineLimit(result.isExpanded ? nil : 6)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .padding(.leading, 28)
    }

    // MARK: - System Reminder

    private func systemReminder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundColor(.textTertiary.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Status Row

    private func statusRow(_ text: String) -> some View {
        Text(text)
            .font(.uiCaption)
            .foregroundColor(.textSecondary)
            .padding(.leading, 4)
    }

    // MARK: - Tool icon mapping

    private func toolIcon(for toolName: String) -> String {
        switch toolName {
        case "Bash", "PowerShell": return "terminal"
        case "Read", "FileRead": return "doc.text"
        case "Write", "FileWrite": return "doc.badge.plus"
        case "Edit", "FileEdit": return "pencil"
        case "Grep": return "magnifyingglass"
        case "Glob": return "folder"
        case "WebFetch", "WebSearch": return "globe"
        case "Task", "TaskCreate", "TaskGet", "TaskList", "TaskStop": return "list.bullet.clipboard"
        case "Agent": return "cpu"
        case "Skill": return "wand.and.stars"
        case "TodoWrite": return "checklist"
        case "NotebookEdit": return "book"
        default: return "wrench"
        }
    }
}

#if DEBUG
struct MessageBubbleView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 0) {
            MessageBubbleView(
                message: AgentMessage.user("Hello, DeepSeek!"),
                thoughtTimeString: nil,
                reasoningExpanded: false,
                onToggleReasoning: {}
            )
            MessageBubbleView(
                message: AgentMessage(
                    role: .assistant,
                    blocks: [
                        .thinking("Let me think about this..."),
                        .text("Hello! How can I help you today?"),
                        .toolUse(ToolUseBlock(
                            toolUseID: "tool_1", toolName: "Bash",
                            inputSummary: "ls -la", inputDetail: "",
                            status: .completed
                        )),
                        .toolResult(ToolResultBlock(
                            toolUseID: "tool_1",
                            content: "total 48\ndrwxr-xr-x  12 user  staff   384 Jun 18 10:00 .",
                            isError: false
                        ))
                    ]
                ),
                thoughtTimeString: "Thought for 3s",
                reasoningExpanded: true,
                onToggleReasoning: {}
            )
        }
        .background(Color.bgContent)
        .preferredColorScheme(.dark)
    }
}
#endif
