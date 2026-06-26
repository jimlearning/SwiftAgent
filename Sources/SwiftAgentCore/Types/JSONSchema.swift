import Foundation

// MARK: - JSONSchema

public struct JSONSchema: Codable, Sendable {
    public var type: String
    public var properties: [String: JSONSchemaProperty]?
    public var required: [String]?
    public var additionalProperties: Bool?
    public var description: String?

    public init(
        type: String,
        properties: [String: JSONSchemaProperty]? = nil,
        required: [String]? = nil,
        additionalProperties: Bool? = nil,
        description: String? = nil
    ) {
        self.type = type
        self.properties = properties
        self.required = required
        self.additionalProperties = additionalProperties
        self.description = description
    }

    /// Validate input against this schema. Returns nil on success, error string on failure.
    /// Matches CC's tool.inputSchema.parse(input) validation step.
    public func validate(_ input: [String: JSONValue]) -> String? {
        // Check required fields
        if let required = required {
            for key in required {
                if input[key] == nil {
                    return "Missing required field: '\(key)'"
                }
            }
        }

        // Check property types
        if let properties = properties {
            for (key, prop) in properties {
                guard let value = input[key] else { continue }
                if let error = validateType(value, expectedType: prop.type, key: key) {
                    return error
                }
                if let enumValues = prop.enum {
                    if case .string(let s) = value, !enumValues.contains(s) {
                        return "Invalid value for '\(key)': '\(s)' not in [\(enumValues.joined(separator: ", "))]"
                    }
                }
            }
        }

        return nil
    }

    private func validateType(_ value: JSONValue, expectedType: String, key: String) -> String? {
        switch expectedType {
        case "string":
            if case .string = value { return nil }
        case "number":
            if case .number = value { return nil }
        case "boolean":
            if case .bool = value { return nil }
        case "array":
            if case .array = value { return nil }
        case "object":
            // object can be .object or .null (nullable objects)
            if case .object = value { return nil }
            if case .null = value { return nil }
        default:
            return nil // Unknown types pass through
        }
        return "Invalid type for '\(key)': expected \(expectedType)"
    }
}

/// Non-recursive JSON schema array items descriptor.
/// Matches CC's JSON Schema `items` field for array element typing.
public struct JSONSchemaItems: Codable, Sendable {
    public var type: String
    public var description: String?
    public var `enum`: [String]?
    public var pattern: String?
    public var minimum: Double?
    public var maximum: Double?
    public var minLength: Int?
    public var maxLength: Int?

    public init(
        type: String,
        description: String? = nil,
        enum: [String]? = nil,
        pattern: String? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        minLength: Int? = nil,
        maxLength: Int? = nil
    ) {
        self.type = type
        self.description = description
        self.enum = `enum`
        self.pattern = pattern
        self.minimum = minimum
        self.maximum = maximum
        self.minLength = minLength
        self.maxLength = maxLength
    }
}

public struct JSONSchemaProperty: Codable, Sendable {
    public var type: String
    public var description: String?
    public var `enum`: [String]?
    public var items: JSONSchemaItems?
    public var pattern: String?
    public var minimum: Double?
    public var maximum: Double?
    public var minLength: Int?
    public var maxLength: Int?

    public init(
        type: String,
        description: String? = nil,
        enum: [String]? = nil,
        items: JSONSchemaItems? = nil,
        pattern: String? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        minLength: Int? = nil,
        maxLength: Int? = nil
    ) {
        self.type = type
        self.description = description
        self.enum = `enum`
        self.items = items
        self.pattern = pattern
        self.minimum = minimum
        self.maximum = maximum
        self.minLength = minLength
        self.maxLength = maxLength
    }
}
