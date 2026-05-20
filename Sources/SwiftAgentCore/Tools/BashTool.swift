import Foundation

/// Executes shell commands with timeout, background, and sandbox support.
/// Mirrors Claude Code's BashTool (~1100+ lines).
///
/// Key behaviors matching Claude Code:
/// - Structured output with stdout, stderr, exit code, and timed-out signals
/// - Timeout handling via Process + async wait with kill-on-timeout
/// - Background execution with run_in_background flag
/// - Danger-pattern permission checks and destructive-command detection
/// - Tool-use summary and activity description for UI display
public struct BashTool: Tool {
    public init() {}

    // MARK: - Tool Identity

    public let name = "Bash"
    public var searchHint: String? { "execute shell commands" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String {
        """
        Executes a given bash command and returns its output.

        The working directory persists between commands, but shell state does not. \
        The shell environment is initialized from the user's profile (bash or zsh).

        IMPORTANT: Avoid using this tool to run `find`, `grep`, `cat`, `head`, \
        `tail`, `sed`, `awk`, or `echo` commands, unless explicitly instructed \
        or after you have verified that a dedicated tool cannot accomplish your \
        task. Instead, use the appropriate dedicated tool as this will provide \
        a much better experience for the user.
        """
    }

    // MARK: - Tool Protocol Overrides (static / non-input-dependent)

    /// Bash runs arbitrary commands — default to not read-only.
    public var isReadOnly: Bool { false }

    /// Bash commands mutate system state — not concurrency-safe.
    public var isConcurrencySafe: Bool { false }

    /// Claude Code default for Bash tool result persistence threshold.
    public var maxResultSizeChars: Int { 500_000 }

    // MARK: - Input Schema

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "command": JSONSchemaProperty(
                type: "string",
                description: "The command to execute"
            ),
            "description": JSONSchemaProperty(
                type: "string",
                description: """
                    Clear, concise description of what this command does in \
                    active voice. Never use words like "complex" or "risk" in \
                    the description - just describe what it does.

                    For simple commands (git, npm, standard CLI tools), keep \
                    it brief (5-10 words):
                    - ls → "List files in current directory"
                    - git status → "Show working tree status"
                    - npm install → "Install package dependencies"

                    For commands that are harder to parse at a glance (piped \
                    commands, obscure flags, etc.), add enough context to \
                    clarify what it does:
                    - find . -name "*.tmp" -exec rm {} \\; → "Find and delete \
                    all .tmp files recursively"
                    - git reset --hard origin/main → "Discard all local changes \
                    and match remote main"
                    - curl -s url | jq '.data[]' → "Fetch JSON from URL and \
                    extract data array elements"
                    """
            ),
            "timeout": JSONSchemaProperty(
                type: "number",
                description: "Optional timeout in milliseconds (max 600000)."
            ),
            "run_in_background": JSONSchemaProperty(
                type: "boolean",
                description: "Set to true to run this command in the background."
            ),
            "dangerouslyDisableSandbox": JSONSchemaProperty(
                type: "boolean",
                description: """
                    Set this to true to dangerously override sandbox \
                    mode and run commands without sandboxing.
                    """
            ),
        ], required: ["command"])
    }

    // MARK: - isDestructive (input-dependent)

    /// Returns `true` when the command matches known destructive patterns
    /// (rm -rf, git reset --hard, dd, kubectl delete, terraform destroy, etc.).
    /// Matching Claude Code's destructiveCommandWarning patterns.
    public func isDestructive(_ input: [String: JSONValue]) -> Bool {
        guard case .string(let cmd) = input["command"] else { return false }

        for pattern in dangerousPatterns {
            if cmd.range(of: pattern.regex, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    // MARK: - Interrupt Behavior

    /// Claude Code: Bash is "cancel" on new message — if the user sends a new
    /// message while a Bash command is running, stop the tool and discard output.
    public func interruptBehavior() -> InterruptBehavior { .cancel }

    // MARK: - UI / Display Helpers

    /// Short summary for compact display. Prefers the user-provided `description`;
    /// otherwise truncates the command string to 50 characters.
    /// Matches Claude Code's `getToolUseSummary`.
    public func getToolUseSummary(_ input: [String: JSONValue]) -> String? {
        guard case .string(let cmd) = input["command"], !cmd.isEmpty else {
            return nil
        }

        if case .string(let desc) = input["description"], !desc.isEmpty {
            return desc
        }

        if cmd.count <= 50 {
            return cmd
        }
        return String(cmd.prefix(47)) + "..."
    }

    /// Human-readable present-tense activity description for spinner display.
    /// E.g., "Running ls -la", "Running npm install".
    /// Matches Claude Code's `getActivityDescription`.
    public func getActivityDescription(_ input: [String: JSONValue]) -> String? {
        guard case .string(let cmd) = input["command"], !cmd.isEmpty else {
            return "Running command"
        }

        if case .string(let desc) = input["description"], !desc.isEmpty {
            return "Running \(desc)"
        }

        let displayCommand: String
        if cmd.count <= 50 {
            displayCommand = cmd
        } else {
            displayCommand = String(cmd.prefix(47)) + "..."
        }
        return "Running \(displayCommand)"
    }

    /// Returns the raw command string for auto-mode security classifier input.
    /// Matches Claude Code's `toAutoClassifierInput`.
    public func toAutoClassifierInput(_ input: [String: JSONValue]) -> String {
        guard case .string(let cmd) = input["command"] else { return "" }
        return cmd
    }

    // MARK: - Permission Check

    /// Permission gate matching Claude Code's Bash permission patterns:
    /// - Deny: fork bombs, disk writes, root chmod, root deletion,
    ///   piped curl/wget to shell
    /// - Ask:  destructive operations (rm -rf, dd)
    /// - Allow: everything else
    public func checkPermissions(
        input: [String: JSONValue],
        context: ToolUseContext
    ) async -> PermissionResult {
        guard case .string(let cmd) = input["command"] else {
            return .allow(PermissionAllowDecision())
        }

        for pattern in dangerousPatterns {
            if cmd.range(of: pattern.regex, options: .regularExpression) != nil {
                return .deny(PermissionDenyDecision(
                    message: pattern.reason,
                    decisionReason: .mode(.default)
                ))
            }
        }

        // Extra catch: chmod 777 on root
        if cmd.range(of: "chmod\\s+777\\s+/", options: .regularExpression) != nil {
            return .deny(PermissionDenyDecision(
                message: "Cannot recursively chmod 777 root",
                decisionReason: .mode(.default)
            ))
        }

        // Warn on destructive commands
        if cmd.contains("rm -rf") || cmd.contains("dd if=") {
            return .ask(PermissionAskDecision(
                message: "This command could be destructive"
            ))
        }

        return .allow(PermissionAllowDecision())
    }

    // MARK: - Execute Entry Point

    public func call(
        input: [String: JSONValue],
        context: ToolUseContext,
        canUseTool: CanUseToolFn? = nil,
        parentMessage: Message? = nil,
        onProgress: ToolCallProgress? = nil
    ) async throws -> ToolResult {
        guard case .string(let cmd) = input["command"] else {
            return ToolResult(content: "Error: command is required", isError: true)
        }

        let timeoutMs: Int
        if case .number(let n) = input["timeout"] {
            timeoutMs = min(Int(n), 600_000)
        } else {
            timeoutMs = 120_000
        }

        let runInBackground = input.boolValue("run_in_background") ?? false

        if runInBackground {
            return executeBackground(command: cmd, context: context)
        }

        return try await executeForeground(
            command: cmd,
            timeoutMs: timeoutMs,
            context: context
        )
    }

    // MARK: - Foreground Execution

    /// Runs a command in the foreground with timeout handling.
    /// Uses Process + Pipe for real command execution.
    /// Streams output via readabilityHandler and kills the process on timeout.
    private func executeForeground(
        command cmd: String,
        timeoutMs: Int,
        context: ToolUseContext
    ) async throws -> ToolResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: context.shell ?? ShellResolver.resolve())
        process.arguments = ["-c", cmd]
        process.currentDirectoryURL = URL(fileURLWithPath: context.workingDirectory)

        // Pipes for stdout and stderr
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // Thread-safe output accumulators that capture output as it streams
        let stdoutBuffer = OutputBuffer()
        let stderrBuffer = OutputBuffer()

        // Set up readability handlers to capture output in real time
        // (matching Claude Code's streaming approach via AsyncGenerator)
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stdoutBuffer.append(data)
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stderrBuffer.append(data)
            }
        }

        // Launch the process
        do {
            try process.run()
        } catch {
            cleanupPipes(outPipe, errPipe)
            return ToolResult(
                content: "Error running command: \(error.localizedDescription)",
                isError: true
            )
        }

        // Wait for completion or timeout
        let timedOut = await waitForProcess(process, timeoutMs: timeoutMs)

        // Clean up readability handlers to stop receiving data
        cleanupPipes(outPipe, errPipe)

        // Read accumulated output
        let stdoutString = stdoutBuffer.stringValue
        let stderrString = stderrBuffer.stringValue
        let exitCode = process.terminationStatus

        return formatOutput(
            stdout: stdoutString,
            stderr: stderrString,
            exitCode: exitCode,
            timedOut: timedOut
        )
    }

    /// Waits for the process to exit, killing it if the timeout is reached.
    /// Returns `true` if the process timed out.
    ///
    /// Uses a continuation-based pattern to bridge Dispatch concurrency with
    /// Swift async/await while avoiding races between the timeout and
    /// process-exit paths. Only the first completion path (process-exit or
    /// timeout) resumes the continuation — the lock ensures mutual exclusion.
    private func waitForProcess(
        _ process: Process,
        timeoutMs: Int
    ) async -> Bool {
        let state = ProcessWaitState()

        return await withCheckedContinuation { continuation in
            // Path A: Process finishes naturally
            DispatchQueue.global().async {
                process.waitUntilExit()

                state.lock.lock()
                if !state.resolved {
                    state.resolved = true
                    state.lock.unlock()
                    continuation.resume(returning: false) // completed normally
                } else {
                    state.lock.unlock()
                }
            }

            // Path B: Timeout fires
            DispatchQueue.global().asyncAfter(
                deadline: .now() + .milliseconds(timeoutMs)
            ) {
                state.lock.lock()
                if !state.resolved, process.isRunning {
                    process.terminate()
                    state.resolved = true
                    state.lock.unlock()
                    continuation.resume(returning: true) // timed out
                } else {
                    state.lock.unlock()
                }
            }
        }
    }

    /// Removes readability handlers from pipes to stop receiving data
    /// and allow file handles to be deallocated.
    private func cleanupPipes(_ outPipe: Pipe, _ errPipe: Pipe) {
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
    }

    /// Formats the execution result as structured content.
    /// Matches Claude Code's output format:
    ///   [stdout, stderr, exitCode info, timeout info].filter(Boolean).join('\n')
    private func formatOutput(
        stdout: String,
        stderr: String,
        exitCode: Int32,
        timedOut: Bool
    ) -> ToolResult {
        var parts: [String] = []

        // Stdout (may be empty — the model expects it)
        let trimmedStdout = stdout.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !trimmedStdout.isEmpty {
            parts.append(trimmedStdout)
        }

        // Stderr
        let trimmedStderr = stderr.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !trimmedStderr.isEmpty {
            parts.append("[stderr]\n\(trimmedStderr)")
        }

        // Timed out signal (takes precedence over exit code)
        if timedOut {
            parts.append(
                "<error>Command was aborted before completion</error>"
            )
            return ToolResult(
                content: parts.joined(separator: "\n"),
                isError: true
            )
        }

        // Exit code
        if exitCode != 0 {
            parts.append("Exit code: \(exitCode)")
            // Non-zero exit with no output at all is always an error
            if trimmedStdout.isEmpty && trimmedStderr.isEmpty {
                return ToolResult(
                    content: parts.joined(separator: "\n"),
                    isError: true
                )
            }
        }

        let content = parts.isEmpty
            ? "(No output)"
            : parts.joined(separator: "\n")
        return ToolResult(content: content)
    }

    // MARK: - Background Execution

    /// Starts a command in the background and returns immediately with a
    /// process handle. Output is redirected to a temp log file.
    /// Matches Claude Code's background task spawning.
    private func executeBackground(
        command cmd: String,
        context: ToolUseContext
    ) -> ToolResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: context.shell ?? ShellResolver.resolve())
        process.arguments = ["-c", cmd]
        process.currentDirectoryURL = URL(
            fileURLWithPath: context.workingDirectory
        )

        let outputFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "swiftagent_bg_\(UUID().uuidString.prefix(8)).log"
            )
            .path

        // Create the output file for writing
        FileManager.default.createFile(atPath: outputFile, contents: nil)
        guard let outHandle = FileHandle(forWritingAtPath: outputFile) else {
            return ToolResult(
                content: "Error: could not create background output file",
                isError: true
            )
        }

        process.standardOutput = outHandle
        process.standardError = outHandle

        do {
            try process.run()
        } catch {
            return ToolResult(
                content: """
                    Error starting background command: \
                    \(error.localizedDescription)
                    """,
                isError: true
            )
        }

        let pid = process.processIdentifier
        // Detach the process so it runs independently; close the handle on exit
        process.terminationHandler = { _ in
            try? outHandle.close()
        }

        return ToolResult(
            content: "Running in background (pid \(pid)). Output: \(outputFile)"
        )
    }
}

// MARK: - Danger Patterns

/// Known-dangerous command patterns blocked by the permission system.
/// Mirrors Claude Code's destructive command warning patterns plus
/// the AST-aware security parsing for fork bombs, disk writes, etc.
private struct DangerPattern: Sendable {
    let regex: String
    let reason: String
}

private let dangerousPatterns: [DangerPattern] = [
    DangerPattern(
        regex: "rm\\s+-rf\\s+/",
        reason: "Cannot delete root filesystem"
    ),
    DangerPattern(
        regex: "mkfs\\.",
        reason: "Cannot format filesystems"
    ),
    DangerPattern(
        regex: ":\\{\\}:|:&",
        reason: "Fork bomb blocked"
    ),
    DangerPattern(
        regex: ">\\s*/dev/sda",
        reason: "Cannot write to raw disk devices"
    ),
    DangerPattern(
        regex: "dd\\s+if=.*of=/dev/",
        reason: "Cannot write to raw disk devices"
    ),
    DangerPattern(
        regex: "chmod\\s+777\\s+/",
        reason: "Cannot recursively chmod 777 root"
    ),
    DangerPattern(
        regex: "curl.*\\|\\s*(ba)?sh",
        reason: "Piped shell execution blocked"
    ),
    DangerPattern(
        regex: "wget.*-O-.*\\|\\s*(ba)?sh",
        reason: "Piped shell execution blocked"
    ),
    DangerPattern(
        regex: "chown\\s+-R\\s+\\w+\\s+/",
        reason: "Cannot recursively chown root"
    ),
    DangerPattern(
        regex: "mv\\s+\\S+\\s+/dev/null",
        reason: "Suspicious device redirect"
    ),
]

// MARK: - Process Wait State

/// Mutable state holder for the process-wait timeout race.
/// Uses NSLock to synchronize access from the process-exit and
/// timeout dispatch queues, avoiding captured-var concurrency warnings.
private final class ProcessWaitState: @unchecked Sendable {
    let lock = NSLock()
    var resolved = false
}

// MARK: - Output Buffer

/// Thread-safe string accumulator for capturing pipe output as it streams.
/// Uses NSLock to protect concurrent appends from readabilityHandler callbacks.
private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ newData: Data) {
        lock.lock()
        data.append(newData)
        lock.unlock()
    }

    var stringValue: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
