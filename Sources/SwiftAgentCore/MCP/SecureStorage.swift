import Foundation
import Security

/// Secure credential storage matching Claude Code's utils/secureStorage/.
///
/// Platform strategy (matching CC):
/// - macOS: macOS Keychain via Security framework (SecItem APIs)
/// - Other platforms: Plaintext JSON file at ~/.swiftagent/.credentials.json
///
/// Storage structure matches CC's secure storage data shape for MCP OAuth:
///   mcpOAuth: { serverKey: { accessToken, refreshToken, expiresAt, scope, clientId, ... } }
///   mcpOAuthClientConfig: { serverKey: { clientSecret } }

// MARK: - Storage Protocol

/// Platform-abstracted secure credential storage.
public protocol SecureStorageProtocol: Sendable {
    func read(_ key: String) throws -> Data?
    func write(_ key: String, data: Data) throws
    func delete(_ key: String) throws
}

// MARK: - Keychain Storage (macOS)

/// macOS Keychain-based secure storage using Security framework APIs.
/// Matches CC's macOsKeychainStorage.ts.
public final class KeychainStorage: SecureStorageProtocol, @unchecked Sendable {
    private let serviceName: String
    private let cache = NSCache<NSString, NSData>()
    private let cacheTTL: TimeInterval = 300 // 5 min cache TTL matching CC

    public init(serviceName: String = "com.anthropic.swiftagent") {
        self.serviceName = serviceName
        cache.countLimit = 100
    }

    public func read(_ key: String) throws -> Data? {
        // Check cache first
        let cacheKey = key as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached as Data
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = result as? Data else {
            throw SecureStorageError.keychainError(status: status)
        }

        // Populate cache
        let nsData = data as NSData
        cache.setObject(nsData, forKey: cacheKey)

        return data
    }

    public func write(_ key: String, data: Data) throws {
        // Try delete-then-add to handle updates
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureStorageError.keychainError(status: status)
        }

        // Update cache
        cache.setObject(data as NSData, forKey: key as NSString)
    }

    public func delete(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStorageError.keychainError(status: status)
        }
        cache.removeObject(forKey: key as NSString)
    }

    /// Invalidate cache entry (used after cross-process refresh).
    public func invalidateCache(_ key: String) {
        cache.removeObject(forKey: key as NSString)
    }
}

// MARK: - Plaintext Storage (Non-macOS)

/// Plaintext JSON file storage for non-macOS platforms.
/// Matches CC's plainTextStorage.ts — file at ~/.swiftagent/.credentials.json with 0600 permissions.
public final class PlaintextStorage: SecureStorageProtocol, @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private var cache: [String: Data] = [:]

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".swiftagent")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent(".credentials.json")
        loadFromDisk()
    }

    public func read(_ key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return cache[key]
    }

    public func write(_ key: String, data: Data) throws {
        lock.lock()
        cache[key] = data
        lock.unlock()
        try persistToDisk()
    }

    public func delete(_ key: String) throws {
        lock.lock()
        cache.removeValue(forKey: key)
        lock.unlock()
        try persistToDisk()
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        lock.lock()
        for (k, v) in dict {
            cache[k] = Data(v.utf8)
        }
        lock.unlock()
    }

    private func persistToDisk() throws {
        lock.lock()
        let stringDict = cache.mapValues { String(data: $0, encoding: .utf8) ?? "" }
        lock.unlock()
        let json = try JSONEncoder().encode(stringDict)
        try json.write(to: fileURL, options: .atomic)
        // Set 0600 permissions
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

// MARK: - Storage Factory

/// Creates the appropriate storage backend for the current platform.
/// Matches CC's secureStorage/index.ts platform selection.
public func createSecureStorage() -> SecureStorageProtocol {
    #if os(macOS)
    return KeychainStorage()
    #else
    return PlaintextStorage()
    #endif
}

// MARK: - OAuth Token Storage Model

/// OAuth token data stored per MCP server.
/// Matches CC's mcpOAuth storage entry in secure storage.
public struct OAuthTokenData: Codable, Sendable {
    public var serverName: String
    public var serverUrl: String
    public var clientId: String?
    public var clientSecret: String?
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: TimeInterval  // seconds since 1970
    public var scope: String?
    public var discoveryState: DiscoveryState?
    public var stepUpScope: String?
}

/// Cached authorization server discovery state.
/// Only URLs are persisted (not full metadata blobs) to avoid keychain overflow.
public struct DiscoveryState: Codable, Sendable {
    public var authorizationServerUrl: String
    public var resourceMetadataUrl: String?
}

/// Client registration data stored per MCP server.
/// Matches CC's mcpOAuthClientConfig storage.
public struct OAuthClientConfigData: Codable, Sendable {
    public var clientSecret: String
}

// MARK: - OAuth Token Storage Manager

/// High-level CRUD for MCP OAuth tokens using the secure storage backend.
/// Matches CC's token management in services/mcp/auth.ts.
public actor OAuthTokenStore {
    private let storage: SecureStorageProtocol
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private static let mcpOAuthPrefix = "mcpOAuth."
    private static let mcpClientConfigPrefix = "mcpClientConfig."

    public init(storage: SecureStorageProtocol? = nil) {
        self.storage = storage ?? createSecureStorage()
    }

    // MARK: - Server Key

    /// CC: getServerKey(serverName, config) → "{serverName}|{sha256(configJson).hex.substring(0,16)}"
    /// Prevents credentials from being reused across different server URLs.
    public static func serverKey(serverName: String, configJson: String) -> String {
        guard let data = configJson.data(using: .utf8) else {
            return "\(serverName)|unknown"
        }
        let hash = SHA256Hash(data)
        let hexPrefix = String(hash.prefix(8))  // 16 hex chars
        return "\(serverName)|\(hexPrefix)"
    }

    // MARK: - Token CRUD

    public func readTokens(serverKey: String) throws -> OAuthTokenData? {
        let key = "\(Self.mcpOAuthPrefix)\(serverKey)"
        guard let data = try storage.read(key) else { return nil }
        return try decoder.decode(OAuthTokenData.self, from: data)
    }

    public func writeTokens(serverKey: String, tokens: OAuthTokenData) throws {
        let key = "\(Self.mcpOAuthPrefix)\(serverKey)"
        let data = try encoder.encode(tokens)
        try storage.write(key, data: data)
    }

    public func deleteTokens(serverKey: String) throws {
        let key = "\(Self.mcpOAuthPrefix)\(serverKey)"
        try storage.delete(key)
    }

    // MARK: - Client Config CRUD

    public func readClientConfig(serverKey: String) throws -> OAuthClientConfigData? {
        let key = "\(Self.mcpClientConfigPrefix)\(serverKey)"
        guard let data = try storage.read(key) else { return nil }
        return try decoder.decode(OAuthClientConfigData.self, from: data)
    }

    public func writeClientConfig(serverKey: String, config: OAuthClientConfigData) throws {
        let key = "\(Self.mcpClientConfigPrefix)\(serverKey)"
        let data = try encoder.encode(config)
        try storage.write(key, data: data)
    }

    public func deleteClientConfig(serverKey: String) throws {
        let key = "\(Self.mcpClientConfigPrefix)\(serverKey)"
        try storage.delete(key)
    }

    /// Clear all tokens for a server.
    /// CC: clearServerTokensFromLocalStorage()
    public func clearAllTokens(serverKey: String) throws {
        try? deleteTokens(serverKey: serverKey)
        try? deleteClientConfig(serverKey: serverKey)
    }
}

// MARK: - SHA256 Helper

/// SHA-256 hash for server key derivation.
/// Uses CryptoKit on Apple platforms (macOS 10.15+, iOS 13+).
#if canImport(CryptoKit)
import CryptoKit

private func SHA256Hash(_ data: Data) -> String {
    let digest = CryptoKit.SHA256.hash(data: data)
    return digest.compactMap { String(format: "%02x", $0) }.joined()
}
#else
/// Fallback: FNV-1a hash for server key derivation on platforms without CryptoKit.
/// Note: FNV-1a is NOT cryptographically secure, but is sufficient for
/// server key derivation (preventing credential reuse across URLs).
private func SHA256Hash(_ data: Data) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in data {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return String(format: "%016lx", hash)
}
#endif

// MARK: - Errors

public enum SecureStorageError: Error, LocalizedError {
    case keychainError(status: OSStatus)
    case encodingError
    case decodingError
    case notFound

    public var errorDescription: String? {
        switch self {
        case .keychainError(let status):
            return "Keychain operation failed: \(status)"
        case .encodingError:
            return "Failed to encode credential data"
        case .decodingError:
            return "Failed to decode credential data"
        case .notFound:
            return "Credential not found"
        }
    }
}
