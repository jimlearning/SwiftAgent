import SwiftUI

/// MCP server configuration view showing all servers and their tools.
/// Reuses SwiftAgentCore's MCP engine for connection management.
public struct MCPConfigView: View {
    @StateObject private var store = MCPConfigStore()
    @State private var showAddSheet = false
    @State private var connectionStatuses: [String: Bool] = [:]
    @State private var serverTools: [String: [String]] = [:]
    @State private var serverErrors: [String: String] = [:]

    // Polling timer
    @State private var refreshTimer: Timer?

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("MCP Servers")
                    .font(.uiHeadline)
                    .foregroundColor(.textPrimary)
                Spacer()
                Button(action: { showAddSheet = true }) {
                    Label("Add Server", systemImage: "plus")
                        .font(.uiCaption)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().background(Color.borderSubtle)

            // Server list
            if store.servers.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Text("No MCP servers configured")
                        .font(.uiBody)
                        .foregroundColor(.textSecondary)
                    Text("Add an MCP server to extend SwiftAgent with custom tools.")
                        .font(.uiCaption)
                        .foregroundColor(.textTertiary)
                        .multilineTextAlignment(.center)
                    Button("Add Server") { showAddSheet = true }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                }
                .padding(32)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.servers) { server in
                            MCPServerCard(
                                config: server,
                                isConnected: connectionStatuses[server.id] ?? false,
                                tools: serverTools[server.id] ?? [],
                                lastError: serverErrors[server.id],
                                onReconnect: { reconnectServer(server) },
                                onTest: { testServer(server) },
                                onDelete: {
                                    store.removeServer(id: server.id)
                                    connectionStatuses.removeValue(forKey: server.id)
                                    serverTools.removeValue(forKey: server.id)
                                    serverErrors.removeValue(forKey: server.id)
                                }
                            )
                            .padding(.horizontal, 12)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 500)
        .background(Color.bgSidebar)
        .onAppear {
            refreshStatuses()
            startPolling()
        }
        .onDisappear {
            stopPolling()
        }
        .sheet(isPresented: $showAddSheet) {
            AddMCPServerSheet { config in
                store.addServer(config)
                refreshStatuses()
            }
        }
    }

    // MARK: - Polling

    private func startPolling() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { @MainActor in refreshStatuses() }
        }
    }

    private func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Connection

    private func refreshStatuses() {
        for server in store.servers {
            checkConnection(server)
        }
    }

    private func checkConnection(_ server: MCPConfigStore.MCPServerConfig) {
        Task {
            let result = await performConnectionCheck(server)
            await MainActor.run {
                connectionStatuses[server.id] = result.connected
                serverTools[server.id] = result.tools
                if let err = result.error {
                    serverErrors[server.id] = err
                } else {
                    serverErrors.removeValue(forKey: server.id)
                }
            }
        }
    }

    private func performConnectionCheck(_ server: MCPConfigStore.MCPServerConfig) async -> (connected: Bool, tools: [String], error: String?) {
        // Use a simple check: for stdio, check if the command exists
        // For now return stub status since full MCP client connection requires SwiftAgentCore runner
        // The actual MCPBootstrapper from Core handles full connection lifecycle
        switch server.transport {
        case .stdio(let cmd, _, _):
            // Check if command is available
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = [cmd]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    return (true, [], nil)
                }
                return (false, [], "Command '\(cmd)' not found")
            } catch {
                return (false, [], error.localizedDescription)
            }
        case .sse(let urlStr, _), .http(let urlStr, _):
            guard let url = URL(string: urlStr) else {
                return (false, [], "Invalid URL: \(urlStr)")
            }
            do {
                var req = URLRequest(url: url, timeoutInterval: 5)
                req.httpMethod = "HEAD"
                let (_, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if (200...299).contains(code) {
                    return (true, [], nil)
                }
                return (false, [], "HTTP \(code)")
            } catch {
                return (false, [], error.localizedDescription)
            }
        }
    }

    private func reconnectServer(_ server: MCPConfigStore.MCPServerConfig) {
        connectionStatuses[server.id] = false
        serverErrors.removeValue(forKey: server.id)
        checkConnection(server)
    }

    private func testServer(_ server: MCPConfigStore.MCPServerConfig) {
        serverErrors.removeValue(forKey: server.id)
        connectionStatuses[server.id] = false
        checkConnection(server)
    }
}
