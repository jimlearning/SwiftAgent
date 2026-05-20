import Foundation

/// Resolves the user's shell based on platform detection and configuration.
/// Matches Claude Code's shell selection: zsh on macOS, bash on Linux,
/// powershell/cmd on Windows, with Settings.defaultShell as an override.
public enum ShellResolver: Sendable {

    /// Resolve the shell executable path from context or platform defaults.
    /// - Parameter configured: Optional shell override from Settings.defaultShell.
    /// - Returns: Absolute path to the shell executable.
    public static func resolve(configured: String? = nil) -> String {
        if let configured, !configured.isEmpty {
            // If the configured value is an absolute path, use it directly.
            // If it's a bare name (e.g. "bash"), resolve via which/find.
            if configured.hasPrefix("/") {
                return configured
            }
            if let resolved = resolveByName(configured) {
                return resolved
            }
        }
        return platformDefault()
    }

    // MARK: - Platform detection

    private static func platformDefault() -> String {
        #if os(macOS)
        return "/bin/zsh"
        #elseif os(Linux)
        // Prefer bash on Linux, fall back to zsh if available
        if let bash = resolveByName("bash") { return bash }
        if let zsh = resolveByName("zsh") { return zsh }
        return "/bin/sh"
        #elseif os(Windows)
        return resolveByName("powershell.exe") ?? resolveByName("cmd.exe") ?? "powershell.exe"
        #else
        return "/bin/sh"
        #endif
    }

    // MARK: - Shell name resolution

    private static func resolveByName(_ name: String) -> String? {
        #if os(Windows)
        let whichCmd = "where"
        #else
        let whichCmd = "which"
        #endif

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [whichCmd, name]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        guard let output = try? runAndWait(process),
              !output.isEmpty else {
            return nil
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Helpers

    private static func runAndWait(_ process: Process) throws -> String? {
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let data = try (process.standardOutput as? Pipe)?.fileHandleForReading.readToEnd(),
              let output = String(data: data, encoding: .utf8) else {
            return nil
        }
        return output
    }
}
