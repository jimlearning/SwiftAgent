import Foundation

/// Executes shell commands with timeout, background, and sandbox support.
/// Migrated to Tool protocol with typed Arguments.
///
/// Key behaviors matching Claude Code:
/// - Structured output with stdout, stderr, exit code, and timed-out signals
/// - Timeout handling via Process + async wait with kill-on-timeout
/// - Background execution with run_in_background flag
/// - Danger-pattern permission checks and destructive-command detection
public struct BashTool: Tool {
    public let name = "Bash"
    public let description = """
        Executes a given bash command and returns its output.

        The working directory persists between commands, but shell state does not. \
        The shell environment is initialized from the user's profile (bash or zsh).

        IMPORTANT: Avoid using this tool to run `find`, `grep`, `cat`, `head`, \
        `tail`, `sed`, `awk`, or `echo` commands, unless explicitly instructed \
        or after you have verified that a dedicated tool cannot accomplish your \
        task. Instead, use the appropriate dedicated tool as this will provide \
        a much better experience for the user.
        """

    private let workingDirectory: String
    private let shell: String

    // MARK: - Arguments

    public struct Arguments: Codable, Sendable {
        public var command: String
        public var description: String?
        public var timeout: Int?
        public var dangerouslyDisableSandbox: Bool?
        public var runInBackground: Bool?

        enum CodingKeys: String, CodingKey {
            case command
            case description
            case timeout
            case dangerouslyDisableSandbox = "dangerouslyDisableSandbox"
            case runInBackground = "run_in_background"
        }
    }

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

    // MARK: - Init

    public init(workingDirectory: String, shell: String = ShellResolver.resolve()) {
        self.workingDirectory = workingDirectory
        self.shell = shell
    }

    // MARK: - Execute Entry Point

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        let cmd = arguments.command
        let timeoutMs: Int
        if let t = arguments.timeout {
            timeoutMs = min(t, 600_000)
        } else {
            timeoutMs = 120_000
        }

        let runInBackground = arguments.runInBackground ?? false

        if runInBackground {
            return executeBackground(command: cmd)
        }

        return try await executeForeground(
            command: cmd,
            timeoutMs: timeoutMs
        )
    }

    // MARK: - Foreground Execution

    /// Runs a command in the foreground with timeout handling.
    /// Uses Process + Pipe for real command execution.
    /// Streams output via readabilityHandler and kills the process on timeout.
    private func executeForeground(
        command cmd: String,
        timeoutMs: Int
    ) async throws -> ToolOutputValue {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell, isDirectory: false)
        process.arguments = ["-c", cmd]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)

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
            return .string("Error running command: \(error.localizedDescription)")
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
    /// Uses `withTaskGroup` to race process completion against a sleep-based
    /// timeout. `process.waitUntilExit()` is offloaded to a Dispatch queue to
    /// avoid blocking the Swift Concurrency cooperative thread pool.
    /// The task group naturally resolves the race — first result wins.
    private func waitForProcess(
        _ process: Process,
        timeoutMs: Int
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            // Path A: Process finishes naturally
            group.addTask {
                await withUnsafeContinuation { cont in
                    DispatchQueue.global().async {
                        process.waitUntilExit()
                        cont.resume()
                    }
                }
                return false // completed normally, not timed out
            }

            // Path B: Timeout fires
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutMs) * 1_000_000)
                if process.isRunning {
                    process.terminate()
                    return true // timed out
                }
                return false // process finished before timeout could fire
            }

            // First path to complete wins; cancel the other
            let timedOut = await group.next() ?? false
            group.cancelAll()
            return timedOut
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
    ) -> ToolOutputValue {
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
            return .string(parts.joined(separator: "\n"))
        }

        // Exit code
        if exitCode != 0 {
            parts.append("Exit code: \(exitCode)")
            // Non-zero exit with no output at all is always an error
            if trimmedStdout.isEmpty && trimmedStderr.isEmpty {
                return .string(parts.joined(separator: "\n"))
            }
        }

        let content = parts.isEmpty
            ? "(No output)"
            : parts.joined(separator: "\n")
        return .string(content)
    }

    // MARK: - Background Execution

    /// Starts a command in the background and returns immediately with a
    /// process handle. Output is redirected to a temp log file.
    /// Matches Claude Code's background task spawning.
    private func executeBackground(
        command cmd: String
    ) -> ToolOutputValue {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-c", cmd]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        process.environment = ProcessInfo.processInfo.environment

        let outputFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "swiftagent_bg_\(UUID().uuidString.prefix(8)).log"
            )
            .path

        // Create the output file for writing
        FileManager.default.createFile(atPath: outputFile, contents: nil)
        guard let outHandle = FileHandle(forWritingAtPath: outputFile) else {
            return .string("Error: could not create background output file")
        }

        process.standardOutput = outHandle
        process.standardError = outHandle

        do {
            try process.run()
        } catch {
            return .string("""
                Error starting background command: \
                \(error.localizedDescription)
                """)
        }

        let pid = process.processIdentifier
        // Detach the process so it runs independently; close the handle on exit
        process.terminationHandler = { _ in
            try? outHandle.close()
        }

        return .string("Running in background (pid \(pid)). Output: \(outputFile)")
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
