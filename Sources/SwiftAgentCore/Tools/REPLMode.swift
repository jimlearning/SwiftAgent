import Foundation

// MARK: - REPL Mode Configuration
// Matches Claude Code's tools/REPLTool/constants.ts and primitiveTools.ts

public let REPL_TOOL_NAME = "REPL"

/// Tools that are only accessible via REPL when REPL mode is enabled.
/// When REPL mode is on, these tools are hidden from Claude's direct use,
/// forcing batch operations through the REPL wrapper.
public let REPL_ONLY_TOOL_NAMES: Set<String> = [
    "Read",
    "Write",
    "Edit",
    "Glob",
    "Grep",
    "Bash",
    "NotebookEdit",
    "Agent",
]

/// Checks whether REPL mode is enabled.
/// REPL mode is default-on for ants in the interactive CLI.
/// Set CLAUDE_CODE_REPL=0 to disable, or CLAUDE_REPL_MODE=1 to force on.
public func isReplModeEnabled() -> Bool {
    if let v = ProcessInfo.processInfo.environment["CLAUDE_CODE_REPL"],
       ["0", "false", "no"].contains(v.lowercased()) {
        return false
    }
    if let v = ProcessInfo.processInfo.environment["CLAUDE_REPL_MODE"],
       ["1", "true", "yes"].contains(v.lowercased()) {
        return true
    }
    let userType = ProcessInfo.processInfo.environment["USER_TYPE"] ?? ""
    let entrypoint = ProcessInfo.processInfo.environment["CLAUDE_CODE_ENTRYPOINT"] ?? ""
    return userType == "ant" && entrypoint == "cli"
}
