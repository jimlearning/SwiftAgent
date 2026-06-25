# Phase 4: Migration, Wiring & Cleanup - Context

**Gathered:** 2026-06-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Migrate 63 tools to the FoundationModels-aligned `RuntimeAgentTool` protocol, wire CLI (`ChatCommand`) and App (`ThreadViewModel`) consumers to `LanguageModelSessionImpl`, remove all deprecated types (`LLMClient`, `QueryEngine`, `LLMStreamParser`, old `Tool` protocol, `ToolUseContext`, `StreamEvent`, `ProviderRegistry`, `ModelInfo`, `DeepSeekClient`, old `Storage/` layer, App-side providers), and ensure all tests pass. No backward compatibility — old data is discarded, old architecture is removed.
</domain>

<decisions>
## Implementation Decisions

### Tool Migration Strategy
- **D-01:** Batch by category — 4-5 batches grouped by tool function (read-only tools, file mutation, task/agent, MCP, etc.). Each batch independently testable.
- **D-02:** Hard cutover per batch — rewrite tools directly to `RuntimeAgentTool`. No adapter shims, no dual protocol conformance.
- **D-03:** Inject session context via tool init — tools that need working directory, permission mode, etc. capture them as `let` properties at construction time.
- **D-04:** Move migrated tools to `Sources/SwiftAgentCore/AgentRuntime/Tools/`. New architecture, new location.
- **D-05:** First batch = read-only tools (FileRead, Glob, Grep, WebSearch, WebFetch). Validate pattern before touching destructive tools.
- **D-06:** Delete old `Tool` protocol + `ToolUseContext` (Types/Tool.swift, 1164 lines) after first batch validates. Remaining tools MUST migrate — no dual maintenance.
- **D-07:** Align naming with Apple FoundationModels: `Input` → `Arguments`, `call(_ input:)` → `call(arguments:)`. Breaking change with zero consumers — rename now.

### Consumer Wiring Approach
- **D-08:** Direct replacement — no feature flag (`AGENT_RUNTIME_ENABLED`), no shadow mode. `QueryEngine` + `LLMClient` replaced directly with `LanguageModelSessionImpl`.
- **D-09:** CLI uses `streamResponse(to:)` — `ChatCommand` consumes `SessionEvent` values progressively. The agent loop (re-prompt on tool calls) is handled internally by `LanguageModelSessionImpl`.
- **D-10:** Rewrite CLI rendering fresh for `SessionEvent`. Do not adapt old `StreamRenderer`/`StatusLine` — build new rendering layer.
- **D-11:** App `ThreadViewModel` uses same `streamResponse(to:)` pattern, bridging `SessionEvent` to `ChatBridge`/`NSTableView`.

### Deprecated Type Removal Cadence
- **D-12:** Remove as wiring completes — incremental and verifiable. CLI wired → delete `LLMClient`, `QueryEngine`, `LLMStreamParser`. App wired → delete `DeepSeekClient`, `ProviderRegistry`. Last tool migrated → delete old `Tool` protocol + `ToolUseContext`.
- **D-13:** Delete App-side providers entirely — `Sources/SwiftAgentApp/LLM/` and `Sources/SwiftAgentApp/DeepSeek/`. Replaced by `AgentRuntime/Providers/` (AnthropicProvider, DeepSeekProvider, OpenAIProvider).
- **D-14:** Delete old Storage/ layer — file-based `SwiftAgentStore`, `SessionStore`, `MemoryStore` replaced by `SQLiteMemoryStore` implementing `SessionMemoryStore`.

### MessageNormalizer Adaptation
- **D-15:** Rewrite as `TranscriptNormalizer` — new file, clean design. Do not adapt old `MessageNormalizer` (848 lines).
- **D-16:** Rethink normalization passes from scratch — design for `Transcript` + `SessionEvent` pipeline, not porting old 17 passes.
- **D-17:** Normalization lives inside each provider — provider-specific `Transcript` → API wire format translation. Matches FoundationModels' `LanguageModelExecutor` pattern. No shared pre-processing pipeline.

### Claude's Discretion
- Exact batch composition (which specific tools in each batch)
- Final tool protocol name after old protocol removal (e.g., rename `RuntimeAgentTool` → `Tool`)
- Rendering implementation details for CLI and App
- Exact normalization logic per provider
- TranscriptNormalizer design and pass selection
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### FoundationModels API Reference
- `https://developer.apple.com/documentation/FoundationModels` — Apple's FoundationModels framework documentation
- `https://developer.apple.com/documentation/FoundationModels/Tool` — Apple's Tool protocol definition
- `https://developer.apple.com/documentation/FoundationModels/LanguageModel` — LanguageModel protocol (Beta, WWDC26)

### Project Architecture
- `docs/ARCHITECTURE.md` — Module boundaries, design decisions, data flow
- `docs/macApp_ARCHITECTURE.md` — App target architecture
- `docs/TUI_ARCHITECTURE.md` — CLI/TUI rendering engine design

### New Runtime (built in Phases 1-3)
- `Sources/SwiftAgentCore/AgentRuntime/AgentRuntime.swift` — LanguageModelSession protocol + subsystem protocols
- `Sources/SwiftAgentCore/AgentRuntime/AgentRuntimeImpl.swift` — LanguageModelSessionImpl actor
- `Sources/SwiftAgentCore/AgentRuntime/Tools/RuntimeAgentTool.swift` — New tool protocol (~6 members)
- `Sources/SwiftAgentCore/AgentRuntime/Providers/` — AnthropicProvider, DeepSeekProvider, OpenAIProvider, SQLiteMemoryStore, AgentPermissionBridge

### Old Code to be Removed (read to understand what to delete)
- `Sources/SwiftAgentCore/Types/Tool.swift` — Old Tool protocol, ToolUseContext, ToolOutput (1164 lines)
- `Sources/SwiftAgentCore/Agent/QueryEngine.swift` — Old agent loop
- `Sources/SwiftAgentCore/LLM/LLMClient.swift` — Old Anthropic API client (1079 lines)
- `Sources/SwiftAgentCore/LLM/LLMStreamParser.swift` — Old SSE parser
- `Sources/SwiftAgentCore/Agent/MessageNormalizer.swift` — Old 17-pass normalizer (848 lines)
- `Sources/SwiftAgentCore/Storage/` — Old file-based persistence (8 files)
- `Sources/SwiftAgentApp/LLM/` — Old App provider layer
- `Sources/SwiftAgentApp/DeepSeek/` — Old DeepSeek standalone client

### Requirements
- `.planning/REQUIREMENTS.md` — MIG-01 through MIG-05 requirements
- `.planning/ROADMAP.md` — Phase 4 goal and acceptance criteria

### Planning Artifacts
- `.planning/codebase/ARCHITECTURE.md` — System overview and component responsibilities
- `.planning/codebase/STRUCTURE.md` — Directory layout and naming conventions
- `.planning/codebase/CONCERNS.md` — Tech debt, known bugs, fragile areas
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **LanguageModelSessionImpl** (AgentRuntimeImpl.swift): Fully functional agent loop with reentrancy guard, tool execution routing, and memory persistence. Ready for consumer wiring.
- **SQLiteMemoryStore** (Providers/): Already implements SessionMemoryStore. Replaces old Storage/ layer.
- **All 3 ModelProviders** (AnthropicProvider, DeepSeekProvider, OpenAIProvider): Already implement LanguageModelExecutor. Ready for consumer use.
- **SessionEvent** (SessionEvent.swift): Provider-agnostic streaming events. Already used by streamResponse(to:).

### Established Patterns
- **Actor-based session:** LanguageModelSessionImpl is an actor with isResponding guard. Consumers call streamResponse(to:) and iterate SessionEvent values.
- **Provider isolation:** Wire-format types internal to each provider. Consumers only see SessionEvent + Transcript.
- **Permission gating:** executeTool() routes through permissionEngine.check(.runCommands) before every tool call.
- **One tool per file:** 63 existing tools follow this convention — maintain it.

### Integration Points
- **ChatCommand** (1192 lines, Sources/SwiftAgentCLI/): Replace `QueryEngine.run()` call with `session.streamResponse(to:)`. Replace StreamEvent rendering with SessionEvent rendering.
- **ThreadViewModel** (Sources/SwiftAgentApp/ViewModels/): Replace `AgentSessionManager` with `LanguageModelSessionImpl`.
- **AppKitChatBridge** (Sources/SwiftAgentApp/Content/): Update ChatBridge to accept SessionEvent values from new stream.
- **Tool registration:** Tools registered via `toolEngine.register(tool:metadata:)` at session init time.
</code_context>

<specifics>
## Specific Ideas

- User wants the most elegant design aligned with Apple FoundationModels — not a backward-compatible migration
- Align naming with Apple: `Arguments` not `Input`, `call(arguments:)` not `call(_ input:)`
- Read-only tools migrate first as the validation batch
- Old protocol deleted immediately after first batch proves the pattern
- CLI and App rendering rewritten fresh for SessionEvent — not adapted from old StreamRenderer
- Each provider handles its own normalization internally — no shared normalizer
- File-based Storage/ deleted entirely — SQLiteMemoryStore is the replacement
</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.
</deferred>

---

*Phase: 04-migration-wiring-cleanup*
*Context gathered: 2026-06-25*
