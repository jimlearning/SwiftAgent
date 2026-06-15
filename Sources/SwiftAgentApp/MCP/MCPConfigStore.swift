import Foundation

/// Store for MCP server configurations using TOML (config.toml).
/// Reads/writes `~/.swiftagent/config.toml` with `[[mcp_servers]]` entries.
public final class MCPConfigStore: ObservableObject {
    @Published public var servers: [MCPServerConfig] = []

    private let configPath: String

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.configPath = "\(home)/.swiftagent/config.toml"
        load()
    }

    // MARK: - Config Model

    public struct MCPServerConfig: Identifiable, Equatable {
        public let id: String
        public var name: String
        public var transport: Transport
        public var isEnabled: Bool

        public enum Transport: Equatable {
            case stdio(command: String, args: [String], env: [String: String])
            case sse(url: String, headers: [String: String])
            case http(url: String, headers: [String: String])
        }

        public init(id: String = UUID().uuidString, name: String, transport: Transport, isEnabled: Bool = true) {
            self.id = id
            self.name = name
            self.transport = transport
            self.isEnabled = isEnabled
        }

        public var typeName: String {
            switch transport {
            case .stdio: return "stdio"
            case .sse: return "sse"
            case .http: return "http"
            }
        }

        public var command: String? {
            if case .stdio(let cmd, _, _) = transport { return cmd }
            return nil
        }

        public var url: String? {
            switch transport {
            case .sse(let url, _), .http(let url, _): return url
            default: return nil
            }
        }
    }

    // MARK: - Load

    public func load() {
        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            self.servers = []
            return
        }
        self.servers = parseTOML(content)
    }

    // MARK: - Save

    public func save() {
        let toml = serializeTOML(servers)
        let dir = (configPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? toml.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Add/Remove

    public func addServer(_ config: MCPServerConfig) {
        servers.append(config)
        save()
    }

    public func removeServer(id: String) {
        servers.removeAll { $0.id == id }
        save()
    }

    public func updateServer(_ config: MCPServerConfig) {
        if let idx = servers.firstIndex(where: { $0.id == config.id }) {
            servers[idx] = config
            save()
        }
    }

    // MARK: - TOML Parsing

    private func parseTOML(_ content: String) -> [MCPServerConfig] {
        var configs: [MCPServerConfig] = []
        var currentName: String?
        var currentCommand: String?
        var currentArgs: [String] = []
        var currentURL: String?
        var currentType: String = "stdio"
        var currentHeaders: [String: String] = [:]
        var currentEnv: [String: String] = [:]

        func flush() {
            guard let name = currentName else { return }
            let transport: MCPServerConfig.Transport
            switch currentType {
            case "sse":
                transport = .sse(url: currentURL ?? "", headers: currentHeaders)
            case "http":
                transport = .http(url: currentURL ?? "", headers: currentHeaders)
            default:
                transport = .stdio(command: currentCommand ?? "", args: currentArgs, env: currentEnv)
            }
            configs.append(MCPServerConfig(name: name, transport: transport))
            // Reset
            currentName = nil; currentCommand = nil; currentArgs = []; currentURL = nil
            currentType = "stdio"; currentHeaders = [:]; currentEnv = [:]
        }

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[[mcp_servers]]") {
                flush()
            } else if trimmed.hasPrefix("name =") {
                currentName = extractStringValue(trimmed)
            } else if trimmed.hasPrefix("command =") {
                currentCommand = extractStringValue(trimmed)
            } else if trimmed.hasPrefix("args =") {
                currentArgs = extractArrayValue(trimmed)
            } else if trimmed.hasPrefix("url =") {
                currentURL = extractStringValue(trimmed)
            } else if trimmed.hasPrefix("type =") {
                currentType = extractStringValue(trimmed) ?? "stdio"
            } else if trimmed.hasPrefix("[headers]") || trimmed.hasPrefix("env.") || trimmed.hasPrefix("env =") {
                // Handle inline tables - simplified
            } else if trimmed.contains("=") && (currentName != nil) {
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let val = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\"")))
                if key == "name" { currentName = val }
                else if key == "command" { currentCommand = val }
                else if key == "url" { currentURL = val }
                else if key == "type" { currentType = val }
            }
        }
        flush()
        return configs
    }

    private func extractStringValue(_ line: String) -> String? {
        let parts = line.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\"")))
    }

    private func extractArrayValue(_ line: String) -> [String] {
        let parts = line.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { return [] }
        let raw = String(parts[1]).trimmingCharacters(in: .whitespaces)
        guard raw.hasPrefix("[") && raw.hasSuffix("]") else { return [] }
        let inner = String(raw.dropFirst().dropLast())
        return inner.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\"")))
        }
    }

    private func serializeTOML(_ configs: [MCPServerConfig]) -> String {
        var lines: [String] = ["# SwiftAgent MCP server configuration", ""]
        for config in configs {
            lines.append("[[mcp_servers]]")
            lines.append("name = \"\(config.name)\"")
            switch config.transport {
            case .stdio(let cmd, let args, _):
                lines.append("type = \"stdio\"")
                lines.append("command = \"\(cmd)\"")
                if !args.isEmpty {
                    lines.append("args = [\"\(args.joined(separator: "\", \""))\"]")
                }
            case .sse(let url, _):
                lines.append("type = \"sse\"")
                lines.append("url = \"\(url)\"")
            case .http(let url, _):
                lines.append("type = \"http\"")
                lines.append("url = \"\(url)\"")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
