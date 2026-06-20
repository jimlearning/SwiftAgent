import Foundation
import Darwin

// MARK: - Shared mutable state (reference types)

/// Mutable state for Ctrl+O expand/collapse toggle, shared between
/// the REPL loop and helper methods via reference semantics.
final class ExpandState: Decodable, @unchecked Sendable {
    var expandedGroupIndex: Int? = nil
    var expandedLineCount: Int = 0
}

/// Mutable model reference shared between the agent loop and slash commands.
/// Allows /model to change the model at runtime without restart.
final class SharedModel: @unchecked Sendable {
    var current: String
    init(_ model: String) { self.current = model }
}

/// Reference-type holder for MCP clients, sharable across closures and methods
/// without requiring struct mutation (same pattern as SharedModel).
final class MCPClientsHolder: @unchecked Sendable, Decodable {
    var clients: [any Sendable] = []
    init() {}
    convenience init(from decoder: Decoder) throws { self.init() }
}

/// Thread-safe session state shared between the REPL loop and tool execution.
/// Enables plan mode state changes and token tracking from within tool callbacks.
final class SessionState: @unchecked Sendable {
    private let lock = NSLock()
    private var _planModeActive = false
    private var _totalTokensIn = 0
    private var _totalTokensOut = 0

    var planModeActive: Bool {
        get { lock.withLock { _planModeActive } }
        set { lock.withLock { _planModeActive = newValue } }
    }

    var totalTokensIn: Int {
        get { lock.withLock { _totalTokensIn } }
        set { lock.withLock { _totalTokensIn = newValue } }
    }

    var totalTokensOut: Int {
        get { lock.withLock { _totalTokensOut } }
        set { lock.withLock { _totalTokensOut = newValue } }
    }

    var isPlanModeActive: Bool { planModeActive }

    func setPlanModeActive(_ active: Bool) {
        planModeActive = active
    }

    func addTokens(in: Int, out: Int) {
        lock.withLock {
            _totalTokensIn += `in`
            _totalTokensOut += out
        }
    }
}

/// Outcome of a slash command execution.
enum CommandOutcome {
    case normal(output: String?)
    case exit
    case resume(sessionId: String)
}

/// Thread-safe flag to pause the spinner during interactive user prompts.
/// When the spinner writes to stdout while a readLine() prompt is active,
/// its \\r\\e[K output clears the user's typed input, making interaction impossible.
final class SpinnerPauseFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _paused = false
    var paused: Bool {
        get { lock.withLock { _paused } }
        set { lock.withLock { _paused = newValue } }
    }
}

/// Holds a reference to the current escape-watcher Task so the interactive
/// prompt handler can cancel it (to stop it stealing stdin bytes) and restart
/// a fresh one afterwards.
final class EscapeTaskHolder: @unchecked Sendable {
    var task: Task<Void, Never>?
}

/// Wraps a `termios` for safe capture in @Sendable closures.
/// termios is a C struct of integers (no pointers) — safe to copy across actors.
struct SendableTermios: @unchecked Sendable {
    var value: termios
}

/// Thread-safe boolean flag for ESC cancellation coordination between Tasks.
final class AtomicBool: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

/// Thread-safe line buffer for queued messages typed during agent execution.
final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func push(_ line: String) { lock.withLock { lines.append(line) } }
    func pop() -> String? { lock.withLock { lines.isEmpty ? nil : lines.removeFirst() } }
    var isEmpty: Bool { lock.withLock { lines.isEmpty } }
}

/// Thread-safe tracker for currently executing tools.
/// Written by the agent loop and read by the spinner Task.
final class CurrentToolTracker: @unchecked Sendable {
    private struct Entry {
        let name: String
        var status: String?
        var displayCmd: String?
    }

    private static let pendingToolID = "__pending_tool__"
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private var _isThinking: Bool = false

    var displayLine: String? {
        lock.withLock {
            let active = order.compactMap { id -> Entry? in entries[id] }
            guard !active.isEmpty else { return nil }
            if active.count == 1 {
                let entry = active[0]
                if let cmd = entry.displayCmd {
                    return entry.status ?? "Running \(entry.name) → \(cmd)"
                }
                return entry.status ?? "Running \(entry.name)..."
            }

            let fragments = active.prefix(3).map { entry in
                if let status = entry.status {
                    return Self.singleLine(status)
                }
                if let cmd = entry.displayCmd {
                    return "\(entry.name) → \(cmd)"
                }
                return "\(entry.name) running"
            }
            let suffix = active.count > 3 ? "; +\(active.count - 3) more" : ""
            let label = active.allSatisfy { $0.name == "TaskOutput" } ? "background tasks" : "tools"
            return "\(active.count) \(label) running | " + fragments.joined(separator: "; ") + suffix
        }
    }

    var name: String? {
        get {
            lock.withLock {
                entries[Self.pendingToolID]?.name
            }
        }
        set {
            lock.withLock {
                if let value = newValue {
                    entries[Self.pendingToolID] = Entry(name: value, status: nil)
                    if !order.contains(Self.pendingToolID) {
                        order.append(Self.pendingToolID)
                    }
                } else {
                    entries[Self.pendingToolID] = nil
                    order.removeAll { $0 == Self.pendingToolID }
                }
            }
        }
    }

    func start(id: String, name: String, displayCmd: String? = nil) {
        lock.withLock {
            entries[id] = Entry(name: name, status: nil, displayCmd: displayCmd)
            if !order.contains(id) {
                order.append(id)
            }
        }
    }

    func update(id: String, status: String) {
        lock.withLock {
            if var entry = entries[id] {
                entry.status = status
                entries[id] = entry
            } else {
                entries[id] = Entry(name: id, status: status)
                order.append(id)
            }
        }
    }

    func finish(id: String) {
        lock.withLock {
            entries[id] = nil
            order.removeAll { $0 == id }
        }
    }

    var isThinking: Bool {
        get { lock.withLock { _isThinking } }
        set { lock.withLock { _isThinking = newValue } }
    }

    private static func singleLine(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}

// MARK: - Shared I/O helpers

/// Write raw bytes directly to stdout (for ANSI escape codes).
func writeToStdout(_ string: String) {
    guard let data = string.data(using: .utf8) else { return }
    _ = data.withUnsafeBytes { ptr in
        Darwin.write(STDOUT_FILENO, ptr.baseAddress!, ptr.count)
    }
}
