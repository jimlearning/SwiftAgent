import Foundation

/// XML tag constants matching Claude Code's constants/xml.ts.
/// Used for marking skill/command metadata in messages and parsing terminal activity.
public enum XmlTags {
    // MARK: - Command metadata

    public static let commandNameTag = "command-name"
    public static let commandMessageTag = "command-message"
    public static let commandArgsTag = "command-args"

    // MARK: - Terminal/bash I/O

    public static let bashInputTag = "bash-input"
    public static let bashStdoutTag = "bash-stdout"
    public static let bashStderrTag = "bash-stderr"
    public static let localCommandStdoutTag = "local-command-stdout"
    public static let localCommandStderrTag = "local-command-stderr"
    public static let localCommandCaveatTag = "local-command-caveat"

    public static let terminalOutputTags: [String] = [
        bashInputTag, bashStdoutTag, bashStderrTag,
        localCommandStdoutTag, localCommandStderrTag,
        localCommandCaveatTag,
    ]

    // MARK: - System prompts

    public static let tickTag = "tick"

    // MARK: - Task notifications

    public static let taskNotificationTag = "task-notification"
    public static let taskIdTag = "task-id"
    public static let toolUseIdTag = "tool-use-id"
    public static let taskTypeTag = "task-type"
    public static let outputFileTag = "output-file"
    public static let statusTag = "status"
    public static let summaryTag = "summary"
    public static let reasonTag = "reason"

    // MARK: - Worktree

    public static let worktreeTag = "worktree"
    public static let worktreePathTag = "worktreePath"
    public static let worktreeBranchTag = "worktreeBranch"

    // MARK: - Ultraplan & remote

    public static let ultraplanTag = "ultraplan"
    public static let remoteReviewTag = "remote-review"
    public static let remoteReviewProgressTag = "remote-review-progress"

    // MARK: - Inter-agent communication

    public static let teammateMessageTag = "teammate-message"
    public static let channelMessageTag = "channel-message"
    public static let channelTag = "channel"
    public static let crossSessionMessageTag = "cross-session-message"

    // MARK: - Fork agent

    public static let forkBoilerplateTag = "fork-boilerplate"
    public static let forkDirectivePrefix = "Your directive: "

    // MARK: - Help/info arg patterns

    public static let commonHelpArgs: [String] = ["help", "-h", "--help"]
    public static let commonInfoArgs: [String] = [
        "list", "show", "display", "current", "view", "get",
        "check", "describe", "print", "version", "about",
        "status", "?",
    ]
}
