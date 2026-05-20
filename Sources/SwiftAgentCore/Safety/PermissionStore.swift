import Foundation

/// Stores and matches permission rules.
/// Supports tool-name, path-based, and wildcard rules.
public struct PermissionStore: Sendable {
    private var rules: [PermissionRule]

    public init(rules: [PermissionRule] = []) {
        self.rules = rules
    }

    /// Add a permission rule.
    public mutating func addRule(_ rule: PermissionRule) {
        rules.append(rule)
    }

    /// Add multiple rules.
    public mutating func addRules(_ newRules: [PermissionRule]) {
        rules.append(contentsOf: newRules)
    }

    /// Get matching rules for a tool (context-free overload).
    public func rules(for toolName: String) -> [PermissionRule] {
        rules.filter {
            $0.ruleValue.toolName == toolName || $0.ruleValue.toolName == "*" || $0.ruleValue.toolName.isEmpty
        }
    }

    /// Get matching rules for a tool, ordered by specificity.
    /// Exact matches first, then wildcard, then global.
    public func rules(for toolName: String, context: ToolUseContext) -> [PermissionRule] {
        var exact: [PermissionRule] = []
        var wildcard: [PermissionRule] = []
        var global: [PermissionRule] = []

        for rule in rules {
            let name = rule.ruleValue.toolName
            if name.isEmpty {
                global.append(rule)
            } else if name == toolName {
                exact.append(rule)
            } else if name == "*" {
                wildcard.append(rule)
            }
        }

        return exact + wildcard + global
    }

    /// Aggregate multiple permission decisions. Strictest wins.
    /// Priority: deny > ask > allow
    public static func aggregate(_ decisions: [PermissionDecision]) -> PermissionDecision {
        if decisions.contains(.deny) { return .deny }
        if decisions.contains(.ask) { return .ask }
        return .allow
    }

    /// Rules that deny a tool.
    public func denyRules(for toolName: String) -> [PermissionRule] {
        rules.filter {
            $0.ruleBehavior == .deny && ($0.ruleValue.toolName == toolName || $0.ruleValue.toolName == "*" || $0.ruleValue.toolName.isEmpty)
        }
    }

    /// Whether an ask rule exists for this tool.
    public func hasAskRule(for toolName: String) -> Bool {
        rules.contains {
            $0.ruleBehavior == .ask && ($0.ruleValue.toolName == toolName || $0.ruleValue.toolName == "*" || $0.ruleValue.toolName.isEmpty)
        }
    }

    /// Rules that allow a tool.
    public func allowRules(for toolName: String) -> [PermissionRule] {
        rules.filter {
            $0.ruleBehavior == .allow && ($0.ruleValue.toolName == toolName || $0.ruleValue.toolName == "*" || $0.ruleValue.toolName.isEmpty)
        }
    }

    /// Default safe rules for common tools.
    public static func defaultRules() -> [PermissionRule] {
        [
            PermissionRule(ruleBehavior: .allow, ruleValue: PermissionRuleValue(toolName: "Read")),
            PermissionRule(ruleBehavior: .allow, ruleValue: PermissionRuleValue(toolName: "Glob")),
            PermissionRule(ruleBehavior: .allow, ruleValue: PermissionRuleValue(toolName: "Grep")),
        ]
    }
}
