import Foundation
import KeychainAccess

/// Secure storage for the DeepSeek API key using macOS Keychain.
/// API key is NEVER logged or displayed in plaintext anywhere (per spec §A).
public enum KeychainStore {
    private static let service = "com.swiftagent.api"
    private static let key = "deepseek-api-key"

    /// Store the API key in Keychain.
    public static func save(apiKey: String) throws {
        let keychain = Keychain(service: service)
        try keychain.set(apiKey, key: key)
    }

    /// Retrieve the API key from Keychain. Returns nil if not set.
    public static func load() -> String? {
        let keychain = Keychain(service: service)
        return try? keychain.get(key)
    }

    /// Remove the API key from Keychain.
    public static func delete() throws {
        let keychain = Keychain(service: service)
        try keychain.remove(key)
    }

    /// Check whether an API key exists in Keychain.
    public static var hasKey: Bool {
        load() != nil
    }
}

/// Resolves the DeepSeek API key from multiple sources.
/// Priority: DEEPSEEK_API_KEY env → Keychain → nil
public enum DeepSeekAPIKeyResolver {
    /// Resolve the API key: env var first, then Keychain.
    public static func resolve() -> String? {
        // 1. Environment variable (for CI / dev convenience)
        if let envKey = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"],
           !envKey.isEmpty {
            return envKey
        }

        // 2. macOS Keychain
        if let keychainKey = KeychainStore.load(), !keychainKey.isEmpty {
            return keychainKey
        }

        return nil
    }
}
