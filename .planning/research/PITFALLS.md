# Domain Pitfalls

**Domain:** AI Agent API Reorganization (Anthropic-specific to FoundationModels Agent Runtime)
**Researched:** 2026-06-25
**Confidence:** HIGH (verified against actual codebase: 1156-line Tool.swift, 1079-line LLMClient.swift, 63 tool source files, 13-case StreamEvent enum)

---

## Critical Pitfalls

Mistakes that cause rewrites, silent breakage, or blocking regressions.

### Pitfall 1: Protocol Member Deletion Without Conformance Verification

**What goes wrong:** When you reduce the `Tool` protocol from 43 members to a target of ~4 (`name`, `description`, `inputSchema`, `call`), you discover after deletion that the extension default behavior for a removed member like `searchHint` is consumed by `ToolSearchTool` and `SystemPromptBuilder` for tool discovery. The system compiles (extension defaults vanish cleanly), but tools silently stop appearing in search results and prompt injection.

**Why it happens:** Swift protocol extension defaults make member removal a silent operation. The compiler doesn't warn when a consumer of the protocol depends on a default that no longer exists if the consumer never explicitly called that member — but it does call it indirectly through `tool.searchHint`. The 55 tools that override `searchHint` disappear from `ToolSearchTool` results because the new protocol has no `searchHint` property to query, and the refactoring code that maps old tools to new doesn't carry that metadata forward.

**Consequences:** Tool search breaks silently. Models can't discover deferred tools. The `alwaysLoad` mechanism stops working. Users get "Tool not found" errors for deferred tools that should be searchable.

**Prevention:** Before deleting any protocol member, perform a full call-site audit:
```bash
# For EVERY member targeted for removal, find ALL consumers
grep -rn "\.searchHint\b\|\.shouldDefer\b\|\.isEnabled\b" Sources/ --include="*.swift"
```
Map each consumer to the new API surface. Do not delete a member until every consumer has been migrated and verified. The 55-tool `searchHint` override count means this is not a "cleanup" — it's a migration of a heavily-used mechanism.

**Detection:** `swift test --filter ToolSearchTests` should cover tool search behavior. If no such tests exist (and currently there are only 197 lines of tool-specific tests), write them *before* protocol deletion. Warning sign: any protocol member overridden by >5 tools is a de facto API contract, not an optional convenience.

**Phase to address:** Phase 1 (Tool protocol simplification). This is ground zero. Must be the first thing done, with exhaustive test coverage built before any member is removed.

---

### Pitfall 2: The "Same Event, Double-Rendered" Bug (Streaming Semantics Migration)

**What goes wrong:** When migrating from delta-based streaming (`StreamEvent.textDelta("Hello")` + `textDelta(" world")`) to snapshot-based streaming (`PartiallyGenerated(text: "Hello")` + `PartiallyGenerated(text: "Hello world")`), half the consumers treat snapshots as deltas and produce "HelloHello worldHello world" output, while the other half diff correctly and produce "Hello world". The result depends on which code path each consumer takes, creating a Heisenbug that only manifests in certain rendering modes.

**Why it happens:** This is a documented production failure pattern. Anthropic's own SDK was found to sometimes return text in both `content_block_start` AND `content_block_delta`, producing the "HelloHello" bug when consumers naively concatenate. The delta-vs-snapshot distinction is subtle: a `PartiallyGenerated` snapshot contains the *total accumulated output so far*, not the *new content since last event*. Consumers that don't maintain a `previousSnapshot` for diffing will double-render.

**Current codebase risk:** The existing `LLMStreamParser.ContentBlockAccumulator` (182 lines, `Sources/SwiftAgentCore/LLM/LLMStreamParser.swift`) already correctly handles delta accumulation for Anthropic format. But consumers include:
- `StreamRenderer.render(event:currentOutput:)` — renders individual deltas
- `QueryEngine` loop — accumulates deltas via `ContentBlockAccumulator`
- `ChatCommand` terminal rendering — consumes `StreamEvent` directly
- App-side SwiftUI rendering — yet another consumer path

If the migration introduces a new event type alongside the old one, or changes event semantics in-place, consumers will split between old-code-that-works and new-code-that-has-the-bug.

**Prevention:** Use a **parallel output comparison strategy** during migration:
1. Keep the old `AsyncThrowingStream<StreamEvent>` path running in production
2. Add a new `AsyncSequence<PartiallyGenerated<T>>` path running in shadow mode
3. At each stream event, compute the rendered string from BOTH paths
4. Assert they produce identical rendered output
5. Only cut over consumers one at a time after verifying no rendering diffs in shadow mode

Do NOT run old and new in the same consumer at once. Migrate consumer-by-consumer: StreamRenderer first (simplest), then QueryEngine (most complex).

**Detection:** Rendering difference detection should be built into the migration infrastructure. At every snapshot event, compute `expectedRenderedOutput = oldDeltaPath.accumulate(event)` and `actualRenderedOutput = newSnapshotPath.render(snapshot)` and assert equality. Warning sign: any consumer that calls `.textDelta` case-matching directly (the current `StreamRenderer` does this).

**Phase to address:** Phase 3 (snapshot streaming). Must come AFTER protocol simplification and AFTER provider abstraction, because the new streaming model depends on both being stable.

---

### Pitfall 3: LanguageModel Protocol Becomes a Leaky Abstraction

**What goes wrong:** You introduce a `LanguageModel` protocol with clean semantics (e.g., `func streamResponse(to: Prompt) -> AsyncSequence<PartiallyGenerated<Response>>`), but provider-specific behavior leaks through:
- Anthropic requires that tool *results* immediately follow tool *use* blocks in the content array (positional pairing)
- OpenAI uses `call_id` for tool correlation (ID-based pairing)
- DeepSeek's Anthropic-compatible endpoint rejects Anthropic beta headers (`fine-grained-tool-streaming-2025-05-14`) and fails silently with `stop_reason=max_tokens` instead of producing a final answer
- Google returns `finishReason: "STOP"` even when there are pending function calls

When the abstraction layer passes through the position-dependent behavior to one caller and the ID-dependent behavior to another, the agent loop breaks in provider-specific ways that can't be reproduced without switching providers.

**Why it happens:** The current codebase already has this pattern: `LLMClient.swift` has a hardcoded `baseURL = "https://api.deepseek.com/anthropic"` default (line 86), meaning the "Anthropic" client is actually talking to DeepSeek's compat endpoint. The `LLMProvider` protocol in the App layer has 4 providers, but `OpenAIProvider` is a stub that returns `OpenAIError.notImplemented`. Each new provider surfaces edge cases that the original Anthropic-only design never considered:
- Tool call lifecycle (pairing semantics)
- Thinking/reasoning block handling (Anthropic has explicit `thinking` blocks; OpenAI o-series doesn't)
- Error formats
- Streaming wire format differences (named SSE events vs flat data: lines)

**Prevention:** Design the `LanguageModel` protocol with an **explicit capability negotiation** step:
```swift
protocol LanguageModel {
    var capabilities: LanguageModelCapabilities { get }
    // capabilities specifies: toolPairingStrategy, supportsThinkingBlocks,
    // maxContextWindow, streamingWireFormat, etc.
}
```

The protocol surface must be rich enough for the executor to adapt its behavior per-provider. If you make the protocol too thin (just `streamResponse`), providers will need to encode provider-specific behavior into generic response types, creating a leak. The `LanguageModelCapabilities` struct (REQ-API-08) is critical — it's not optional metadata, it's the contract that prevents leaks.

Also: explicitly handle the DeepSeek-beta-header bug in `DeepSeekExecutor` by detecting the endpoint type and suppressing Anthropic-specific headers for proxied endpoints. This is a known production failure mode where the model stops at the thinking block and never produces a final answer.

**Detection:** Write a **cross-provider conformance test** that sends identical conversation history to all providers and asserts that the agent loop produces semantically equivalent tool call sequences. If provider A triggers a tool call and provider B doesn't, the abstraction is leaking. Warning sign: any `switch provider { case .anthropic: ... case .deepSeek: ... }` in the agent loop.

**Phase to address:** Phase 2 (LanguageModel protocol). This is the core abstraction layer. Getting capability negotiation right from the start prevents cascading provider-specific workarounds.

---

### Pitfall 4: Tool Conformance Migration Orphaning Feature Flags

**What goes wrong:** 39 of 58 tool structs override `isEnabled()` with feature flag checks (`FeatureFlags.isAgentSwarmsEnabled()`, `FeatureFlags.isLSPEnabled()`, etc.). When the new ~4-member Tool protocol removes `isEnabled()`, these feature gates have nowhere to live. If they move to the ToolExecutor or ToolRegistry, the gate becomes centralized and loses per-tool granularity. If they move to some kind of tool metadata, every tool registration site must be updated. Either way, tools that should be disabled in certain configurations become unconditionally available.

**Why it happens:** The current `isEnabled()` pattern couples feature flags to tool identity. This is convenient (one override per tool) but not architecturally clean. The FoundationModels approach would move this to a `Profile` concept (REQ-API-10) where the profile specifies which tools are active. But the migration needs to bridge the gap without breaking anything.

**Consequences:** Features like agent swarms, LSP integration, cron scheduling, worktree mode — all gated behind `isEnabled()` — become unconditionally available. This is both a correctness issue (features that shouldn't work on certain platforms become available) and a safety issue (experimental features get exposed to production users).

**Prevention:** Plan the migration path explicitly:
1. Add a `ToolRegistry` method: `func isEnabled(_ toolName: String) -> Bool` that checks registered metadata
2. Keep the old `isEnabled()` in a compatibility extension on the new Tool protocol during transition
3. Migrate each tool's `isEnabled()` override to registry metadata one at a time
4. Each migration step is testable (register tool with `enabled: false`, verify it's not callable)
5. Only remove `isEnabled()` from the protocol after zero overrides remain

**Detection:** Before removal, assert count of `isEnabled()` overrides is zero:
```bash
grep -c "func isEnabled()" Sources/SwiftAgentCore/Tools/*.swift
```
Warning sign: 39 overrides means this is the second-most-overridden member after `searchHint`. Treat it like a critical migration, not a cleanup.

**Phase to address:** Phase 1 (Tool protocol simplification) alongside other member migrations.

---

### Pitfall 5: Consumer Fragmentation During Streaming Migration

**What goes wrong:** The `StreamEvent` enum has 13 cases and 5+ consumers (LLMStreamParser, ContentBlockAccumulator, QueryEngine, StreamRenderer, ChatCommand terminal, App SwiftUI). During migration from `AsyncThrowingStream<StreamEvent>` to `AsyncSequence<PartiallyGenerated<T>>`, consumers migrate at different rates. QueryEngine uses the new snapshot API but StreamRenderer still expects `StreamEvent.textDelta`. The compiler catches some mismatches (type errors), but others are subtle: the QueryEngine accumulates snapshots correctly, but when it passes the accumulated text to StreamRenderer, the renderer receives the full text (snapshot) and treats it as a delta, producing double output in the terminal but correct output in the app's SwiftUI.

**Why it happens:** The current streaming model has structured lifecycle events (`contentBlockStart`, `contentBlockStop`, `messageStop`) that signal boundaries in the response. A snapshot model replaces these with state that the snapshot *contains* (e.g., `PartiallyGenerated.isComplete`). But consumers of the old model use the lifecycle events as control flow (e.g., `QueryEngine` runs tool execution at `contentBlockStop`, enters end_turn at `messageStop`). If the new model expresses these boundaries differently, some consumers interpret them correctly and others don't.

**Prevention:** Define the migration as a **consumer-at-a-time cutover**, not an in-place refactoring:
1. Introduce the new streaming API as a parallel path (not replacing the old)
2. Each consumer gets a dedicated adapter that converts new-style events to the interface it expects
3. Migrate consumers in dependency order: `ContentBlockAccumulator` first (it's the simplest, purely internal), then `StreamRenderer` (stateless rendering), then `QueryEngine` (has the tool execution loop), then CLI/App consumers
4. At each step, verify with the parallel output comparison described in Pitfall 2
5. Only remove the old `StreamEvent` path after ALL consumers have been verified on the new path for a full test cycle

**Detection:** Compile-time: only one consumer at a time references the old API path. Runtime: the parallel output comparison catches semantic mismatches. Warning sign: any file that imports both old and new stream types simultaneously.

**Phase to address:** Phase 3 (snapshot streaming). Consumer migration ordering is critical — the QueryEngine cannot use snapshots until StreamRenderer knows how to render them.

---

## Moderate Pitfalls

### Pitfall 6: The Three-Abstraction-Layer Trap

**What goes wrong:** The codebase already has TWO abstraction layers for LLM interaction:
1. `LLMClient` (Core) — Anthropic Messages API client, returns `AsyncThrowingStream<StreamEvent>`
2. `LLMProvider` protocol (App) — multi-provider surface with `AnthropicProvider`, `DeepSeekProvider`, stub `OpenAIProvider`
3. Plus `DeepSeekClient` (App/DeepSeek/) — standalone DeepSeek integration, separate from both

Adding `LanguageModel` as a THIRD abstraction layer creates a situation where developers don't know which abstraction to use for which purpose. New features might use `LanguageModel` while existing features use `LLMClient`, and no single developer understands why all three exist.

**Why it happens:** The project plan (PROJECT.md) correctly identifies that models should be swappable plugins. But it doesn't address what happens to the existing two abstraction layers during and after migration. Will `LLMClient` be removed? Will `LLMProvider` be replaced by `LanguageModelExecutor`? Will `DeepSeekClient` be folded into a unified path?

**Prevention:** Explicitly declare the migration end-state for each existing abstraction:
- `LLMClient` → REMOVED. Replaced by `LanguageModel` protocol + specific executors.
- `LLMProvider` (App) → MIGRATED to `LanguageModelExecutor` protocol. The App's provider registry becomes a `LanguageModelExecutor` registry.
- `DeepSeekClient` → FOLDED into `DeepSeekExecutor` (REQ-API-07). No standalone code path.
- `LLMDebugLogger` → REMOVED after all callers migrate to `DebugLogSink` (already in-progress per CONCERNS.md).

Write this end-state into a migration document and reference it in every phase plan. After each phase, verify the gap between current state and end-state is decreasing, not increasing.

**Detection:** Count the number of distinct LLM abstraction protocols after each phase. It should decrease monotonically. Warning sign: any new code that adds a fourth abstraction.

**Phase to address:** Phase 2 (LanguageModel protocol). This is the phase where the end-state must be clearly defined and communicated.

---

### Pitfall 7: The JSON Accumulator Rewrite Creates Silent Parse Failures

**What goes wrong:** The current `LLMStreamParser.ContentBlockAccumulator` handles Anthropic's streaming tool input JSON accumulation (partial_json chunks parsed at content_block_stop). During migration to a snapshot-based model, the accumulation logic is rewritten. But the rewrite misses edge cases that the original handled:
- Double-stringified JSON (`"\"{}\""` → `{}`) via `safeParseJSON()`
- Mid-stream truncation (LLM hits max_tokens before completing JSON)
- Provider-specific JSON formatting (Anthropic sends partial JSON; OpenAI sends pre-escaped JSON)

The new accumulator silently produces empty tool inputs for edge cases that the old accumulator handled correctly. Tools execute with `[:]` input instead of the intended arguments.

**Why it happens:** The existing `safeParseJSON()` function (line 128 of LLMStreamParser.swift) exists because Anthropic's API sometimes double-stringifies JSON. This is accumulated production wisdom — it wasn't obvious from the API spec, it was discovered through debugging. Rewriting the accumulator risks losing this knowledge. Similarly, `accumulateToolInput(from:)` handles empty deltas and missing keys.

**Prevention:** Do NOT rewrite the accumulator. **Preserve it verbatim** as an internal utility. The snapshot model's `PartiallyGenerated` should internally use the same accumulator logic, just with a different output wrapper. The accumulator is battle-tested against real API behavior; changing it introduces risk without benefit.

Specifically:
1. Extract `ContentBlockAccumulator` into its own file (it's already a standalone struct)
2. Add it as a dependency of the new streaming layer
3. The new `PartiallyGenerated` snapshot is just the accumulator's current state serialized differently
4. Write regression tests that feed the accumulator edge-case JSON (double-stringified, truncated, empty) and assert correct parsing

**Detection:** Feed the exact same SSE data through old and new accumulators, compare final parsed tool inputs. Warning sign: any diff in tool input parsing between old and new paths.

**Phase to address:** Phase 3 (snapshot streaming). The accumulator is the bridge between wire format and structured output.

---

### Pitfall 8: The 43-Member Protocol Defaults Are Not Just Convenience

**What goes wrong:** The Tool protocol extension provides defaults for 39 of 43 members. At first glance, this means only 4 members are "required" and 39 are "optional" — making the reduction from 43 to 4 seem trivial. But the defaults encode business rules that consumers depend on:
- `isDestructive()` defaults to `false` — the permission engine uses this to decide auto-approval
- `interruptBehavior()` defaults to `.block` — controls whether new user input interrupts running tools
- `prompt()` defaults to calling `description()` — the system prompt builder relies on this
- `userFacingName()` defaults to returning `name` — the UI layer depends on this

If you remove these from the protocol, the defaults disappear from the type system. Consumers that call `tool.isDestructive(input)` would need to find that information elsewhere. The question is where — and the answer changes the architecture of permissions, UI rendering, and system prompt building.

**Prevention:** Category analysis before deletion. Group the 43 members by consumer:
| Category | Members | Consumer |
|----------|---------|----------|
| LLM-facing | `name`, `description`, `inputSchema`, `prompt`, `searchHint` | ToolExecutor, SystemPromptBuilder, ToolSearchTool |
| Permission | `isReadOnly`, `isDestructive`, `checkPermissions`, `validateInput`, `isOpenWorld`, `requiresUserInteraction` | PermissionEngine, ToolExecutor |
| Execution | `call`, `isConcurrencySafe`, `interruptBehavior`, `isEnabled` | ToolExecutor, QueryEngine |
| UI/Display | `userFacingName`, `getActivityDescription`, `getToolUseSummary`, `userFacingNameBackgroundColor` | StreamRenderer, Terminal, SwiftUI |
| Hook/Plugin | `preparePermissionMatcher`, `inputsEquivalent`, `backfillObservableInput` | HookSystem |
| MCP/SDK | `isMcp`, `mcpInfo`, `isLsp`, `mapToolResultToToolResultBlockParam` | MCP integration |
| Schema | `inputJSONSchema`, `outputSchema`, `strict` | ToolExecutor validation |
| Result processing | `extractSearchText`, `isResultTruncated`, `maxResultSizeChars` | Transcript persistence, UI collapse |
| Auto-mode | `toAutoClassifierInput`, `isSearchOrReadCommand` | Safety classifier |
| Deferred loading | `shouldDefer`, `alwaysLoad` | SystemPromptBuilder (decides initial tool list) |
| Legacy/edge | `aliases`, `getPath`, `isTransparentWrapper` | Various consumers |

Each category needs a migration plan per category before any member is deleted.

**Detection:** Before deletion, for each member: `grep -rn "\.memberName\b" Sources/` and verify zero callers remain. Warning sign: any member with >0 callers after "migration" but before deletion.

**Phase to address:** Phase 1 (Tool protocol simplification). This is the biggest Phase 1 risk.

---

### Pitfall 9: The App Provider Registry and Core LanguageModel Become Competing Registries

**What goes wrong:** The App already has a `ProviderRegistry` (`Sources/SwiftAgentApp/LLM/ProviderRegistry.swift`) that manages `LLMProvider` instances (Anthropic, DeepSeek, OpenAI). When `LanguageModel` is introduced at the Core level with its own executor registry pattern, the two registries compete. The App might register providers in its registry while the Core queries the `LanguageModel` registry, or vice versa. Missing providers in one registry but present in the other create "model not found" errors that only affect certain code paths.

**Why it happens:** The App's provider abstraction is UI-aware (it has capabilities like `supports(.computerUse)`, user-facing model names). The Core's `LanguageModel` is supposed to be UI-agnostic. But both need to answer the question "which models are available and what can they do?" If they answer differently, the App shows a model in the picker that the Core can't actually use, or the Core supports a model that doesn't appear in the UI.

**Prevention:** Consolidate into a single registry. The `LanguageModel` protocol is the Core abstraction; the App's `ProviderRegistry` becomes a thin wrapper that:
1. Maps user-facing model names to `LanguageModel` instances
2. Maintains the capabilities info for UI display
3. Delegates all actual model interaction to the Core's `LanguageModelSession`

Do NOT maintain two registries with overlapping responsibilities. REQ-API-08 (`LanguageModelCapabilities`) should be the single source of truth for what a model can do.

**Detection:** After Phase 2, `grep -rn "ProviderRegistry\|LLMProvider" Sources/SwiftAgentApp/LLM/` should show only adapter/thin-wrapper code, not independent model management. Warning sign: any code that queries both registries.

**Phase to address:** Phase 2 (LanguageModel protocol). Provider registry consolidation is part of defining the `LanguageModel` boundary.

---

### Pitfall 10: Hook System Breaks When Tool Call Signatures Change

**What goes wrong:** The Hook system (`HookSystem` in QueryEngine, hook types in `HookJSONTypes.swift`) intercepts tool calls before/after execution. If the Tool protocol's `call()` method signature changes (e.g., parameters removed or reordered), the hook system's type-based matching breaks. Hooks that matched `BashTool.call(input:context:canUseTool:parentMessage:onProgress:)` no longer match the new `Tool.call(input:context:)` signature.

**Why it happens:** The 968-line `HookJSONTypes.swift` file defines hook event types that reference tool execution semantics. When the tool interface changes, hook event signatures must change too. But hooks are user-defined (via hook config files), so changing the internal hook format breaks existing hook installations.

**Prevention:** The hook system should operate on an intermediary `ToolInvocation` type that is stable across the Tool protocol migration:
```swift
struct ToolInvocation {
    let toolName: String
    let input: [String: JSONValue]
    let context: ToolUseContext
}
```

Hooks match on `ToolInvocation`, not on the raw Tool protocol. The ToolExecutor converts new-protocol calls into `ToolInvocation` before passing them to the hook system. This decouples the hook wire format from the Tool protocol shape.

**Detection:** Hook-related tests (if any exist) should pass unchanged after the Tool protocol migration. Warning sign: any change to `HookJSONTypes.swift` during Phase 1.

**Phase to address:** Phase 1 (Tool protocol simplification). The hook decoupling must happen before or during the Tool protocol change, not after.

---

## Minor Pitfalls

### Pitfall 11: Test File Organization Obscures What Broke

**What goes wrong:** Tests are organized as `Phase{N}{Topic}Tests.swift` with each file covering an entire topic. After the API reorganization, a test file like `Phase4ToolsTests.swift` (only 197 lines for 63 tools) either passes entirely or fails entirely — but when it fails, the test runner says "Phase4ToolsTests: 8 failures" without indicating which of the 43 changed protocol members caused which failure. Developers spend hours bisecting.

**Prevention:** Before the reorganization, refactor tests to one-file-per-concern:
- `ToolProtocolNameTests.swift` — only tests `name` behavior
- `ToolProtocolCallTests.swift` — only tests `call()` behavior
- `ToolProtocolSearchHintTests.swift` — tests tool search
- `ToolProtocolFeatureFlagsTests.swift` — tests `isEnabled` gating

This way, when `searchHint` is migrated, only `ToolProtocolSearchHintTests.swift` changes, and failures are immediately localized.

**Detection:** If a test file has >5 `@Test` methods covering >3 protocol members, it's too coarse. Warning sign: test failures that require reading the entire test file to diagnose.

**Phase to address:** Phase 0 (preparation). Test restructuring should happen before any API changes.

---

### Pitfall 12: The Migration Creates Two Tool Execution Paths

**What goes wrong:** During the migration, some tools are registered with the new `Tool` protocol and others with the old one via a compatibility adapter. The `ToolExecutor` needs to handle both. If the adapter path has different error handling, permission checking, or timeout behavior than the native path, tools behave differently depending on whether they've been migrated yet.

**Prevention:** The compatibility adapter must be a **passthrough with zero behavioral difference**:
```swift
struct LegacyToolAdapter: Tool {
    let legacy: any LegacyTool
    // Every method delegates 1:1 to legacy
}
```

Do NOT add error handling, logging, or behavior changes in the adapter. The adapter exists solely to bridge compile-time type systems. Validate this with property-based tests: for every tool, execute it via both old and adapter paths with identical inputs and assert identical outputs.

**Detection:** Run `swift test --filter Adapter` with assertions that adapter output == direct output for all 58 tools. Warning sign: any `if` statement in the adapter that isn't a simple delegation.

**Phase to address:** Phase 1 (Tool protocol simplification). The adapter is the bridge.

---

### Pitfall 13: `nonisolated(unsafe)` Escape Hatches Accumulate During Migration

**What goes wrong:** The codebase already has three `nonisolated(unsafe)` declarations (CONCERNS.md lines 88-93). During migration, when new async contexts are introduced (e.g., `LanguageModelSession` actors, `PartiallyGenerated` async sequences), developers add more `nonisolated(unsafe)` annotations as quick fixes for Sendable conformance errors. The migration finishes with 8+ unsafe escape hatches, making data race diagnosis harder than before the migration started.

**Prevention:** Add a CI check that fails on any new `nonisolated(unsafe)`: 
```bash
git diff origin/main -- Sources/ | grep "nonisolated(unsafe)" && exit 1
```

Every new `nonisolated(unsafe)` must be justified in a code comment referencing a specific migration task that will remove it. No blanket "temporary" unsafe annotations.

**Detection:** `grep -c "nonisolated(unsafe)" Sources/` before and after each phase. The count should not increase. Warning sign: any new `nonisolated(unsafe)` without a tracking issue number.

**Phase to address:** All phases. This is a continuous invariant.

---

## Phase-Specific Warnings

| Phase | Likely Pitfall | Mitigation |
|-------|---------------|------------|
| Phase 0 (Prep) | Test reorganization adds 3 weeks to schedule | Only reorganize tests for the 5 most-critical protocol members: `name`, `call`, `searchHint`, `isEnabled`, `inputSchema` |
| Phase 1 (Tool Protocol) | 55 tool `searchHint` overrides orphaned → tool search silently broken | Build ToolSearchTool regression tests BEFORE removing `searchHint`; migrate metadata to registry |
| Phase 1 (Tool Protocol) | 39 tool `isEnabled` overrides orphaned → feature gates bypassed | Countdown migration: remove only after zero overrides remain |
| Phase 1 (Tool Protocol) | Hook system breaks on `call()` signature change | Decouple hooks to `ToolInvocation` type before changing `call()` |
| Phase 2 (LanguageModel) | Three abstractions coexist (LLMClient + LLMProvider + LanguageModel) | Declare end-state: LLMClient removed, LLMProvider migrated to LanguageModelExecutor |
| Phase 2 (LanguageModel) | App ProviderRegistry and Core LanguageModel registry compete | Consolidate to single registry before Phase 2 ends |
| Phase 3 (Snapshot Streaming) | Consumers treat snapshots as deltas → double rendering | Parallel output comparison in shadow mode before consumer cutover |
| Phase 3 (Snapshot Streaming) | ContentBlockAccumulator rewrite loses edge-case parsing | Preserve accumulator verbatim; wrap with snapshot output |
| Phase 4 (Adapter Cleanup) | Legacy adapter becomes permanent tech debt | Set deadline: adapter must be removed within 1 phase of all tools migrated |

---

## Prevention Strategies (Summary)

1. **Call-site audit before deletion** — Every protocol member must have zero callers before removal. Use `grep`, not assumptions.
2. **Parallel output comparison** — Run old and new streaming paths in shadow mode; assert identical rendered output before cutting over any consumer.
3. **Consumer-at-a-time migration** — Never migrate two consumers to a new API simultaneously. Each consumer cutover is independently verified.
4. **Capability negotiation** — `LanguageModel` must expose provider capabilities explicitly to prevent leaky abstractions.
5. **Preserve battle-tested internals** — The `ContentBlockAccumulator`, `safeParseJSON`, and tool input accumulation logic should be wrapped, not rewritten.
6. **Declare end-state** — Document what gets removed, migrated, and folded for every existing abstraction. Verify progress toward end-state after each phase.
7. **Adapter fidelity testing** — Compatibility adapters must produce identical output to direct calls for all 58 tools.
8. **`nonisolated(unsafe)` freeze** — No new unsafe annotations during migration without tracking issue.

---

## Sources

- **Codebase analysis:** Tool.swift (1156 lines, 43 protocol members, 39 extension defaults), 63 tool source files (58 conforming structs), LLMClient.swift (1079 lines, Anthropic-specific), LLMStreamParser.swift (ContentBlockAccumulator, safeParseJSON), StreamEvent.swift (13-case enum, delta-based)
- **CONCERNS.md:** 23 documented concerns including dual logging protocols, `nonisolated(unsafe)` escape hatches, fragile areas (MCP transport, message schema compatibility)
- **TESTING.md:** 197 lines of tool-specific tests for 63 tools, no mock LLM client, no full agent loop integration tests
- **PROJECT.md:** 12 active requirements (REQ-API-01 through REQ-API-12), FoundationModels target architecture
- **AboutAppleFoundationModels.md:** LanguageModel protocol, LanguageModelSession, snapshot streaming model, @Generable structured output
- **Production streaming pitfalls:** `req_llm` Issue #272 (streaming vs non-streaming code path divergence causing 4+ provider-specific bugs), Anthropic SDK "HelloHello" duplication bug, DeepSeek beta header injection failure mode, Google `finishReason: "STOP"` conflated with tool calls (Issue #271)
- **Refactoring patterns:** Expand-Migrate-Contract (Strangler Fig), OpenRewrite deterministic transformations, multi-layer validation (unit + API comparison + consumer regression), traffic shadowing for verification
