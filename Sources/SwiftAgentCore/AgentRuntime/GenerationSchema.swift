import Foundation

// MARK: - GenerationSchema Protocol

/// Protocol for types that support runtime JSON schema generation.
///
/// Types conforming to `GenerationSchema` automatically derive their
/// JSON Schema from their `Codable` stored properties via Mirror reflection.
/// The default implementation calls `generationSchemaFromMirror(Self.self)`.
///
/// ## Example
/// ```swift
/// struct BashParams: Codable, GenerationSchema {
///     var command: String
///     var timeout: Int?
/// }
/// // BashParams.jsonSchema → {
/// //   type: "object",
/// //   properties: { "command": { type: "string" }, "timeout": { type: "number" } },
/// //   required: ["command"]  // timeout is Optional, not required
/// // }
/// ```
public protocol GenerationSchema: Codable, Sendable {
    /// The JSON Schema describing this type's Codable properties.
    static var jsonSchema: JSONSchema { get }
}

public extension GenerationSchema {
    /// Default implementation: auto-derive JSON Schema from Mirror reflection.
    static var jsonSchema: JSONSchema {
        generationSchemaFromMirror(Self.self)
    }
}

// MARK: - Mirror-Based Schema Generation

/// Internal protocol for types that can be default-initialized.
/// Used by `generationSchemaFromMirror` to create sample instances for
/// Mirror reflection. Accessible via `@testable import` for test structs.
protocol DefaultInitializable {
    init()
}

/// Generate a `JSONSchema` from a Swift type's stored properties using Mirror.
///
/// Creates a sample instance via `DefaultInitializable`, reflects on its
/// children, and maps each stored property to a JSON Schema property.
/// Optional properties (wrapped in `Optional<T>`) are NOT added to the
/// `required` array; non-Optional properties ARE.
///
/// - Parameter metatype: The Swift metatype to derive a schema from.
/// - Returns: A `JSONSchema` with `type: "object"` and derived properties.
/// - Note: If the type does not conform to `DefaultInitializable`, returns
///   a best-effort schema with `type: "object"` and a description note.
public func generationSchemaFromMirror(_ metatype: Any.Type) -> JSONSchema {
    guard let sampleType = metatype as? DefaultInitializable.Type else {
        return JSONSchema(
            type: "object",
            description: "Schema unavailable — type does not support default initialization via DefaultInitializable"
        )
    }

    let sample = sampleType.init()
    let mirror = Mirror(reflecting: sample)

    var properties: [String: JSONSchemaProperty] = [:]
    var required: [String] = []

    for child in mirror.children {
        guard let label = child.label, !label.isEmpty else { continue }

        let swiftType = String(describing: type(of: child.value))
        let (jsonType, isOptional) = mapSwiftToJSONType(swiftType)

        properties[label] = JSONSchemaProperty(type: jsonType)

        if !isOptional {
            required.append(label)
        }
    }

    return JSONSchema(type: "object", properties: properties, required: required)
}

// MARK: - Swift-to-JSON Type Mapping

/// Map a Swift type name string to a JSON Schema type name.
///
/// Handles Optional unwrapping (`Optional<InnerType>` → inner type).
/// Unknown types default to `"string"`.
///
/// - Parameter swiftType: The result of `String(describing: type(of: value))`.
/// - Returns: A tuple of `(jsonType: String, isOptional: Bool)`.
public func mapSwiftToJSONType(_ swiftType: String) -> (String, Bool) {
    let isOptional = swiftType.hasPrefix("Optional<")
    let innerType: String
    if isOptional {
        // Extract inner type from "Optional<InnerType>"
        innerType = String(swiftType.dropFirst("Optional<".count).dropLast())
    } else {
        innerType = swiftType
    }

    let jsonType: String
    switch innerType {
    case "String":
        jsonType = "string"
    case "Int", "Int32", "Int64", "UInt", "UInt32", "UInt64":
        jsonType = "number"
    case "Double", "Float", "CGFloat":
        jsonType = "number"
    case "Bool":
        jsonType = "boolean"
    case let t where t.hasPrefix("Array<") || t.hasPrefix("[") || t.hasPrefix("Swift.Array<"):
        jsonType = "array"
    default:
        jsonType = "string"
    }

    return (jsonType, isOptional)
}
