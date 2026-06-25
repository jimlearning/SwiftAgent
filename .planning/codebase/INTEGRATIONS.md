# External Integrations

**Analysis Date:** 2026-06-25

## APIs & External Services

**LLM Providers:**

- **Anthropic Messages API** - Primary LLM provider for Claude model family.
  - SDK/Client: `LLMClient` (`Sources/SwiftAgentCore/LLM/LLMClient.swift`)
  - Endpoint: `https://api.anthropic.com/v1/messages` (streaming + non-streaming)
  - App provider wrapper: `AnthropicProvider` (`Sources/SwiftAgentApp/LLM/AnthropicProvider.swift`)
  - Auth: `ANTHROPIC_API_KEY` env var, `ANTHROPIC_AUTH_TOKEN` env var, macOS Keychain, or `~/.claude.json` primaryApiKey
  - Auth header: `x-api-key` + `Bearer <key>` (via `authorizationHeaderValue()` in `LLMClient.swift:702-706`)
  - API version header: `anthropic-version: 2023-06-01`
  - Beta features: 14+ beta headers managed via `Betas` enum (`Sources/SwiftAgentCore/Constants/Betas.swift`)
  - Streaming: SSE (Server-Sent Events) parsed via `LLMStreamParser` (`Sources/SwiftAgentCore/LLM/LLMStreamParser.swift`)
  - Model registry: `ModelRegistry` (`Sources/SwiftAgentCore/LLM/ModelRegistry.swift`) — haiku-4-5, sonnet-4-6, opus-4-7

- **DeepSeek API** - Alternative LLM provider via Anthropic-compatible and OpenAI-compatible endpoints.
  - SDK/Client: `LLMClient` configured for `https://api.deepseek.com/anthropic` (Anthropic-compatible path)
  - Alternative client: `DeepSeekClient` (`Sources/SwiftAgentApp/DeepSeek/DeepSeekClient.swift`) directly calls `https://api.deepseek.com/v1/chat/completions` (OpenAI-compatible, SSE streaming)
  - App provider wrapper: `DeepSeekProvider` (`Sources/SwiftAgentApp/LLM/DeepSeekProvider.swift`)
  - Auth: `DEEPSEEK_API_KEY` env var or macOS Keychain (`KeychainStore`, `Sources/SwiftAgentApp/DeepSeek/KeychainStore.swift`)
  - Auth header: `Bearer <key>` (DeepSeekClient) or `x-api-key` + `Bearer <key>` (LLMClient)
  - Models: `deepseek-v4-pro`, `deepseek-v4-flash` (via `DeepSeekModel` enum)

- **OpenAI API** - Stub provider for future use.
  - Provider: `OpenAIProvider` (`Sources/SwiftAgentApp/LLM/OpenAIProvider.swift`)
  - Auth: `OPENAI_API_KEY` env var
  - Currently registered in `ProviderRegistry` discovery chain but has no active client implementation beyond the stub

**Provider Resolution:**
- Multi-provider orchestration via `ProviderRegistry` (`Sources/SwiftAgentApp/LLM/ProviderRegistry.swift`)
- Auto-discovery priority: Anthropic → DeepSeek → OpenAI
- `AppAgentProvider` (`Sources/SwiftAgentApp/Agent/AppAgentProvider.swift`) unifies all providers behind a single `currentModel` state
- Key resolution chain: `DEEPSEEK_API_KEY` env → Keychain → `ANTHROPIC_API_KEY` env → `ANTHROPIC_AUTH_TOKEN` env → Keychain → `~/.claude.json`

**Web Search:**
- **DuckDuckGo HTML** - Free web search via HTML scraping.
  - Tool: `WebSearchTool` (`Sources/SwiftAgentCore/Tools/WebSearchTool.swift`)
  - Endpoint: `https://html.duckduckgo.com/html/?q=<query>`
  - User-Agent: `SwiftAgent/1.0`
  - No API key required
  - Parses `class="result__a"` links from DuckDuckGo HTML results

**Web Fetch:**
- **Generic URL Fetch** - Fetch and extract content from any HTTP/HTTPS URL.
  - Tool: `WebFetchTool` (`Sources/SwiftAgentCore/Tools/WebFetchTool.swift`)
  - User-Agent: `SwiftAgent/1.0 (markdown-fetcher)`
  - Timeout: 30 seconds
  - No API key required

**OAuth (Anthropic):**
- **Anthropic OAuth** - Console and Claude.ai OAuth flows for API key provisioning.
  - Implementation: `OAuthFlow` (`Sources/SwiftAgentCore/MCP/OAuthFlow.swift`), `OAuthCallbackServer` (`Sources/SwiftAgentCore/MCP/OAuthCallbackServer.swift`), `OAuthPKCE` (`Sources/SwiftAgentCore/MCP/OAuthPKCE.swift`)
  - Constants: `OAuthConstants` (`Sources/SwiftAgentCore/Constants/OAuthConstants.swift`)
  - Production endpoints: `https://api.anthropic.com`, `https://platform.claude.com/oauth/authorize`, `https://claude.com/cai/oauth/authorize`
  - Staging endpoints: Configurable via `USER_TYPE=ant` env var
  - Token URL: `https://platform.claude.com/v1/oauth/token`
  - Client ID (prod): `9d1c250a-e61b-44d9-88ed-5944d1962f5e`
  - OAuth beta header: `oauth-2025-04-20`

## Data Storage

**Databases:**
- **SQLite** - Embedded database for app persistence.
  - Connection: File at `~/Library/Application Support/SwiftAgent/threads.db` (default), configurable via `Database.init(path:)`
  - Client: Direct `sqlite3` C API wrapper (`Sources/SwiftAgentApp/Storage/Database.swift`)
  - WAL mode enabled for concurrent reads
  - Thread safety: `NSRecursiveLock` serialization
  - Schema: Projects, Threads, Messages tables managed via `Migrations` (`Sources/SwiftAgentApp/Storage/Migrations.swift`)
  - Repository layer: `ProjectRepository`, `ThreadRepository`, `MessageRepository` (`Sources/SwiftAgentApp/Storage/`)

**File Storage:**
- **JSONL Session Logs** - Per-session logs at `~/.swift-agent/projects/<sanitized-path>/<session-uuid>.jsonl`
  - CC-compatible `LogEntry` format via `SessionStore` (`Sources/SwiftAgentCore/Storage/SessionStore.swift`)
- **Session Index** - `sessions-index.json` for fast metadata lookup via `SessionIndexStore`
- **Debug Logs** - Plain text debug logs at `~/.swift-agent/debug/<session-uuid>.txt`
- **Memory Files** - Project-level memory as markdown files at `~/.swift-agent/projects/<sanitized>/memory/`
- **Transcripts** - Session transcripts via `TranscriptStore` (`Sources/SwiftAgentCore/Storage/TranscriptStore.swift`)
- **Configuration** - `~/.swift-agent/config.json` via `ConfigLoader` (`Sources/SwiftAgentCore/Config/ConfigLoader.swift`)

**Caching:**
- Agent runtime uses in-memory caching (no external cache service).
- Prompt caching supported at the API level via Anthropic's `ephemeral` cache (handled in `LLMClient` streaming/non-streaming paths).

## Authentication & Identity

**Auth Provider:**
- Custom API key resolution system. No third-party auth service integration.
- API key resolution chain (implemented in `APIKeyResolver`, `Sources/SwiftAgentCore/Config/APIKeyResolver.swift`):
  1. `ANTHROPIC_API_KEY` environment variable
  2. `ANTHROPIC_AUTH_TOKEN` environment variable
  3. macOS Keychain (`KeychainAccess` wrapper)
  4. `~/.claude.json` file (Claude Code `primaryApiKey` field)
- DeepSeek key resolution (`DeepSeekAPIKeyResolver`, `Sources/SwiftAgentApp/DeepSeek/KeychainStore.swift`):
  1. `DEEPSEEK_API_KEY` environment variable
  2. macOS Keychain (service: `com.swiftagent.api`, key: `deepseek-api-key`)
- OAuth flow for API key provisioning from Anthropic Console (not for end-user authentication)

## Monitoring & Observability

**Error Tracking:**
- `ErrorPresenter` actor (`Sources/SwiftAgentApp/Errors/ErrorPresenter.swift`) — 16 error states with banner/toast/modal views
- `ErrorTaxonomy` (`Sources/SwiftAgentApp/Errors/ErrorTaxonomy.swift`) — structured error categorization
- No external error tracking service (Sentry, Crashlytics, etc.) detected

**Logs:**
- `DebugLogger` (`Sources/SwiftAgentCLI/DebugLogger.swift`) — JSONL debug logging to `~/.swift-agent/debug/` with API key masking
- `DebugLogSink` protocol (`Sources/SwiftAgentCore/LLM/LLMClient.swift:15`) with categories: `[API:request]`, `[API:stream]`, `[ToolExecutor]`, `[Permission]`, `[MCP]`, `[Skill]`, `[Hook]`, `[Storage]`, `[Compactor]`
- `AgentDebugger` (`Sources/SwiftAgentApp/Debug/AgentDebugger.swift`) — in-app debug panel
- All logging is local file-based. No log aggregation service.

## CI/CD & Deployment

**Hosting:**
- Local macOS application. No server hosting detected.
- CLI installed as `swift-agent` binary (SPM executable)

**CI Pipeline:**
- No CI/CD configuration detected (no `.github/workflows/` directory)
- Build and test run locally via `scripts/build.sh` and `scripts/test.sh`

## Environment Configuration

**Required env vars:**
- At least one API key must be configured: `ANTHROPIC_API_KEY`, `DEEPSEEK_API_KEY`, or `OPENAI_API_KEY`
- `ANTHROPIC_BASE_URL` — optional, defaults to `https://api.deepseek.com/anthropic`
- `USER_TYPE` — optional, set to `"ant"` for Anthropic internal staging endpoints

**Secrets location:**
- macOS Keychain: `com.swiftagent.api` service entry (DeepSeek), "Claude Code" legacy entry (Anthropic)
- Environment variables (for CI/dev convenience)
- `~/.claude.json` — Claude Code auth file (migration path)

## MCP (Model Context Protocol)

**MCP Client:**
- Full MCP client implementation in `Sources/SwiftAgentCore/MCP/`
- Transports: `StdioTransport` (child process stdin/stdout), `MCPWebSocketTransport` (WebSocket)
- Messages: JSON-RPC 2.0 format (`MCPMessage` enum in `MCPTransport.swift`)
- SSE frame parsing via `parseSSEFrames()` in `MCPTransport.swift`
- OAuth flow support for MCP servers via `OAuthFlow` + `OAuthPKCE`
- MCP proxy: `https://mcp-proxy.anthropic.com/v1/mcp/{server_id}`
- Secure storage: `SecureStorage` (`Sources/SwiftAgentCore/MCP/SecureStorage.swift`)
- Server configuration managed via `MCPConfigStore` (`Sources/SwiftAgentApp/MCP/MCPConfigStore.swift`) and `.mcp.json` project file

**Active MCP configuration:**
- `codegraph` server configured in `.mcp.json` (stdio transport, `codegraph serve --mcp`)

## LSP (Language Server Protocol)

**LSP Integration:**
- `LSPTool` (`Sources/SwiftAgentCore/Tools/LSPTool.swift`) — 9 LSP operations: goToDefinition, findReferences, hover, documentSymbol, workspaceSymbol, goToImplementation, prepareCallHierarchy, incomingCalls, outgoingCalls
- Communicates with local LSP servers via JSON-RPC over stdio (local process communication)
- Uses `FeatureFlags.isLSPEnabled()` gate
- No hard dependency on any specific LSP server — tool-agnostic

## Webhooks & Callbacks

**Incoming:**
- `swiftagent://` URL scheme registered in `Info.plist` for deep linking
- Handled via `URLRouter` (`Sources/SwiftAgentApp/URLHandling/URLRouter.swift`)
- `OAuthCallbackServer` (`Sources/SwiftAgentCore/MCP/OAuthCallbackServer.swift`) — local HTTP server for OAuth redirect callbacks

**Outgoing:**
- No outbound webhook support detected
- `PushNotificationTool` and `CronCreateTool` exist for scheduled/notified agent prompts but operate locally

## Browser Integration

**Browser Panel:**
- `BrowserPanelView` (`Sources/SwiftAgentApp/RightTabs/panels/BrowserPanelView.swift`) uses `WKWebView` for in-app browsing
- Configurable default search engine (Google, DuckDuckGo, Bing) via `BrowserSettingsView`
- Allow-list domain filtering for security

## Skill System

**Skills:**
- `SkillFileLoader` (`Sources/SwiftAgentCore/Skills/SkillFileLoader.swift`) — loads skill definitions from filesystem
- `SkillYAMLParser` (`Sources/SwiftAgentCore/Skills/SkillYAMLParser.swift`) — parses skill YAML manifests
- `SkillsView`, `SkillCreatorSheet` in App target for skill management UI
- No external skill marketplace integration. Skills are local files.

---

*Integration audit: 2026-06-25*
