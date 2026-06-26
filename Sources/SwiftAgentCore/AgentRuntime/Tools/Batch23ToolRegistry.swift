import Foundation

/// Registry for Batch 2 (file mutation) and Batch 3 (command execution) tools.
/// Constructs each tool with its required init-time context and pairs it with
/// ToolMetadata. Consumed by session construction in CLI (Plan 04-05) and App (Plan 04-06).
public struct Batch23ToolRegistry {
    public static func tools(
        workingDirectory: String,
        shell: String = "/bin/zsh"
    ) -> [(any Tool, ToolMetadata)] {
        [
            // MARK: Batch 2 — File Mutation

            (
                FileWriteTool(workingDirectory: workingDirectory),
                ToolMetadata(
                    searchHint: "create or overwrite files write",
                    isReadOnly: false,
                    isConcurrencySafe: false,
                    isDestructive: true,
                    interruptBehavior: .cancel,
                    activityDescription: "Writing file",
                    requiresApproval: true
                )
            ),
            (
                FileEditTool(workingDirectory: workingDirectory),
                ToolMetadata(
                    searchHint: "modify file contents in place edit",
                    isReadOnly: false,
                    isConcurrencySafe: false,
                    isDestructive: true,
                    interruptBehavior: .cancel,
                    activityDescription: "Editing file",
                    requiresApproval: true
                )
            ),
            (
                NotebookEditTool(),
                ToolMetadata(
                    searchHint: "edit Jupyter notebook cells ipynb",
                    isReadOnly: false,
                    isConcurrencySafe: false,
                    isDestructive: true,
                    interruptBehavior: .cancel,
                    activityDescription: "Editing notebook",
                    requiresApproval: true
                )
            ),
            (
                SnipTool(),
                ToolMetadata(
                    searchHint: "snip conversation history manage context",
                    isReadOnly: false,
                    isConcurrencySafe: false,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Snipping history",
                    requiresApproval: false
                )
            ),

            // MARK: Batch 3 — Command Execution

            (
                BashTool(workingDirectory: workingDirectory, shell: shell),
                ToolMetadata(
                    searchHint: "execute shell commands bash terminal",
                    isReadOnly: false,
                    isConcurrencySafe: false,
                    isDestructive: true,
                    interruptBehavior: .cancel,
                    activityDescription: "Running command",
                    requiresApproval: true
                )
            ),
            (
                LSPTool(workingDirectory: workingDirectory),
                ToolMetadata(
                    searchHint: "code intelligence definitions references symbols hover LSP",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .cancel,
                    activityDescription: "Querying LSP",
                    requiresApproval: false
                )
            ),
            (
                PowerShellTool(),
                ToolMetadata(
                    searchHint: "execute Windows PowerShell commands",
                    isReadOnly: false,
                    isConcurrencySafe: false,
                    isDestructive: true,
                    interruptBehavior: .cancel,
                    activityDescription: "Running PowerShell",
                    requiresApproval: true
                )
            ),
            (
                TerminalCaptureTool(),
                ToolMetadata(
                    searchHint: "capture terminal output screenshot",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Capturing terminal",
                    requiresApproval: false
                )
            ),
            (
                TungstenTool(),
                ToolMetadata(
                    searchHint: "analyze bytecode tungsten artifacts",
                    isReadOnly: true,
                    isConcurrencySafe: true,
                    isDestructive: false,
                    interruptBehavior: .block,
                    activityDescription: "Analyzing artifacts",
                    requiresApproval: false
                )
            ),
        ]
    }
}
