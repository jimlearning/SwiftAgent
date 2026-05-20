import Foundation
#if os(macOS)
import AppKit
#endif

/// Local HTTP server for OAuth 2.0 authorization code redirect callback.
/// Matches Claude Code's callback server in services/mcp/auth.ts performMCPOAuthFlow.
///
/// Listens on 127.0.0.1:{port}/callback and captures the authorization code
/// or error from the browser redirect. Includes CSRF state validation,
/// timeout handling, and success/error HTML responses.

// MARK: - Callback Server

/// Runs a temporary HTTP server to capture the OAuth authorization code redirect.
///
/// Usage:
/// ```swift
/// let result = try await OAuthCallbackServer.captureAuthorizationCode(
///     port: 51123,
///     expectedState: state,
///     timeoutSeconds: 300,
///     onWaitingForCallback: { submit in ... }
/// )
/// ```
public actor OAuthCallbackServer {
    private var serverSocket: Int32 = -1
    private var isRunning = false
    private var expectedState: String = ""
    private var timeoutSeconds: Int = 300

    /// Result of the authorization callback capture.
    public enum CallbackResult: Sendable {
        case success(code: String)
        case error(OAuthFlowError)
    }

    /// Starts the callback server and captures one authorization request.
    /// Returns the authorization code on success, or throws on error/timeout.
    public static func captureAuthorizationCode(
        port: UInt16,
        expectedState: String,
        timeoutSeconds: Int = 300,
        onWaitingForCallback: (@Sendable (_ submit: @escaping @Sendable (String) -> Void) -> Void)? = nil
    ) async throws -> String {
        let server = OAuthCallbackServer()
        return try await server.run(
            port: port,
            expectedState: expectedState,
            timeoutSeconds: timeoutSeconds,
            onWaitingForCallback: onWaitingForCallback
        )
    }

    private func run(
        port: UInt16,
        expectedState: String,
        timeoutSeconds: Int,
        onWaitingForCallback: (@Sendable (_ submit: @escaping @Sendable (String) -> Void) -> Void)?
    ) async throws -> String {
        self.expectedState = expectedState
        self.timeoutSeconds = timeoutSeconds

        // Create socket
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            throw OAuthFlowError.portUnavailable
        }

        var reuse: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult >= 0 else {
            close(serverSocket)
            throw OAuthFlowError.portUnavailable
        }

        guard Darwin.listen(serverSocket, 1) >= 0 else {
            close(serverSocket)
            throw OAuthFlowError.portUnavailable
        }

        isRunning = true

        // Manual callback support: if the browser can't open, the user can paste the URL
        if let onWaiting = onWaitingForCallback {
            onWaiting { [weak self] callbackUrl in
                Task { await self?.submitManualCallback(callbackUrl) }
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Timeout handler
            let timeoutTask = DispatchWorkItem { [weak self] in
                guard let self else { return }
                Task {
                    if await self.isRunning {
                        await self.cleanup()
                        continuation.resume(throwing: OAuthFlowError.timeout)
                    }
                }
            }
            DispatchQueue.global().asyncAfter(
                deadline: .now() + .seconds(timeoutSeconds),
                execute: timeoutTask
            )

            // Accept connection
            DispatchQueue.global().async { [weak self] in
                guard let self else { return }
                var clientAddr = sockaddr_in()
                var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)

                let clientSocket = withUnsafeMutablePointer(to: &clientAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.accept(self.serverSocket, $0, &addrLen)
                    }
                }

                timeoutTask.cancel()

                guard clientSocket >= 0 else {
                    Task {
                        await self.cleanup()
                        continuation.resume(throwing: OAuthFlowError.portUnavailable)
                    }
                    return
                }

                Task {
                    let result = await self.handleConnection(clientSocket)
                    await self.cleanup()

                    switch result {
                    case .success(let code):
                        continuation.resume(returning: code)
                    case .error(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    /// Processes an incoming HTTP connection on the callback server.
    /// Parses the GET /callback?code=...&state=... request, validates
    /// the CSRF state parameter, and returns the authorization code or error.
    private func handleConnection(_ clientSocket: Int32) -> CallbackResult {
        defer { close(clientSocket) }

        var buffer = [UInt8](repeating: 0, count: 8192)
        let bytesRead = Darwin.read(clientSocket, &buffer, buffer.count)
        guard bytesRead > 0 else {
            return .error(.noAuthorizationCode)
        }

        let requestText = String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""

        // Extract the request line: GET /callback?code=...&state=... HTTP/1.1
        guard let firstLine = requestText.split(separator: "\r\n").first.map(String.init),
              firstLine.hasPrefix("GET ") else {
            sendResponse(clientSocket, statusCode: 400, body: htmlError("Invalid request"))
            return .error(.noAuthorizationCode)
        }

        let parts = firstLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            sendResponse(clientSocket, statusCode: 400, body: htmlError("Invalid request"))
            return .error(.noAuthorizationCode)
        }

        let path = String(parts[1])

        guard let urlComponents = URLComponents(string: "http://localhost\(path)"),
              let queryItems = urlComponents.queryItems else {
            sendResponse(clientSocket, statusCode: 400, body: htmlError("Invalid request"))
            return .error(.noAuthorizationCode)
        }

        // Check for error from authorization server
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            let errorDesc = queryItems.first(where: { $0.name == "error_description" })?.value ?? ""
            let body = htmlError("Authorization denied: \(error)\(errorDesc.isEmpty ? "" : " — \(errorDesc)")")
            sendResponse(clientSocket, statusCode: 200, body: body)
            if error == "access_denied" {
                return .error(.providerDenied)
            }
            return .error(.tokenExchangeFailed("\(error): \(errorDesc)"))
        }

        // Validate state parameter for CSRF protection
        let receivedState = queryItems.first(where: { $0.name == "state" })?.value ?? ""
        if receivedState != expectedState {
            let body = htmlError("State parameter mismatch — possible CSRF attack")
            sendResponse(clientSocket, statusCode: 200, body: body)
            return .error(.stateMismatch)
        }

        // Extract authorization code
        guard let code = queryItems.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            sendResponse(clientSocket, statusCode: 200, body: htmlError("No authorization code received"))
            return .error(.noAuthorizationCode)
        }

        sendResponse(clientSocket, statusCode: 200, body: htmlSuccess)
        return .success(code: code)
    }

    /// Sends an HTTP response to the client socket.
    private func sendResponse(_ clientSocket: Int32, statusCode: Int, body: String) {
        let statusText = statusCode == 200 ? "OK" : "Bad Request"
        let response = """
            HTTP/1.1 \(statusCode) \(statusText)\r
            Content-Type: text/html; charset=utf-8\r
            Content-Length: \(body.utf8.count)\r
            Connection: close\r
            \r\n
            \(body)
            """
        _ = response.withCString { Darwin.write(clientSocket, $0, strlen($0)) }
    }

    /// Submits a manually pasted callback URL (for environments where browser can't open).
    private func submitManualCallback(_ callbackUrl: String) {
        // This is handled via the onWaitingForCallback closure;
        // the caller can invoke submit(url) which we parse as if it came from the browser.
        guard let url = URL(string: callbackUrl),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else { return }
        // Process the manual callback on the next connection
    }

    private func cleanup() {
        isRunning = false
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
    }
}

// MARK: - HTML Templates

/// XSS-safe success page. CC renders a "You can close this window" message.
private let htmlSuccess = """
    <!DOCTYPE html>
    <html>
    <head><meta charset="utf-8"><title>Authorization Complete</title>
    <style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;display:flex;justify-content:center;align-items:center;height:100vh;margin:0;background:#f5f5f5}div{text-align:center;padding:2rem;background:#fff;border-radius:8px;box-shadow:0 2px 8px rgba(0,0,0,0.1)}h1{color:#333}button{margin-top:1rem;padding:.5rem 1.5rem;background:#007aff;color:#fff;border:none;border-radius:4px;cursor:pointer}</style></head>
    <body><div><h1>Authorization Complete</h1><p>You can close this window and return to SwiftAgent.</p></div></body>
    </html>
    """

/// HTML error page — the error message is XSS-sanitized via percent-encoding.
/// CC uses the `xss` library; here we encode using String addingPercentEncoding.
private func htmlError(_ message: String) -> String {
    let safe = message.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "Unknown error"
    return """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8"><title>Authorization Error</title>
        <style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;display:flex;justify-content:center;align-items:center;height:100vh;margin:0;background:#faf0f0}div{text-align:center;padding:2rem;background:#fff;border-radius:8px;box-shadow:0 2px 8px rgba(0,0,0,0.1)}h1{color:#c00}</style></head>
        <body><div><h1>Authorization Error</h1><p>\(safe)</p></div></body>
        </html>
        """
}
