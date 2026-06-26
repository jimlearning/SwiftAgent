import Foundation
import SwiftAgentCore

// MARK: - AgentDebugger

/// Singleton debugger that instruments the entire agent pipeline.
///
/// Wires into `LanguageModelSessionImpl` (bootstrap, tool reg, MCP, skills, hooks),
/// `ThreadViewModel` (send lifecycle, streaming events, turn completion),
/// and `AppViewModel` (API key configuration).
///
/// Exposes `isEnabled` for the Settings toggle (persisted to UserDefaults).
/// When enabled, every subsystem event is logged to `DebugLog` for real-time
/// inspection via `DebugPanelView`.
@MainActor
public final class AgentDebugger: ObservableObject {
    public static let shared = AgentDebugger()

    private let log = DebugLog.shared
    private let defaultsKey = "AgentDebugger.isEnabled"

    /// Master switch — persisted to UserDefaults.
    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: defaultsKey)
            if isEnabled {
                log.info("Debugger enabled", category: .lifecycle, subsystem: "debugger")
            }
        }
    }

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: defaultsKey)
    }

    // MARK: - Logging helpers

    public func logLifecycle(_ message: String, metadata: [String: String] = [:]) {
        guard isEnabled else { return }
        log.info(message, category: .lifecycle, subsystem: "agent", metadata: metadata)
    }

    public func logLLM(_ message: String, metadata: [String: String] = [:]) {
        guard isEnabled else { return }
        log.info(message, category: .llm, subsystem: "agent", metadata: metadata)
    }

    public func logTool(_ message: String, metadata: [String: String] = [:]) {
        guard isEnabled else { return }
        log.info(message, category: .tool, subsystem: "agent", metadata: metadata)
    }

    public func logMCP(_ message: String, metadata: [String: String] = [:]) {
        guard isEnabled else { return }
        log.info(message, category: .mcp, subsystem: "agent", metadata: metadata)
    }

    public func logSkill(_ message: String, metadata: [String: String] = [:]) {
        guard isEnabled else { return }
        log.info(message, category: .skill, subsystem: "agent", metadata: metadata)
    }

    public func logHook(_ message: String, metadata: [String: String] = [:]) {
        guard isEnabled else { return }
        log.info(message, category: .hook, subsystem: "agent", metadata: metadata)
    }

    public func logPermission(_ message: String, metadata: [String: String] = [:]) {
        guard isEnabled else { return }
        log.info(message, category: .permission, subsystem: "agent", metadata: metadata)
    }

    public func logStreaming(_ message: String, metadata: [String: String] = [:]) {
        guard isEnabled else { return }
        log.info(message, category: .streaming, subsystem: "agent", metadata: metadata)
    }

    public func logUI(_ message: String, metadata: [String: String] = [:]) {
        guard isEnabled else { return }
        log.info(message, category: .ui, subsystem: "ui", metadata: metadata)
    }

    public func logError(_ message: String, category: DebugCategory = .general) {
        guard isEnabled else { return }
        log.error(message, category: category, subsystem: "agent")
    }

    public func logWarn(_ message: String, category: DebugCategory = .general) {
        guard isEnabled else { return }
        log.warn(message, category: category, subsystem: "agent")
    }

    // MARK: - Diagnostics

    /// Run a full self-check of all subsystems and log results.
    public func runDiagnostics(appViewModel: AppViewModel?) {
        guard isEnabled else { return }

        logLifecycle("=== Diagnostics Start ===")

        // API key
        if let provider = appViewModel?.provider {
            logLifecycle("API Key: configured (model: \(provider.displayName))")
        } else if appViewModel != nil {
            logError("API Key: NOT CONFIGURED", category: .lifecycle)
        } else {
            logLifecycle("API Key: unknown (appViewModel not available during bootstrap)")
        }

        // Agent session
        if appViewModel?.session != nil {
            logLifecycle("AgentSession: configured")
        } else {
            logLifecycle("AgentSession: nil (not bootstrapped)")
        }

        // Thread count
        if let avm = appViewModel {
            logLifecycle("Threads: \(avm.threadViewModels.count) total, projects: \(avm.projects.count)")
            logLifecycle("Storage: \(avm.isStorageReady ? "ready" : "NOT READY")")
        }

        logLifecycle("=== Diagnostics End ===")
    }
}
