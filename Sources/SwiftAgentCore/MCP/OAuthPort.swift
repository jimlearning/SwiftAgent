import Foundation

/// OAuth redirect port finding and URI construction matching Claude Code's services/mcp/oauthPort.ts.
/// Handles dynamic port selection for the localhost OAuth callback server (RFC 8252 Section 7.3).

// MARK: - Port Ranges

/// CC: REDIRECT_PORT_RANGE — platform-specific ephemeral port range.
/// On Windows the range is 39152..49151; on other platforms 49152..65535.
#if os(Windows)
private let REDIRECT_PORT_MIN = 39152
private let REDIRECT_PORT_MAX = 49151
#else
private let REDIRECT_PORT_MIN = 49152
private let REDIRECT_PORT_MAX = 65535
#endif

/// CC: REDIRECT_PORT_FALLBACK = 3118
let REDIRECT_PORT_FALLBACK: UInt16 = 3118

/// Maximum number of random port attempts before falling back.
private let MAX_PORT_ATTEMPTS = 100

// MARK: - Redirect URI

/// CC: buildRedirectUri(port?) → "http://localhost:{port}/callback"
public func buildRedirectUri(port: UInt16 = 3118) -> String {
    "http://localhost:\(port)/callback"
}

// MARK: - Port Finding

/// CC: getMcpOAuthCallbackPort() — reads MCP_OAUTH_CALLBACK_PORT env var.
private func getMcpOAuthCallbackPort() -> UInt16? {
    guard let raw = ProcessInfo.processInfo.environment["MCP_OAUTH_CALLBACK_PORT"],
          let num = UInt16(raw),
          num > 0 else { return nil }
    return num
}

/// CC: findAvailablePort() — finds an available port for the OAuth redirect server.
///
/// Algorithm:
/// 1. If MCP_OAUTH_CALLBACK_PORT is set, use it directly.
/// 2. Otherwise, try random ports in the platform range (up to 100 attempts).
/// 3. Fall back to port 3118.
/// 4. Throw if nothing works.
public func findAvailablePort() throws -> UInt16 {
    // Respect explicit port override
    if let configured = getMcpOAuthCallbackPort() {
        return configured
    }

    // Try random ports
    let range = REDIRECT_PORT_MAX - REDIRECT_PORT_MIN + 1
    let attempts = min(range, MAX_PORT_ATTEMPTS)

    for _ in 0..<attempts {
        let port = UInt16(REDIRECT_PORT_MIN) + UInt16.random(in: 0..<UInt16(range))
        if isPortAvailable(port: port) {
            return port
        }
    }

    // Fallback
    if isPortAvailable(port: REDIRECT_PORT_FALLBACK) {
        return REDIRECT_PORT_FALLBACK
    }

    throw OAuthPortError.noAvailablePorts
}

/// Port availability errors matching CC's error paths.
public enum OAuthPortError: Error, LocalizedError {
    case noAvailablePorts

    public var errorDescription: String? {
        switch self {
        case .noAvailablePorts:
            return "No available ports for OAuth redirect"
        }
    }
}

// MARK: - Port Availability Check

/// Tests whether a TCP port is available for listening.
/// Uses a temporary socket bind test (matching CC's createServer().listen() probe).
private func isPortAvailable(port: UInt16) -> Bool {
    let sock = socket(AF_INET, SOCK_STREAM, 0)
    guard sock >= 0 else { return false }
    defer { close(sock) }

    // Reuse address to clean up quickly
    var reuse: Int32 = 1
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    addr.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian

    let result = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }

    return result == 0
}
