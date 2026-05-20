# Phase 10: MCP Integration

## Requirements
- MCP client core (Model Context Protocol)
- Transport abstraction (stdio, SSE)
- MCP tool → ToolProtocol bridge
- MCP server configuration parsing

## Files to Create
| File | Description |
|---|---|
| Core/MCP/MCPClient.swift | MCP client core — connect, list tools, call |
| Core/MCP/MCPTransport.swift | Transport abstraction (stdio process, SSE HTTP) |
| Core/MCP/MCPToolBridge.swift | Bridge MCP tools into ToolProtocol |
| Core/MCP/MCPServerConfig.swift | Server config parsing |

## Acceptance Criteria
- [ ] MCPClient can connect to an MCP server via stdio
- [ ] MCPTransport protocol with stdio and SSE implementations
- [ ] MCPToolBridge wraps MCP tool listing as ToolDefinition array
- [ ] MCPServerConfig parses JSON config entries
- [ ] `swift build` + `swift test` pass

**Output when complete:** `<promise>DONE</promise>`
