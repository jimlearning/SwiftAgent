import Foundation

/// Asks the user one or more multiple-choice questions.
/// Matches Claude Code's AskUserQuestionTool.
///
/// Usage notes:
/// - Users will always be able to select "Other" to provide custom text input
/// - Use multiSelect: true to allow multiple answers to be selected for a question
/// - If you recommend a specific option, make that the first option in the list
///   and add "(Recommended)" at the end of the label
public struct AskUserQuestionTool: Tool {
    public let name = "AskUserQuestion"
    public let description = "Ask the user a multiple-choice question"

    /// Handler for presenting questions to the user interactively.
    /// When nil, the tool formats questions as text for the LLM to present.
    private let userInputPromptHandler: UserInputPromptHandler?

    // MARK: - Arguments

    public struct Arguments: Codable, Sendable {
        public var questions: [Question]

        public init(questions: [Question] = []) {
            self.questions = questions
        }
    }

    public struct Question: Codable, Sendable {
        public var question: String
        public var header: String?
        public var multiSelect: Bool?
        public var options: [Option]?
    }

    public struct Option: Codable, Sendable {
        public var label: String
        public var description: String?
    }

    public typealias Output = ToolOutputValue

    public var inputSchema: JSONSchema {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["questions"] = JSONSchemaProperty(
            type: "array",
            description: "Questions to ask (max 4). Users can always type free-text answers outside the listed options — the text is treated as a valid custom answer."
        )
        schema.required = ["questions"]
        return schema
    }

    public init(userInputPromptHandler: UserInputPromptHandler? = nil) {
        self.userInputPromptHandler = userInputPromptHandler
    }

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        let questions = arguments.questions

        // Parse into structured format used by the handler
        let parsedQuestions: [UserQuestion] = questions.map { q in
            UserQuestion(
                header: q.header ?? "",
                question: q.question,
                options: (q.options ?? []).map { opt in
                    UserQuestionOption(label: opt.label, description: opt.description)
                },
                multiSelect: q.multiSelect ?? false
            )
        }

        // If an interactive handler is available, use it to ask the user
        if let handler = userInputPromptHandler {
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
            return .string(output)
        }

        // Fallback: no interactive handler — format as text for the LLM
        // (useful in non-interactive contexts like sub-agents or tests)
        var output = ""
        for q in parsedQuestions {
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
        return .string(output)
    }
}
