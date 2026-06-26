import Foundation

/// Bundled skill definitions that are available to the LLM via the Skill tool.
/// These match Claude Code's bundled skill set where possible.
public enum BundledSkills {

    // MARK: - Skill Definitions

    /// /commit — create a git commit with proper message formatting.
    public static let commit = BundledSkill(
        name: "commit",
        description: "Create a git commit with proper message formatting and verification",
        aliases: ["commit-push-pr", "commit-push"],
        progressMessage: "Creating commit...",
        argNames: ["message"],
        whenToUse: "When you need to commit changes to git",
        userInvocable: true,
        getPromptForCommand: { args, ctx in
            let message = args.isEmpty ? "" : args
            return [.text("""
                Create a git commit with the following guidelines:

                1. Stage relevant changes (prefer specific files over git add -A)
                2. Draft a concise commit message (1-2 sentences focusing on "why")
                3. Commit with: git commit -m "..."
                4. Verify the commit succeeded

                \(message.isEmpty ? "" : "Commit message hint: \(message)")
                """)]
        }
    )

    /// /review — review code changes.
    public static let review = BundledSkill(
        name: "review",
        description: "Review code changes with structured feedback",
        progressMessage: "Reviewing changes...",
        argNames: ["branch-or-pr"],
        whenToUse: "When asked to review code or a pull request",
        userInvocable: true,
        getPromptForCommand: { args, ctx in
            [.text("""
                Review the code changes systematically:

                1. Check git diff for the changes
                2. Analyze for: bugs, security issues, style problems, logic errors
                3. Provide structured feedback with severity ratings
                4. Suggest concrete improvements

                \(args.isEmpty ? "" : "Focus on: \(args)")
                """)]
        }
    )

    /// /brainstorm — brainstorm ideas or designs.
    public static let brainstorm = BundledSkill(
        name: "brainstorm",
        description: "Brainstorm ideas and design approaches before implementation",
        progressMessage: "Brainstorming...",
        argNames: ["topic"],
        whenToUse: "When you need to explore ideas or design approaches",
        userInvocable: true,
        getPromptForCommand: { args, ctx in
            [.text("""
                Brainstorming session:

                1. Understand the goal: \(args.isEmpty ? "(describe what you want to accomplish)" : args)
                2. Explore the codebase for relevant patterns
                3. Design 2-3 approaches with trade-offs
                4. Evaluate each approach
                5. Recommend the best path forward

                Present your analysis in a clear, structured format.
                """)]
        }
    )

    /// /plan — enter plan mode for structured implementation planning.
    public static let plan = BundledSkill(
        name: "plan",
        description: "Enter plan mode to design an implementation strategy before coding",
        progressMessage: "Entering plan mode...",
        argNames: ["topic"],
        whenToUse: "When you need to plan implementation before coding",
        userInvocable: true,
        getPromptForCommand: { args, ctx in
            [.text("""
                Enter plan mode to design an implementation strategy:

                1. Use EnterPlanMode tool to switch to read-only exploration
                2. Explore the codebase thoroughly
                3. Identify critical files and dependencies
                4. Design implementation steps
                5. Use ExitPlanMode to present your plan for approval

                \(args.isEmpty ? "" : "Plan topic: \(args)")
                """)]
        }
    )

    /// /goal — goal-oriented brainstorming (ralph-wiggum equivalent).
    public static let goal = BundledSkill(
        name: "goal",
        description: "Set a goal and work through structured brainstorming",
        aliases: ["ralph-wiggum"],
        progressMessage: "Goal mode activated...",
        argNames: ["goal-description"],
        whenToUse: "When you have a goal and want to work through it systematically",
        userInvocable: true,
        getPromptForCommand: { args, ctx in
            [.text("""
                Work through this goal systematically:

                GOAL: \(args.isEmpty ? "(describe what you want to accomplish)" : args)

                Step 1: CLARIFY — Understand exactly what's needed
                Step 2: EXPLORE — Find relevant code, patterns, and constraints
                Step 3: DESIGN — Brainstorm 2-3 approaches with trade-offs
                Step 4: EVALUATE — Pick the best approach with clear reasoning
                Step 5: PLAN — Create a concrete, step-by-step implementation plan

                Be thorough. Think through edge cases and failure modes.
                """)]
        }
    )

    // MARK: - Registry

    /// All bundled skills in registration order.
    public static var all: [BundledSkill] {
        [commit, review, brainstorm, plan, goal]
    }
}

/// A bundled skill definition — the data needed to create a PromptCommand.
public struct BundledSkill: Sendable {
    public let name: String
    public let description: String
    public let aliases: [String]?
    public let progressMessage: String
    public let argNames: [String]?
    public let allowedTools: [String]?
    public let model: String?
    public let whenToUse: String?
    public let argumentHint: String?
    public let userInvocable: Bool
    public let disableModelInvocation: Bool
    public let context: CommandExecutionContext?
    public let agent: String?
    public let effort: EffortValue?
    public let paths: [String]?
    public let getPromptForCommand: @Sendable (String, ToolUseContext) async -> [ContentBlock]

    public var contentLength: Int { 500 } // approximate

    public init(
        name: String,
        description: String,
        aliases: [String]? = nil,
        progressMessage: String,
        argNames: [String]? = nil,
        allowedTools: [String]? = nil,
        model: String? = nil,
        whenToUse: String? = nil,
        argumentHint: String? = nil,
        userInvocable: Bool = true,
        disableModelInvocation: Bool = false,
        context: CommandExecutionContext? = nil,
        agent: String? = nil,
        effort: EffortValue? = nil,
        paths: [String]? = nil,
        getPromptForCommand: @escaping @Sendable (String, ToolUseContext) async -> [ContentBlock] = { _, _ in [] }
    ) {
        self.name = name
        self.description = description
        self.aliases = aliases
        self.progressMessage = progressMessage
        self.argNames = argNames
        self.allowedTools = allowedTools
        self.model = model
        self.whenToUse = whenToUse
        self.argumentHint = argumentHint
        self.userInvocable = userInvocable
        self.disableModelInvocation = disableModelInvocation
        self.context = context
        self.agent = agent
        self.effort = effort
        self.paths = paths
        self.getPromptForCommand = getPromptForCommand
    }
}
