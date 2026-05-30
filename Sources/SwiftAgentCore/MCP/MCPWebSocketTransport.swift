import Foundation

/// MCP transport over WebSocket connections.
/// Matches Claude Code's WebSocketTransport in utils/mcpWebSocketTransport.ts.
///
/// Uses URLSessionWebSocketTask for native Apple platform support.
/// Supports both `ws` and `ws-ide` MCP transport types.
public final class MCPWebSocketTransport: MCPStreamingTransport, @unchecked Sendable {
    private let url: URL
    private let headers: [String: String]
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var listenTask: Task<Void, Never>?
    private var started = false

    /// CC: onmessage callback — delivers parsed JSON-RPC messages.
    public var onMessage: (@Sendable (MCPMessage) -> Void)?
    /// CC: onclose callback — connection closed.
    public var onClose: (@Sendable () -> Void)?
    /// CC: onerror callback — transport error.
    public var onError: (@Sendable (Error) -> Void)?

    /// CC: WS_OPEN = 1 — task is running and started flag is set.
    private var isOpen: Bool { started && task?.state == .running }
    /// CC: WS_CONNECTING = 0 — task exists but not yet confirmed open.
    private var isConnecting: Bool { task != nil && !started }

    public init(url: URL, headers: [String: String] = [:]) {
        self.url = url
        self.headers = headers
    }

    // MARK: - MCPTransport

    public func connect() async throws {
        let config = URLSessionConfiguration.default
        if !headers.isEmpty {
            config.httpAdditionalHeaders = headers
        }
        session = URLSession(configuration: config)
        task = session!.webSocketTask(with: url)
        task!.resume()

        // Wait for the connection to open (CC: await this.opened)
        // URLSessionWebSocketTask.resume() starts connecting; we ping to confirm readiness.
        // Timeout after 10s if ping doesn't respond.
        let pingTask = Task {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                task!.sendPing { error in
                    if let error = error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume()
                    }
                }
            }
        }

        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 10_000_000_000)
            pingTask.cancel()
            throw MCPTransportError.notConnected
        }

        do {
            try await pingTask.value
            timeoutTask.cancel()
        } catch {
            timeoutTask.cancel()
            throw error
        }

        started = true
    }

    public func send(_ message: MCPMessage) async throws -> MCPMessage {
        guard let task = task, isOpen else {
            throw MCPTransportError.notConnected
        }
        let data = try encodeMCPMessage(message)
        try await task.send(.data(data))

        // WebSocket is streaming — response comes via onMessage callback.
        // Return a sentinel indicating the message was dispatched.
        return .notification(method: "sent", params: nil)
    }

    public func disconnect() async {
        listenTask?.cancel()
        listenTask = nil
        if isOpen || isConnecting {
            task?.cancel(with: .normalClosure, reason: nil)
        }
        session?.invalidateAndCancel()
        session = nil
        task = nil
        started = false
        onClose?()
    }

    // MARK: - MCPStreamingTransport

    public func sendWithoutResponse(_ message: MCPMessage) async throws {
        guard let task = task, isOpen else {
            throw MCPTransportError.notConnected
        }
        let data = try encodeMCPMessage(message)
        try await task.send(.data(data))
    }

    // MARK: - Message Listening

    /// Start the background message listener. Call after connect().
    /// CC: attaches persistent event handlers for 'message', 'error', 'close'.
    public func startListening() {
        guard listenTask == nil else { return }
        listenTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled, let task = self.task {
                do {
                    let message = try await task.receive()
                    switch message {
                    case .data(let data):
                        if let mcpMsg = try? decodeMCPMessage(data) {
                            self.onMessage?(mcpMsg)
                        }
                    case .string(let text):
                        if let data = text.data(using: .utf8),
                           let mcpMsg = try? decodeMCPMessage(data) {
                            self.onMessage?(mcpMsg)
                        }
                    @unknown default:
                        break
                    }
                } catch let error as URLError where error.code == .cancelled {
                    self.onClose?()
                    return
                } catch {
                    self.onError?(error)
                }
            }
        }
    }

    // MARK: - Helpers

    private func encodeMCPMessage(_ message: MCPMessage) throws -> Data {
        let dict = messageToDictionary(message)
        return try JSONSerialization.data(withJSONObject: dict)
    }

    private func decodeMCPMessage(_ data: Data) throws -> MCPMessage {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let dict = json as? [String: Any] else {
            throw MCPTransportError.invalidMessage
        }
        return try dictionaryToMessage(dict)
    }

    private func messageToDictionary(_ message: MCPMessage) -> [String: Any] {
        switch message {
        case .request(let id, let method, let params):
            var d: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
            if let p = params { d["params"] = jsonValueToAny(p) }
            return d
        case .response(let id, let result):
            var d: [String: Any] = ["jsonrpc": "2.0", "id": id]
            if let r = result { d["result"] = jsonValueToAny(r) }
            return d
        case .error(let id, let code, let message):
            return ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
        case .notification(let method, let params):
            var d: [String: Any] = ["jsonrpc": "2.0", "method": method]
            if let p = params { d["params"] = jsonValueToAny(p) }
            return d
        }
    }

    private func dictionaryToMessage(_ dict: [String: Any]) throws -> MCPMessage {
        let method = dict["method"] as? String
        let id = dict["id"] as? Int
        if let error = dict["error"] as? [String: Any] {
            return .error(id: id ?? 0, code: error["code"] as? Int ?? -1,
                          message: error["message"] as? String ?? "unknown error")
        }
        if let result = dict["result"] as? [String: Any] {
            return .response(id: id ?? 0, result: jsonDictToJSONValue(result))
        }
        if let m = method, id != nil {
            let params = dict["params"] as? [String: Any]
            return .request(id: id!, method: m, params: params.map(jsonDictToJSONValue))
        }
        if let m = method {
            let params = dict["params"] as? [String: Any]
            return .notification(method: m, params: params.map(jsonDictToJSONValue))
        }
        throw MCPTransportError.invalidMessage
    }

    private func jsonValueToAny(_ value: [String: JSONValue]) -> [String: Any] {
        value.mapValues { jsonValueToAnyPrimitive($0) }
    }

    private func jsonValueToAnyPrimitive(_ value: JSONValue) -> Any {
        switch value {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .null: return NSNull()
        case .array(let arr): return arr.map(jsonValueToAnyPrimitive)
        case .object(let dict): return dict.mapValues(jsonValueToAnyPrimitive)
        }
    }

    private func jsonDictToJSONValue(_ dict: [String: Any]) -> [String: JSONValue] {
        dict.mapValues { anyToJSONValue($0) }
    }

    private func anyToJSONValue(_ value: Any) -> JSONValue {
        switch value {
        case let s as String: return .string(s)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return .bool(n.boolValue)
            }
            return .number(n.doubleValue)
        case let b as Bool: return .bool(b)
        case is NSNull: return .null
        case let arr as [Any]: return .array(arr.map(anyToJSONValue))
        case let dict as [String: Any]: return .object(dict.mapValues(anyToJSONValue))
        default: return .null
        }
    }
}

// MARK: - Transport Errors

public enum MCPTransportError: Error, LocalizedError {
    case notConnected
    case invalidMessage
    case connectionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "WebSocket is not connected"
        case .invalidMessage:
            return "Invalid JSON-RPC message format"
        case .connectionFailed(let reason):
            return "WebSocket connection failed: \(reason)"
        }
    }
}
