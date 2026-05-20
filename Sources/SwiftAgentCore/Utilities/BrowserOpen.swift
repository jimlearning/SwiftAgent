import Foundation
#if os(macOS)
import AppKit
#endif

/// Browser and path opening utilities matching Claude Code's utils/browser.ts.
/// Works on macOS (NSWorkspace), with Linux (xdg-open) support where available.

// MARK: - URL Validation

/// CC: validateUrl(url) — rejects non-http/https URLs.
private func validateURL(_ urlString: String) throws {
    guard let url = URL(string: urlString) else {
        throw BrowserError.invalidURL(urlString)
    }
    guard let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https" else {
        throw BrowserError.invalidProtocol(url.scheme ?? "(none)")
    }
}

// MARK: - Browser Opening

/// CC: openBrowser(url) — opens a URL in the system browser.
/// Returns `true` on success, `false` on any error.
@discardableResult
public func openBrowser(_ urlString: String) async -> Bool {
    do {
        try validateURL(urlString)
    } catch {
        return false
    }

    guard let url = URL(string: urlString) else { return false }

    // Respect BROWSER environment variable
    if let browserPath = ProcessInfo.processInfo.environment["BROWSER"] {
        do {
            try await runCommand(browserPath, urlString)
            return true
        } catch {
            return false
        }
    }

    #if os(macOS)
    return await MainActor.run {
        NSWorkspace.shared.open(url)
    }
    #elseif os(Linux)
    do {
        try await runCommand("xdg-open", urlString)
        return true
    } catch {
        return false
    }
    #elseif os(Windows)
    do {
        try await runCommand("rundll32", "url,OpenURL", urlString)
        return true
    } catch {
        return false
    }
    #else
    return false
    #endif
}

/// CC: openPath(path) — opens a file or folder with the system default handler.
/// Returns `true` on success, `false` on any error.
@discardableResult
public func openPath(_ path: String) async -> Bool {
    #if os(macOS)
    let url = URL(fileURLWithPath: path)
    return await MainActor.run {
        NSWorkspace.shared.open(url)
    }
    #elseif os(Linux)
    do {
        try await runCommand("xdg-open", path)
        return true
    } catch {
        return false
    }
    #elseif os(Windows)
    do {
        // Windows: use explorer for paths, rundll32 for URLs
        try await runCommand("explorer", path)
        return true
    } catch {
        return false
    }
    #else
    return false
    #endif
}

// MARK: - Command Execution Helper

private func runCommand(_ command: String, _ args: String...) async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [command] + args
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw BrowserError.commandFailed(command, process.terminationStatus)
    }
}

// MARK: - Errors

public enum BrowserError: Error, LocalizedError {
    case invalidURL(String)
    case invalidProtocol(String)
    case commandFailed(String, Int32)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL format: \(url)"
        case .invalidProtocol(let proto):
            return "Invalid URL protocol: must use http:// or https://, got \(proto)"
        case .commandFailed(let cmd, let code):
            return "Command '\(cmd)' failed with exit code \(code)"
        }
    }
}
