import Foundation

/// Asks the user one or more multiple-choice questions.
/// Matches Claude Code's AskUserQuestionTool.
public struct AskUserQuestionTool: Tool {
    public let name = "AskUserQuestion"
    public var searchHint: String? { "prompt the user with a multiple-choice question" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Ask the user a multiple-choice question" }
    public let isReadOnly = true
    public let isConcurrencySafe = true
    public var shouldDefer: Bool { true }
    public func isEnabled() -> Bool { !FeatureFlags.isChannelsActive() }
    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        var questionSchema = JSONSchema(type: "object", properties: [:])
        questionSchema.properties?["question"] = JSONSchemaProperty(type: "string", description: "The question to ask the user")
        questionSchema.properties?["header"] = JSONSchemaProperty(type: "string", description: "A label for the option group")
        var optionSchema = JSONSchema(type: "object", properties: [:])
        optionSchema.properties?["label"] = JSONSchemaProperty(type: "string", description: "Display label for this option")
        optionSchema.properties?["description"] = JSONSchemaProperty(type: "string", description: "Description of what this option means")
        questionSchema.properties?["options"] = JSONSchemaProperty(type: "array", description: "List of options", enum: nil)
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

        var output = ""
        for (i, qval) in questions.enumerated() {
            guard case .object(let q) = qval,
                  let questionVal = q["question"],
                  case .string(let question) = questionVal else { continue }

            let header: String
            if let h = q["header"], case .string(let s) = h { header = s }
            else { header = "Question \(i + 1)" }

            output += "\n\(header): \(question)\n"

            if let optsVal = q["options"], case .array(let opts) = optsVal {
                for (j, optVal) in opts.enumerated() {
                    guard case .object(let opt) = optVal,
                          let labelVal = opt["label"],
                          case .string(let label) = labelVal else { continue }
                    let letter = String(UnicodeScalar(97 + j)!)
                    output += "  \(letter)) \(label)"
                    if let descVal = opt["description"], case .string(let desc) = descVal {
                        output += " - \(desc)"
                    }
                    output += "\n"
                }
            }

            let multi: Bool
            if let m = q["multiSelect"], case .bool(let b) = m { multi = b }
            else { multi = false }

            if multi { output += "  [Multi-select - can pick one or more options]\n" }
        }

        output += "\nPlease respond with your answer(s)."
        return ToolResult(content: output)
    }
}
