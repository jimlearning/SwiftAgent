# Phase 3: Provider Implementations - Research

**Researched:** 2026-06-25
**Domain:** Multi-provider AI inference backends (Anthropic Messages API, DeepSeek dual-endpoint, OpenAI Chat Completions), SQLite-based persistent memory, permission engine bridging
**Confidence:** HIGH

## Summary

Phase 3 implements the three `LanguageModelExecutor` backends (Anthropic, DeepSeek, OpenAI), a `SQLiteMemoryStore` implementing `RuntimeMemoryStore`, and bridges the existing `PermissionEngine` to accept the `AgentPermission` taxonomy. All contract types were defined in Phase 1 and the agent loop that calls them was built in Phase 2 -- this phase fills in the real implementations behind those contracts.

The bulk of the work is in the three ModelProviders. The `AnthropicProvider` absorbs the 1080-line `LLMClient` and 309-line `LLMStreamParser` from `Sources/SwiftAgentCore/LLM/`, moving their logic into a new `Sources/SwiftAgentCore/AgentRuntime/Providers/Anthropic/` directory. The `DeepSeekProvider` unifies two currently-separate code paths (App/LLM/DeepSeekProvider wrapping LLMClient + App/DeepSeek/DeepSeekClient for OpenAI-compat) into a single executor behind an internal `APICompatibility` switch. The `OpenAIProvider` replaces its current stub with a full Chat Completions SSE parser that maps OpenAI streaming chunks to `SessionEvent` values.

The `SQLiteMemoryStore` provides persistent key-value storage with LIKE-based search, heuristic summarization, and schema migration support. It replaces the ad-hoc file-based `MemoryStore` (Storage/MemoryStore.swift, 417 lines) for the Runtime protocol path while coexisting with the existing storage during the migration window.

The PermissionEngine upgrade is a bridge: the existing `PermissionEngine` struct (Safety/PermissionEngine.swift, 315 lines) with its tool-name-based rule system gains a new adapter struct that maps `AgentPermission` enum cases into the existing permission check pipeline.

**Primary recommendation:** Build AnthropicProvider first (validates the executor contract end-to-end with a real API), then DeepSeek (unifies existing dual paths), then OpenAI (new implementation from stub), then SQLiteMemoryStore, and finally the PermissionEngine bridge. Each provider gets its own subdirectory under `Providers/` and owns all wire-format types internally.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Anthropic Messages API translation | Core (Provider) | -- | Translate Transcript -> Anthropic wire format, SSE parsing -> SessionEvent. All wire types internal. |
| DeepSeek dual-endpoint translation | Core (Provider) | -- | Single provider with internal APICompatibility switch. Both paths produce identical SessionEvent output. |
| OpenAI Chat Completions translation | Core (Provider) | -- | New implementation from stub. Function calling mapped to SessionEvent tool calls. |
| SQLite persistence (MemoryStore) | Core (Provider) | -- | Stores Codable values. Schema versioned. System SQLite3 linked into Core target. |
| Permission taxonomy bridging | Core (Adapter) | Core (Safety) | AgentPermission -> existing PermissionEngine rule system. Thin adapter, no new permission logic. |
| Retry / SSE lifecycle | Core (Provider) | -- | Each provider owns its retry strategy and SSE connection lifecycle internally. |
| Provider model listing / capabilities | Core (Provider) | App (LLM picker) | Core declares LanguageModelCapabilities; App reads for UI display. |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift 6.3 stdlib | 6.3 | AsyncThrowingStream, actors, Task, Sendable | Zero-dependency foundation for all streaming and concurrency |
| Foundation | (macOS 15) | URLSession, JSONEncoder/Decoder, FileManager, Data | URLSession.AsyncBytes for SSE streaming; Codable for type bridging |
| System SQLite3 | 3.51.0 (macOS) | Persistent key-value storage for SQLiteMemoryStore | Ships with macOS; no package dependency needed |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| (none) | -- | -- | All provider implementations use only stdlib + Foundation + system SQLite3 |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| System SQLite3 module | GRDB.swift (groue/GRDB.swift) | GRDB provides type-safe query builders and migrations, but adds an external dependency. System SQLite3 is zero-dependency and the MemoryStore protocol needs only simple CRUD. |
| Hand-written SSE parser | swift-nio or AsyncHTTPClient | Overkill. URLSession.AsyncBytes handles SSE efficiently. No need for HTTP/2 frame-level control. |
| Provider-per-target (App vs Core) | -- | Anti-pattern. All providers go in Core/AgentRuntime/Providers/ -- App consumes them through AgentRuntime protocol. |

**Installation:**
```bash
# No external packages to install. All dependencies are system-provided.
# SQLite3 must be linked into SwiftAgentCore target (see Package.swift modification below).
```

**Version verification:** The existing `Database.swift` in `SwiftAgentApp/Storage/` already uses `import SQLite3` (system module, macOS 15). No additional package installation required. System SQLite3 is at version 3.51.0 on this machine.

## Package Legitimacy Audit

> No external packages are installed or recommended in this phase. All dependencies are system-provided (Foundation, SQLite3). Skip.

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
USER PROMPT (from CLI ChatCommand or App ThreadViewModel)
    │
    ▼
AgentRuntimeImpl (Phase 2 agent loop)
    │ modelProvider.makeExecutor()
    ▼
┌───────────────────────────────────────────────────────────────────┐
│ LanguageModelExecutor.respond(to: Transcript, tools:, options:,   │
│                              streamingInto: GenerationChannel)    │
└───────────────────────────────────────────────────────────────────┘
    │                              │                    │
    ▼                              ▼                    ▼
┌───────────────┐  ┌───────────────────────┐  ┌───────────────────┐
│ Anthropic     │  │ DeepSeekProvider      │  │ OpenAIProvider    │
│ Provider      │  │ (AnthropicCompat OR   │  │ (Chat Completions)│
│               │  │  OpenAICompat switch) │  │                   │
│ Transcript -> │  │ Transcript ->         │  │ Transcript ->     │
│ Anthropic     │  │  .anthropicCompat:    │  │ OpenAI messages[] │
│ messages[]    │  │    reuse translation  │  │ + function_call   │
│               │  │  .openAICompat:       │  │                   │
│ POST /v1/     │  │    ChatMessage[]      │  │ POST /v1/chat/    │
│ messages      │  │                       │  │ completions      │
│ (SSE)         │  │ POST /anthropic/v1/   │  │ (SSE)            │
│               │  │ messages OR           │  │                   │
│ Provider-     │  │ /v1/chat/completions  │  │ Provider-         │
│ internal:     │  │ (SSE)                 │  │ internal:         │
│ SSE parsing   │  │                       │  │ SSE parsing       │
│ ContentBlock  │  │ Provider-internal:    │  │ OpenAIStreamChunk │
│ Accumulator   │  │ APICompat switch      │  │ -> SessionEvent   │
│ -> SessionEvt │  │ -> SessionEvent       │  │                   │
└───────┬───────┘  └───────────┬───────────┘  └────────┬──────────┘
        │                      │                        │
        └──────────────────────┼────────────────────────┘
                               │
                               ▼
                    GenerationChannel
                    (RuntimeGenerationChannel actor)
                               │
                               ▼
                    AsyncThrowingStream<SessionEvent, Error>
                               │
                               ▼
                    AgentRuntimeImpl agent loop
                    (tool execution, re-prompt, memory store)

═══════════════════════════════════════════════════════════════════
                    SEPARATE SUBSYSTEMS
═══════════════════════════════════════════════════════════════════

SQLiteMemoryStore                    PermissionEngine Bridge
    │                                      │
    ▼                                      ▼
RuntimeMemoryStore protocol         RuntimePermissionEngine protocol
    │                                      │
store/retrieve/search/              check(AgentPermission) -> Bool
summarize/forget/listNamespaces           │
    │                                      ▼
    ▼                               Existing PermissionEngine
~/.swift-agent/memory.db            (Safety/PermissionEngine.swift)
(SQLite3, schema versioned)         check(toolName, input, mode, context)
                                    -> AgentPermission mapped to
                                       tool-name-based rules
```

### Recommended Project Structure

```
Sources/SwiftAgentCore/AgentRuntime/Providers/
├── Anthropic/
│   ├── AnthropicProvider.swift          # LanguageModel + LanguageModelExecutor conformance
│   ├── AnthropicTranscriptTranslator.swift  # Transcript -> Anthropic messages[]
│   ├── AnthropicSSEParser.swift         # SSE line -> internal events (moved from LLMStreamParser)
│   ├── AnthropicContentAccumulator.swift # ContentBlock accumulation (moved from LLMStreamParser)
│   ├── AnthropicToolTranslator.swift    # RuntimeToolDefinition -> Anthropic tool JSON
│   ├── AnthropicRequestBuilder.swift    # URLRequest construction, headers, retry
│   └── AnthropicRetryPolicy.swift       # Retry logic (moved from RetryPolicy.swift)
├── DeepSeek/
│   ├── DeepSeekProvider.swift           # LanguageModel + LanguageModelExecutor conformance
│   ├── DeepSeekAPICompatibility.swift   # Internal enum + endpoint switching
│   ├── DeepSeekTranscriptTranslator.swift # Transcript -> messages (both compat modes)
│   ├── DeepSeekSSEParser.swift          # SSE parsing for both compat modes
│   └── DeepSeekToolTranslator.swift     # Tool definitions for both endpoints
├── OpenAI/
│   ├── OpenAIProvider.swift             # LanguageModel + LanguageModelExecutor conformance
│   ├── OpenAITranscriptTranslator.swift # Transcript -> OpenAI messages[]
│   ├── OpenAISSEParser.swift            # OpenAI SSE chunk -> SessionEvent
│   └── OpenAIToolTranslator.swift       # RuntimeToolDefinition -> OpenAI function format
├── Memory/
│   └── SQLiteMemoryStore.swift          # RuntimeMemoryStore conformance via SQLite3
├── Permission/
│   └── AgentPermissionBridge.swift      # Adapter: AgentPermission -> existing PermissionEngine
├── LanguageModel.swift                  # [existing] LanguageModel protocol
├── LanguageModelExecutor.swift          # [existing] LanguageModelExecutor protocol
├── GenerationChannel.swift              # [existing] GenerationChannel protocol
├── AgentPermission.swift                # [existing] AgentPermission enum + RuntimePermissionEngine
└── AgentMemoryStore.swift               # [existing] RuntimeMemoryStore protocol
```

### Pattern 1: Provider as LanguageModel + Executor in One Struct

**What:** Each provider is a single `Sendable` struct that conforms to both `LanguageModel` (provides capabilities + `makeExecutor()`) and `LanguageModelExecutor` (performs inference). The struct holds API key, base URL, and model configuration. `makeExecutor()` returns `self`.

**When to use:** Every provider implementation in Phase 3.

**Why:** The `LanguageModelExecutor` protocol has `var model: any LanguageModel { get }`. When model and executor are the same struct, the executor has direct access to its own configuration without needing to guard-cast. This is simpler than the Phase 2 mock pattern where `MockLanguageModelExecutor` does `guard let mock = model as? MockLanguageModel`.

**Example:**
```swift
// Source: Phase 1 LanguageModelExecutor protocol + Phase 2 MockProvider lessons
public struct AnthropicProvider: LanguageModel, LanguageModelExecutor, Sendable {
    public let capabilities: LanguageModelCapabilities
    public let displayName: String
    private let apiKey: String
    private let baseURL: URL
    private let session: URLSession

    // LanguageModel conformance
    public func makeExecutor() -> any LanguageModelExecutor { self }

    // LanguageModelExecutor conformance
    public var model: any LanguageModel { self }

    public func respond(
        to transcript: Transcript,
        tools: [RuntimeToolDefinition],
        options: GenerationOptions,
        streamingInto channel: GenerationChannel
    ) async throws {
        // Translate Transcript -> Anthropic messages[], stream SSE -> SessionEvent
    }
}
```

### Pattern 2: Transcript-to-Wire Translation

**What:** Each provider contains a dedicated `TranscriptTranslator` (internal struct or private methods) that maps `Transcript.Entry` cases to provider-native message formats. This is pure-functional (input Transcript, output wire format) and independently testable.

**When to use:** Every provider. Translation logic varies by provider.

**Example (Anthropic):**
```swift
// Source: LLMClient.swift Message.apiFormatted (existing) mapped to Transcript.Entry
// .instruction(String)     -> system prompt string (or system content blocks with cache_control)
// .prompt(String)          -> { role: "user", content: [{ type: "text", text: String }] }
// .response(String)        -> { role: "assistant", content: [{ type: "text", text: String }] }
// .toolCall(id:name:input:) -> { role: "assistant", content: [{ type: "tool_use", id, name, input }] }
// .toolOutput(id:output:)  -> { role: "user", content: [{ type: "tool_result", tool_use_id, content }] }
// .thinking(String)        -> { role: "assistant", content: [{ type: "thinking", thinking }] }
// .system(String)          -> injected as user-role system-reminder block
```

**Example (OpenAI):**
```swift
// .instruction(String)    -> { role: "system", content: String }
// .prompt(String)         -> { role: "user", content: String }
// .response(String)       -> { role: "assistant", content: String }
// .toolCall(id:name:input:)-> { role: "assistant", tool_calls: [{ id, function: { name, arguments } }] }
// .toolOutput(id:output:) -> { role: "tool", tool_call_id: id, content: output }
// .thinking(String)       -> (o4 models) injected as reasoning_tokens; (non-o4) no equivalent
// .system(String)         -> { role: "user", content: "[System] String" }
```

### Pattern 3: SSE Parser Internal to Each Provider

**What:** Each provider has its own SSE parser that consumes `URLSession.AsyncBytes.lines`, extracts provider-specific JSON chunks, and translates them into `SessionEvent` values sent through the `GenerationChannel`. The parser is `private`/`internal` to the provider.

**When to use:** Every provider. SSE wire format differs across providers.

**Example (Anthropic SSE):**
```swift
// Source: LLMStreamParser.parse(data:) (existing), adapted for SessionEvent output
// SSE line: data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}
// -> channel.send(textDelta: accumulatedText + "Hello")
//
// SSE line: data: {"type":"content_block_start","content_block":{"type":"tool_use","name":"Bash","id":"toolu_01"}}
// -> track tool start (don't send yet -- wait for input_json_delta completion)
//
// SSE line: data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{...}}
// -> channel.complete(stopReason: "end_turn", usage: parsedUsage)
```

**Example (OpenAI SSE):**
```swift
// SSE line: data: {"id":"chatcmpl-123","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"Hello"}}]}
// -> channel.send(textDelta: accumulatedText + "Hello")
//
// SSE line: data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"Bash","arguments":"{\"command\":\"ls\"}"}}]}}]}
// -> accumulate per-index, when function.arguments is complete JSON: channel.send(toolCallRequest: ...)
//
// SSE line: data: {"choices":[{"index":0,"finish_reason":"stop"}]}
// -> channel.complete(stopReason: "stop", usage: ...)
```

### Pattern 4: DeepSeek API Compatibility Switch

**What:** Single `DeepSeekProvider` struct with an internal `APICompatibility` enum that switches between Anthropic-compat (`/anthropic/v1/messages`) and OpenAI-compat (`/v1/chat/completions`) endpoints. The same `Transcript` and `SessionEvent` types flow through both paths.

**When to use:** DeepSeekProvider exclusively. The switch is internal -- external consumers never see it.

**Example:**
```swift
// Source: existing dual DeepSeek paths (App/LLM/DeepSeekProvider via LLMClient + App/DeepSeek/DeepSeekClient)
enum APICompatibility: Sendable {
    case anthropicCompatible   // reuses Anthropic transcript translation + SSE parser
    case openAICompatible      // uses DeepSeek-specific Chat Completions translation + parser
}

func respond(to transcript: Transcript, tools: [RuntimeToolDefinition],
             options: GenerationOptions, streamingInto channel: GenerationChannel) async throws {
    switch compatibility {
    case .anthropicCompatible:
        // Reuse most of AnthropicProvider's translation, but:
        // - Change baseURL to https://api.deepseek.com/anthropic
        // - Strip Anthropic beta headers (known DeepSeek pitfall)
        // - Strip cache_control markers (DeepSeek doesn't support prompt caching)
        try await streamAnthropicCompat(transcript, tools, options, channel)
    case .openAICompatible:
        // New implementation: Transcript -> ChatMessage[], SSE chunk -> SessionEvent
        // - Handle R1 reasoning_content as thinkingDelta
        // - Map stop reasons: "stop" -> endTurn, "tool_calls" -> toolUse
        try await streamOpenAICompat(transcript, tools, options, channel)
    }
}
```

### Pattern 5: SQLiteMemoryStore Schema Migration

**What:** The `SQLiteMemoryStore` maintains a `schema_version` table. On init, it checks the current version and applies sequential migrations (1->2, 2->3, etc.) within a transaction. Each migration is a private method.

**When to use:** SQLiteMemoryStore initialization.

**Example:**
```swift
// Source: standard SQLite migration pattern, mirrored in App/Storage/Database.swift
actor SQLiteMemoryStore: RuntimeMemoryStore {
    private let db: OpaquePointer  // SQLite3 connection handle

    func migrateIfNeeded() throws {
        let currentVersion = schemaVersion()
        let migrations: [(Int, String)] = [
            (1, "CREATE TABLE IF NOT EXISTS memory_entries (key TEXT, namespace TEXT, value BLOB, created_at REAL, updated_at REAL, metadata TEXT, PRIMARY KEY (key, namespace))"),
            (2, "CREATE INDEX IF NOT EXISTS idx_namespace ON memory_entries(namespace)"),
            (3, "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY)"),
        ]
        for (version, sql) in migrations where version > currentVersion {
            try execute(sql)
            try execute("INSERT OR REPLACE INTO schema_version VALUES (\(version))")
        }
    }
}
```

### Pattern 6: Permission Engine Adapter Bridge

**What:** A thin adapter struct that wraps the existing `PermissionEngine` and conforms to `RuntimePermissionEngine`. It maps `AgentPermission` cases to tool-name + input patterns that the existing permission pipeline understands.

**When to use:** RuntimePermissionEngine conformance. Existing PermissionEngine logic is preserved verbatim.

**Example:**
```swift
// Source: existing PermissionEngine.check(toolName:input:mode:context:) (Safety/PermissionEngine.swift)
//          + AgentPermission enum (Providers/AgentPermission.swift)
public struct AgentPermissionBridge: RuntimePermissionEngine, Sendable {
    private let engine: PermissionEngine
    private let mode: PermissionMode

    public func check(_ permission: AgentPermission) async throws -> Bool {
        switch permission {
        case .runCommands:
            // Map to existing permission check with dummy tool context
            let result = await engine.check(
                toolName: "Bash",
                input: [:],
                mode: mode,
                context: ToolUseContext.default
            )
            return result.decision == .allow
        case .readFiles(let paths):
            // Map to existing Read tool permission
            ...
        case .writeFiles(let paths):
            // Map to existing Write/Edit tool permission
            ...
        case .all:
            return true
        case .default, .plan:
            return mode == .plan || mode == .default
        default:
            // Contacts, calendar, location, camera, microphone, delete
            // These don't have existing permission rules -> deny by default
            return false
        }
    }
}
```

### Anti-Patterns to Avoid

- **Creating a parallel provider registry:** Do NOT create a new `ProviderRegistry` in Core. Providers are instantiated by consumers (CLI/App) and passed into `AgentRuntimeImpl.init(modelProvider:)`.
- **Exposing provider-internal types:** `AnthropicContentBlock`, `OpenAIStreamChunk`, SSE parsing logic, and any `StreamEvent` (old type) references must stay within `Providers/`. Grep for `StreamEvent` outside `Providers/` and `Types/` must return zero results after this phase.
- **Two separate DeepSeek types:** Do NOT create `DeepSeekAnthropicCompatProvider` + `DeepSeekOpenAICompatProvider`. Single `DeepSeekProvider` with internal switch.
- **Leaking URLSession configuration into the Runtime:** Each provider owns its `URLSession` instance. The Runtime never sees session configuration.
- **Hard-coding model lists in the App layer:** Model IDs and capabilities are declared in each provider's `capabilities` property. The App reads from `modelProvider.capabilities`, not from its own model list.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SQLite database access | Custom file-based key-value store | System SQLite3 module (already used by App/Storage/Database.swift) | SQLite provides ACID transactions, WAL mode, BLOB storage, and index support. A custom flat-file store would need to reimplement all of these. |
| HTTP streaming (SSE) | Custom socket-based SSE parser | `URLSession.shared.bytes(for:)` -> `AsyncBytes.lines` | Already battle-tested in LLMClient.swift. Handles HTTP/2, chunked encoding, connection reuse, and cancellation natively. |
| JSON streaming accumulation | Custom streaming JSON parser | `ContentBlockAccumulator` pattern from LLMStreamParser (preserved verbatim, adapted for SessionEvent output) | The existing accumulator already handles double-stringified JSON, mid-stream truncation, and provider-specific formatting. Rewriting would lose 18+ months of production bug fixes. |
| Retry with exponential backoff | Custom retry loop per provider | Existing `RetryPolicy.swift` logic (extracted and moved to AnthropicProvider) | Already handles 429/529 backoff, max retries, non-streaming fallback. Extract to shared internal utility. |
| Schema migration framework | Custom migration DSL | Sequential numbered SQL migrations in SQLiteMemoryStore | The MemoryStore protocol needs ~6 methods. A migration framework for 6 methods is overengineered. |
| API key resolution | Custom keychain access per provider | Existing `APIKeyResolver` (Core) + `KeychainStore` (App) | Already handles ANTHROPIC_API_KEY, ANTHROPIC_AUTH_TOKEN, ~/.claude.json resolution. |

**Key insight:** The Anthropic provider's most valuable IP is not the API call itself -- it's the accumulated edge-case handling in `ContentBlockAccumulator` (double-stringified JSON), `safeParseJSON`, the cache control breakpoint placement, and the 529/non-streaming fallback logic. Preserve these verbatim; wrap them with the new SessionEvent interface.

## Runtime State Inventory

> This phase involves absorbing existing implementations (LLMClient, LLMStreamParser, DeepSeekClient) and replacing stubs (OpenAIProvider). It also creates a new SQLite database file.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | Existing `MemoryStore` (Storage/MemoryStore.swift) stores files under `~/.claude/projects/<sanitized>/memory/` as `.md` files with YAML frontmatter. SQLiteMemoryStore creates a NEW database at `~/.swift-agent/memory.db` -- no migration from old file-based store needed (two stores coexist during transition). | None (new database, no migration from old store) |
| Live service config | `AnthropicProvider` (App) reads API key from `APIKeyResolver` (ANTHROPIC_API_KEY env, ANTHROPIC_AUTH_TOKEN env, ~/.claude.json). `DeepSeekProvider` (App) reads from DEEPSEEK_API_KEY env or KeychainStore. `DeepSeekClient` reads from DeepSeekConfig. `OpenAIProvider` (App stub) reads from OPENAI_API_KEY env. | Code edit -- Core providers will use same environment variable / keychain sources via existing resolution infrastructure |
| OS-registered state | None -- no launchd plists, pm2 processes, or Windows Task Scheduler entries reference agent runtime internals. Verified by: no system service registrations in the codebase. | None |
| Secrets/env vars | API keys stored in env vars (ANTHROPIC_API_KEY, DEEPSEEK_API_KEY, OPENAI_API_KEY) and Keychain. Key names do not change. Provider structs read same keys. | None (key names unchanged) |
| Build artifacts | No installed packages, no stale egg-info. Core target builds cleanly. No cached build artifacts reference old provider paths. | None |

**Nothing found in category:** OS-registered state (verified by grep for launchd, pm2, systemd in codebase = zero results). Build artifacts (no pip/npm/cargo packages involved).

## Common Pitfalls

### Pitfall 1: DeepSeek Beta Header Injection (Silent Failure)

**What goes wrong:** When using DeepSeek's Anthropic-compat endpoint (`/anthropic/v1/messages`), sending Anthropic-specific beta headers (e.g., `fine-grained-tool-streaming-2025-05-14`, `prompt-caching-2024-07-31`) causes DeepSeek to silently reject the streaming format and return `stop_reason=max_tokens` without producing content. The agent loop treats this as a normal completion and returns empty text.

**Why it happens:** The existing `LLMClient.applyClaudeCodeBetaHeader()` sets Anthropic beta headers unconditionally. When `LLMClient` is configured with `baseURL: "https://api.deepseek.com/anthropic"`, those headers go to DeepSeek's servers, which don't understand them.

**How to avoid:** In `DeepSeekProvider.anthropicCompatible` path, strip all `anthropic-beta` headers and cache_control markers before sending. Do NOT reuse `LLMClient` directly for DeepSeek Anthropic-compat -- the new `DeepSeekProvider` must control its own header construction.

**Warning signs:** Model returns empty text with `stop_reason: "max_tokens"` on first turn despite being well under the token limit.

**Reference:** PITFALLS.md Pitfall 3 (Leaky Abstraction), documented DeepSeek production failure mode.

### Pitfall 2: ContentBlockAccumulator Rewrite Loses Edge Cases

**What goes wrong:** The existing `ContentBlockAccumulator` in `LLMStreamParser.swift` handles: double-stringified JSON via `safeParseJSON()`, mid-stream truncation, provider-specific JSON formatting, and content block index tracking across streaming events. Rewriting or "simplifying" this for AnthropicProvider loses these edge cases.

**Why it happens:** The accumulator is the result of 18+ months of production debugging against real Anthropic API behavior. Simplifying it removes hard-won knowledge.

**How to avoid:** Extract `ContentBlockAccumulator`, `safeParseJSON`, `accumulateToolInput`, and `parseUsage` verbatim from `LLMStreamParser.swift` into `AnthropicProvider` as `internal` types. Change only the output wrapper: instead of producing `[ContentBlock]`, have it produce `SessionEvent` values (or an internal event type that maps to `SessionEvent`). Write regression tests that feed the accumulator known-tricky JSON payloads before removing the old code.

**Warning signs:** Any diff in tool input parsing between old (LLMClient) and new (AnthropicProvider) paths for identical SSE data.

**Reference:** PITFALLS.md Pitfall 7 (JSON Accumulator Rewrite).

### Pitfall 3: Snapshot vs Delta Semantics Mismatch

**What goes wrong:** The `SessionEvent.textDelta(String)` carries ACCUMULATED snapshots (replacement semantics), but SSE parsers receive INCREMENTAL deltas from the API. If the provider sends incremental deltas to `channel.send(textDelta:)`, consumers see only the last token, not the full text.

**Why it happens:** The `SessionEvent` documentation states: "The value is the COMPLETE text accumulated so far." The RuntimeGenerationChannel uses REPLACEMENT semantics: `accumulatedText = textDelta`. Providers must accumulate text internally and send the full accumulated string each time, not the incremental delta.

**How to avoid:** Each provider maintains an internal `accumulatedText: String` (or `accumulatedThinking: String`) variable. On each SSE text delta, append to the accumulator, then send the FULL accumulated string: `channel.send(textDelta: accumulatedText)`. Same for thinking/reasoning deltas.

**Warning signs:** Tests that expect multi-token responses but receive only the last token.

**Reference:** PITFALLS.md Pitfall 2 (Double-Render Bug), SessionEvent documentation header.

### Pitfall 4: OpenAI Tool Call Streaming is Multi-Chunk

**What goes wrong:** OpenAI streams tool calls across multiple SSE chunks: first chunk has `tool_calls[0].function.name`, subsequent chunks have `tool_calls[0].function.arguments` fragments. Sending `toolCallRequested` on the first chunk produces a tool call with no arguments. Waiting until `finish_reason` to send produces correct but delayed tool calls.

**Why it happens:** OpenAI's streaming format accumulates tool call arguments incrementally across chunks. The provider must buffer per-index tool call state and only emit `toolCallRequested` when the arguments JSON is complete (or when `finish_reason` signals completion).

**How to avoid:** Maintain a `[Int: ToolCallAccumulator]` dictionary keyed by tool call index. On each chunk, append arguments JSON fragments. When `finish_reason` is received (or the arguments string parses as valid complete JSON), emit `channel.send(toolCallRequest: id, name: name, input: parsedArguments)`. Use `safeParseJSON` to handle potential double-stringified arguments.

**Warning signs:** Tool calls with empty or truncated arguments in tests against the OpenAI API.

### Pitfall 5: The Three-Abstraction Trap Persists

**What goes wrong:** After Phase 3, the codebase has Core `LLMClient` (not yet removed until Phase 4 MIG-03), App `LLMProvider` protocol (not yet removed), AND the new `LanguageModelExecutor` providers. Developers write new code against the wrong abstraction.

**Why it happens:** Phase 3 adds new providers without removing old ones. The old types stay until Phase 4 shadow-mode validation is complete.

**How to avoid:** Every new provider file in `Sources/SwiftAgentCore/AgentRuntime/Providers/` should have a clear doc comment: "This is the post-migration provider. The legacy LLMClient/LLMProvider path is deprecated and will be removed in Phase 4." No new code in this phase should use `LLMClient`, `LLMProvider`, or `QueryEngine`. The `StreamEvent` (old) and `ContentBlock` (old) types must not appear in any new file.

**Warning signs:** Any new file that imports or references `LLMClient`, `LLMProvider`, or the old `StreamEvent` enum.

**Reference:** PITFALLS.md Pitfall 6 (Three-Abstraction-Layer Trap).

## Code Examples

Verified patterns from official sources and existing codebase:

### AnthropicProvider: Transcript Translation

```swift
// Source: LLMClient.swift Message.apiFormatted (existing codebase, adapted for Transcript.Entry)
// Verified: this pattern is already in production use via LLMClient
func translateTranscript(_ transcript: Transcript, systemPrompt: String?) -> (messages: [[String: Any]], system: Any?) {
    var messages: [[String: Any]] = []
    var role: String? = nil
    var contentBlocks: [[String: Any]] = []

    func flush() {
        guard let role, !contentBlocks.isEmpty else { return }
        messages.append(["role": role, "content": contentBlocks])
        contentBlocks = []
        self.role = nil
    }

    for entry in transcript.entries {
        switch entry {
        case .instruction(let text):
            // System prompt is handled separately, not in messages array
            break
        case .prompt(let text):
            flush()
            role = "user"
            contentBlocks.append(["type": "text", "text": text])
        case .response(let text):
            flush()
            role = "assistant"
            contentBlocks.append(["type": "text", "text": text])
        case .toolCall(let id, let name, let input):
            flush()
            role = "assistant"
            let parsed = try? JSONSerialization.jsonObject(with: input) as? [String: Any] ?? [:]
            contentBlocks.append(["type": "tool_use", "id": id, "name": name, "input": parsed])
        case .toolOutput(let id, let output, let isError):
            flush()
            role = "user"
            contentBlocks.append(["type": "tool_result", "tool_use_id": id, "content": output, "is_error": isError])
        case .thinking(let text):
            flush()
            role = "assistant"
            contentBlocks.append(["type": "thinking", "thinking": text])
        case .system(let text):
            flush()
            role = "user"
            contentBlocks.append(["type": "text", "text": text])
        }
    }
    flush()
    return (messages, systemPrompt)
}
```

### SSE Parsing Pattern (Anthropic, for SessionEvent)

```swift
// Source: LLMStreamParser.parse(data:) + LLMClient.streamRequest() (existing, adapted for GenerationChannel)
for try await line in bytes.lines {
    if Task.isCancelled { break }
    guard line.hasPrefix("data: ") else { continue }
    let jsonStr = String(line.dropFirst(6))
    guard let data = jsonStr.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let type = json["type"] as? String else { continue }

    switch type {
    case "content_block_delta":
        guard let delta = json["delta"] as? [String: Any] else { continue }
        if let text = delta["text"] as? String {
            accumulatedText += text
            await channel.send(textDelta: accumulatedText)
        } else if let thinking = delta["thinking"] as? String {
            accumulatedThinking += thinking
            await channel.send(thinkingDelta: accumulatedThinking)
        } else if let partialJSON = delta["partial_json"] as? String {
            // Accumulate per-index; emit toolCallRequested at content_block_stop
        }
    case "message_delta":
        let stopReason = (json["delta"] as? [String: Any])?["stop_reason"] as? String
        let usage = (json["usage"] as? [String: Any]).map { parseUsage($0) }
        await channel.complete(stopReason: stopReason, usage: usage)
    case "message_stop":
        break // Stream ends; loop breaks naturally
    case "error":
        let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
        await channel.fail(with: .serverError(statusCode: 0, body: msg))
    default:
        break
    }
}
```

### SQLiteMemoryStore: Store and Retrieve

```swift
// Source: SQLite3 C API pattern used in existing App/Storage/Database.swift
public func store<T: Codable & Sendable>(key: String, namespace: String, value: T) async throws {
    let data = try JSONEncoder().encode(value)
    let now = Date().timeIntervalSince1970
    let sql = """
        INSERT OR REPLACE INTO memory_entries (key, namespace, value, created_at, updated_at, metadata)
        VALUES (?, ?, ?, COALESCE((SELECT created_at FROM memory_entries WHERE key=? AND namespace=?), ?), ?, '{}')
        """
    // Bind parameters and step...
}

public func retrieve<T: Codable & Sendable>(key: String, namespace: String) async throws -> T? {
    let sql = "SELECT value FROM memory_entries WHERE key=? AND namespace=?"
    // Bind, step, decode from BLOB...
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `LLMClient` (1080 lines) monolithic Anthropic API client in Core/LLM/ | Absorbed into `AnthropicProvider` under Core/AgentRuntime/Providers/Anthropic/ | Phase 3 | All Anthropic-specific wire logic confined to one directory; LLMClient deprecated (removed in Phase 4) |
| `LLMStreamParser` (309 lines) standalone SSE parser | Becomes `AnthropicSSEParser` internal to AnthropicProvider | Phase 3 | SSE parsing is provider-internal; no other subsystem sees raw SSE events |
| Dual DeepSeek paths (LLMClient for Anthropic-compat + DeepSeekClient for OpenAI-compat) | Single `DeepSeekProvider` with internal `APICompatibility` switch | Phase 3 | One provider, one code path to maintain; both endpoints produce identical SessionEvent output |
| `OpenAIProvider` stub returning `OpenAIError.notImplemented` | Full Chat Completions SSE parser with function calling | Phase 3 | GPT-5.2, GPT-5.2-mini, o4 models available as first-class providers |
| `MemoryStore` (417 lines) file-based with YAML frontmatter | `SQLiteMemoryStore` with SQLite3, schema versioned | Phase 3 | Structured queries (search, summarize) replace file scanning; ACID transactions |
| `PermissionEngine` check(toolName:input:mode:context:) | `AgentPermissionBridge` adapter: `check(AgentPermission)` -> existing pipeline | Phase 3 | AgentPermission taxonomy maps to existing rule system; no permission logic rewritten |

**Deprecated/outdated:**
- `LLMClient` (Sources/SwiftAgentCore/LLM/LLMClient.swift): Internals absorbed into AnthropicProvider. Remains in place until Phase 4 removal.
- `LLMStreamParser` (Sources/SwiftAgentCore/LLM/LLMStreamParser.swift): ContentBlockAccumulator and parse logic moved to AnthropicProvider as internal types. Remains until Phase 4.
- Old `StreamEvent` enum (Sources/SwiftAgentCore/Types/StreamEvent.swift): Replaced by `SessionEvent` for new provider paths. Remains for legacy consumers until Phase 4.
- `DeepSeekClient` (Sources/SwiftAgentApp/DeepSeek/DeepSeekClient.swift): OpenAI-compat path absorbed into DeepSeekProvider. Remains until Phase 4.
- `OpenAIProvider` stub (Sources/SwiftAgentApp/LLM/OpenAIProvider.swift): Replaced by Core OpenAIProvider with real implementation.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | System SQLite3 module can be linked into SwiftAgentCore library target via `.linkedLibrary("sqlite3")` linker setting in Package.swift. | Standard Stack | If SPM library targets cannot link system sqlite3 this way, we need a `.systemLibrary` target wrapping sqlite3.h. Mitigation: existing `App/Storage/Database.swift` already uses `import SQLite3` successfully. |
| A2 | All three providers can be `Sendable` structs (not actors). URLSession is Sendable-safe in its default configuration. | Architecture Patterns | If URLSession or other state requires actor isolation, individual providers may need to become actors. Mitigation: LanguageModelExecutor protocol doesn't require Actor conformance. |
| A3 | The existing `RetryPolicy.swift` logic (DEFAULT_MAX_RETRIES=10, exponential backoff, 529 fallback) applies to Anthropic Provider without modification. | Don't Hand-Roll | If retry behavior differs for the new LanguageModelExecutor contract, adjustments needed. Mitigation: retry is internal to AnthropicProvider, testable independently. |
| A4 | The ContentBlockAccumulator and safeParseJSON from LLMStreamParser can be moved verbatim to AnthropicProvider without behavioral change. | Common Pitfalls | If the accumulator depends on types outside LLMStreamParser that also change, extra adaptation needed. Mitigation: extract the accumulator as a standalone internal type first, test it, then wrap. |
| A5 | DeepSeek's Anthropic-compat endpoint handles the same request shape as Anthropic's first-party API minus beta headers and cache_control. | DeepSeek Provider | If DeepSeek has additional quirks (different max_tokens behavior, different stop reasons), the AnthropicCompat path needs DeepSeek-specific adjustments. Mitigation: existing LLMClient(baseURL: "https://api.deepseek.com/anthropic") already works in production. |
| A6 | OpenAI's function calling can be mapped to SessionEvent toolCallRequested/toolCallCompleted without semantic loss. | OpenAI Provider | If OpenAI function calling has semantics that don't map cleanly (e.g., parallel tool calls with different lifecycle), the SessionEvent model may need extension. Mitigation: Phase 1 SessionEvent design already accounts for multi-tool-call turns. |

## Open Questions

1. **Should the `SQLiteMemoryStore` live in `SwiftAgentCore` or `SwiftAgentApp`?**
   - What we know: The `RuntimeMemoryStore` protocol is in Core. The existing `MemoryStore` (file-based) is in Core/Storage/. The existing `Database` (SQLite wrapper) is in App/Storage/.
   - What's unclear: Whether Core should have a dependency on SQLite3. Adding `linkedLibrary("sqlite3")` to Core is straightforward, but some module layouts are cleaner if SQLite-dependent code lives in a separate target.
   - Recommendation: Put SQLiteMemoryStore in Core with a `.linkedLibrary("sqlite3")` linker setting. This keeps the implementation with its protocol. The existing App/Storage/Database.swift can be deprecated later.

2. **How should the `LanguageModel` model identity work across providers?**
   - What we know: `LanguageModelCapabilities` has `providerDisplayName` but no `modelID` field. The Phase 1 design does not include model-specific identification in the capabilities struct. The existing AnthropicProvider has a list of `ModelInfo` with IDs like "claude-sonnet-4-6".
   - What's unclear: Whether the `LanguageModel` protocol needs a `modelID` property for the executor to know which model to call, or whether each provider instance is bound to a single model ID at construction time.
   - Recommendation: Each provider struct holds its model ID at construction time (e.g., `AnthropicProvider(modelID: "claude-sonnet-4-6", apiKey: ...)`). The `capabilities` property returns model-specific capabilities. The `modelID` is a stored property on the provider, not in `LanguageModelCapabilities`.

3. **Should the AnthropicProvider retain the CC-format request headers (x-stainless-*, anthropic-dangerous-direct-browser-access, metadata.user_id)?**
   - What we know: The current LLMClient sets these headers to match Claude Code's API client identification. They are required for API access with the current key format. Removing them may cause 401/403 errors.
   - What's unclear: Whether the new AnthropicProvider should present as "SwiftAgent" or maintain Claude Code compatibility.
   - Recommendation: Retain all existing headers and the `claudeCodeBillingHeaderBlock()` system prompt injection verbatim. This is an API compatibility concern, not an architectural one. Can be changed later with API key migration.

4. **How are provider-specific GenerationOptions handled (e.g., OpenAI `response_format`, Anthropic `thinking` budget)?**
   - What we know: `GenerationOptions` has `maxTokens`, `temperature`, `reasoningBudget`, and `stream` fields. These are provider-agnostic. The existing LLMClient.ts has Anthropic-specific thinking config (`adaptive`, `enabled(budget)`, `disabled`).
   - What's unclear: Whether additional provider-specific options need to thread through `GenerationOptions` or stay internal to each provider.
   - Recommendation: `GenerationOptions.reasoningBudget` maps to Anthropic `thinking.budget_tokens` and OpenAI `reasoning_effort`. Provider-specific options that have no cross-provider equivalent (e.g., Anthropic `output_config.effort`, OpenAI `response_format`) are configured at provider construction time, not per-request.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| SQLite3 (system) | SQLiteMemoryStore | Yes | 3.51.0 | -- (required for MEM-02) |
| macOS 15.0+ | All (Swift Concurrency, Foundation) | Yes | 25.5.0 | -- (minimum deployment target) |
| Swift 6.3 | Compilation | Yes | 6.3 | -- (required for Sendable, actors) |
| URLSession | All providers (HTTP streaming) | Yes | (system) | -- (required for API calls) |
| Network access (api.anthropic.com) | AnthropicProvider testing | Not checked | -- | Mock/provider-internal testing can verify parsing without live API |
| Network access (api.deepseek.com) | DeepSeekProvider testing | Not checked | -- | Mock/provider-internal testing can verify parsing without live API |
| Network access (api.openai.com) | OpenAIProvider testing | Not checked | -- | Mock/provider-internal testing can verify parsing without live API |

**Missing dependencies with no fallback:** None -- all dependencies are available.
**Missing dependencies with fallback:** Network access to provider APIs (not needed for unit testing -- SSE parsing can be tested with recorded/fixture data).

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | Yes | API keys stored in environment variables and Keychain. Never hard-coded in source. Existing `APIKeyResolver` and `KeychainStore` handle secure retrieval. |
| V3 Session Management | No | Session management is the agent loop (Phase 2), not provider-specific. |
| V4 Access Control | Yes | `AgentPermissionBridge` maps AgentPermission taxonomy to existing `PermissionEngine` rule system. Tool execution is gated. |
| V5 Input Validation | Yes | Each provider validates SSE input from the network before processing (JSON parsing, type checking). Tool inputs are validated before execution (existing `PermissionEngine` + `Tool` validation). |
| V6 Cryptography | No | No custom cryptography. API communication uses HTTPS (TLS) via URLSession. |
| V7 Error Handling | Yes | Provider errors mapped to `AgentRuntimeError` cases (rateLimited, unauthorized, serverError, timeout, invalidResponse). No raw error details leaked to consumers. |
| V8 Data Protection | Yes | `SQLiteMemoryStore` stores data at `~/.swift-agent/memory.db` with standard file system permissions. No additional encryption needed for agent memory (local-only). |

### Known Threat Patterns for Provider Implementations

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| API key logged in error messages or debug output | Information Disclosure | Provider structs store API key as `private let`; debug logging masks key values. Existing `DebugLogger` pattern from `LLMDebugLogger` applies. |
| SSE injection — malicious server sends crafted SSE events that trigger unexpected code paths | Tampering | Each SSE parser validates JSON structure before interpreting event types. Unknown event types are silently ignored (defense in depth). |
| Tool call argument injection — LLM hallucinates destructive tool inputs | Elevation of Privilege | All tool calls route through `PermissionEngine` before execution. AgentPermission taxonomy gates every capability category. This is a Runtime concern (Phase 2), not provider-specific. |
| SQL injection in MemoryStore search | Tampering | SQLiteMemoryStore uses parameterized queries (`?` bind parameters) for all SQL operations. Never string-interpolates user input into SQL. |
| Retry amplification — attacker triggers auth failures to cause exponential retry storms | Denial of Service | RetryPolicy caps max retries at 10 and distinguishes retryable errors (429, 529, 5xx) from non-retryable (401, 403). Exponential backoff with jitter. |
| API response parsing crash — malformed response causes force-unwrap to crash | Denial of Service | All JSON parsing uses `try?` or `do/catch`. Force-unwraps in parsing code are prohibited. SSE lines that fail to parse are silently skipped. |

## Sources

### Primary (HIGH confidence)
- [Codebase] `Sources/SwiftAgentCore/LLM/LLMClient.swift` (1080 lines) — existing Anthropic Messages API client with streaming, thinking, caching, retry, and fallback. All patterns to be absorbed into AnthropicProvider. [VERIFIED: codebase analysis]
- [Codebase] `Sources/SwiftAgentCore/LLM/LLMStreamParser.swift` (309 lines) — ContentBlockAccumulator, safeParseJSON, parseUsage. All to become AnthropicProvider internal types. [VERIFIED: codebase analysis]
- [Codebase] `Sources/SwiftAgentCore/AgentRuntime/Providers/` — LanguageModel, LanguageModelExecutor, GenerationChannel, AgentPermission, RuntimeMemoryStore protocols (Phase 1 output). Provider contract definitions. [VERIFIED: codebase analysis]
- [Codebase] `Sources/SwiftAgentCore/AgentRuntime/AgentRuntimeImpl.swift` (271 lines) — Agent loop that calls `modelProvider.makeExecutor()` and `executor.respond()`. Defines the exact calling pattern providers must support. [VERIFIED: codebase analysis]
- [Codebase] `Sources/SwiftAgentCore/AgentRuntime/SessionEvent.swift` — SessionEvent enum with snapshot semantics. Output target for all provider SSE parsers. [VERIFIED: codebase analysis]
- [Codebase] `Sources/SwiftAgentCore/AgentRuntime/RuntimeGenerationChannel.swift` — Concrete GenerationChannel actor. Defines the channel contract providers write to. [VERIFIED: codebase analysis]
- [Codebase] `Sources/SwiftAgentCore/Safety/PermissionEngine.swift` (315 lines) — Existing permission pipeline to bridge to AgentPermission taxonomy. [VERIFIED: codebase analysis]
- [Codebase] `Sources/SwiftAgentApp/Storage/Database.swift` — Existing SQLite3 usage pattern (system module, WAL mode, NSLock serialization). Reference for SQLiteMemoryStore design. [VERIFIED: codebase analysis]
- [Codebase] `.planning/research/PITFALLS.md` — 13 documented pitfalls, 6 relevant to Phase 3 (Pitfalls 2, 3, 6, 7, 8, 13). [VERIFIED: codebase analysis]

### Secondary (MEDIUM confidence)
- [Documentation] Anthropic Messages API: `https://docs.anthropic.com/en/api/messages` — SSE event format, content block types, thinking/cache control. [CITED: docs.anthropic.com]
- [Documentation] OpenAI Chat Completions API: `https://platform.openai.com/docs/api-reference/chat` — SSE streaming format, function calling, finish_reason. [CITED: platform.openai.com]
- [Documentation] DeepSeek API: `https://api-docs.deepseek.com/` — Anthropic-compat and OpenAI-compat endpoints, R1 reasoning tokens. [CITED: api-docs.deepseek.com]
- [Codebase] `Sources/SwiftAgentApp/LLM/AnthropicProvider.swift` (104 lines) — existing App-level Anthropic wrapper over LLMClient. [VERIFIED: codebase analysis]
- [Codebase] `Sources/SwiftAgentApp/LLM/DeepSeekProvider.swift` (110 lines) — existing App-level DeepSeek wrapper (Anthropic-compat path only). [VERIFIED: codebase analysis]
- [Codebase] `Sources/SwiftAgentApp/DeepSeek/DeepSeekClient.swift` (299 lines) — existing standalone DeepSeek OpenAI-compat client. [VERIFIED: codebase analysis]
- [Codebase] `Sources/SwiftAgentApp/LLM/OpenAIProvider.swift` (115 lines) — current stub returning notImplemented error. [VERIFIED: codebase analysis]
- [Codebase] `Tests/SwiftAgentCoreTests/MockProviders.swift` (158 lines) — MockLanguageModel, MockLanguageModelExecutor, MockMemoryStore, MockPermissionEngine. Reference for test patterns. [VERIFIED: codebase analysis]

### Tertiary (LOW confidence)
- [ASSUMED] SQLite3 system module linking via `.linkedLibrary("sqlite3")` in SPM library target works identically to executable target. [ASSUMED]
- [ASSUMED] DeepSeek's Anthropic-compat endpoint behavior matches Anthropic's first-party API except for beta headers and cache_control (based on existing LLMClient configuration at `https://api.deepseek.com/anthropic`). [ASSUMED]
- [ASSUMED] OpenAI o4 model's `reasoning_tokens` content can be surfaced as SessionEvent.thinkingDelta (based on OpenAI's documented reasoning support). [ASSUMED]

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — No external packages needed. All dependencies are system-provided (Foundation, SQLite3). Verified against existing codebase usage.
- Architecture: HIGH — Provider contract (LanguageModelExecutor, GenerationChannel, SessionEvent) is well-defined from Phase 1. Agent loop calling pattern is verified from Phase 2 AgentRuntimeImpl. Provider-internal isolation pattern is verified from PITFALLS.md and existing codebase.
- Pitfalls: HIGH — 6 Phase 3-relevant pitfalls documented in PITFALLS.md. SSE parsing, snapshot semantics, DeepSeek headers, accumulator preservation all verified against existing codebase.

**Research date:** 2026-06-25
**Valid until:** 2026-07-25 (stable API contracts from Phase 1; Anthropic/OpenAI/DeepSeek API changes are the primary risk)

**What might I have missed:**
- The exact mapping of OpenAI's `response_format` (structured output) to the AgentRuntime's `GenerationSchema` / `PartiallyGenerated<T>` system. Phase 2 defined the snapshot streaming contract; how OpenAI's `json_schema` mode interacts with it is unexplored.
- The impact of moving `LLMClient` internals on the existing `QueryEngine` path (which still uses `LLMClient` directly until Phase 4). The `LLMClient` source must be copied/moved, not deleted -- the old file stays until MIG-03.
- Whether the App-level `LLMProvider` protocol (with `stream(messages:model:systemPrompt:maxTokens:tools:thinking:)`) needs an adapter during the transition period, or if CLI/App consumers can be switched to AgentRuntime directly in Phase 4.
