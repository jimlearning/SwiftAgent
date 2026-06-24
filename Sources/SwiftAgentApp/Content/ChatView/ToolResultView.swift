import SwiftUI

/// Expandable tool call display. Ported from ClarcChatKit's `ToolResultView`.
struct ToolResultView: View {
    @Environment(ChatBridge.self) private var chatBridge
    let toolCall: ChatToolCall
    var isMessageStreaming: Bool = false
    @State private var isExpanded: Bool
    @State private var isDiffExpanded = false

    private let toolNameLower: String

    init(toolCall: ChatToolCall, isMessageStreaming: Bool = false) {
        self.toolCall = toolCall
        self.isMessageStreaming = isMessageStreaming
        let lower = toolCall.name.lowercased()
        self.toolNameLower = lower
        let isTransient = ToolCategory(toolName: lower).isTransient
        self._isExpanded = State(initialValue:
            lower == "edit" || lower == "multiedit"
            || (isTransient && isMessageStreaming && toolCall.result == nil)
        )
    }

    private var agentDescription: String? {
        guard toolNameLower == "agent" else { return nil }
        return toolCall.input["description"]?.stringValue
    }

    private var agentDisplayTitle: String {
        let agentType = toolCall.input["subagent_type"]?.stringValue
        let desc = toolCall.input["description"]?.stringValue
        if let type = agentType, let desc { return "\(type): \(desc)" }
        return desc ?? agentType ?? "Agent"
    }

    private var skillName: String? {
        guard toolNameLower == "skill" else { return nil }
        return toolCall.input["skill"]?.stringValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: sfSymbol)
                            .font(.system(size: ChatTheme.size(13), weight: .medium))
                            .foregroundStyle(iconColor)
                            .frame(width: 16, height: 16)

                        if toolNameLower == "agent" {
                            Text(agentDisplayTitle)
                                .font(.system(size: ChatTheme.size(13), weight: .medium))
                                .foregroundStyle(ChatTheme.textPrimary)
                        } else if let skillName = skillName {
                            Text(skillName)
                                .font(.system(size: ChatTheme.size(13), weight: .medium))
                                .foregroundStyle(ChatTheme.textPrimary)
                        } else {
                            Text(toolCall.name)
                                .font(.system(size: ChatTheme.size(13), weight: .medium))
                                .foregroundStyle(ChatTheme.textPrimary)
                        }

                        Spacer()

                        if toolCall.isError {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(ChatTheme.statusError)
                                .font(.caption)
                        } else if toolCall.result != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(ChatTheme.statusSuccess)
                                .font(.caption)
                        } else if isMessageStreaming {
                            Image(systemName: "circle.dotted")
                                .font(.system(size: ChatTheme.size(11), weight: .medium))
                                .foregroundStyle(ChatTheme.textTertiary)
                                .symbolEffect(.pulse)
                        } else {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(ChatTheme.textTertiary)
                                .font(.caption)
                        }

                        if toolCall.result != nil || hasExpandableContent {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(ChatTheme.textTertiary)
                        }
                    }

                    inputSummaryView
                        .lineLimit(isExpanded ? nil : 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                if isEditTool, let oldStr = toolCall.input["old_string"]?.stringValue,
                   let newStr = toolCall.input["new_string"]?.stringValue {
                    ClaudeThemeDivider()
                    editDiffView(oldString: oldStr, newString: newStr)
                } else if let result = toolCall.result, !result.isEmpty {
                    ClaudeThemeDivider()
                    ScrollView {
                        Text(result)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(toolCall.isError ? ChatTheme.statusError : ChatTheme.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                }
            }
        }
        .bubbleStyle(toolCall.isError ? .toolError : .tool)
        .chatPerfTimer("D2-toolResult tool=\(toolNameLower)", thresholdMs: 2)
        .onChange(of: toolCall.result) { _, newResult in
            guard ToolCategory(toolName: toolNameLower).isTransient, newResult != nil else { return }
            isExpanded = false
        }
    }

    // MARK: - Edit Diff

    private var isEditTool: Bool {
        toolNameLower == "edit" || toolNameLower == "multiedit" || toolNameLower == "multi_edit"
    }

    private var hasExpandableContent: Bool {
        isEditTool && toolCall.input["old_string"]?.stringValue != nil
            && toolCall.input["new_string"]?.stringValue != nil
    }

    private func editDiffView(oldString: String, newString: String) -> some View {
        let (trimmedOld, trimmedNew) = stripCommonIndent(
            old: oldString.components(separatedBy: .newlines),
            new: newString.components(separatedBy: .newlines)
        )
        let removedLines = trimmedOld.map { ("-", $0, false) }
        let addedLines = trimmedNew.map { ("+", $0, true) }
        let allLines = removedLines + addedLines

        let collapseThreshold = 12
        let needsToggle = allLines.count > collapseThreshold
        let visibleLines = needsToggle && !isDiffExpanded
            ? Array(allLines.prefix(collapseThreshold))
            : allLines

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visibleLines.enumerated()), id: \.offset) { _, item in
                let (prefix, text, isAdded) = item
                Text(prefix + " " + text)
                    .font(.system(size: ChatTheme.size(12), design: .monospaced))
                    .foregroundStyle(isAdded ? ChatTheme.statusSuccess : ChatTheme.statusError)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1)
                    .background((isAdded ? ChatTheme.statusSuccess : ChatTheme.statusError).opacity(0.06))
            }

            if needsToggle {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isDiffExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Group {
                            if isDiffExpanded { Text("Show less") }
                            else { Text("Show more") }
                        }
                        .font(.system(size: ChatTheme.size(12), weight: .medium))
                        Image(systemName: isDiffExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: ChatTheme.size(10), weight: .medium))
                    }
                    .foregroundStyle(ChatTheme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: ChatTheme.cornerRadiusSmall).fill(ChatTheme.surfacePrimary.opacity(0.6)))
                }
                .buttonStyle(.plain)
            }
        }
        .textSelection(.enabled)
    }

    // MARK: - Helpers

    private var sfSymbol: String {
        switch toolNameLower {
        case "agent": return "cpu"
        case "read": return "doc.text"
        case "grep", "glob": return "magnifyingglass"
        case "write": return "square.and.pencil"
        case "edit", "multiedit", "multi_edit": return "pencil"
        case "bash": return "terminal"
        case "notebookedit": return "book.and.wrench"
        case InteractiveTerminalState.toolName: return "apple.terminal"
        default: return ToolCategory(toolName: toolNameLower).sfSymbol
        }
    }

    private var iconColor: Color {
        switch toolNameLower {
        case "agent", "bash", InteractiveTerminalState.toolName: return ChatTheme.accent
        case "edit", "multiedit", "multi_edit", "write", "notebookedit": return ChatTheme.statusWarning
        case "read", "grep", "glob": return ChatTheme.textSecondary
        default:
            switch ToolCategory(toolName: toolNameLower).kind {
            case .execution: return ChatTheme.accent
            case .fileModification: return ChatTheme.statusWarning
            case .readOnly: return ChatTheme.textSecondary
            case .mcp, .unknown: return ChatTheme.textTertiary
            }
        }
    }

    @ViewBuilder
    private var inputSummaryView: some View {
        if isEditTool || toolNameLower == "write",
           let filePath = toolCall.input["file_path"]?.stringValue {
            let fileName = URL(fileURLWithPath: filePath).lastPathComponent
            HStack(spacing: 0) {
                Text("\(toolDescriptionPrefix) — ")
                    .font(.system(size: ChatTheme.size(12)))
                    .foregroundStyle(ChatTheme.textSecondary)
                Button {
                    chatBridge.inspectorFile = PreviewFile(path: filePath, name: fileName)
                } label: {
                    Text(fileName)
                        .font(.system(size: ChatTheme.size(12)))
                        .foregroundStyle(ChatTheme.accent)
                        .underline()
                }
                .buttonStyle(.plain)
                .pointerCursorOnHover()
            }
        } else {
            Text(inputSummary)
                .font(.system(size: ChatTheme.size(12)))
                .foregroundStyle(ChatTheme.textSecondary)
        }
    }

    private var inputSummary: String {
        if toolNameLower == "agent" {
            if let desc = toolCall.input["description"]?.stringValue { return desc }
            if let prompt = toolCall.input["prompt"]?.stringValue {
                return prompt.count > 60 ? String(prompt.prefix(60)) + "..." : prompt
            }
            return toolDescriptionPrefix
        }
        if toolNameLower == "skill" {
            if let name = toolCall.input["skill"]?.stringValue {
                return "\(toolDescriptionPrefix) — \(name)"
            }
            return toolDescriptionPrefix
        }
        if let filePath = toolCall.input["file_path"]?.stringValue {
            let fileName = URL(fileURLWithPath: filePath).lastPathComponent
            return "\(toolDescriptionPrefix) — \(fileName)"
        }
        if let command = toolCall.input["command"]?.stringValue {
            return "\(toolDescriptionPrefix) — \(command.count > 50 ? String(command.prefix(50)) + "..." : command)"
        }
        if let pattern = toolCall.input["pattern"]?.stringValue {
            return "\(toolDescriptionPrefix) — '\(pattern)'"
        }
        if let path = toolCall.input["path"]?.stringValue {
            let fileName = URL(fileURLWithPath: path).lastPathComponent
            return "\(toolDescriptionPrefix) — \(fileName)"
        }
        return toolDescriptionPrefix
    }

    private var toolDescriptionPrefix: String {
        switch toolNameLower {
        case "read": "Read file"
        case "edit": "Edit file"
        case "write": "Create new file"
        case "bash": "Run command"
        case "glob": "Find files"
        case "grep": "Search in code"
        case "multiedit": "Edit multiple locations"
        case "notebookedit": "Edit notebook"
        case "agent": "Subagent"
        case "skill": "Skill"
        case InteractiveTerminalState.toolName: "Interactive terminal"
        default: toolCall.name
        }
    }
}

/// Strips common leading whitespace from old/new strings for diff display.
private func stripCommonIndent(old: [String], new: [String]) -> ([String], [String]) {
    let allLines = old + new
    let minIndent = allLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        .map { $0.prefix(while: { $0 == " " || $0 == "\t" }).count }
        .min() ?? 0
    guard minIndent > 0 else { return (old, new) }
    return (old.map { String($0.dropFirst(minIndent)) }, new.map { String($0.dropFirst(minIndent)) })
}
