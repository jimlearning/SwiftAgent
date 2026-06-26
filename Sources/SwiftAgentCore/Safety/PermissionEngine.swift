import Foundation

/// Permission decision pipeline matching Claude Code's architecture.
/// Inner pipeline (steps 1-7) mirrors `hasPermissionsToUseToolInner`.
/// Outer pipeline adds mode transformations (dontAsk, auto, headless).
public struct PermissionEngine: Sendable {
    public let store: PermissionStore
    public let safetyChecker: SafetyChecker
    public let classifier: any PermissionClassifying
    public let autoModeConfig: AutoModeConfig?

    public init(
        store: PermissionStore = PermissionStore(),
        safetyChecker: SafetyChecker = SafetyChecker(),
        classifier: any PermissionClassifying = PermissionClassifier(),
        autoModeConfig: AutoModeConfig? = nil
    ) {
        self.store = store
        self.safetyChecker = safetyChecker
        self.classifier = classifier
        self.autoModeConfig = autoModeConfig
    }

    /// Run the full permission decision pipeline.
    /// ToolMetadata provides isReadOnly, isDestructive, requiresApproval for decisions.
    public func check(
        toolName: String,
        input: [String: JSONValue],
        mode: PermissionMode,
        context: ToolUseContext,
        metadata: ToolMetadata? = nil
    ) async -> PermissionVerdict {
        var result = await innerCheck(toolName: toolName, input: input, mode: mode, context: context, metadata: metadata)
        result = applyModeTransformations(result, mode: mode, toolName: toolName, context: context)
        return result
    }

    // MARK: - Inner Pipeline (steps 1-10)

    private func innerCheck(
        toolName: String,
        input: [String: JSONValue],
        mode: PermissionMode,
        context: ToolUseContext,
        metadata: ToolMetadata?
    ) async -> PermissionVerdict {

        // Step 1a: Check tool-wide deny rules — deny wins immediately
        for rule in store.denyRules(for: toolName) {
            return PermissionVerdict(decision: .deny, reason: "denied by rule", matchedRule: rule)
        }

        // Step 1b: Check tool-wide ask rules
        // If sandboxed and tool is safe, auto-allow despite ask rules (sandbox-auto-allow bypass)
        let hasAskRule = store.hasAskRule(for: toolName)
        let isSandboxed = context.sandbox == true
        if hasAskRule && isSandboxed && safetyChecker.isReadOnlyTool(toolName) {
            return PermissionVerdict(decision: .allow, reason: "safe tool in sandbox — ask rule bypassed")
        }

        // Step 1c-e: Tool permission checks now use ToolMetadata instead of Tool protocol methods.
        // ToolMetadata.requiresApproval replaces old Tool.requiresUserInteraction().
        if let metadata = metadata, metadata.requiresApproval {
            return PermissionVerdict(decision: .ask, reason: "tool requires approval")
        }

        // Step 1f: Content-specific rules (e.g., Bash(git:*) patterns)
        if let contentRule = matchContentRule(toolName: toolName, input: input) {
            switch contentRule {
            case .deny:
                return PermissionVerdict(decision: .deny, reason: "content-specific deny rule")
            case .allow:
                return PermissionVerdict(decision: .allow, reason: "content-specific allow rule")
            case .ask:
                break // Continue to remaining checks
            }
        }

        // Step 1g: Safety checks (bypass-immune — run even in bypassPermissions mode)
        // Includes path-based safety for write/edit tools
        if let safetyReason = safetyChecker.check(toolName: toolName, input: input) {
            return PermissionVerdict(decision: .deny, reason: safetyReason)
        }
        if ["Write", "Edit"].contains(toolName),
           case .string(let path) = input["file_path"] ?? input["path"],
           let pathReason = safetyChecker.checkFilePath(path, inWorkingDirectory: context.workingDirectory) {
            return PermissionVerdict(decision: .deny, reason: pathReason)
        }

        // Step 2a: Check if mode bypasses permissions.
        if mode == .bypassPermissions {
            return PermissionVerdict(decision: .allow, reason: "bypassPermissions mode")
        }

        // Step 2b: Check allow rules (tool-wide)
        for rule in store.allowRules(for: toolName) {
            return PermissionVerdict(decision: .allow, reason: "allowed by rule", matchedRule: rule)
        }

        // Step 3: Convert passthrough to ask (CC defaults: unhandled → ask)
        return await applyModeDefault(toolName: toolName, input: input, mode: mode, hasAskRule: hasAskRule, context: context)
    }

    // MARK: - Content-Specific Rules

    /// Match tool name + input against content-specific permission patterns.
    /// E.g., toolName=Bash with input containing "rm -rf" matches a Bash(rm *) deny rule.
    private func matchContentRule(toolName: String, input: [String: JSONValue]) -> PermissionBehavior? {
        // Extract the primary content string from input for pattern matching
        let content: String?
        if toolName == "Bash", case .string(let cmd) = input["command"] {
            content = cmd
        } else if toolName == "Read" || toolName == "Write" || toolName == "Edit",
                  case .string(let path) = input["file_path"] ?? input["path"] {
            content = path
        } else {
            content = nil
        }

        guard let content = content else { return nil }

        // Check content-specific rules (e.g., "Bash(git *)" → matches Bash with "git" commands)
        for rule in store.rules(for: toolName) {
            if rule.ruleValue.matchesContent(content) {
                return rule.ruleBehavior
            }
        }

        return nil
    }

    // MARK: - Mode Defaults

    private func applyModeDefault(
        toolName: String,
        input: [String: JSONValue],
        mode: PermissionMode,
        hasAskRule: Bool,
        context: ToolUseContext
    ) async -> PermissionVerdict {
        switch mode {
        case .plan:
            if safetyChecker.isReadOnlyTool(toolName) {
                return PermissionVerdict(decision: .allow, reason: "read-only tool in plan mode")
            }
            return PermissionVerdict(decision: .ask, reason: "plan mode: confirm before executing")

        case .acceptEdits:
            if ["Read", "Edit", "Write", "Glob", "Grep"].contains(toolName) {
                return PermissionVerdict(decision: .allow, reason: "acceptEdits mode")
            }
            return PermissionVerdict(decision: .ask, reason: "acceptEdits: shell tool needs confirmation")

        case .dontAsk:
            if hasAskRule {
                return PermissionVerdict(decision: .deny, reason: "Operation blocked in dontAsk mode")
            }
            if safetyChecker.isReadOnlyTool(toolName) {
                return PermissionVerdict(decision: .allow, reason: "safe tool in dontAsk mode")
            }
            return PermissionVerdict(decision: .deny, reason: "Operation requires confirmation — blocked in dontAsk mode")

        case .auto:
            // Build classifier input from toolName + input
            let classifierInput: String
            if toolName == "Bash", case .string(let cmd) = input["command"] {
                classifierInput = cmd
            } else if toolName == "Write" || toolName == "Edit" {
                classifierInput = (input["file_path"].flatMap { if case .string(let p) = $0 { return p } else { return nil } }) ?? ""
            } else {
                classifierInput = ""
            }

            let result = await classifier.classify(
                toolName: toolName,
                input: classifierInput,
                config: autoModeConfig
            )

            switch result {
            case .allow(let reason):
                return PermissionVerdict(decision: .allow, reason: "auto mode classifier: \(reason)")
            case .deny(let reason):
                return PermissionVerdict(decision: .deny, reason: "auto mode classifier: \(reason)")
            case .ask(let reason):
                return PermissionVerdict(decision: .ask, reason: "auto mode classifier: \(reason)")
            case .classify(let reason):
                if safetyChecker.isReadOnlyTool(toolName) {
                    return PermissionVerdict(decision: .allow, reason: "auto mode heuristic: \(reason)")
                }
                if toolName == "Bash",
                   case .string(let cmd) = input["command"],
                   safetyChecker.isReadOnlyCommand(cmd) {
                    return PermissionVerdict(decision: .allow, reason: "auto mode heuristic (read-only bash): \(reason)")
                }
                return PermissionVerdict(decision: .ask, reason: "auto mode: \(reason)")
            }

        case .default:
            if safetyChecker.isReadOnlyTool(toolName) {
                return PermissionVerdict(decision: .allow, reason: "safe tool default")
            }
            if hasAskRule {
                return PermissionVerdict(decision: .ask, reason: "configured ask rule")
            }
            return PermissionVerdict(decision: .ask, reason: "default: confirm before executing")

        case .bypassPermissions:
            return PermissionVerdict(decision: .allow, reason: "bypass mode")

        case .bubble:
            if safetyChecker.isReadOnlyTool(toolName) {
                return PermissionVerdict(decision: .allow, reason: "safe tool in bubble mode")
            }
            return PermissionVerdict(decision: .deny, reason: "bubble mode: permission must bubble to parent")
        }
    }

    // MARK: - Mode Transformations

    private func applyModeTransformations(
        _ result: PermissionVerdict,
        mode: PermissionMode,
        toolName: String,
        context: ToolUseContext
    ) -> PermissionVerdict {
        // Headless/async agent: deny ask prompts
        if result.decision == .ask && context.mode == .dontAsk {
            let headlessResult = runPermissionHooks(toolName: toolName, input: [:], context: context)
            if let hookResult = headlessResult {
                return hookResult
            }
            return PermissionVerdict(decision: .deny,
                reason: "Permission prompt suppressed — headless agent mode")
        }

        return result
    }

    /// Run configured permission hooks, returning nil if no hook intervened.
    private func runPermissionHooks(
        toolName: String,
        input: [String: JSONValue],
        context: ToolUseContext
    ) -> PermissionVerdict? {
        // Hooks are environment-specific; in headless mode, deny by default
        return nil
    }
}

// MARK: - Read-only tool classification

extension SafetyChecker {
    /// Check if a file path is safe for write operations.
    func checkFilePath(_ path: String, inWorkingDirectory cwd: String) -> String? {
        return validatePath(path, workingDirectory: cwd)
    }

    /// Check if a tool is read-only (safe for auto-approval).
    func isReadOnlyTool(_ name: String) -> Bool {
        return ["Read", "Glob", "Grep"].contains(name)
    }
}
