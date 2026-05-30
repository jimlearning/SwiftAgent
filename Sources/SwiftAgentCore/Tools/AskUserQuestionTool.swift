import Foundation

/// Asks the user one or more multiple-choice questions.
/// Matches Claude Code's AskUserQuestionTool.
public struct AskUserQuestionTool: Tool {
    public let name = "AskUserQuestion"
    public var searchHint: String? { "prompt the user with a multiple-choice question" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Ask the user a multiple-choice question" }
    public let isReadOnly = true
    public let isConcurrencySafe = false // Must run alone — cannot parallelize user interaction
    public var shouldDefer: Bool { true }
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

        schema.properties?["questions"] = JSONSchemaProperty(type: "array", description: "Questions to ask (max 4)")
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

            // Build result string from responses
            var output = ""
            for (i, response) in responses.enumerated() {
                let q = parsedQuestions[i]
                if !output.isEmpty { output += "\n" }

                if !q.header.isEmpty { output += "\(q.header): " }
                output += "\(q.question)\n"

                if let customText = response.customText, !customText.isEmpty {
                    output += "User answered: \(customText)"
                } else if !response.optionIndices.isEmpty {
                    let selectedLabels = response.optionIndices.compactMap { idx in
                        q.options.indices.contains(idx) ? q.options[idx].label : nil
                    }
                    output += "User answered: \(selectedLabels.joined(separator: ", "))"
                } else {
                    output += "User did not select an option."
                }
            }

            return ToolResult(content: output)
        }

        // Fallback: no interactive handler — format as text to the LLM
        // (useful in non-interactive contexts like sub-agents or tests)
        var output = ""
        for (i, q) in parsedQuestions.enumerated() {
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
