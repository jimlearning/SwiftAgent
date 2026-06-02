import Foundation

/// Asks the user one or more multiple-choice questions.
/// Matches Claude Code's AskUserQuestionTool.
public struct AskUserQuestionTool: Tool {
    public let name = "AskUserQuestion"
    public var searchHint: String? { "prompt the user with a multiple-choice question" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Ask the user a multiple-choice question" }

    /// Matches CC's ASK_USER_QUESTION_TOOL_PROMPT. The critical line is
    /// "Users will always be able to select 'Other' to provide custom text input"
    /// — this tells the LLM that free-text answers outside the listed options are
    /// expected and normal, not an anomaly to question or overthink.
    public func prompt(
        getToolPermissionContext: @Sendable () async -> ToolPermissionContext,
        tools: [any Tool],
        agents: [any Sendable],
        allowedAgentTypes: [String]?
    ) async -> String {
        """
        Use this tool when you need to ask the user questions during execution. This allows you to:
        1. Gather user preferences or requirements
        2. Clarify ambiguous instructions
        3. Get decisions on implementation choices as you work
        4. Offer choices to the user about what direction to take.

        Usage notes:
        - Users will always be able to select "Other" to provide custom text input
        - Use multiSelect: true to allow multiple answers to be selected for a question
        - If you recommend a specific option, make that the first option in the list and add "(Recommended)" at the end of the label

        Plan mode note: In plan mode, use this tool to clarify requirements or choose between approaches BEFORE finalizing your plan. Do NOT use this tool to ask "Is my plan ready?" or "Should I proceed?" - use ExitPlanMode for plan approval. IMPORTANT: Do not reference "the plan" in your questions (e.g., "Do you have feedback about the plan?", "Does the plan look good?") because the user cannot see the plan in the UI until you call ExitPlanMode. If you need plan approval, use ExitPlanMode instead.
        """
    }

    public let isReadOnly = true
    public let isConcurrencySafe = false // Must run alone — cannot parallelize user interaction
    public func isEnabled() -> Bool { !FeatureFlags.isChannelsActive() }
    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])

        var optionSchema = JSONSchema(type: "object", properties: [:])
        optionSchema.properties?["label"] = JSONSchemaProperty(type: "string", description: "Display label for this option")
        optionSchema.properties?["description"] = JSONSchemaProperty(type: "string", description: "Description of what this option means")

        var questionSchema = JSONSchema(type: "object", properties: [:])
        questionSchema.properties?["question"] = JSONSchemaProperty(type: "string", description: "The question to ask the user")
        questionSchema.properties?["header"] = JSONSchemaProperty(type: "string", description: "A label for the option group")
        questionSchema.properties?["multiSelect"] = JSONSchemaProperty(type: "boolean", description: "Allow selecting multiple options")

        schema.properties?["questions"] = JSONSchemaProperty(type: "array", description: "Questions to ask (max 4). Users can always type free-text answers outside the listed options — the text is treated as a valid custom answer.")
        schema.required = ["questions"]
        return schema
    }()

    public init() {}

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        guard let questionsVal = input["questions"],
              case .array(let questions) = questionsVal else {
            return ToolResult(content: "Error: questions array is required", isError: true)
        }

        // Parse questions into structured format
        var parsedQuestions: [UserQuestion] = []
        for qval in questions {
            guard case .object(let q) = qval,
                  let questionVal = q["question"],
                  case .string(let questionText) = questionVal else { continue }

            let header: String
            if let h = q["header"], case .string(let s) = h { header = s }
            else { header = "" }

            let multi: Bool
            if let m = q["multiSelect"], case .bool(let b) = m { multi = b }
            else { multi = false }

            var options: [UserQuestionOption] = []
            if let optsVal = q["options"], case .array(let opts) = optsVal {
                for optVal in opts {
                    guard case .object(let opt) = optVal,
                          let labelVal = opt["label"],
                          case .string(let label) = labelVal else { continue }
                    let desc: String?
                    if let d = opt["description"], case .string(let s) = d { desc = s }
                    else { desc = nil }
                    options.append(UserQuestionOption(label: label, description: desc))
                }
            }

            parsedQuestions.append(UserQuestion(
                header: header,
                question: questionText,
                options: options,
                multiSelect: multi
            ))
        }

        if parsedQuestions.isEmpty {
            return ToolResult(content: "Error: no valid questions provided", isError: true)
        }

        // If an interactive handler is available, use it to ask the user
        if let handler = context.userInputPromptHandler {
            let responses = await handler(parsedQuestions)

            // Build result string in CC-compatible format.
            // Concise, declarative — tells the LLM the interaction is done
            // and to continue with the user's answers in mind.
            let answersText = zip(parsedQuestions, responses).compactMap { q, response -> String? in
                let answer: String
                if let customText = response.customText, !customText.isEmpty {
                    answer = customText
                } else if !response.optionIndices.isEmpty {
                    answer = response.optionIndices.compactMap { idx in
                        q.options.indices.contains(idx) ? q.options[idx].label : nil
                    }.joined(separator: ", ")
                } else {
                    return nil // skipped (no answer)
                }
                return "\"\(q.question)\"=\"\(answer)\""
            }.joined(separator: ", ")

            let output: String
            if answersText.isEmpty {
                output = "User did not select an option."
            } else {
                output = "User has answered your questions: \(answersText). You can now continue with the user's answers in mind."
            }
            return ToolResult(content: output)
        }

        // Fallback: no interactive handler — format as text to the LLM
        // (useful in non-interactive contexts like sub-agents or tests)
        var output = ""
        for (_, q) in parsedQuestions.enumerated() {
            if !output.isEmpty { output += "\n" }
            if !q.header.isEmpty { output += "\(q.header): " }
            output += "\(q.question)\n"

            for (j, opt) in q.options.enumerated() {
                let letter = String(UnicodeScalar(97 + j)!)
                output += "  \(letter)) \(opt.label)"
                if let desc = opt.description {
                    output += " - \(desc)"
                }
                output += "\n"
            }

            if q.multiSelect {
                output += "  [Multi-select - can pick one or more options]\n"
            }
        }

        output += "\nPlease respond with your answer(s)."
        return ToolResult(content: output)
    }
}
