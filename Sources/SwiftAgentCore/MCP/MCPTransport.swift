import Foundation

// MARK: - SSE Frame

struct MCPSSEFrame {
    var event: String?
    var id: String?
    var data: String?
}

/// Parse SSE frames from a text buffer.
/// Returns parsed frames and the remaining (incomplete) buffer.
func parseSSEFrames(_ buffer: String) -> (frames: [MCPSSEFrame], remaining: String) {
    var frames: [MCPSSEFrame] = []
    var pos = buffer.startIndex

    while let doubleNewline = buffer[pos...].range(of: "\n\n") {
        let rawFrame = String(buffer[pos..<doubleNewline.lowerBound])
        pos = doubleNewline.upperBound

        guard !rawFrame.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

        var frame = MCPSSEFrame()
        for line in rawFrame.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(":") { continue } // SSE comment
            guard let colonIdx = line.firstIndex(of: ":") else { continue }
            let field = String(line[..<colonIdx])
            var value = String(line[line.index(after: colonIdx)...])
            if value.hasPrefix(" ") { value.removeFirst() }

            switch field {
            case "event": frame.event = value
            case "id": frame.id = value
            case "data":
                frame.data = frame.data.map { $0 + "\n" + value } ?? value
            default: break
            }
        }

        if frame.data != nil { frames.append(frame) }
    }

    return (frames, String(buffer[pos...]))
}

// MARK: - MCP Message Types

/// MCP JSON-RPC 2.0 message types.
public enum MCPMessage: Sendable {
    case request(id: Int, method: String, params: [String: JSONValue]?)
    case response(id: Int, result: [String: JSONValue]?)
    case error(id: Int, code: Int, message: String)
    case notification(method: String, params: [String: JSONValue]?)
}

// MARK: - Transport Protocols

/// Transport abstraction for MCP communication.
public protocol MCPTransport: Sendable {
    func connect() async throws
    func send(_ message: MCPMessage) async throws -> MCPMessage
    func disconnect() async
}

/// Streaming variant: responses arrive asynchronously via onMessage callback.
public protocol MCPStreamingTransport: MCPTransport {
    var onMessage: (@Sendable (MCPMessage) -> Void)? { get set }
    var onClose: (@Sendable () -> Void)? { get set }
    func sendWithoutResponse(_ message: MCPMessage) async throws
}

// MARK: - Stdio Transport

/// MCP transport over a child process's stdin/stdout (newline-delimited JSON).
public actor StdioTransport: MCPTransport {
    private let command: [String]
    private var process: Process?
    private var stdoutHandle: FileHandle?
    private var stdinHandle: FileHandle?

    public init(command: [String]) {
        self.command = command
    }

    public func connect() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        let stdoutPipe = Pipe()
        let stdinPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardInput = stdinPipe
        try process.run()
        self.process = process
        self.stdoutHandle = stdoutPipe.fileHandleForReading
        self.stdinHandle = stdinPipe.fileHandleForWriting
    }

    public func send(_ message: MCPMessage) async throws -> MCPMessage {
        guard let stdinHandle, let stdoutHandle else {
            throw MCPError.transportNotConnected
        }
        let requestData = try MessageCoder.encode(message)
        stdinHandle.write(requestData)
        stdinHandle.write("\n".data(using: .utf8)!)
        let responseData = try await readResponse(from: stdoutHandle)
        return try MessageCoder.decode(responseData)
    }

    public func disconnect() {
        process?.terminate()
        process = nil
        stdoutHandle = nil
        stdinHandle = nil
    }

    private func readResponse(from handle: FileHandle) async throws -> Data {
        var buffer = Data()
        for _ in 0..<1000 {
            let available = try handle.read(upToCount: 4096) ?? Data()
            buffer.append(available)
            if buffer.contains(10) { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        guard let newline = buffer.firstIndex(of: 10) else {
            throw MCPError.invalidResponse
        }
        return buffer[..<newline]
    }
}

// MARK: - SSE Transport

/// MCP transport using SSE for receiving and HTTP POST for sending.
public final class SSETransport: MCPStreamingTransport, @unchecked Sendable {
    private let url: URL
    private let headers: [String: String]
    private let session: URLSession

    private var streamTask: URLSessionDataTask?
    private var streamBuffer = ""
    private var isConnected = false
    private let stateLock = NSLock()

    private var pendingRequests: [Int: CheckedContinuation<MCPMessage, any Error>] = [:]
    private let pendingLock = NSLock()

    public var onMessage: (@Sendable (MCPMessage) -> Void)?
    public var onClose: (@Sendable () -> Void)?

    public init(url: URL, headers: [String: String] = [:]) {
        self.url = url
        self.headers = headers
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config)
    }

    public func connect() async throws {
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            streamTask = session.dataTask(with: request) { [weak self] _, response, error in
                guard let self else { return }
                if error != nil {
                    self.stateLock.withLock { self.isConnected = false }
                    self.onClose?()
                    self.pendingLock.withLock {
                        for (_, c) in self.pendingRequests {
                            c.resume(throwing: MCPError.transportNotConnected)
                        }
                        self.pendingRequests.removeAll()
                    }
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse else { return }
                if httpResponse.statusCode == 200 {
                    self.stateLock.withLock { self.isConnected = true }
                }
            }
            stateLock.withLock { isConnected = true }
            cont.resume()
            streamTask?.resume()
        }
    }

    public func send(_ message: MCPMessage) async throws -> MCPMessage {
        guard case .request(let id, _, _) = message else {
            throw MCPError.invalidResponse
        }

        let requestData = try MessageCoder.encode(message)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = requestData

        return try await withCheckedThrowingContinuation { continuation in
            pendingLock.withLock { pendingRequests[id] = continuation }

            let task = session.dataTask(with: request) { [weak self] data, response, error in
                guard let self else { return }
                if error != nil {
                    _ = self.pendingLock.withLock { self.pendingRequests.removeValue(forKey: id) }
                    continuation.resume(throwing: MCPError.transportNotConnected)
                    return
                }
                if let httpResponse = response as? HTTPURLResponse {
                    let ct = httpResponse.allHeaderFields["Content-Type"] as? String ?? ""
                    if ct.contains("text/event-stream") { return } // response via SSE stream
                }
                if let data, !data.isEmpty, let msg = try? MessageCoder.decode(data) {
                    _ = self.pendingLock.withLock { self.pendingRequests.removeValue(forKey: id) }
                    continuation.resume(returning: msg)
                }
            }
            task.resume()
        }
    }

    public func sendWithoutResponse(_ message: MCPMessage) async throws {
        guard case .notification = message else {
            throw MCPError.invalidResponse
        }
        let requestData = try MessageCoder.encode(message)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = requestData
        _ = try await session.data(for: request)
    }

    public func disconnect() {
        stateLock.withLock { isConnected = false }
        streamTask?.cancel()
        streamTask = nil
        pendingLock.withLock {
            for (_, cont) in pendingRequests {
                cont.resume(throwing: MCPError.transportNotConnected)
            }
            pendingRequests.removeAll()
        }
    }

    /// Process raw SSE data received from the stream.
    func handleSSEData(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        streamBuffer += text

        let result = parseSSEFrames(streamBuffer)
        streamBuffer = result.remaining

        for frame in result.frames {
            guard let dataStr = frame.data,
                  let messageData = dataStr.data(using: .utf8),
                  let message = try? MessageCoder.decode(messageData)
            else { continue }
            routeMessage(message)
        }
    }

    private func routeMessage(_ message: MCPMessage) {
        let responseId: Int?
        switch message {
        case .response(let id, _): responseId = id
        case .error(let id, _, _): responseId = id
        default: responseId = nil
        }

        if let id = responseId {
            pendingLock.withLock {
                if let cont = pendingRequests.removeValue(forKey: id) {
                    cont.resume(returning: message)
                    return
                }
            }
        }
        onMessage?(message)
    }
}

// MARK: - Streamable HTTP Transport

/// MCP transport using HTTP POST with optional SSE streaming responses.
public final class HTTPTransport: MCPStreamingTransport, @unchecked Sendable {
    private let url: URL
    private let headers: [String: String]
    private let session: URLSession

    private var isConnected = false
    private let stateLock = NSLock()

    public var onMessage: (@Sendable (MCPMessage) -> Void)?
    public var onClose: (@Sendable () -> Void)?

    public init(url: URL, headers: [String: String] = [:]) {
        self.url = url
        self.headers = headers
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config)
    }

    public func connect() async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 405 else {
            throw MCPError.transportError("Server unreachable")
        }
        stateLock.withLock { isConnected = true }
    }

    public func send(_ message: MCPMessage) async throws -> MCPMessage {
        guard case .request(let id, _, _) = message else {
            throw MCPError.invalidResponse
        }

        let requestData = try MessageCoder.encode(message)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = requestData

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPError.invalidResponse
        }

        let contentType = httpResponse.allHeaderFields["Content-Type"] as? String ?? ""

        if contentType.contains("text/event-stream") {
            // SSE streaming response
            let result = parseSSEFrames(String(data: data, encoding: .utf8) ?? "")
            for frame in result.frames {
                guard let dataStr = frame.data,
                      let msgData = dataStr.data(using: .utf8),
                      let msg = try? MessageCoder.decode(msgData)
                else { continue }
                switch msg {
                case .response(let respId, _), .error(let respId, _, _):
                    if respId == id { return msg }
                    onMessage?(msg)
                default:
                    onMessage?(msg)
                }
            }
            throw MCPError.invalidResponse
        }

        return try MessageCoder.decode(data)
    }

    public func sendWithoutResponse(_ message: MCPMessage) async throws {
        guard case .notification = message else {
            throw MCPError.invalidResponse
        }
        let requestData = try MessageCoder.encode(message)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = requestData
        _ = try await session.data(for: request)
    }

    public func disconnect() {
        stateLock.withLock { isConnected = false }
        session.invalidateAndCancel()
    }
}

// MARK: - Message Coder

enum MessageCoder {
    static func encode(_ message: MCPMessage) throws -> Data {
        let dict = messageToDict(message)
        return try JSONSerialization.data(withJSONObject: dict)
    }

    static func decode(_ data: Data) throws -> MCPMessage {
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return dictToMessage(dict)
    }

    private static func messageToDict(_ message: MCPMessage) -> [String: Any] {
        switch message {
        case .request(let id, let method, let params):
            var dict: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
            if let params { dict["params"] = params.mapValues { $0.anyValue } }
            return dict
        case .response(let id, let result):
            return ["jsonrpc": "2.0", "id": id, "result": result?.mapValues { $0.anyValue } ?? NSNull()]
        case .error(let id, let code, let message):
            return ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
        case .notification(let method, let params):
            var dict: [String: Any] = ["jsonrpc": "2.0", "method": method]
            if let params { dict["params"] = params.mapValues { $0.anyValue } }
            return dict
        }
    }

    private static func dictToMessage(_ dict: [String: Any]) -> MCPMessage {
        if let id = dict["id"] as? Int {
            if let error = dict["error"] as? [String: Any] {
                return .error(id: id, code: error["code"] as? Int ?? -1, message: error["message"] as? String ?? "unknown")
            }
            if let method = dict["method"] as? String {
                return .request(id: id, method: method, params: dictToJSONValue(dict["params"]))
            }
            return .response(id: id, result: dictToJSONValue(dict["result"]))
        }
        if let method = dict["method"] as? String {
            return .notification(method: method, params: dictToJSONValue(dict["params"]))
        }
        return .notification(method: "", params: nil)
    }

    private static func dictToJSONValue(_ value: Any?) -> [String: JSONValue]? {
        guard let dict = value as? [String: Any] else { return nil }
        return dict.compactMapValues { JSONValue.fromAny($0) }
    }
}

// MARK: - Error

public enum MCPError: Error, Sendable {
    case transportNotConnected
    case invalidResponse
    case serverError(code: Int, message: String)
    case toolNotFound(String)
    case transportError(String)
}
