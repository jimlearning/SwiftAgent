import Foundation

// MARK: - SortedJSON

/// Encodable wrapper that recursively sorts all dictionary keys.
/// Uses `JSONEncoder.sortedKeys` to produce deterministic JSON byte output
/// regardless of Swift's non-deterministic `[String: Any]` key ordering.
///
/// Shared by LLMClient (request serialization) and DebugLogger (log entry
/// serialization) so that debug logs faithfully reflect the wire format —
/// essential for debugging cache-key mismatches.
public struct SortedJSON: Encodable {
    let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public func encode(to encoder: Encoder) throws {
        if let dict = value as? [String: Any] {
            var container = encoder.container(keyedBy: _CodingKey.self)
            for (key, val) in dict.sorted(by: { $0.key < $1.key }) {
                try container.encode(SortedJSON(val), forKey: _CodingKey(stringValue: key))
            }
        } else if let arr = value as? [Any] {
            var container = encoder.unkeyedContainer()
            for item in arr { try container.encode(SortedJSON(item)) }
        } else {
            var container = encoder.singleValueContainer()
            switch value {
            case let str as String:  try container.encode(str)
            case let num as Int:     try container.encode(num)
            case let num as Int64:   try container.encode(num)
            case let num as UInt:    try container.encode(num)
            case let num as Double:  try container.encode(num)
            case let num as Float:   try container.encode(num)
            case let bool as Bool:   try container.encode(bool)
            case is NSNull:          try container.encodeNil()
            default:                 try container.encodeNil()
            }
        }
    }

    struct _CodingKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
