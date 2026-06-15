import SwiftUI

/// Sheet for adding a new MCP server (stdio or SSE/HTTP).
struct AddMCPServerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var transportType: String = "stdio"
    @State private var command: String = ""
    @State private var args: String = ""
    @State private var url: String = ""
    @State private var headers: String = ""

    var onAdd: ((MCPConfigStore.MCPServerConfig) -> Void)?

    private let transportTypes = ["stdio", "sse", "http"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add MCP Server")
                .font(.uiHeadline)
                .foregroundColor(.textPrimary)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name").font(.uiCaption).foregroundColor(.textSecondary)
                    TextField("My Server", text: $name)
                        .textFieldStyle(.roundedBorder).font(.uiBody)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Type").font(.uiCaption).foregroundColor(.textSecondary)
                    Picker("Type", selection: $transportType) {
                        ForEach(transportTypes, id: \.self) { t in Text(t).tag(t) }
                    }
                    .pickerStyle(.segmented).frame(maxWidth: 200)
                }
                if transportType == "stdio" {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Command").font(.uiCaption).foregroundColor(.textSecondary)
                        TextField("npx", text: $command).textFieldStyle(.roundedBorder).font(.uiBody)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Arguments (comma-separated)").font(.uiCaption).foregroundColor(.textSecondary)
                        TextField("-y, @modelcontextprotocol/server-filesystem", text: $args).textFieldStyle(.roundedBorder).font(.uiBody)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("URL").font(.uiCaption).foregroundColor(.textSecondary)
                        TextField("https://example.com/mcp", text: $url).textFieldStyle(.roundedBorder).font(.uiBody)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Headers (key:value, comma-separated)").font(.uiCaption).foregroundColor(.textSecondary)
                        TextField("Authorization: Bearer xxx", text: $headers).textFieldStyle(.roundedBorder).font(.uiBody)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
                Button("Add") {
                    let parsedArgs = args.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    let parsedHeaders = parseHeaders(headers)
                    let cfg: MCPConfigStore.MCPServerConfig
                    switch transportType {
                    case "sse":
                        cfg = .init(name: name.trimmingCharacters(in: .whitespaces), transport: .sse(url: url.trimmingCharacters(in: .whitespaces), headers: parsedHeaders))
                    case "http":
                        cfg = .init(name: name.trimmingCharacters(in: .whitespaces), transport: .http(url: url.trimmingCharacters(in: .whitespaces), headers: parsedHeaders))
                    default:
                        cfg = .init(name: name.trimmingCharacters(in: .whitespaces), transport: .stdio(command: command.trimmingCharacters(in: .whitespaces), args: parsedArgs, env: [:]))
                    }
                    onAdd?(cfg)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460, height: 400)
    }

    private func parseHeaders(_ s: String) -> [String: String] {
        var result: [String: String] = [:]
        for part in s.split(separator: ",") {
            let kv = part.split(separator: ":", maxSplits: 1)
            if kv.count == 2 {
                let k = kv[0].trimmingCharacters(in: .whitespaces)
                let v = kv[1].trimmingCharacters(in: .whitespaces)
                if !k.isEmpty { result[k] = v }
            }
        }
        return result
    }
}
