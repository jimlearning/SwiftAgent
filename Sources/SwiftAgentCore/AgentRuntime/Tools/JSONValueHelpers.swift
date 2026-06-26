import Foundation

/// Helpers for extracting typed values from [String: JSONValue] dictionaries.
/// Used by old-style tools that still use dictionary-based input.
extension Dictionary where Key == String, Value == JSONValue {
    func stringValue(_ key: String) -> String? {
        guard case .string(let s) = self[key] else { return nil }
        return s
    }

    func intValue(_ key: String) -> Int? {
        guard case .number(let n) = self[key] else { return nil }
        return Int(n)
    }

    func boolValue(_ key: String) -> Bool? {
        guard case .bool(let b) = self[key] else { return nil }
        return b
    }
}
