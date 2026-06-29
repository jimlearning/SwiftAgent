import Foundation
import KeychainAccess

/// Secure storage for the DeepSeek API key using macOS Keychain.
/// API key is NEVER logged or displayed in plaintext anywhere (per spec §A).
///
/// In DEBUG builds, credentials are stored in `~/.swift-agent/credentials.json`
/// to avoid repeated macOS keychain permission prompts (which occur because
/// unsigned development builds can't establish a persistent code identity
/// across launches). Keychain is still used in RELEASE builds where code
/// signing ensures the app identity is stable.
public enum KeychainStore {
    private static let service = "com.swiftagent.api"
    private static let key = "deepseek-api-key"

#if DEBUG
    // MARK: - File-based (development builds)

    private static var credentialsURL: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swift-agent")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("credentials.json")
    }

    private struct CredentialsFile: Codable {
        var apiKey: String
    }

    /// Store the API key in `~/.swift-agent/credentials.json` with
    /// owner-read-only permissions (0600). No Keychain interaction
    /// means zero permission prompts during development.
    public static func save(apiKey: String) throws {
        let data = try JSONEncoder().encode(CredentialsFile(apiKey: apiKey))
        try data.write(to: credentialsURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: credentialsURL.path
        )
    }

    /// Read the API key from the credentials file, if it exists and
    /// is valid JSON. Returns nil otherwise.
    public static func load() -> String? {
        guard FileManager.default.fileExists(atPath: credentialsURL.path),
              let data = try? Data(contentsOf: credentialsURL),
              let creds = try? JSONDecoder().decode(CredentialsFile.self, from: data)
        else { return nil }
        return creds.apiKey.isEmpty ? nil : creds.apiKey
    }

    /// Remove the credentials file.
    public static func delete() throws {
        if FileManager.default.fileExists(atPath: credentialsURL.path) {
            try FileManager.default.removeItem(at: credentialsURL)
        }
    }

    /// Whether an API key exists in the credentials file.
    public static var hasKey: Bool {
        load() != nil
    }

#else
    // MARK: - Keychain (release builds)

    /// Store the API key in Keychain.
    public static func save(apiKey: String) throws {
        let keychain = Keychain(service: service)
            .accessibility(.afterFirstUnlock)
        try keychain.set(apiKey, key: key)
    }

    /// Retrieve the API key from Keychain. Returns nil if not set.
    /// After a successful read, re-saves with relaxed accessibility to fix
    /// ACL prompts on development builds (one last prompt, then permanent).
    public static func load() -> String? {
        let keychain = Keychain(service: service)
            .accessibility(.afterFirstUnlock)
        guard let value = try? keychain.get(key), !value.isEmpty else { return nil }

        // Re-save with afterFirstUnlock to migrate old items that were created
        // with restrictive ACL. After one approval, prompts stop permanently.
        let migrationFlag = "com.swiftagent.api.keychain-migrated"
        if !UserDefaults.standard.bool(forKey: migrationFlag) {
            try? Keychain(service: service)
                .accessibility(.afterFirstUnlock)
                .set(value, key: key)
            UserDefaults.standard.set(true, forKey: migrationFlag)
        }

        return value
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
#endif
}

/// Resolves the DeepSeek API key from multiple sources.
/// Priority: DEEPSEEK_API_KEY env → Keychain → nil
public enum DeepSeekAPIKeyResolver {
    /// Resolve the API key: env var first, then Keychain.
    public static func resolve() -> String? {
        // 1. macOS Keychain
        if let keychainKey = KeychainStore.load(), !keychainKey.isEmpty {
            return keychainKey
        }

        // 2. Environment variable (for CI / dev convenience)
        if let envKey = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"],
           !envKey.isEmpty {
            return envKey
        }

        return nil
    }
}
