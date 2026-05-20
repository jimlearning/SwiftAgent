import Foundation

/// Result of a hook execution.
/// Matches CC's hook result model: blocking errors (exit code 2) prevent continuation,
/// non-blocking errors (exit code != 0,2) are logged but allow continuation,
/// stop prevents continuation with a user-facing reason.
public enum HookResult: Sendable {
    case `continue`
    case stop(reason: String)
    case modify(input: String)
    /// Blocking error — exit code 2. Prevents continuation. Matches CC's blockingError.
    case blockingError(reason: String)
    /// Non-blocking error — exit code != 0,2. Logged but allows continuation. Matches CC's nonBlockingError.
    case nonBlockingError(message: String)
}

/// Where a hook was defined. Matches CC's HookSource.
public enum HookSource: String, Sendable, Codable {
    case userSettings = "user_settings"
    case projectSettings = "project_settings"
    case localSettings = "local_settings"
    case policySettings = "policy_settings"
    case plugin
    case builtin
}

/// A single registered hook entry.
/// Matches Claude Code's hook system supporting command, HTTP, agent, and prompt types.
public struct HookEntry: Sendable, Identifiable {
    public let id: String
    public let type: HookType
    public let event: HookEvent
    public let command: String?
    public let url: String?
    public let matcher: String?
    public let conditionFilter: String?
    public let shell: String?
    public let prompt: String?
    public let model: String?
    public let headers: [String: String]?
    public let allowedEnvVars: [String]?
    public let statusMessage: String?
    public let once: Bool
    public let async: Bool
    public let asyncRewake: Bool
    public var enabled: Bool
    public let timeout: Int?
    /// Tracks where this hook was defined (user settings, project, plugin, etc.).
    /// Matches CC's hook.source field.
    public let source: HookSource?

    public init(
        id: String = UUID().uuidString,
        type: HookType = .command,
        event: HookEvent,
        command: String? = nil,
        url: String? = nil,
        matcher: String? = nil,
        conditionFilter: String? = nil,
        shell: String? = nil,
        prompt: String? = nil,
        model: String? = nil,
        headers: [String: String]? = nil,
        allowedEnvVars: [String]? = nil,
        statusMessage: String? = nil,
        once: Bool = false,
        async: Bool = false,
        asyncRewake: Bool = false,
        enabled: Bool = true,
        timeout: Int? = nil,
        source: HookSource? = nil
    ) {
        self.id = id
        self.type = type
        self.event = event
        self.command = command
        self.url = url
        self.matcher = matcher
        self.conditionFilter = conditionFilter
        self.shell = shell
        self.prompt = prompt
        self.model = model
        self.headers = headers
        self.allowedEnvVars = allowedEnvVars
        self.statusMessage = statusMessage
        self.once = once
        self.async = async
        self.asyncRewake = asyncRewake
        self.enabled = enabled
        self.timeout = timeout
        self.source = source
    }
}

/// Manages hook registration and event dispatch.
/// Hooks are shell commands executed on lifecycle events.
public actor HookSystem {
    private var hooks: [HookEntry] = []

    public init() {}

    /// Register a hook.
    public func register(_ hook: HookEntry) {
        hooks.append(hook)
    }

    /// Register a hook from config.
    public func register(from config: HookConfig) {
        let entry = HookEntry(
            id: config.id,
            type: config.type,
            event: config.event,
            command: config.command,
            url: config.url,
            matcher: config.matcher,
            conditionFilter: config.conditionFilter,
            shell: config.shell,
            prompt: config.prompt,
            model: config.model,
            headers: config.headers,
            allowedEnvVars: config.allowedEnvVars,
            statusMessage: config.statusMessage,
            once: config.once ?? false,
            async: config.async ?? false,
            asyncRewake: config.asyncRewake ?? false,
            timeout: config.timeout,
            source: config.source
        )
        hooks.append(entry)
    }

    /// Load all hooks from settings into the hook system.
    /// Matches CC's captureHooksConfigSnapshot + getHooksFromAllowedSources:
    /// respects disableAllHooks, allowManagedHooksOnly, and source tracking.
    public func loadFromSettings(_ settings: Settings) {
        // disableAllHooks: skip all hook loading.
        if settings.disableAllHooks == true {
            return
        }

        // allowManagedHooksOnly: only load policy/remote hooks.
        if settings.allowManagedHooksOnly == true {
            for hook in settings.hooks {
                if hook.source == .policySettings {
                    register(from: hook)
                }
            }
            return
        }

        // Normal mode: load all hooks from settings.
        for hook in settings.hooks {
            register(from: hook)
        }
    }

    /// Remove a hook by ID.
    public func remove(id: String) {
        hooks.removeAll { $0.id == id }
    }

    /// Disable a hook.
    public func disable(id: String) {
        if let index = hooks.firstIndex(where: { $0.id == id }) {
            var updated = hooks[index]
            updated.enabled = false
            hooks[index] = updated
        }
    }

    /// Dispatch an event to all matching hooks. Returns aggregated result.
    /// Matches CC's getMatchingHooks + executeHooksOutsideREPL aggregation:
    /// hooks run in PARALLEL (matching CC's Promise.all pattern), results are
    /// combined with blocking taking precedence over modify over continue.
    public func dispatch(event: HookEvent, input: String = "") async -> HookResult {
        // Evaluate matcher and conditionFilter for each hook.
        // Matches CC's matchesPattern (pipe-separated exact, wildcard, regex)
        // and getMatchingHooks conditionFilter evaluation.
        let matching = hooks.filter { hook in
            guard hook.enabled, hook.event == event else { return false }
            // Outer matcher check: pipe-separated list, regex, or "*" wildcard
            if let matcher = hook.matcher {
                guard matchesPattern(input, matcher: matcher) else { return false }
            }
            // Inner conditionFilter check: permission-rule syntax
            if let filter = hook.conditionFilter {
                guard matchesConditionFilter(input, filter: filter) else { return false }
            }
            return true
        }

        // Remove once hooks before execution (they self-deregister after one run).
        // Matches CC's once-hook lifecycle: hook runs, then removeHook(id) fires.
        let onceIDs = matching.filter { $0.once }.map { $0.id }
        for id in onceIDs {
            hooks.removeAll { $0.id == id }
        }

        // Separate hooks by execution mode.
        // Matches CC: async hooks run in background without blocking,
        // asyncRewake hooks also run in background but wake the model on exit code 2.
        let syncHooks = matching.filter { !$0.async && !$0.asyncRewake }
        let asyncHooks = matching.filter { $0.async || $0.asyncRewake }

        // Fire-and-forget async hooks in background (matches CC's async hook execution).
        // asyncRewake hooks should wake the model on exit code 2 — for now, they
        // run the same way. Full rewake integration requires conversation loop changes.
        for hook in asyncHooks {
            Task.detached { [self] in
                _ = await self.executeHook(hook, input: input)
            }
        }

        // Parallel execution matching CC's Promise.all(hookPromises) for sync hooks.
        // Each sync hook runs independently; results are aggregated after all complete.
        let results = await withTaskGroup(of: (HookEntry, HookResult).self) { group in
            for hook in syncHooks {
                group.addTask {
                    let result = await self.executeHook(hook, input: input)
                    return (hook, result)
                }
            }
            var collected: [(HookEntry, HookResult)] = []
            for await pair in group {
                collected.append(pair)
            }
            return collected
        }

        // Aggregate results: blockingError > stop > nonBlockingError > modify > continue.
        // Matches CC's aggregateHookResult: blocking errors prevent continuation,
        // non-blocking errors are logged, stop prevents with a reason.
        var didBlock = false
        var blockingReason: String?
        var didStop = false
        var stopReason: String?
        var nonBlockingMessages: [String] = []
        var modifiedInput: String?

        for (_, result) in results {
            switch result {
            case .blockingError(let reason):
                didBlock = true
                blockingReason = reason
            case .stop(let reason):
                didStop = true
                stopReason = reason
            case .nonBlockingError(let message):
                nonBlockingMessages.append(message)
            case .modify(let modified):
                modifiedInput = modified
            case .continue:
                break
            }
        }

        if didBlock, let reason = blockingReason {
            return .blockingError(reason: reason)
        }
        if didStop, let reason = stopReason {
            return .stop(reason: reason)
        }
        if let modified = modifiedInput {
            return .modify(input: modified)
        }
        if !nonBlockingMessages.isEmpty {
            return .nonBlockingError(message: nonBlockingMessages.joined(separator: "; "))
        }
        return .continue
    }

    // MARK: - Matcher Helpers

    /// Evaluate a hook matcher against an input string.
    /// Matches CC's matchesPattern(): supports "*" wildcard, pipe-separated
    /// exact matches (e.g. "Write|Edit"), and regex patterns.
    private func matchesPattern(_ input: String, matcher: String) -> Bool {
        // "*" matches everything
        if matcher == "*" { return true }
        // Pipe-separated list: each segment is an exact name match
        if matcher.contains("|") {
            let parts = matcher.components(separatedBy: "|")
            return parts.contains { input == $0.trimmingCharacters(in: .whitespaces) }
        }
        // Regex pattern match
        return input.range(of: matcher, options: .regularExpression) != nil
    }

    /// Evaluate a conditionFilter against input.
    /// CC uses permission-rule syntax (e.g. "Bash(git *)").
    /// For now, treat as a substring match against the tool name.
    private func matchesConditionFilter(_ input: String, filter: String) -> Bool {
        // Extract the tool name part before parentheses, if present
        let toolName = filter.components(separatedBy: "(").first ?? filter
        return input.contains(toolName.trimmingCharacters(in: .whitespaces))
    }

    /// List all registered hooks.
    public func listAll() -> [HookEntry] {
        hooks
    }

    /// List hooks for a specific event.
    public func list(for event: HookEvent) -> [HookEntry] {
        hooks.filter { $0.event == event }
    }

    /// Default hook execution timeout (matches CC's TOOL_HOOK_EXECUTION_TIMEOUT_MS: 10 minutes).
    private static let defaultHookTimeoutMs: Int = 600_000

    private func executeHook(_ hook: HookEntry, input: String) async -> HookResult {
        switch hook.type {
        case .command:
            return await executeCommandHook(hook, input: input)
        case .http:
            return await executeHTTPHook(hook, input: input)
        case .prompt:
            // Prompt hooks: substitute $ARGUMENTS placeholder in prompt text,
            // then return the result as modified input.
            // Matches CC's addArgumentsToPrompt / substituteArguments pattern.
            if let prompt = hook.prompt {
                let substituted = substituteArguments(in: prompt, args: input)
                return .modify(input: substituted)
            }
            return .modify(input: input)
        case .agent:
            // Agent hooks delegate to a subagent — for now, log and continue.
            // Full implementation requires SubAgentManager integration.
            return .continue
        case .callback:
            // Callback hooks invoke an in-process callback function.
            return .continue
        case .function:
            // Function hooks invoke an inline function handler.
            return .continue
        }
    }

    // MARK: - Command Hook Execution

    /// Executes a command hook, writing JSON input to stdin (matching CC's protocol).
    /// CC exit-code protocol: 0 = success, 2 = blocking (stderr shown to model), other = non-blocking error.
    private func executeCommandHook(_ hook: HookEntry, input: String) async -> HookResult {
        guard let command = hook.command else {
            return .continue
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.environment = [
            "CLAUDE_HOOK_EVENT": hook.event.rawValue,
            "CLAUDE_HOOK_INPUT": input
        ]

        let stdinPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        let timeoutMs = hook.timeout.map { $0 * 1000 } ?? Self.defaultHookTimeoutMs

        do {
            try process.run()

            // Write JSON input to stdin (matching CC's child.stdin.write(jsonInput + '\n', 'utf8')).
            // CC uses snake_case keys: session_id, transcript_path, cwd, permission_mode, etc.
            let jsonInput: [String: Any] = [
                "hook_event_name": hook.event.rawValue,
                "hook_name": command,
                "input": input,
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: jsonInput),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                try stdinPipe.fileHandleForWriting.write(contentsOf: (jsonString + "\n").data(using: .utf8)!)
            }
            try stdinPipe.fileHandleForWriting.close()

            let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
            while process.isRunning {
                if Date() >= deadline {
                    process.terminate()
                    return .continue
                }
                try await Task.sleep(nanoseconds: 50_000_000)
            }

            let data = try outputPipe.fileHandleForReading.readToEnd() ?? Data()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // Try parsing JSON output from hook stdout (matching CC's parseHookJSONOutput).
            // CC hooks emit JSON on stdout with structured fields: decision, reason, systemMessage, etc.
            if let jsonData = output.data(using: .utf8),
               let parsed = try? JSONDecoder().decode(HookJSONOutputDecodable.self, from: jsonData) {
                return parsed.toHookResult(fallbackOutput: output, exitCode: process.terminationStatus)
            }

            // Fallback: exit-code-based protocol (no JSON parsing)
            switch process.terminationStatus {
            case 0:
                return .continue
            case 2:
                return .blockingError(reason: output.isEmpty ? "Hook blocked continuation" : output)
            default:
                return .nonBlockingError(message: output.isEmpty ? "Hook exited with code \(process.terminationStatus)" : output)
            }
        } catch {
            return .continue
        }
    }

    // MARK: - HTTP Hook Execution

    private func executeHTTPHook(_ hook: HookEntry, input: String) async -> HookResult {
        guard let urlString = hook.url, let url = URL(string: urlString) else {
            return .continue
        }

        let timeoutMs = hook.timeout.map { $0 * 1000 } ?? Self.defaultHookTimeoutMs

        guard let body = try? JSONSerialization.data(withJSONObject: [
            "event": hook.event.rawValue,
            "input": input,
            "hookId": hook.id,
        ]) else {
            return .continue
        }

        var request = URLRequest(url: url, timeoutInterval: Double(timeoutMs) / 1000.0)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("SwiftAgent/0.1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .continue
            }

            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            switch httpResponse.statusCode {
            case 200..<300:
                return .continue
            case 400:
                return .stop(reason: output)
            case 410:
                return .modify(input: output)
            default:
                return .continue
            }
        } catch {
            return .continue
        }
    }

    // MARK: - Argument Substitution

    /// Substitute `$ARGUMENTS` placeholders in prompt/command text.
    /// Matches CC's substituteArguments in utils/argumentSubstitution.ts.
    /// Supports:
    /// - `$ARGUMENTS` — replaced with the full arguments string
    /// - `$ARGUMENTS[0]`, `$ARGUMENTS[1]`, etc. — replaced with indexed args by whitespace split
    /// - `$0`, `$1`, etc. — shorthand for `$ARGUMENTS[0]`, `$ARGUMENTS[1]`
    /// If no placeholders found and args is non-empty, appends `ARGUMENTS: {args}`.
    private func substituteArguments(in content: String, args: String) -> String {
        guard !args.isEmpty else { return content }

        let parsedArgs = parseArguments(args)
        var result = content

        // Replace $ARGUMENTS[N] with indexed argument using NSRegularExpression
        if let regex = try? NSRegularExpression(pattern: "\\$ARGUMENTS\\[(\\d+)\\]") {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard match.numberOfRanges > 1,
                      let indexRange = Range(match.range(at: 1), in: result) else { continue }
                let indexStr = String(result[indexRange])
                if let index = Int(indexStr), index < parsedArgs.count {
                    if let fullRange = Range(match.range, in: result) {
                        result.replaceSubrange(fullRange, with: parsedArgs[index])
                    }
                } else {
                    if let fullRange = Range(match.range, in: result) {
                        result.replaceSubrange(fullRange, with: "")
                    }
                }
            }
        }

        // Replace $N shorthand (only standalone, not inside words)
        if let regex = try? NSRegularExpression(pattern: "\\$(\\d+)(?!\\w)") {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard match.numberOfRanges > 1,
                      let indexRange = Range(match.range(at: 1), in: result) else { continue }
                let indexStr = String(result[indexRange])
                if let index = Int(indexStr), index < parsedArgs.count {
                    if let fullRange = Range(match.range, in: result) {
                        result.replaceSubrange(fullRange, with: parsedArgs[index])
                    }
                } else {
                    if let fullRange = Range(match.range, in: result) {
                        result.replaceSubrange(fullRange, with: "")
                    }
                }
            }
        }

        // Replace $ARGUMENTS with full args string
        result = result.replacingOccurrences(of: "$ARGUMENTS", with: args)

        // If no placeholders were found and args is non-empty, append
        if result == content {
            result = result + "\n\nARGUMENTS: \(args)"
        }

        return result
    }

    /// Parse an arguments string into an array of whitespace-split tokens.
    /// Matches CC's parseArguments: splits on whitespace, preserving quoted strings.
    private func parseArguments(_ args: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuote: Character? = nil

        for ch in args {
            if let quote = inQuote {
                if ch == quote {
                    inQuote = nil
                } else {
                    current.append(ch)
                }
            } else if ch == "\"" || ch == "'" {
                inQuote = ch
            } else if ch.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}
