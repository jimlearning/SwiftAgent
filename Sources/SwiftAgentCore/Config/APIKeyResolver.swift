import Foundation

/// Resolves the API key from multiple sources, matching Claude Code's behavior.
/// Priority: ANTHROPIC_API_KEY env → macOS keychain → ~/.claude.json primaryApiKey
public struct APIKeyResolver: Sendable {

    public init() {}

    /// Resolve the API key using the same sources as Claude Code.
    /// Priority: ANTHROPIC_API_KEY → ANTHROPIC_AUTH_TOKEN → keychain → ~/.claude.json
    public func resolve() -> String? {
        // 1. Direct API key environment variable
        if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !envKey.isEmpty {
            return envKey
        }

        // 2. OAuth bearer token (also used as API key — common for DeepSeek setups)
        if let authToken = ProcessInfo.processInfo.environment["ANTHROPIC_AUTH_TOKEN"], !authToken.isEmpty {
            return authToken
        }

        // 3. macOS keychain (same as Claude Code's /login managed key)
        if let keychainKey = readFromKeychain() {
            return keychainKey
        }

        // 4. ~/.claude.json primaryApiKey
        if let configKey = readFromClaudeJSON() {
            return configKey
        }

        return nil
    }

    private func readFromKeychain() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-a", NSUserName(),
            "-w",
            "-s", "Claude Code"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }
            let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
            let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return key?.isEmpty == false ? key : nil
        } catch {
            return nil
        }
    }

    private func readFromClaudeJSON() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configURL = home.appendingPathComponent(".claude.json")

        guard FileManager.default.fileExists(atPath: configURL.path),
              let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // primaryApiKey field (set by `claude /login`)
        if let primaryKey = json["primaryApiKey"] as? String, !primaryKey.isEmpty {
            return primaryKey
        }

        return nil
    }
}
