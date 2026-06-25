# Phase 4: Migration, Wiring & Cleanup - Research

**Researched:** 2026-06-25
**Domain:** Swift codebase migration -- tool protocol refactoring, consumer rewiring, deprecated type removal
**Confidence:** HIGH

## Summary

Phase 4 is the capstone migration phase: 63 tools adopt the simplified `RuntimeAgentTool` protocol, CLI `ChatCommand` and App `ThreadViewModel` wire to `LanguageModelSessionImpl`, and all deprecated types from the pre-FoundationModels architecture are removed. The codebase is fully understood -- every tool, every consumer, every deprecated type dependency has been mapped.

The old architecture builds the agent loop manually: `QueryEngine` calls `LLMClient.send()` producing raw `StreamEvent` SSE events; the consumer parses `inputJSONDelta` tokens into accumulated tool input JSON; `contentBlockStop` signals tool calls ready for execution via `ToolExecutor`. The new architecture inverts this: `LanguageModelSessionImpl.streamResponse(to:)` returns an `AsyncThrowingStream<SessionEvent>` where tool calls arrive as fully-parsed `toolCallRequested(id:name:input:)` events; the agent loop (re-prompt on tool calls) runs inside the session actor. Consumers iterate `SessionEvent` values -- no JSON accumulation, no SSE parsing, no re-prompt loop.

ToolUseContext is the largest dependency: 63 tools accept it via `call(input:context:...)`. However, actual field access is highly selective -- only ~12 of 70+ fields are used by tools. The majority of tool-specific fields (`abortSignal`, `setStreamMode`, `onCompactProgress`, etc.) are never accessed by any tool and exist solely for future expansion. The migration strategy is to capture only used fields as `let` properties on each tool at construction time (D-03).

**Primary recommendation:** Execute in strict dependency order: migrate read-only tools first (batch 1), validate, delete old Tool protocol and ToolUseContext (forcing remaining tools to migrate), then wire CLI consumer, then App consumer, then remove deprecated types as each consumer migrates. Each batch is independently testable and the hard-cutover approach (no feature flags per D-08) means old code is gone before new code is written in its place.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Tool protocol definition | Core | -- | RuntimeAgentTool lives in AgentRuntime/Tools/ |
| Tool execution | Core (ToolEngine) | -- | execute(name:input:) routes via ToolEngine, not ToolExecutor |
| Agent loop (re-prompt) | Core (LanguageModelSessionImpl) | -- | Loop lives inside the actor, not in consumers |
| Stream consumption | CLI / App | -- | Consumers iterate SessionEvent, don't manage loops |
| Permission gating | Core (PermissionEngine) | -- | executeTool() checks `.runCommands` before every call |
| Working directory / context | Consumer → Tool constr | -- | Injected at tool init time as `let` properties |
| MCP client routing | Core (MCPBootstrapper → DynamicMCPTool) | -- | Tool captures serverName/toolName at init |
| Memory persistence | Core (SQLiteMemoryStore) | -- | Stores Transcript entries after each turn |
| CLI rendering (tool cards, spinners) | CLI | -- | Fresh rendering for SessionEvent, not adapted from StreamRenderer |
| App message display (NSTableView) | App | -- | SessionEvent bridged to ChatBridge/AgentMessage |

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MIG-01 | Migrate all 60+ tools to simplified Tool protocol | Section: Tool Migration Patterns -- 63 tools catalogued, categories defined, migration template documented |
| MIG-02 | Wire CLI ChatCommand and App ThreadViewModel | Section: Consumer Wiring -- old API surface mapped, SessionEvent rendering gap analyzed, touchpoints identified |
| MIG-03 | Remove deprecated types | Section: Deprecated Type Dependency Graph -- blast radius calculated per type, safe removal order established |
| MIG-04 | All 258+ existing tests pass | Section: Test Impact -- 7 test files with direct deprecated type references, test migration strategy defined |
| MIG-05 | MessageNormalizer adaptation | Section: MessageNormalizer Analysis -- 17 passes documented, provider-internal normalization confirmed |

## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Batch by category -- 4-5 batches grouped by tool function (read-only tools, file mutation, task/agent, MCP, etc.). Each batch independently testable.
- **D-02:** Hard cutover per batch -- rewrite tools directly to `RuntimeAgentTool`. No adapter shims, no dual protocol conformance.
- **D-03:** Inject session context via tool init -- tools that need working directory, permission mode, etc. capture them as `let` properties at construction time.
- **D-04:** Move migrated tools to `Sources/SwiftAgentCore/AgentRuntime/Tools/`. New architecture, new location.
- **D-05:** First batch = read-only tools (FileRead, Glob, Grep, WebSearch, WebFetch). Validate pattern before touching destructive tools.
- **D-06:** Delete old `Tool` protocol + `ToolUseContext` (Types/Tool.swift, 1164 lines) after first batch validates. Remaining tools MUST migrate -- no dual maintenance.
- **D-07:** Align naming with Apple FoundationModels: `Input` -> `Arguments`, `call(_ input:)` -> `call(arguments:)`. Breaking change with zero consumers -- rename now.
- **D-08:** Direct replacement -- no feature flag (`AGENT_RUNTIME_ENABLED`), no shadow mode. `QueryEngine` + `LLMClient` replaced directly with `LanguageModelSessionImpl`.
- **D-09:** CLI uses `streamResponse(to:)` -- `ChatCommand` consumes `SessionEvent` values progressively. The agent loop (re-prompt on tool calls) is handled internally by `LanguageModelSessionImpl`.
- **D-10:** Rewrite CLI rendering fresh for `SessionEvent`. Do not adapt old `StreamRenderer`/`StatusLine` -- build new rendering layer.
- **D-11:** App `ThreadViewModel` uses same `streamResponse(to:)` pattern, bridging `SessionEvent` to `ChatBridge`/`NSTableView`.
- **D-12:** Remove as wiring completes -- incremental and verifiable. CLI wired -> delete `LLMClient`, `QueryEngine`, `LLMStreamParser`. App wired -> delete `DeepSeekClient`, `ProviderRegistry`. Last tool migrated -> delete old `Tool` protocol + `ToolUseContext`.
- **D-13:** Delete App-side providers entirely -- `Sources/SwiftAgentApp/LLM/` and `Sources/SwiftAgentApp/DeepSeek/`. Replaced by `AgentRuntime/Providers/` (AnthropicProvider, DeepSeekProvider, OpenAIProvider).
- **D-14:** Delete old Storage/ layer -- file-based `SwiftAgentStore`, `SessionStore`, `MemoryStore` replaced by `SQLiteMemoryStore` implementing `SessionMemoryStore`.
- **D-15:** Rewrite as `TranscriptNormalizer` -- new file, clean design. Do not adapt old `MessageNormalizer` (848 lines).
- **D-16:** Rethink normalization passes from scratch -- design for `Transcript` + `SessionEvent` pipeline, not porting old 17 passes.
- **D-17:** Normalization lives inside each provider -- provider-specific `Transcript` -> API wire format translation. Matches FoundationModels' `LanguageModelExecutor` pattern. No shared pre-processing pipeline.

### Claude's Discretion
- Exact batch composition (which specific tools in each batch)
- Final tool protocol name after old protocol removal (e.g., rename `RuntimeAgentTool` -> `Tool`)
- Rendering implementation details for CLI and App
- Exact normalization logic per provider
- TranscriptNormalizer design and pass selection

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.

## Standard Stack

### Core (Already Built -- Phase 1-3)

| Library | Location | Purpose | Status |
|---------|----------|---------|--------|
| `RuntimeAgentTool` protocol | `AgentRuntime/Tools/RuntimeAgentTool.swift` | New tool contract (~6 members) | Built |
| `LanguageModelSessionImpl` | `AgentRuntime/AgentRuntimeImpl.swift` | Actor agent loop with reentrancy guard | Built |
| `SessionEvent` enum | `AgentRuntime/SessionEvent.swift` | Provider-agnostic streaming events | Built |
| `ToolEngine` protocol | `AgentRuntime/AgentRuntime.swift` | Tool registry + execution interface | Built |
| `LanguageModelExecutor` protocol | `AgentRuntime/Providers/LanguageModelExecutor.swift` | Provider backend contract | Built |
| `AnthropicProvider` | `AgentRuntime/Providers/Anthropic/` | Anthropic API executor | Built |
| `DeepSeekProvider` | `AgentRuntime/Providers/DeepSeek/` | DeepSeek unified executor | Built |
| `OpenAIProvider` | `AgentRuntime/Providers/OpenAI/` | OpenAI executor | Built |
| `SQLiteMemoryStore` | `AgentRuntime/Providers/Memory/SQLiteMemoryStore.swift` | Persistent memory (replaces Storage/) | Built |
| `ToolMetadata` struct | `AgentRuntime/Tools/` | Per-tool operational data | Built |
| `ToolOutputValue` enum | `AgentRuntime/Types/` | Output type replacing ToolResult | Built |
| `Transcript` struct | `AgentRuntime/Transcript.swift` | Canonical conversation history | Built |

### Supporting (Shared/Reused)

| Type | Location | Purpose | Migration Note |
|------|----------|---------|----------------|
| `JSONSchema` | `Types/Tool.swift` (line 401) | Input schema type | Used by both old and new protocols. Keep in Types/ after old protocol removal, or move to AgentRuntime/Types/. |
| `JSONValue` | `Types/InputTypes.swift` | JSON value enum | Used pervasively. No change needed. |
| `JSONSchemaProperty` | `Types/Tool.swift` (line 509) | Schema property descriptor | Same fate as JSONSchema -- relocate if old file deleted. |
| `PermissionMode` | `Types/Permission.swift` | Permission taxonomy | Used by both old and new code. Keep. |
| `InterruptBehavior` | `Types/Tool.swift` | Tool interrupt behavior | Referenced by Tool protocol defaults only. Check if new protocol needs it. |
| `SearchOrReadResult` | `Types/Tool.swift` | UI classification | Used by CLI rendering for collapse detection. May need in new rendering. |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Direct replacement (D-08) | Feature flag + shadow mode | CONTEXT.md explicitly overrides -- no feature flags |
| Adapter shims for tools | Write dual-protocol conformance | D-02 explicitly forbids -- hard cutover only |
| Adapt old StreamRenderer | Build new SessionEvent renderer | D-10 explicitly requires fresh rendering |
| Port old MessageNormalizer | Provider-internal TranscriptNormalizer | D-15/D-17 require rewrite from scratch |

### What Gets Deleted (Not Replaced)

| Old Code | Lines | Delete When | Replacement |
|----------|-------|-------------|-------------|
| `Types/Tool.swift` (old Tool protocol, ToolUseContext) | 1164 | After batch 1 validates | RuntimeAgentTool + let-property context |
| `Agent/QueryEngine.swift` | ~630 | After CLI wired | LanguageModelSessionImpl |
| `LLM/LLMClient.swift` | ~1079 | After CLI wired | AnthropicProvider (in AgentRuntime) |
| `LLM/LLMStreamParser.swift` | ~500 est | After CLI wired | Provider-internal SSE parsers |
| `Agent/MessageNormalizer.swift` | 848 | After App wired | Per-provider TranscriptNormalizer |
| `Agent/StreamRenderer.swift` | ~200 est | After CLI rewired | New SessionEvent renderer |
| `Storage/` (8 files) | 1624 | After App wired | SQLiteMemoryStore |
| `App/LLM/` (5 files) | TBD | After App wired | AgentRuntime/Providers/ |
| `App/DeepSeek/` (4 files) | TBD | After App wired | AgentRuntime/Providers/DeepSeek/ |
| `App/Agent/AgentSessionManager.swift` | ~400 est | After App wired | LanguageModelSessionImpl |
| `App/Agent/AppAgentProvider.swift` | TBD | After App wired | Direct provider construction |
| `App/Agent/AgentMessages.swift` | TBD | After App wired | SessionEvent -> AgentMessage bridge |
| `Agent/Compactor.swift` | TBD | After wiring complete | Transcript-based compaction (or defer) |
| `Agent/SubAgentManager.swift` | TBD | After AgentTool migrated | AgentTool uses session directly |
| `Agent/ToolExecutor.swift` | TBD | After tools migrated | ToolEngine.execute() |
| `LLM/RetryPolicy.swift` | TBD | After CLI wired | Provider-internal retry |
| `LLM/SortedJSON.swift` | TBD | After CLI wired | Provider-internal JSON handling |

**Total lines to delete: ~7,500+**

**Installation:** No external packages required. This is a pure codebase migration using only built Swift types and existing FoundationModels-aligned runtime.

**Version verification:** N/A -- all dependencies are project-internal Swift modules. No external packages are installed in this phase.

## Package Legitimacy Audit

> No external packages are installed in this phase. All work uses existing project-internal Swift types and the FoundationModels-aligned AgentRuntime built in Phases 1-3.

## Architecture Patterns

### System Architecture Diagram

```
USER INPUT
    |
    v
CLI (ChatCommand)                    App (ThreadViewModel)
    |                                     |
    | session.streamResponse(to:)         | session.streamResponse(to:)
    v                                     v
+----------------------------------------------------+
|         LanguageModelSessionImpl (actor)            |
|                                                    |
|  streamResponse(to:) -> ResponseStream             |
|    |                                               |
|    | [agent loop internal]                         |
|    |  1. Append prompt to Transcript               |
|    |  2. Call modelProvider.makeExecutor()          |
|    |  3. Executor.respond() -> GenerationChannel   |
|    |  4. Yield SessionEvent to consumer            |
|    |  5. If tool calls:                            |
|    |     a. executeTool() via ToolEngine            |
|    |     b. Append to Transcript                   |
|    |     c. Yield .toolCallCompleted               |
|    |     d. Goto 2 (re-prompt)                     |
|    |  6. Store transcript in SQLiteMemoryStore     |
|    |  7. Finish stream                             |
|    |                                               |
|    +-- ToolEngine.execute(name:input:)             |
|    |     |                                         |
|    |     v                                         |
|    |   Registered RuntimeAgentTool instances       |
|    |   (constructed with let context properties)   |
|    |                                               |
|    +-- PermissionEngine.check(.runCommands)        |
|    +-- ModelProvider.makeExecutor()                |
|          |                                         |
|          v                                         |
|    +------------------------------------------------+
|    | Provider Executors (internal)                  |
|    |  - AnthropicProvider: Transcript -> Anthropic  |
|    |    API, SSE parse -> SessionEvent              |
|    |  - DeepSeekProvider: Transcript -> API compat  |
|    |  - OpenAIProvider: Transcript -> OpenAI API    |
|    |                                                |
|    | Each owns: wire format, SSE parsing,           |
|    | Transcript translation, normalization          |
|    +------------------------------------------------+
+----------------------------------------------------+
```

### Recommended Project Structure (After Migration)

```
Sources/SwiftAgentCore/
├── AgentRuntime/
│   ├── Tools/                          # NEW: migrated tools live here
│   │   ├── RuntimeAgentTool.swift      # Tool protocol (~6 members)
│   │   ├── FileReadTool.swift          # Batch 1: read-only
│   │   ├── GrepTool.swift
│   │   ├── GlobTool.swift
│   │   ├── WebSearchTool.swift
│   │   ├── WebFetchTool.swift
│   │   ├── FileWriteTool.swift         # Batch 2: file mutation
│   │   ├── FileEditTool.swift
│   │   ├── BashTool.swift              # Batch 3: commands
│   │   ├── ...
│   │   └── AgentTool.swift             # Batch 4: task/agent
│   ├── AgentRuntime.swift              # LanguageModelSession protocol
│   ├── AgentRuntimeImpl.swift          # LanguageModelSessionImpl actor
│   ├── SessionEvent.swift              # Provider-agnostic events
│   └── Providers/                      # Model, Memory, Permission providers
├── Types/                              # Shared domain types (trimmed)
│   ├── JSONSchema.swift                # Extracted from Tool.swift
│   ├── JSONValue.swift (InputTypes.swift)
│   ├── Permission.swift
│   └── ...
├── Tools/                              # DELETED (migrated to AgentRuntime/Tools/)
├── Agent/                              # DELETED (except files not dependent on old types)
├── LLM/                                # DELETED entirely
├── Storage/                            # DELETED entirely
└── ...
```

### Pattern 1: Tool Migration Template

**What:** Convert an old `Tool` conformer to `RuntimeAgentTool` by creating a typed `Input` struct, capturing needed context fields at init time, and implementing the 5-method protocol.

**Source:** Verified against existing `RuntimeAgentTool.swift` protocol (AgentRuntime/Tools/RuntimeAgentTool.swift, lines 18-35) and sample old tool `FileReadTool.swift` (Tools/FileReadTool.swift, 492 lines).

**When to use:** Every tool migration. Standardize across all 63 tools.

**Example:**
```swift
// NEW: Sources/SwiftAgentCore/AgentRuntime/Tools/FileReadTool.swift
import Foundation

/// Reads a file from the local filesystem.
public struct FileReadTool: RuntimeAgentTool {
    // Context captured at init time (D-03)
    private let workingDirectory: String

    public init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    // MARK: - RuntimeAgentTool

    public var name: String { "Read" }
    public var description: String {
        "Reads a file from the local filesystem. Supports text, images, PDFs, and Jupyter notebooks."
    }

    // Typed input replaces [String: JSONValue] dictionary
    public struct Arguments: Codable, Sendable {
        var filePath: String
        var offset: Int?
        var limit: Int?
        var pages: String?

        enum CodingKeys: String, CodingKey {
            case filePath = "file_path"
            case offset, limit, pages
        }
    }

    public var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: [
            "file_path": JSONSchemaProperty(type: "string",
                description: "The absolute path to the file to read"),
            "offset": JSONSchemaProperty(type: "number",
                description: "The line number to start reading from."),
            "limit": JSONSchemaProperty(type: "number",
                description: "The number of lines to read."),
            "pages": JSONSchemaProperty(type: "string",
                description: "Page range for PDF files."),
        ], required: ["file_path"])
    }

    public func call(arguments: Arguments) async throws -> ToolOutputValue {
        // Use self.workingDirectory for path resolution
        // ... tool logic ...
        return .string(content)
    }
}
```

**Key differences from old pattern:**
1. `Arguments` struct replaces `[String: JSONValue]` -- typed, Codable, Sendable
2. `call(arguments:)` replaces `call(input:context:canUseTool:parentMessage:onProgress:)`
3. Context fields (`workingDirectory`, `sessionID`, `shell`, etc.) captured as `let` at init
4. Return type `ToolOutputValue` replaces `ToolResult`
5. No `validateInput()`, `checkPermissions()` -- these are ToolEngine/ToolMetadata responsibilities
6. No `prompt()`, `userFacingName()`, `getPath()`, etc. -- moved to ToolMetadata or removed
7. File moves from `Tools/` to `AgentRuntime/Tools/`

### Pattern 2: Consumer Wiring Template (CLI)

**What:** Replace the manual agent loop in ChatCommand with `session.streamResponse(to:)`.

**Source:** Verified against `LanguageModelSessionImpl.streamResponse(to:)` (AgentRuntimeImpl.swift, lines 190-273) and current ChatCommand agent loop (ChatCommand.swift, lines 548-816).

**When to use:** After batch 1 tool migration validates and old Tool protocol is deleted.

**Key change -- old loop:**
```swift
// OLD: ChatCommand manually manages streaming, tool input accumulation,
// tool execution, and re-prompt loop (~270 lines of loop code).
while true {
    let stream = client.send(messages: conversationHistory, ...)
    for try await event in stream {
        switch event {
        case .textDelta(let text): ...
        case .inputJSONDelta(let delta): toolInputAccumulator.append(delta)
        case .contentBlockStop: toolInputAccumulator.stopCurrentBlock()
        // ... 10+ more cases
        }
    }
    let toolBlocks = toolInputAccumulator.parsedCalls
    // execute tools, build result blocks, append to history, loop or break
}
```

**Key change -- new loop:**
```swift
// NEW: LanguageModelSessionImpl handles the agent loop internally.
// Consumer only iterates SessionEvent for rendering.
let session = LanguageModelSessionImpl(
    modelProvider: provider,
    memoryStore: SQLiteMemoryStore(...),
    permissionEngine: bridge,
    toolEngine: engine
)
// Register tools with metadata
for tool in tools { await engine.register(tool: tool, metadata: ...) }

let stream = await session.streamResponse(to: userInput)
for try await event in stream {
    switch event {
    case .textDelta(let text): renderText(text)
    case .thinkingDelta(let text): renderThinking(text)
    case .toolCallRequested(let id, let name, let input):
        renderToolStarted(id: id, name: name)
    case .toolCallCompleted(let id, let output, let isError):
        renderToolCompleted(id: id, output: output, isError: isError)
    case .turnCompleted(let usage, let stopReason):
        renderTurnDone(usage: usage, stopReason: stopReason)
    case .error(let err): renderError(err)
    }
}
```

**Rendering gap analysis (SessionEvent vs old StreamEvent):**

| Old Rendering (ChatCommand) | New Event | Rendering Needed |
|---------------------------|-----------|-----------------|
| `.textDelta` -> print text | `.textDelta(text)` | Same -- print text directly |
| `.thinkingDelta` -> dimmed print | `.thinkingDelta(text)` | Same -- dimmed print |
| `.contentBlockStart(.toolUse)` -> spinner | `.toolCallRequested` | Start spinner/status |
| `.inputJSONDelta` -> "." dots | (none -- handled internally) | No consumer rendering |
| `.contentBlockStop` -> clear spinner | `.toolCallCompleted` | Clear spinner, show result |
| `.messageDelta` -> print usage/stop | `.turnCompleted(usage, stopReason)` | Print usage/stats |
| Manual `executeTool()` -> emit collapsed result | (done by agent loop) | No consumer execution |
| `.ping` -> nothing | (no ping in SessionEvent) | N/A |
| `.error` -> print error | `.error(AgentRuntimeError)` | Print error |

### Pattern 3: App Consumer Wiring Template

**What:** Replace `AgentSessionManager.run()` with `LanguageModelSessionImpl.streamResponse(to:)`.

**Source:** Verified against `ThreadViewModel.send()` (ThreadViewModel.swift, lines 251-393) and `AgentSessionManager.run()` (AgentSessionManager.swift, lines 270-330).

**Key change -- old path:**
```
ThreadViewModel.send(userText:)
  -> AgentSessionManager.run(userInput:conversation:...)
    -> QueryEngine.run()
      -> LLMClient.send()
      -> ToolExecutor.execute()
    -> onEvent(StreamingQueryEvent) callback
  -> handleStreamEvent() -> update AgentMessage blocks
  -> handleRunResult() -> finalize
```

**Key change -- new path:**
```
ThreadViewModel.send(userText:)
  -> LanguageModelSessionImpl.streamResponse(to: userText)
    -> AsyncThrowingStream<SessionEvent>
  -> for await event: update AgentMessage via ChatBridge
  -> stream.onTermination: finalize
```

**App-specific concerns:**
- `AgentSessionManager` is `@MainActor ObservableObject` -- `LanguageModelSessionImpl` is an actor. The App must hold the session as a property (constructed at app launch) and call `streamResponse(to:)` from within a Task.
- `StreamingQueryEvent` has `.assistantTextStreaming` and `.modelStreaming` lifecycle events -- `SessionEvent` has no equivalent. App rendering must adapt.
- `RunResult` (text, turns, toolCalls, tokenUsage) is the old return type -- new code uses `Transcript` (returned via `.turnCompleted` or by reading `session.memoryStore` after stream ends).
- Message queuing and cancellation patterns (`messageQueue`, `streamingTask?.cancel()`) remain valid -- they operate at the consumer level, not inside the agent loop.

### Anti-Patterns to Avoid
- **Dual protocol conformance:** Do NOT make a tool conform to both old `Tool` and new `RuntimeAgentTool`. D-02 explicitly forbids.
- **Adapter/wrapper around ToolUseContext:** Do NOT create a `ToolUseContext` adapter that wraps `LanguageModelSessionImpl`. D-03 requires context injection at tool init.
- **Porting old rendering code:** Do NOT adapt `StreamRenderer` or `StatusLine` for SessionEvent. D-10 requires fresh rendering.
- **Feature flags or shadow mode:** Do NOT implement `AGENT_RUNTIME_ENABLED` flag. D-08 mandates direct replacement.
- **Partial removal of old protocol:** Do NOT delete `Tool` protocol without migrating all tools. D-06 says delete after batch 1, which FORCES remaining tools to migrate (not optional).
- **Shared normalizer:** Do NOT create a shared TranscriptNormalizer. D-17 requires normalization inside each provider.

## Tool Migration Patterns

### Tool Inventory (63 tools, categorized)

All tools are in `Sources/SwiftAgentCore/Tools/`. They all conform to the old `Tool` protocol and use `ToolUseContext`. Below is the complete inventory with proposed batch assignments.

**Batch 1: Read-Only Tools (~15 tools)**
Source-verified from `isReadOnly: Bool` declarations and tool behavior analysis.

| Tool | File | Lines | isReadOnly | Context Fields Used |
|------|------|-------|------------|---------------------|
| FileReadTool | FileReadTool.swift | 492 | true | workingDirectory |
| GrepTool | GrepTool.swift | 692 | true | workingDirectory |
| GlobTool | GlobTool.swift | 204 | true | workingDirectory |
| WebSearchTool | WebSearchTool.swift | 114 | true | (none -- network-only) |
| WebFetchTool | WebFetchTool.swift | 147 | true | (none -- network-only) |
| ListSkillsTool | ListSkillsTool.swift | 88 | true | workingDirectory |
| ToolSearchTool | ToolSearchTool.swift | 234 | true | tools |
| ListMcpResourcesTool | ListMcpResourcesTool.swift | 50 | true | mcpClients |
| ReadMcpResourceTool | ReadMcpResourceTool.swift | 55 | true | mcpClients |
| CtxInspectTool | CtxInspectTool.swift | 23 | true | (none) |
| ListPeersTool | ListPeersTool.swift | 23 | true | (none) |
| BriefTool | BriefTool.swift | 39 | true | (none) |
| TaskGetTool | TaskGetTool.swift | 45 | true | (none -- reads task state) |
| TaskListTool | TaskListTool.swift | 42 | true | (none -- reads task state) |
| BundledSkills | BundledSkills.swift | 191 | true | (none -- static data) |

**Batch 2: File Mutation Tools (~4 tools)**

| Tool | File | Lines | isReadOnly | Context Fields Used |
|------|------|-------|------------|---------------------|
| FileWriteTool | FileWriteTool.swift | 124 | false | workingDirectory (implicit via path resolution) |
| FileEditTool | FileEditTool.swift | 211 | false | workingDirectory |
| NotebookEditTool | NotebookEditTool.swift | 210 | false | (none apparent) |
| SnipTool | SnipTool.swift | 26 | false | (none apparent) |

**Batch 3: Command Execution Tools (~5 tools)**

| Tool | File | Lines | isReadOnly | Context Fields Used |
|------|------|-------|------------|---------------------|
| BashTool | BashTool.swift | 597 | false | workingDirectory, shell |
| LSPTool | LSPTool.swift | 378 | false | workingDirectory |
| PowerShellTool | PowerShellTool.swift | 47 | false | (none apparent) |
| TerminalCaptureTool | TerminalCaptureTool.swift | 25 | false | (none apparent) |
| TungstenTool | TungstenTool.swift | 25 | false | (none apparent) |

**Batch 4: Task/Agent/Workflow Tools (~20 tools)**

| Tool | File | Lines | isReadOnly | Context Fields Used |
|------|------|-------|------------|---------------------|
| AgentTool | AgentTool.swift | 289 | false | sessionID, workingDirectory, mode, mainLoopModel, toolUseID |
| TaskCreateTool | TaskCreateTool.swift | 38 | false | (none -- task manager only) |
| TaskUpdateTool | TaskUpdateTool.swift | 55 | false | (none) |
| TaskStopTool | TaskStopTool.swift | 47 | false | (none) |
| TaskOutputTool | TaskOutputTool.swift | 257 | false | toolUseID |
| TodoWriteTool | TodoWriteTool.swift | 106 | false | sessionID |
| TeamCreateTool | TeamCreateTool.swift | 42 | false | (none) |
| TeamDeleteTool | TeamDeleteTool.swift | 38 | false | (none) |
| SendMessageTool | SendMessageTool.swift | 74 | false | (none) |
| EnterPlanModeTool | EnterPlanModeTool.swift | 39 | false | setPlanModeActive |
| ExitPlanModeV2Tool | ExitPlanModeV2Tool.swift | 38 | false | setPlanModeActive |
| VerifyPlanExecutionTool | VerifyPlanExecutionTool.swift | 26 | false | (none) |
| SyntheticOutputTool | SyntheticOutputTool.swift | 38 | false | (none) |
| WorkflowTool | WorkflowTool.swift | 27 | false | (none) |
| REPLMode | REPLMode.swift | 37 | false | (none) |
| EnterWorktreeTool | EnterWorktreeTool.swift | 74 | false | workingDirectory |
| ExitWorktreeTool | ExitWorktreeTool.swift | 75 | false | (none) |
| SuggestBackgroundPRTool | SuggestBackgroundPRTool.swift | 27 | false | (none) |
| SubscribePRTool | SubscribePRTool.swift | 27 | false | (none) |
| SleepTool | SleepTool.swift | 48 | false | (none) |

**Batch 5: MCP, Config, Cron, Interactive, Misc (~19 tools)**

| Tool | File | Lines | isReadOnly | Context Fields Used |
|------|------|-------|------------|---------------------|
| MCPTool | MCPTool.swift | 90 | false | mcpClients |
| DynamicMCPTool | DynamicMCPTool.swift | 61 | false | mcpClients (implicit via bootstrapper) |
| McpAuthTool | McpAuthTool.swift | 109 | false | mcpClients, mcpResources |
| ConfigTool | ConfigTool.swift | 117 | false | (none -- config system only) |
| TestingPermissionTool | TestingPermissionTool.swift | 29 | false | (none) |
| SkillTool | SkillTool.swift | 221 | false | commands |
| AskUserQuestionTool | AskUserQuestionTool.swift | 159 | false | userInputPromptHandler |
| CronCreateTool | CronCreateTool.swift | 72 | false | (none) |
| CronDeleteTool | CronDeleteTool.swift | 38 | false | (none) |
| CronListTool | CronListTool.swift | 37 | false | (none) |
| PushNotificationTool | PushNotificationTool.swift | 27 | false | (none) |
| RemoteTriggerTool | RemoteTriggerTool.swift | 43 | false | (none) |
| MonitorTool | MonitorTool.swift | 26 | false | (none) |
| SendUserFileTool | SendUserFileTool.swift | 27 | false | (none) |
| WebBrowserTool | WebBrowserTool.swift | 27 | false | (none) |
| OverflowTestTool | OverflowTestTool.swift | 25 | false | (none) |
| BuiltInAgents | BuiltInAgents.swift | 232 | N/A | Agent definitions (static data) |
| CronTypes | CronTypes.swift | 90 | N/A | Shared types for Cron tools |
| WorktreeTypes | WorktreeTypes.swift | 46 | N/A | Shared types for Worktree tools |

### ToolUseContext Field Usage Analysis

Source-verified by grepping for `context.` in all 63 tool files.

| Field | Tools That Use It | Count | Migration Strategy |
|-------|-------------------|-------|-------------------|
| `workingDirectory` | FileRead, Grep, Glob, Bash, FileWrite, LSP, EnterWorktree, ExitWorktree, ListSkills, Agent | 10 | `let workingDirectory: String` at init |
| `shell` | Bash | 1 | `let shell: String` at init |
| `sessionID` | TodoWrite, Agent | 2 | `let sessionID: String` at init |
| `toolUseID` | TaskOutput, Agent | 2 | Passed as part of execution, not init |
| `mcpClients` | MCP, DynamicMCP, McpAuth, ListMcpResources, ReadMcpResource | 5 | Captured bootstrapper/client reference at init |
| `mcpResources` | McpAuth | 1 | Captured at init |
| `tools` | ToolSearch | 1 | Can be retrieved from ToolEngine at call time |
| `mode` | Agent | 1 | `let permissionMode: PermissionMode` at init |
| `setPlanModeActive` | EnterPlanMode, ExitPlanModeV2 | 2 | Closure property at init: `let setPlanModeActive: (Bool) -> Void` |
| `commands` | Skill | 1 | `let commands: [any Sendable]?` at init |
| `userInputPromptHandler` | AskUserQuestion | 1 | Closure property at init |
| `mainLoopModel` | Agent | 1 | `let mainLoopModel: String` at init |

**All other ToolUseContext fields (abortSignal, getAppState, setStreamMode, onCompactProgress, etc.):** Used by ZERO tools. These exist solely for future expansion and are removed with ToolUseContext.

### Tool Protocol Member Override Counts

Source-verified by counting overrides across all 63 tools.

| Protocol Member | Tools Overriding | Notes |
|----------------|------------------|-------|
| `searchHint` | ~55 | Moves to `ToolMetadata.searchHint` |
| `isEnabled()` | ~39 | Moves to `ToolMetadata.isEnabled` |
| `isReadOnly` | ~25 | Becomes `ToolMetadata.isReadOnly` |
| `shouldDefer` | ~33 | Moves to `ToolMetadata.shouldDefer` |
| `isConcurrencySafe` | ~10 | Moves to `ToolMetadata.isConcurrencySafe` |
| `interruptBehavior()` | ~20 | Moves to `ToolMetadata.interruptBehavior` |
| `getPath()` | ~8 | Removed -- ToolEngine/permission handles path extraction |
| `getToolUseSummary()` | ~15 | Moves to `ToolMetadata.activityDescription` |
| `getActivityDescription()` | ~10 | Moves to `ToolMetadata.activityDescription` |
| `isSearchOrReadCommand()` | ~5 | Moves to `ToolMetadata` or CLI rendering |
| `validateInput()` | ~15 | Becomes part of `call(arguments:)` with typed validation |
| `isDestructive()` | ~30 | Moves to `ToolMetadata.isDestructive` |
| `prompt()` | ~10 | Removed -- system prompt built by ToolEngine from metadata |

## Consumer Wiring Touchpoints

### CLI: ChatCommand (2051 lines across 6 files)

**Current dependency chain:**
```
ChatCommand.run()
  -> LLMClient(apiKey:baseURL:model:)              // ChatCommand.swift:96
  -> ToolRegistry()                                  // ChatCommand.swift:97
  -> ToolExecutor(registry:)                        // ChatCommand.swift:99
  -> QueryEngine(client:toolExecutor:contextManager:promptBuilder:)  // ChatCommand.swift:100
  -> SubAgentManager(engine:taskManager:)           // ChatCommand.swift:106
  -> registerBuiltinTools(into:taskManager:subAgentManager:)  // ChatCommand.swift:107
  -> DynamicMCPTool(serverName:toolName:...)        // ChatCommand.swift:131
  -> registry.register(dynamicTool)                 // ChatCommand.swift:138
  -> client.send(messages:model:systemPrompt:maxTokens:tools:...)  // ChatCommand.swift:571
  -> for try await event in stream { ... }          // ChatCommand.swift:581
  -> ChatToolInputAccumulator                       // ChatCommand.swift:555
  -> ChatToolExecutionScheduler.execute(...)        // ChatCommand.swift:688,759
  -> executeTool(name:input:toolUseID:...)          // ChatCommand.swift:766 (calls ToolExecutor)
  -> emitCollapsedResults(...)                      // ChatCommand.swift:708,794
  -> conversationHistory.append(...)                // ChatCommand.swift:686,718,755,811
```

**Replacement for each touchpoint:**
1. `LLMClient` -> `AnthropicProvider` or `DeepSeekProvider` from `AgentRuntime/Providers/`
2. `ToolRegistry` + `ToolExecutor` -> `DefaultToolEngine` (already built, implements `ToolEngine`)
3. `QueryEngine` -> `LanguageModelSessionImpl`
4. `SubAgentManager` -> Removed; `AgentTool` migrated to use session directly
5. `registerBuiltinTools()` -> `toolEngine.register(tool:metadata:)` for each tool
6. `DynamicMCPTool` -> Migrated; captures `MCPBootstrapper` reference at init
7. `client.send()` -> `session.streamResponse(to:)`
8. `for try await event` on `StreamEvent` -> `for try await event` on `SessionEvent`
9. `ChatToolInputAccumulator` -> DELETED (tool input parsing handled by provider internally)
10. `ChatToolExecutionScheduler` -> DELETED (tool execution handled by agent loop internally)
11. `executeTool()` -> DELETED (handled by `LanguageModelSessionImpl.executeTool()`)
12. `emitCollapsedResults()` -> Rewritten for SessionEvent-based rendering (D-10)
13. `conversationHistory: [Message]` -> Replaced by `Transcript` (managed by session)
14. `AppState`, `SessionState` -> Replaced by `AgentProfile` + `LanguageModelSession` subsystems
15. `cachedSystemPrompt` / `SystemPromptBuilder` -> Built from `AgentProfile` and tool metadata at session init

**Session construction in CLI (new):**
```swift
// Construct providers
let provider = DeepSeekProvider(apiKey: key, baseURL: baseURL, model: model)
let memory = SQLiteMemoryStore(path: "~/.swift-agent/memory.sqlite")
let permission = AgentPermissionBridge(mode: permissionMode)
let toolEngine = DefaultToolEngine()

// Build session
let session = LanguageModelSessionImpl(
    modelProvider: provider,
    memoryStore: memory,
    permissionEngine: permission,
    toolEngine: toolEngine
)

// Register all tools with metadata
for tool in migratedTools {
    await toolEngine.register(tool: tool, metadata: tool.metadata)
}

// Replace the entire agent loop (~270 lines) with:
let stream = await session.streamResponse(to: userInput)
for try await event in stream {
    // New rendering for SessionEvent
}
```

### App: ThreadViewModel + AgentSessionManager

**Current dependency chain:**
```
ThreadViewModel.send(userText:)
  -> AgentSessionManager.run(userInput:conversation:workingDirectory:onEvent:)
    -> AppAgentProvider (wraps DeepSeekClient/Anthropic LLM provider)
    -> ToolRegistry (same as CLI)
    -> QueryEngine.run(userInput:conversation:state:tools:onEvent:...)
      -> LLMClient.send()
      -> ToolExecutor.execute()
    -> onEvent(StreamingQueryEvent) callback -> ThreadViewModel.handleStreamEvent()
  -> ThreadViewModel.handleRunResult(result, assistantID:)
```

**Files to delete (App-side):**
- `Sources/SwiftAgentApp/Agent/AgentSessionManager.swift` -- Replaced by `LanguageModelSessionImpl`
- `Sources/SwiftAgentApp/Agent/AppAgentProvider.swift` -- Replaced by direct provider construction
- `Sources/SwiftAgentApp/Agent/AgentMessages.swift` -- Messages built from `SessionEvent` via bridge
- `Sources/SwiftAgentApp/LLM/` (5 files) -- Replaced by `AgentRuntime/Providers/`
- `Sources/SwiftAgentApp/DeepSeek/` (4 files) -- Replaced by `AgentRuntime/Providers/DeepSeek/`

**New dependency chain:**
```
ThreadViewModel.send(userText:)
  -> session.streamResponse(to: userText)        // session = LanguageModelSessionImpl
  -> for try await event in stream { handle(event) }
    -> Convert SessionEvent -> AgentMessage block updates
    -> Update messages[index] with text, thinking, tool blocks
  -> stream.onTermination: finalize state
```

**Key differences in App wiring:**
1. `AgentSessionManager.bootstrap()` logic (tool registration, MCP bootstrapping, skill loading) moves to app launch / session construction
2. `AgentMessage` model stays -- only the event-to-block conversion adapter changes
3. `PersistedMessage`, `SwiftAgentStore` persistence replaced by `SQLiteMemoryStore`
4. Message queuing (`messageQueue`, `queueCount`) remains -- consumer-level concern
5. `ThreadViewModel.handleStreamEvent()` must map `SessionEvent` cases (not `StreamingQueryEvent` cases)
6. `RunResult` (turns, toolCalls, tokenUsage) not returned -- consumer reconstructs from stream events

### Other Consumers Touching Deprecated Types

| File | Deprecated Types Used | Action |
|------|----------------------|--------|
| `EvalCommand.swift` | LLMClient, QueryEngine, ToolUseContext | Rewrite or remove (eval/testing tool) |
| `Compactor.swift` | LLMClient (via QueryEngine?) | Defer or rewrite for Transcript |
| `SubAgentManager.swift` | QueryEngine, StreamingQueryEvent | Delete (AgentTool uses session directly) |
| `MCPToolBridge.swift` | QueryEngine (reference) | Verify; may need updating |
| `SkillTool.swift` | QueryEngine (sub-agent spawning) | Migrate -- uses session directly |
| `AgentTool.swift` | QueryEngine (via SubAgentManager), ToolUseContext | Migrate -- captures session/model at init |

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Tool execution dispatch | Custom executeTool() with manual permission check | `ToolEngine.execute()` | Already built, permission-gated in LanguageModelSessionImpl.executeTool() |
| Tool input JSON parsing | ChatToolInputAccumulator with incremental delta assembly | Provider-internal SSE parser yields parsed `toolCallRequested` events | SSE parsing is provider-specific; consumers should never see raw JSON deltas |
| Tool concurrency scheduling | ChatToolExecutionScheduler with isConcurrencySafe checks | `ToolEngine` manages execution; concurrency model in ToolMetadata | Already abstracted in new architecture |
| Agent loop (re-prompt) | Manual while-loop with conversation history management | `LanguageModelSessionImpl.streamResponse(to:)` | Already built; handles re-prompt, transcript, and memory internally |
| Message normalization | 17-pass shared normalizer with [ContentBlock] input | Per-provider Transcript->API translation | D-17: normalization lives inside each provider |
| Spinner/status line management | `StatusLine` + `AppStateSnapshot` poll-based rendering | Event-driven rendering from SessionEvent stream | D-10: fresh rendering; StatusLine is poll-based (old architecture) |
| Memory persistence | File-based JSONL `SwiftAgentStore` / `SessionStore` | `SQLiteMemoryStore` implementing `SessionMemoryStore` | Already built; schema-versioned, transactional |
| System prompt building | `SystemPromptBuilder` with per-call caching logic | `AgentProfile.instructions` + `ToolEngine.getAllDefinitions()` | New architecture builds prompt once at session init |

**Key insight:** The old architecture has ~270 lines of manual agent loop in ChatCommand (LLM call -> SSE parse -> tool input accumulate -> tool execute -> history append -> re-prompt). The new architecture collapses this to a single `for try await event in stream` loop in the consumer, because the agent loop is internal to the session actor. Every piece of the old loop has a corresponding built replacement.

## Deprecated Type Dependency Graph

### Removal Order (Safest Execution Sequence)

```
Batch 1 tools migrated (read-only)
    |
    v
DELETE old Tool protocol + ToolUseContext (Types/Tool.swift)
    |  (Forces remaining 48+ tools to migrate -- D-06)
    v
Batch 2-5 tools migrated (sequentially)
    |
    v
CLI ChatCommand rewired to LanguageModelSessionImpl
    |
    +---> DELETE LLMClient, LLMStreamParser (D-12)
    +---> DELETE QueryEngine (D-12)
    +---> DELETE StreamRenderer, StatusLine, old rendering code
    +---> DELETE ChatToolInputAccumulator, ChatToolExecutionScheduler
    |
    v
App ThreadViewModel rewired to LanguageModelSessionImpl
    |
    +---> DELETE AgentSessionManager, AppAgentProvider, AgentMessages
    +---> DELETE App/LLM/ (AnthropicProvider, DeepSeekProvider, OpenAIProvider, LLMProvider, ProviderRegistry)
    +---> DELETE App/DeepSeek/ (DeepSeekClient, DeepSeekConfig, DeepSeekModel, KeychainStore)
    +---> DELETE Storage/ (SwiftAgentStore, SessionStore, MemoryStore, etc. -- 8 files)
    |
    v
DELETE MessageNormalizer (replaced by per-provider normalizers -- D-15/D-17)
DELETE Compactor (defer or rewrite for Transcript)
DELETE SubAgentManager (AgentTool migrated)
DELETE ToolExecutor, ToolRegistry (replaced by ToolEngine)
DELETE EvalCommand or rewrite (depends on LLMClient/QueryEngine)
```

### Blast Radius Per Type

| Type to Delete | Direct Consumers | Test Impact | Safe After |
|---------------|------------------|-------------|------------|
| **ToolUseContext** | 63 tools + ChatCommand + EvalCommand + QueryEngine + ToolExecutor + PermissionEngine + PermissionStore | Phase1TypesTests, Phase2LLMTests, Phase3AgentTests, Phase4ToolsTests, Phase11SubAgentTests | Batch 1 validates |
| **Old Tool protocol** | 63 tools, ToolRegistry, all tests with mock tools | Same as above | Batch 1 validates |
| **LLMClient** | ChatCommand, EvalCommand, Compactor, old Anthropic/DeepSeek providers, Phase2LLMTests | Phase2LLMTests | CLI wired |
| **QueryEngine** | ChatCommand, EvalCommand, AgentSessionManager, SubAgentManager, SkillTool, AgentTool | Phase3AgentTests (indirect) | CLI wired |
| **LLMStreamParser** | LLMClient, AnthropicSSEParser (new), AnthropicContentAccumulator (new) | None direct | CLI wired |
| **MessageNormalizer** | EvalCommand (reference only), Phase3AgentTests | Phase3AgentTests (MessageNormalizerTests) | App wired |
| **StreamRenderer** | ChatCommand (referenced via TerminalRenderer), Phase3AgentTests | Phase3AgentTests (StreamRendererTests) | CLI rewired |
| **SwiftAgentStore** | ThreadViewModel, PersistenceRoundTripTests | PersistenceRoundTripTests | App wired |
| **SessionStore** | ChatCommand (session picker), Phase9StorageTests | Phase9StorageTests | App wired |
| **DeepSeekClient** | AppAgentProvider | None direct in tests | App wired |
| **ProviderRegistry** | AppAgentProvider | None direct | App wired |

### Files That Become Dead When QueryEngine Is Removed

- `Sources/SwiftAgentCore/Agent/QueryEngine.swift` (deleted)
- `Sources/SwiftAgentCore/Agent/ToolExecutor.swift` (deleted, replaced by ToolEngine)
- `Sources/SwiftAgentCore/Agent/StreamRenderer.swift` (deleted)
- `Sources/SwiftAgentCore/Agent/SubAgentManager.swift` (deleted)
- `Sources/SwiftAgentCore/Types/StreamEvent.swift` (deleted -- old anthropic-specific events)
- `Sources/SwiftAgentCLI/ChatToolInputAccumulator.swift` (deleted)
- `Sources/SwiftAgentCLI/ChatToolExecutionScheduler.swift` (deleted)
- `Sources/SwiftAgentCLI/StatusLine.swift` (deleted or rewritten for SessionEvent)
- `Sources/SwiftAgentCLI/ToolResultCache.swift` (rewritten for SessionEvent)
- `Sources/SwiftAgentCLI/CollapseDetector.swift` (may be reusable, review)

## MessageNormalizer Analysis

### Current 17-Pass Pipeline

Source: `Sources/SwiftAgentCore/Agent/MessageNormalizer.swift` (848 lines). Analyzed line-by-line.

| Pass | Name | What It Does | Needed in New Pipeline? |
|------|------|-------------|------------------------|
| 1 | Filter virtual messages | Removes `isVirtual` messages (display-only) | NO -- Transcript has no virtual concept |
| 2 | Filter progress messages | Removes `.progress` type messages | NO -- SessionEvent has no progress messages |
| 3 | Filter system messages | Removes `.system` type (display-only) | PARTIAL -- Transcript may have `.instruction` entries that providers filter |
| 4 | Deduplicate by UUID | First occurrence wins for duplicate UUIDs | YES -- Transcript entries may have duplicate IDs from retries |
| 5 | Normalize tool_use inputs | Strips internal-only fields (plan/planFilePath, synthetic edits) | YES -- but now at Transcript.Entry level, filtering `.toolCall` input fields |
| 6 | Strip unavailable tool references | Removes tool_use blocks for tools not in the available set | YES -- provider filters tool definitions before sending |
| 7 | Filter orphaned thinking | Removes assistant messages that only have thinking blocks (no text, no tools) | YES -- Transcript may have `.thinking` entries without corresponding `.response` |
| 8 | Filter trailing thinking | Strips thinking from last assistant message if it's the only content | YES -- provider controls thinking placement |
| 9 | Filter whitespace-only assistant | Removes messages where text content is only whitespace | YES -- provider validates before sending |
| 10 | Merge consecutive user messages | Joins adjacent user messages into one | MAYBE -- depends on how transcript accumulates entries |
| 11 | Merge assistant messages (same ID) | Backward walk: merges assistant messages with identical messageID | MAYBE -- Transcript entry model may prevent duplicates structurally |
| 12 | Smoosh system reminders | Merges system-reminder siblings into tool_result content | NO -- system reminders are handled at prompt construction, not normalization |
| 13 | Sanitize error tool_result | Strips non-text content from is_error=true tool results | YES -- provider ensures tool output is string-safe |
| 14 | Ensure non-empty assistant content | Adds placeholder text to empty assistant arrays | YES -- API requirement for Anthropic |
| 15 | Normalize content | Strips empty text blocks from content arrays | YES -- provider strips before serialization |
| 16 | Apply aggregate tool result budget | Limits total tool result content size | YES -- provider enforces budget in Translation layer |
| 17 | Ensure tool_use/tool_result pairing | Validates every tool_use has a matching tool_result | NO -- Transcript structurally guarantees pairing |

**Verdict:** Approximately 10 of 17 passes have equivalents in the new architecture, but they are implemented differently (at the Transcript level, per-provider, structurally guaranteed). The old implementation operates on raw `[Message]` with mutation -- the new approach operates on `Transcript` entries with structural guarantees. D-15/D-16 (rewrite from scratch for Transcript) is the correct approach.

**Provider-internal normalization (D-17):** Each provider's `LanguageModelExecutor.respond(to:tools:options:streamingInto:)` receives a `Transcript` and must translate it to the provider's wire format. This is where normalization happens:
- `AnthropicTranscriptTranslator` (already built: AgentRuntime/Providers/Anthropic/AnthropicTranscriptTranslator.swift)
- `DeepSeekTranscriptTranslator` (already built: AgentRuntime/Providers/DeepSeek/DeepSeekTranscriptTranslator.swift)
- `OpenAITranscriptTranslator` (already built: AgentRuntime/Providers/OpenAI/OpenAITranscriptTranslator.swift)

Each translator is responsible for the normalization passes that apply to its provider's API requirements.

## Test Impact

### Test Files Directly Referencing Deprecated Types

Source-verified by grep: 7 test files have direct references to types being deleted.

| Test File | Deprecated Types Used | Lines Affected | Strategy |
|-----------|----------------------|----------------|----------|
| `Phase1TypesTests.swift` | ToolUseContext, CanUseToolFn, ToolResult | ~10 test functions | Rewrite mock tools using RuntimeAgentTool; delete ToolUseContext tests |
| `Phase2LLMTests.swift` | LLMClient, ToolRegistry, ToolUseContext | ~15 test functions | Delete LLMClient tests; migrate ToolRegistry tests to ToolEngine |
| `Phase3AgentTests.swift` | MessageNormalizer, StreamRenderer, ToolExecutor, ToolUseContext | ~8 test functions | Delete MessageNormalizer/StreamRenderer tests; migrate ToolExecutor tests |
| `Phase4ToolsTests.swift` | ToolUseContext (global `testCtx`) | 1+ test functions | Replace testCtx with typed Arguments structs |
| `Phase9StorageTests.swift` | SessionStore | 5 test functions | Delete; replaced by SQLiteMemoryStoreTests |
| `Phase11SubAgentTests.swift` | ToolUseContext | ~3 test functions | Update to use new tool init pattern |
| `PersistenceRoundTripTests.swift` | SwiftAgentStore | 2 test functions | Delete; replaced by SQLiteMemoryStoreTests |

### Test Files That Need NEW Tests (Not Exists Yet)

| New Test | Covers | Needed For |
|----------|--------|------------|
| `RuntimeAgentToolConformanceTests` | Every migrated tool's conformance to RuntimeAgentTool | MIG-01 validation |
| `ToolEngineRegistrationTests` | Tool registration with metadata, getDefinition, getAllDefinitions | MIG-01 validation |
| `CLISessionEventRenderingTests` | CLI rendering of each SessionEvent case | MIG-02 CLI wiring |
| `AppSessionEventBridgeTests` | SessionEvent -> AgentMessage block conversion | MIG-02 App wiring |
| `ToolArgumentCodingTests` | Round-trip Codable for each tool's Arguments type | MIG-01 validation |
| `SessionConstructionTests` | LanguageModelSessionImpl init with all subsystems | MIG-02 wiring |

### Existing Test Files NOT Affected

The following 30 test files have NO references to deprecated types and should pass without changes:
- CoreTypesTests, Phase2StreamingTests, Phase6SafetyTests, Phase7ConfigTests, Phase8CommandsTests, Phase10MCPTests, Phase12AdvancedTests, SyntaxHighlightingTests
- AgentPermissionBridgeTests, AgentRuntimeImplTests, AnthropicProviderTests, DeepSeekProviderTests, OpenAIProviderTests, MockProviders, SQLiteMemoryStoreTests
- All CLI tests (ComposerPopupIntegrationTests, LineEditor*Tests, TerminalRenderingTests)
- All App tests (PermissionFlowTests, RightTabsStoreTests, RightTabTypeTests, SkillRoutingTests, ThreadRepositoryTests)
- All UI tests (LaunchAndSeeLayout, NewThreadSendsMessage, SettingsOpens, SwitchPanel, ThemeSwitch)

**MIG-04 strategy:** Update affected tests as each batch completes. Existing AgentRuntime tests (AgentRuntimeImplTests, provider tests, SQLiteMemoryStoreTests) validate the new infrastructure independently.

## Risk Assessment

### Risk Matrix

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| Batch 1 reveals RuntimeAgentTool protocol is insufficient | MEDIUM | HIGH -- blocks all tool migration | Batch 1 is read-only (simplest tools). Validate protocol early. |
| Tool migration introduces regression in tool behavior | MEDIUM | HIGH -- breaks agent functionality | Each tool gets a conformance test; batch testing before old protocol deletion. |
| Consumer wiring breaks CLI/App rendering | HIGH | MEDIUM -- cosmetic, not functional | Fresh rendering for SessionEvent means no regression from old code. CLI and App can be tested independently. |
| Old Tool protocol deletion breaks un-migrated tools at compile time | CERTAIN (by design) | MEDIUM -- intentional forcing function | D-06: forces migration. All un-migrated tools get compiler errors -- they MUST be migrated. |
| App persistence migration (file-based -> SQLite) loses data | MEDIUM | LOW -- old data is discarded per CONTEXT.md | D-14: old data discarded. SQLiteMemoryStore starts fresh. |
| MessageNormalizer removal causes API errors | LOW | MEDIUM -- provider translators handle normalization | D-17: each provider owns its normalization. Existing AnthropicTranscriptTranslator validates the pattern. |
| EvalCommand broken by consumer wiring | MEDIUM | LOW -- EvalCommand is a testing tool | Either rewrite EvalCommand for new API or remove it. |
| Compactor broken (depends on LLMClient) | MEDIUM | LOW -- compaction is a future concern | Defer compaction to a future phase. Transcript-based compaction can be built later. |
| Build time regression from 63 tool rewrites | LOW | LOW -- Swift incremental compilation handles this | Each tool migration is a single file change. |
| `nonisolated(unsafe)` count increases | LOW | HIGH -- STATE.md invariant | Cross-phase invariant: count must not increase from current 3. Audited at each removal. |

### Execution Order Safety

The CONTEXT.md D-12 mandate ("Remove as wiring completes") creates a strict dependency order:

```
1. Batch 1 tool migration (read-only)    -- LOW risk, simple tools
2. Validate batch 1                       -- Test conformance
3. DELETE old Tool protocol + ToolUseContext -- FORCES remaining migration (D-06)
   RISK: Compile error on 48+ un-migrated tools. Acceptable per D-06.
4. Batch 2-5 migration (sequentially)     -- Must complete before CLI wiring
5. CLI ChatCommand rewired                -- HIGH complexity (270 lines replaced)
6. DELETE LLMClient, QueryEngine, LLMStreamParser -- (D-12)
7. App ThreadViewModel rewired            -- MEDIUM complexity
8. DELETE App providers, Storage/, AgentSessionManager -- (D-12, D-13, D-14)
9. DELETE MessageNormalizer               -- (D-15)
10. Final cleanup (StreamRenderer, ToolRegistry, SubAgentManager, etc.)
```

**Safest execution order:** Do not deviate from this sequence. Each step unlocks the next. Reordering risks:
- Wiring before tool migration: no tools registered, session has nothing to execute
- Deleting old types before wiring: compile errors in ChatCommand/ThreadViewModel
- Migrating destructive tools before read-only batch: riskier tools before pattern is validated

### Blast Radius Summary

| Removal Event | Files Breaking | Severity |
|--------------|----------------|----------|
| Delete ToolUseContext | 63 tools + 6 other files | CRITICAL -- compile failure |
| Delete old Tool protocol | 63 tools + ToolRegistry + tests | CRITICAL -- compile failure |
| Delete LLMClient | ChatCommand, EvalCommand, Compactor, old providers | HIGH |
| Delete QueryEngine | ChatCommand, EvalCommand, AgentSessionManager, SubAgentManager, SkillTool, AgentTool | HIGH |
| Delete StreamRenderer | ChatCommand (indirect), Phase3AgentTests | LOW |
| Delete Storage/ | ThreadViewModel, PersistenceRoundTripTests, Phase9StorageTests | MEDIUM |
| Delete App LLM/DeepSeek/ | AppAgentProvider, AgentSessionManager | MEDIUM (both already deleted) |

## Runtime State Inventory

> This phase involves renaming (Input->Arguments, call(_:)->call(arguments:)), file moves (Tools/ -> AgentRuntime/Tools/), and deletion of Storage/ (file-based persistence). Runtime state check:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | File-based session data in `~/.swift-agent/projects/` (JSONL files created by SwiftAgentStore/SessionStore) | D-14: old data is discarded. SQLiteMemoryStore starts fresh. No migration needed. |
| Live service config | None -- SwiftAgent has no external service dashboards | None |
| OS-registered state | None -- no launchd plists, no pm2 processes, no Task Scheduler entries | None |
| Secrets/env vars | API keys in environment/keychain (ANTHROPIC_API_KEY, etc.) -- unchanged | None -- keys read by new providers, same sources |
| Build artifacts | `.build/` directory (SPM derived data) | Clean build after migration: `swift build --disable-sandbox` |

**Nothing found requiring data migration.** Old file-based storage data is intentionally discarded (D-14). API keys remain in the same locations. No OS-level registrations exist.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Swift 6.0+ | Compilation | ✓ | swift-driver version: 1.115.1 Apple Swift version 6.0.3 | -- |
| macOS 15+ | AppKit/SwiftUI | ✓ | Darwin 25.5.0 (macOS 26) | -- |
| SPM (Swift Package Manager) | Build | ✓ | Bundled with Swift 6.0.3 | -- |
| SQLite3 | SQLiteMemoryStore | ✓ | System library (macOS bundled) | -- |
| Git | Worktree tools, file search index | ✓ | System git | -- |

**Missing dependencies:** None. All required runtimes and libraries are available on the target system.

## Validation Architecture

> `workflow.nyquist_validation` is explicitly `false` in `.planning/config.json`. Validation architecture section skipped per instructions.

## Common Pitfalls

### Pitfall 1: Forgetting ToolUseContext Fields in Migration

**What goes wrong:** A tool is migrated to RuntimeAgentTool but loses a context field it silently depended on (e.g., `workingDirectory` for path resolution, `shell` for Bash). The tool compiles but behaves incorrectly at runtime.

**Why it happens:** ToolUseContext has 70+ fields; tools access only a subset. It's easy to miss a field used deep in a private helper method.

**How to avoid:** For each tool being migrated, grep for `context.` in the source file before writing the migration. Document every accessed field. Capture them all as `let` properties at init time.

**Warning signs:** Tool compiles but `workingDirectory` resolution fails silently (paths resolve relative to cwd instead of project root). Bash tool uses wrong shell. MCP tools can't find clients.

### Pitfall 2: Typed Input Struct Mismatch

**What goes wrong:** The new `Arguments: Codable` struct uses different key names or types than the old `[String: JSONValue]` dictionary. The LLM sends JSON matching the old schema but the new decoder fails.

**Why it happens:** Old tools access input via `input.stringValue("file_path")` -- stringly-typed. New tools use `arguments.filePath` -- strongly typed. CodingKeys mapping must match exactly.

**How to avoid:** Use `CodingKeys` enum to preserve snake_case JSON keys (e.g., `file_path`, `tool_use_id`). Add unit tests that round-trip JSON -> Arguments -> JSON and compare against the old schema.

**Warning signs:** `DecodingError` at runtime when the LLM sends a tool call. Tool is never executed because input fails to parse.

### Pitfall 3: Deleting Old Protocol Too Early

**What goes wrong:** Old `Tool` protocol is deleted but some code still references it (e.g., ToolRegistry, PermissionEngine, tests). Compile errors cascade across the project.

**Why it happens:** ToolUseContext and Tool protocol are deeply embedded. Even after all tools are migrated, there may be residual references in utility code, tests, or type extensions.

**How to avoid:** After all tools are migrated, do a full-project grep for `ToolUseContext`, `: Tool`, `CanUseToolFn`, `ToolResult`, `ToolCallProgress` before deleting. Fix all references first.

**Warning signs:** Swift compiler errors referencing deleted types in files outside Tools/.

### Pitfall 4: Consumer Rendering Gap

**What goes wrong:** CLI or App consumer renders SessionEvent but misses visual elements the old rendering provided (spinner updates, tool progress, status line).

**Why it happens:** The old `StreamEvent` has 12 cases; `SessionEvent` has 6. The mapping is not 1:1 -- some old events have no equivalent (`.contentBlockStart`, `.inputJSONDelta`, `.ping`), and new events require new rendering (`.toolCallRequested` carries parsed input data).

**How to avoid:** Build the new rendering layer from scratch per D-10, referencing old rendering only for visual parity (not code reuse). Test with a live session to verify spinner behavior, tool card display, and text streaming.

**Warning signs:** Spinner doesn't clear when tool starts. Tool results don't appear. Text streaming flickers or duplicates.

### Pitfall 5: Session Actor Reentrancy

**What goes wrong:** Consumer calls `streamResponse(to:)` while a previous stream is still active. Gets `rateLimited` error or hangs.

**Why it happens:** `LanguageModelSessionImpl` has an `isResponding` guard. Calling `streamResponse(to:)` while `isResponding == true` returns an immediately-failing stream with `.rateLimited`.

**How to avoid:** Consumers must track stream lifecycle. CLI uses the existing `isCancelled` flag + cancel-before-new-request pattern. App uses `ThreadState.executing` guard + `messageQueue` for backpressure.

**Warning signs:** Second message silently fails. Stream terminates immediately with rate limit error.

### Pitfall 6: SPM Target Dependency Confusion

**What goes wrong:** After deleting `Types/Tool.swift` (which contains JSONSchema, JSONSchemaProperty, ToolUseContext), other types in the same file (JSONSchema, JSONSchemaProperty) are also deleted.

**Why it happens:** Multiple types cohabitate in `Types/Tool.swift`: old Tool protocol (lines 45-289), ToolUseContext (lines 543-800+), JSONSchema (lines 401-471), JSONSchemaProperty (lines 509-541), InterruptBehavior, ValidationResult, ToolResultBlockParam, etc.

**How to avoid:** Before deleting `Types/Tool.swift`, extract shared types (JSONSchema, JSONSchemaProperty, InterruptBehavior, ValidationResult) into their own files. Only delete types that are actually deprecated. Check all importers of these types.

**Warning signs:** Compile errors about missing JSONSchema, JSONSchemaProperty after deleting Types/Tool.swift. These types are used by the new RuntimeAgentTool protocol!

## Code Examples

### Tool Registration (New Pattern)

```swift
// Source: ToolEngine protocol in AgentRuntime.swift (lines 11-25)
// and DefaultToolEngine implementation

let engine = DefaultToolEngine()

// Register read-only tools (Batch 1)
await engine.register(
    tool: FileReadTool(workingDirectory: cwd),
    metadata: ToolMetadata(
        searchHint: "read files, images, PDFs, notebooks",
        isReadOnly: true,
        isConcurrencySafe: true,
        interruptBehavior: .cancel,
        activityDescription: "Reading file"
    )
)

await engine.register(
    tool: GrepTool(workingDirectory: cwd),
    metadata: ToolMetadata(
        searchHint: "search file contents with regex",
        isReadOnly: true,
        isConcurrencySafe: true,
        interruptBehavior: .cancel,
        activityDescription: "Searching"
    )
)

// Register destructive tools (Batch 2+)
await engine.register(
    tool: BashTool(workingDirectory: cwd, shell: "/bin/zsh"),
    metadata: ToolMetadata(
        searchHint: "execute shell commands",
        isReadOnly: false,
        isConcurrencySafe: false,
        isDestructive: true,
        interruptBehavior: .cancel,
        activityDescription: "Running command",
        requiresApproval: true
    )
)
```

### CLI Consumer: SessionEvent Rendering (New Pattern)

```swift
// Source: LanguageModelSessionImpl.streamResponse(to:) (AgentRuntimeImpl.swift:190-273)
// New rendering replaces ~270 lines of manual agent loop

let stream = await session.streamResponse(to: userInput)
var responseText = ""
var currentToolName: String?

for try await event in stream {
    switch event {
    case .textDelta(let text):
        // Clear spinner if active, then print text
        if currentToolName != nil { clearSpinner() }
        print(text, terminator: "")
        fflush(stdout)
        responseText += text

    case .thinkingDelta(let text):
        // Dimmed thinking output when --show-thinking
        if showThinking {
            print("\u{001B}[2m\(text)\u{001B}[0m", terminator: "")
            fflush(stdout)
        }

    case .toolCallRequested(let id, let name, let input):
        // Start spinner with tool name
        currentToolName = name
        renderToolStarted(name: name, id: id)

    case .toolCallCompleted(let id, let output, let isError):
        // Clear spinner, render result
        currentToolName = nil
        renderToolCompleted(id: id, output: output, isError: isError)

    case .turnCompleted(let usage, let stopReason):
        // Print usage stats
        if let u = usage {
            print("\n[Tokens: in=\(u.inputTokens) out=\(u.outputTokens)]")
        }

    case .error(let err):
        print("\nError: \(err.localizedDescription)")
    }
}
```

### App Consumer: SessionEvent -> AgentMessage Bridge

```swift
// Source: ThreadViewModel.handleStreamEvent (ThreadViewModel.swift:442-497)
// Adapted for SessionEvent

func handleSessionEvent(_ event: SessionEvent, assistantID: String) {
    guard let index = messages.firstIndex(where: { $0.id == assistantID }) else { return }

    switch event {
    case .textDelta(let text):
        messages[index].appendText(text)

    case .thinkingDelta(let text):
        messages[index].appendThinking(text)

    case .toolCallRequested(let id, let name, let input):
        messages[index].addToolUse(ToolUseBlock(
            toolUseID: id,
            toolName: name,
            inputSummary: name,
            inputDetail: "",
            status: .executing
        ))

    case .toolCallCompleted(let id, let output, let isError):
        messages[index].updateToolUse(
            toolUseID: id,
            status: isError ? .error(output.stringValue) : .completed
        )
        messages[index].addToolResult(ToolResultBlock(
            toolUseID: id,
            content: output.stringValue,
            isError: isError
        ))

    case .turnCompleted:
        // Persist intermediate state
        persistMessageWithBlocks(messages[index])

    case .error(let err):
        messages[index].appendText("[Error: \(err.localizedDescription)]")
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `[String: JSONValue]` tool input | Typed `Arguments: Codable` struct | Phase 4 | Compile-time safety; eliminates stringly-typed bugs |
| `ToolUseContext` with 70+ fields | `let` properties captured at tool init | Phase 4 | Each tool only sees fields it needs; removes 700+ lines |
| Manual agent loop in ChatCommand (270 lines) | `session.streamResponse(to:)` loop internal to actor | Phase 4 | Consumer code drops from ~270 to ~50 lines |
| `StreamEvent` (12 Anthropic-specific cases) | `SessionEvent` (6 provider-agnostic cases) | Phase 2 (built) / Phase 4 (wired) | Consumers never see provider-specific events |
| `LLMClient` + `QueryEngine` dual types | Single `LanguageModelSessionImpl` actor | Phase 1 (protocol) / Phase 4 (wired) | One API surface for all consumers |
| Shared `MessageNormalizer` (17 passes, 848 lines) | Per-provider `TranscriptTranslator` | Phase 4 | Each provider owns its normalization; no shared coupling |
| File-based JSONL `SwiftAgentStore` / `SessionStore` (1624 lines) | `SQLiteMemoryStore` (schema-versioned) | Phase 3 (built) / Phase 4 (wired) | Transactional, queryable, versioned schema |
| App-specific `DeepSeekClient` + `ProviderRegistry` | `AgentRuntime/Providers/` shared across CLI & App | Phase 3 (built) / Phase 4 (wired) | Single provider implementation for both consumers |

**Deprecated/outdated:**
- `StreamRenderer` (old): Only understands `StreamEvent` (Anthropic-specific SSE events). Replaced by new SessionEvent rendering.
- `ToolRegistry` (old): Stores `any Tool` (old protocol). Replaced by `ToolEngine` which stores `any RuntimeAgentTool` + `ToolMetadata`.
- `ChatToolInputAccumulator` (old): Manually assembles tool input JSON from SSE deltas. Provider-internal parsers now yield fully-parsed tool calls.
- `ChatToolExecutionScheduler` (old): Manages concurrent vs serial tool execution. `ToolEngine` now owns execution policies.

## Security Domain

> `security_enforcement: true` in config.json. ASVS Level 1.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | No | API keys in environment/keychain -- unchanged this phase |
| V3 Session Management | No | Session persistence moves from file-based to SQLite -- same trust boundary |
| V4 Access Control | Yes | `PermissionEngine.check(.runCommands)` gates every tool execution in `LanguageModelSessionImpl.executeTool()` |
| V5 Input Validation | Yes | Typed `Arguments: Codable` structs replace `[String: JSONValue]` -- JSONDecoder provides structural validation; `inputSchema` validates types |
| V6 Cryptography | No | No cryptographic operations in this phase |

### Known Threat Patterns for Swift Actor-Based Agent Runtime

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Tool input injection via malformed JSON | Tampering | `Arguments: Codable` + `JSONDecoder` fails on type mismatch; `inputSchema.validate()` catches schema violations |
| Unauthorized tool execution bypassing permissions | Elevation of Privilege | `LanguageModelSessionImpl.executeTool()` calls `permissionEngine.check(.runCommands)` before every tool call |
| Reentrancy attack (concurrent turns) | Denial of Service | Actor `isResponding` guard; second `streamResponse(to:)` returns immediately-failing stream |
| Tool output containing sensitive data in error messages | Information Disclosure | `ToolOutputValue.stringValue` for error output; App-side rendering controls display |
| Old Storage/ data leakage after deletion | Information Disclosure | D-14: old data intentionally discarded. Verify `~/.swift-agent/projects/` cleanup. |

### Permission Model Preservation

The old `ToolUseContext.mode` (PermissionMode) maps to `AgentPermissionBridge` which implements `SessionPermissionEngine`. Tool-level permission checks (`checkPermissions(input:context:)`) are removed -- all tools route through the unified `permissionEngine.check(.runCommands)` gate. This is a security simplification: one gate, uniformly applied, instead of per-tool custom permission logic.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Batch composition: 5 batches with the specific tools assigned above. Exact batch boundaries are Claude's discretion per CONTEXT.md. | Tool Migration Patterns | LOW -- any reasonable grouping works. Planner should validate batch sizes are workable. |
| A2 | `RuntimeAgentTool` will be renamed to `Tool` after old protocol deletion. | Architecture Patterns | LOW -- naming convention. No functional impact. |
| A3 | `JSONSchema` and `JSONSchemaProperty` can be extracted from `Types/Tool.swift` before deletion and placed in `Types/JSONSchema.swift`. | Common Pitfalls #6 | HIGH if wrong -- these types are used by the new RuntimeAgentTool protocol. Must be preserved. |
| A4 | `DefaultToolEngine` (Phase 2) is sufficient for production use. Codebase inspection shows it implements `ToolEngine` with `register`, `getDefinition`, `getAllDefinitions`, `execute`. | Consumer Wiring Touchpoints | MEDIUM -- if DefaultToolEngine is stub-only, a production implementation may be needed before CLI wiring. |
| A5 | Existing AgentRuntime provider tests (AnthropicProviderTests, DeepSeekProviderTests, OpenAIProviderTests) pass independently and don't reference deprecated types. Source grep confirms no `LLMClient`/`ToolUseContext` references. | Test Impact | LOW -- verified by grep. |
| A6 | `LanguageModelExecutor.respond()` returns `SessionEvent` values that are semantically equivalent to the old `StreamEvent` values for text/thinking/tool/error cases. | Consumer Wiring Touchpoints | MEDIUM -- if SessionEvent semantics differ from what consumers expect, rendering will be wrong. Validate with a smoke test. |
| A7 | After App wiring, `ThreadRepository` and `ThreadViewModel` can read from `SQLiteMemoryStore` instead of file-based `SwiftAgentStore`. | Consumer Wiring Touchpoints | MEDIUM -- persistence schema differences could break existing App views. |
| A8 | `EvalCommand` can be rewritten or safely removed without blocking other functionality. | Deprecated Type Dependency Graph | LOW -- EvalCommand is a testing/evaluation tool, not a production feature. |

## Open Questions (RESOLVED)

1. **Compactor fate** — RESOLVED: Delete with deprecated types. `Compactor.swift` is removed in 04-05 Task 3 along with LLMClient, StreamRenderer, and other deprecated Core files. Deferred to future phase per recommendation.

2. **EvalCommand fate** — RESOLVED: Delete. `EvalCommand.swift` is removed in 04-06 Task 2 along with other App-side deprecated files. No CI scripts reference it; safe to remove.

3. **SubAgentManager integration with new AgentTool** — RESOLVED: AgentTool migrated in 04-04 Task 1. Creates child `LanguageModelSessionImpl` with same providers but fresh transcript. `SubAgentManager` deleted in 04-05 Task 3.

4. **DefaultToolEngine production readiness** — RESOLVED: Given real tool execution in 04-01 Task 3. `DefaultToolEngine.execute(name:input:)` decodes `Data` into typed `Arguments` and invokes `call(arguments:)` returning real `ToolOutputValue`, not stub strings. Production-ready before any tool migration begins.

## Project Constraints (from CLAUDE.md)

- **Build:** `swift build --disable-sandbox` (all targets), `swift test --disable-sandbox --no-parallel` (shared state)
- **No god files:** ChatCommand already decomposed (1192->2051 lines across 6 files). Migration should maintain or improve the decomposition.
- **Core vs CLI boundary:** `SwiftAgentCore` is reusable; `SwiftAgentCLI` is ArgumentParser + terminal rendering. Tools move to Core (`AgentRuntime/Tools/`).
- **Actor isolation:** `LanguageModelSessionImpl` is an actor. Consumers must cross the actor boundary correctly.
- **Testable without live models:** Tool conformance, argument coding, and rendering should all be testable without live LLM calls.
- **Name for concepts, not accidents:** Use `Arguments` not `Input`, `call(arguments:)` not `call(_:)`, per D-07.
- **Conventional Commits:** `feat(agent): migrate FileReadTool to RuntimeAgentTool`, `refactor(cli): wire ChatCommand to streamResponse`, `chore(core): delete old Tool protocol`
- **CLAUDE.md and AGENTS.md must stay identical:** Update both if build commands change.

## Sources

### Primary (HIGH confidence -- direct codebase inspection)

All claims about the codebase were verified by directly reading source files:

- `Sources/SwiftAgentCore/AgentRuntime/Tools/RuntimeAgentTool.swift` -- New tool protocol definition (5 core members)
- `Sources/SwiftAgentCore/AgentRuntime/AgentRuntime.swift` -- LanguageModelSession protocol, ToolEngine protocol
- `Sources/SwiftAgentCore/AgentRuntime/AgentRuntimeImpl.swift` -- LanguageModelSessionImpl actor (274 lines)
- `Sources/SwiftAgentCore/Types/Tool.swift` -- Old Tool protocol (~30 members), ToolUseContext (70+ fields), JSONSchema, JSONSchemaProperty (1164 lines total)
- `Sources/SwiftAgentCore/Agent/MessageNormalizer.swift` -- 17-pass normalization pipeline (848 lines)
- `Sources/SwiftAgentCore/Agent/QueryEngine.swift` -- Old agent loop + StreamingQueryEvent + RunResult (~630 lines)
- `Sources/SwiftAgentCore/LLM/LLMClient.swift` -- Old Anthropic API client (~1079 lines)
- `Sources/SwiftAgentCore/Types/StreamEvent.swift` -- Old anthropic-specific SSE event enum
- `Sources/SwiftAgentCLI/ChatCommand.swift` -- CLI consumer with manual agent loop (~2051 lines across 6 files)
- `Sources/SwiftAgentApp/ViewModels/ThreadViewModel.swift` -- App consumer (~500+ lines)
- `Sources/SwiftAgentApp/Agent/AgentSessionManager.swift` -- App agent bridge (~400 lines)
- All 63 tool files in `Sources/SwiftAgentCore/Tools/` -- ToolUseContext field usage analysis
- `Sources/SwiftAgentCore/Storage/` -- 8 files, 1624 lines of old file-based persistence
- `Sources/SwiftAgentApp/LLM/` -- 5 files of old App provider layer
- `Sources/SwiftAgentApp/DeepSeek/` -- 4 files of old standalone DeepSeek client
- `Sources/SwiftAgentCore/AgentRuntime/Providers/` -- New provider implementations (Anthropic, DeepSeek, OpenAI, Memory, Permission)
- `.planning/phases/04-migration-wiring-cleanup/04-CONTEXT.md` -- Authoritative user decisions (D-01 through D-17)
- `.planning/REQUIREMENTS.md` -- MIG-01 through MIG-05 requirements
- `.planning/config.json` -- Workflow configuration (nyquist_validation: false, security_enforcement: true)

### Secondary (MEDIUM confidence)

- `docs/ARCHITECTURE.md` -- Module boundaries and design decisions (referenced for architecture validation)
- `.planning/STATE.md` -- Project phase history and accumulated decisions (naming collisions, Runtime prefix convention)
- `.planning/ROADMAP.md` -- Phase 4 goal context (noted: feature-flag approach overridden by CONTEXT.md D-08)

### Tertiary (LOW confidence -- assumptions based on training data)

- Apple FoundationModels framework WWDC26 Beta documentation (not directly accessed; protocol alignment assumed from Phase 1-3 design)
- Swift actor reentrancy patterns (training knowledge; verified against LanguageModelSessionImpl implementation)
- SPM target dependency resolution (training knowledge; verified against project Package.swift)

### Context7 / WebSearch

Not used in this phase. All research is codebase-internal -- no external library documentation needed. The phase is a pure migration of project-internal types with no external package dependencies.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all dependencies are project-internal and verified by direct file reading
- Architecture: HIGH -- both old and new architectures fully mapped from source code
- Pitfalls: HIGH -- derived from detailed codebase analysis and known Swift migration patterns
- Tool inventory: HIGH -- every tool file read, ToolUseContext field usage verified by grep
- Consumer wiring: HIGH -- ChatCommand and ThreadViewModel agent loops fully analyzed
- Deprecated type dependency graph: HIGH -- all references traced by grep across Sources/ and Tests/
- Test impact: HIGH -- test files audited for deprecated type references
- MessageNormalizer: HIGH -- all 17 passes analyzed line-by-line from source

**Research date:** 2026-06-25
**Valid until:** 2026-07-25 (30 days; codebase is stable, migration patterns change slowly)

**Tool count:** 63 tools in `Sources/SwiftAgentCore/Tools/` (plus 3 shared type files: CronTypes, WorktreeTypes, BuiltInAgents)
**Lines to delete:** ~7,500+ across 20+ files
**Lines to write (new):** ~63 tool rewrites + ~200 lines CLI rendering + ~100 lines App bridge = ~4,000-5,000 estimated
**Files to create:** 63 tool files in `AgentRuntime/Tools/` + ~3 new rendering files (CLI + App)
**Files to delete:** ~25+ files (Types/Tool.swift, QueryEngine, LLMClient, LLMStreamParser, MessageNormalizer, StreamRenderer, Compactor, SubAgentManager, ToolExecutor, ToolRegistry, ChatToolInputAccumulator, ChatToolExecutionScheduler, StatusLine, Storage/ (8 files), App/LLM/ (5 files), App/DeepSeek/ (4 files), App/Agent/ (3 files), Types/StreamEvent.swift)
**Codebase knowledge graph:** Not loaded (graph.json not found in .planning/graphs/ -- graph context skipped per Step 1.3 instructions)















