# Phase 4: Migration, Wiring & Cleanup - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-25
**Phase:** 04-migration-wiring-cleanup
**Areas discussed:** Tool Migration Strategy, Consumer Wiring Approach, Deprecated Type Removal Cadence, MessageNormalizer Adaptation

---

## Tool Migration Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Batch by category | Migrate tools in 4-5 batches grouped by function. Each batch independently testable. | ✓ |
| All at once (big-bang) | One PR migrates all 63 tools. Faster but riskier. | |
| One tool at a time | Individual PRs per tool. Safest but slowest. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Hard cutover per batch | Rewrite each batch's tools directly to RuntimeAgentTool. No adapter shims. | ✓ |
| Adapter shim per batch | Create ToolToRuntimeAdapter wrapping old tools for new runtime. | |
| Protocol conformance dual | Make RuntimeAgentTool a refinement of Tool. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Inject via tool init | Pass context dependencies at construction time (BashTool(workingDir:permissionMode:)). | ✓ |
| Global actor access | Tools read context from shared actor. | |
| Keep ToolUseContext as second param | Add context parameter to call(). | |

| Option | Description | Selected |
|--------|-------------|----------|
| AgentRuntime/Tools/ | Tools are part of the AgentRuntime subsystem. Clean architectural boundary. | ✓ |
| Keep in Tools/ but rewrite | Less git churn but mixes old and new paradigms. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Read-only tools first | FileRead, Glob, Grep, WebSearch, WebFetch — safest, no side effects. | ✓ |
| File mutation tools first | Highest impact, most complex. | |
| Task/Agent tools first | Core orchestration tools. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Delete after first batch validates | Remove old Tool protocol + ToolUseContext immediately after first batch proves the pattern. | ✓ |
| Delete after all tools migrate | Safer but maintains two protocols for entire migration. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Align with Apple | Rename Input → Arguments, call(_ input:) → call(arguments:). Zero consumers — rename now. | ✓ |
| Keep current names | Input and call(_:) are clear conventional Swift. | |

**User's choice:** Clean-slate approach — no backward compatibility, no old data preservation, no old architecture considerations. Everything designed for the new FoundationModels-aligned AgentRuntime.

---

## Consumer Wiring Approach

| Option | Description | Selected |
|--------|-------------|----------|
| Direct replacement | Replace QueryEngine+LLMClient with LanguageModelSessionImpl directly. No feature flag. | ✓ |
| Feature-flag gated | AGENT_RUNTIME_ENABLED flag for gradual cutover. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Use streamResponse(to:) | ChatCommand consumes SessionEvent values progressively. Loop handled internally. | ✓ |
| Keep ChatCommand loop | ChatCommand retains own loop logic, calls respond(to:) per turn. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Rewrite rendering fresh | Build new rendering layer for SessionEvent. Not adapting old StreamRenderer. | ✓ |
| Adapt renderers to SessionEvent | Update StreamRenderer/StatusLine to consume SessionEvent. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Same streamResponse(to:) pattern | ThreadViewModel bridges SessionEvent to ChatBridge/NSTableView. | ✓ |
| Use respond(to:) for App | Non-streaming turns — simpler but loses real-time feedback. | |

**User's choice:** All consumers use streamResponse(to:). Rendering rewritten fresh. Direct replacement, no feature flags.

---

## Deprecated Type Removal Cadence

| Option | Description | Selected |
|--------|-------------|----------|
| Remove as wiring completes | Incremental and verifiable — each consumer wired → its old types deleted. | ✓ |
| All at once after everything wired | Wire first, then delete all deprecated types in one sweep. | |
| Delete first, then wire | Most aggressive — forces all wiring against new API. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Delete App-side providers | Sources/SwiftAgentApp/LLM/ and Sources/SwiftAgentApp/DeepSeek/ entirely removed. | ✓ |
| Keep App providers as wrappers | Thin wrappers around new AgentRuntime providers. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Delete and replace with SQLiteMemoryStore | Old file-based Storage/ deleted. SQLiteMemoryStore is the replacement. | ✓ |
| Keep Storage/, rewrite internals | Keep directory structure but rewrite to use new data types. | |

**User's choice:** Incremental removal tied to wiring progress. App-side providers and old Storage deleted entirely.

---

## MessageNormalizer Adaptation

| Option | Description | Selected |
|--------|-------------|----------|
| Rewrite as TranscriptNormalizer | New file, clean design for Transcript + SessionEvent pipeline. | ✓ |
| Adapt MessageNormalizer in-place | Change existing normalizer to accept Transcript. | |
| Skip normalization entirely | Providers handle internally — risky. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Rethink from scratch | Design for new Transcript + SessionEvent pipeline. Not porting old 17 passes. | ✓ |
| Port all 17 passes | Translate each pass to work with Transcript.Entry. | |

| Option | Description | Selected |
|--------|-------------|----------|
| Inside each provider | Provider-specific Transcript → API wire format. Matches LanguageModelExecutor pattern. | ✓ |
| Shared pre-processing step | Single normalizer before any provider sees transcript. | |

**User's choice:** Normalization is provider-internal, not a shared pipeline. Design from scratch for Transcript, not porting old passes.

---

## Claude's Discretion

- Exact batch composition (which specific tools in each batch)
- Final tool protocol name after old protocol removal (e.g., rename RuntimeAgentTool → Tool)
- Rendering implementation details for CLI and App
- Exact normalization logic per provider
- TranscriptNormalizer design and pass selection
