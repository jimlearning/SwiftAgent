# Project Research Summary

**Project:** SwiftAgent FoundationModels API Reorganization
**Domain:** AI Coding Agent Runtime -- Provider-Agnostic Agent API (brownfield refactoring)
**Researched:** 2026-06-25
**Confidence:** HIGH

## Executive Summary

This project reorganizes the SwiftAgent AI agent API from its current Anthropic-specific architecture (43 tools, 258+ tests, ~30 core API files) into a provider-agnostic Agent Runtime modeled on Apple's FoundationModels framework (WWDC25/26 LanguageModelSession API). The core principle: **models become plugins, not the architecture.**

The recommended approach is a layered, brownfield migration executed in 9 phases. Foundation types and protocols are built first (Phases 0-2), the unified LanguageModelSession centralizes the agent loop (Phase 3), provider executors are built in parallel (Phases 4-6), tools are migrated to the simplified protocol (Phase 7), and entry point adapters wire everything into CLI and App targets (Phase 8). This is deliberately NOT a rewrite -- the existing QueryEngine, LLMClient, StreamEvent, and 30-member Tool protocol remain operational until the final phase when consumers are cut over.

The three critical risks are: (1) silently orphaning heavily-overridden protocol members (searchHint has 55 overrides, isEnabled has 39) during Tool protocol simplification, (2) the delta-to-snapshot streaming semantics mismatch producing double-rendering bugs in heterogeneous consumers, and (3) the LanguageModel protocol becoming a leaky abstraction if provider capability negotiation is insufficient. Each is mitigated by explicit prevention strategies documented in PITFALLS.md: call-site audits before deletion, parallel output comparison in shadow mode, and a rich LanguageModelCapabilities struct that encodes per-provider behavioral differences.

## Key Findings

### Recommended Stack

The existing Swift 6.3 / macOS 15.0+ / SPM stack is the correct foundation. The reorganization is purely architectural -- no new dependencies are required beyond what the codebase already uses. The key framework capabilities needed (actors for session isolation, Sendable for protocol conformance, AsyncSequence for snapshot streaming) are available in Swift 6.3 today. The FoundationModels @Generable macro (compile-time schema derivation) is a future capability; initial implementation uses runtime Codable-based schema derivation until the macro infrastructure is built.

**Core technologies (unchanged):**
- **Swift 6.3 (SPM, swift-tools-version 6.2):** Language foundation. Actors, Sendable, AsyncSequence, existentials (any Tool) all available.
- **ArgumentParser 1.5.0:** CLI entry point. ChatCommand adapter phase wires into this.
- **SwiftTerm 1.3.0:** Terminal emulation. Snapshot streaming consumer.
- **KeychainAccess 4.2.0:** Secure API key storage. Per-provider executors use this.
- **Swift Collections 1.0.0:** OrderedDictionary for Transcript entries, tool registry ordering.

**No new dependencies needed.** The reorganization is internal restructuring, not external integration.

### Expected Features

**Must have (table stakes -- MVP):**
- LanguageModel protocol + LanguageModelCapabilities -- Model abstraction boundary. Everything depends on this.
- LanguageModelSession -- Unified public API replacing QueryEngine + LLMClient.
- LanguageModelExecutor protocol (internal) -- Provider executor contract. Transcript-to-wire translation.
- Simplified Tool protocol (~4 members: name, description, Arguments associated type, call()) -- Matches FoundationModels shape.
- LanguageModelError enum -- Unified error taxonomy replacing fragmented per-provider errors.
- Transcript -- Provider-agnostic conversation history. Canonical representation.
- Snapshot streaming (AsyncSequence<PartiallyGenerated<T>>) -- Provider-agnostic progress snapshots.
- Tool execution harness (permissions, compaction, retry) -- Preserved from existing code, wrapped behind session.
- MCP support -- Tool implementations conforming to new protocol; MCP transport unchanged.

**Should have (differentiators -- Phase 2+):**
- Dynamic Profiles -- Mid-session model/tool/instruction switching. FoundationModels-native pattern.
- Type-driven structured output (@Generable / runtime schema derivation) -- Compile-time schema from Swift types.
- Wire-format isolation -- All provider-specific types (ContentBlock, StreamEvent) become internal to executors.
- Tool execution harness separation -- Protocol defines model contract; registry defines runtime contract.
- Unified model capabilities struct -- Replaces dual ModelInfo types.

**Defer (v3+ or out of scope):**
- @Generable macro -- Requires Swift macro infrastructure. Use runtime schema derivation initially.
- Vision/multimodal support -- Explicitly out of scope for this reorganization.
- Multi-agent orchestration -- Explicitly excluded from API layer (anti-feature).

### Architecture Approach

The target architecture uses four layers: **Layer 1 (Core Public API)** -- LanguageModelSession, LanguageModel protocol, simplified Tool protocol, Transcript, GenerationChannel, LanguageModelCapabilities. These types form the public surface with zero provider-specific knowledge. **Layer 2 (Core Internal Bridge)** -- LanguageModelExecutor protocol (internal), ToolDefinitionGenerator. Defines the transcript-to-wire translation contract. **Layer 3 (Per-Provider Executors)** -- AnthropicExecutor, DeepSeekExecutor, OpenAIExecutor. Self-contained modules implementing LanguageModelExecutor. All provider-specific types, SSE parsing, authentication, retry, and wire format logic live here. **Layer 4 (Entry Point Adapters)** -- Thin CLI and App adapters bridging LanguageModelSession into ChatCommand and ThreadViewModel.

The central pattern is **Transcript as Universal Wire Format**: every executor accepts Transcript and translates to its provider's native API format internally. Adding a new provider means only implementing Transcript-to-NativeRequest translation -- zero changes to session, public API, or entry points. The LanguageModelSession owns the agent loop (prompt -> executor -> tool calls -> execute -> loop -> response), replacing the current QueryEngine.run() + inline streaming architecture.

**Major components:**
1. LanguageModelSession -- Stateful agent loop: transcript management, tool execution orchestration, streaming dispatch. Replaces QueryEngine + LLMClient.
2. LanguageModel protocol -- Model abstraction with capabilities and executor factory. Models are swappable plugins.
3. LanguageModelExecutor protocol (internal) -- Translates Transcript to provider-native wire format, streams responses through GenerationChannel.
4. Tool protocol (simplified) -- Contract between model and agent (~4 members). Runtime concerns move to registries.
5. Per-provider executors -- Self-contained modules (Anthropic, DeepSeek, OpenAI) with all wire-format logic internal.

### Critical Pitfalls

1. **Protocol Member Deletion Without Conformance Verification** -- The current 43-member Tool protocol has 55 searchHint overrides and 39 isEnabled overrides. Deleting these members silently orphanes tool search and feature gating. **Prevention:** Full call-site audit (grep -rn "\\.memberName\\b") before any deletion. Metadata migration to ToolRegistry one member at a time. Zero overrides must remain before deletion.

2. **"Same Event, Double-Rendered" Streaming Bug** -- Migrating from delta-based (textDelta("Hello") -> textDelta(" world")) to snapshot-based (PartiallyGenerated(text: "Hello") -> PartiallyGenerated(text: "Hello world")) causes consumers to misread snapshots as deltas. **Prevention:** Parallel output comparison in shadow mode. Assert old and new paths produce identical rendered output before cutting over any consumer. Migrate consumer-at-a-time.

3. **LanguageModel Protocol Becomes Leaky Abstraction** -- Providers differ in tool call pairing (positional vs ID-based), thinking block handling, error formats. **Prevention:** LanguageModelCapabilities must encode behavioral differences. Cross-provider conformance tests that send identical history to all providers.

4. **Tool Conformance Migration Orphaning Feature Flags** -- 39 of 58 tools override isEnabled() with feature flag checks. **Prevention:** Countdown migration: keep isEnabled() on compatibility extension until zero overrides remain.

5. **Consumer Fragmentation During Streaming Migration** -- 5+ consumers of 13-case StreamEvent enum migrate at different rates. **Prevention:** Consumer-at-a-time cutover, never two simultaneously.

## Implications for Roadmap

Based on combined research, suggested 9-phase build sequence:

### Phase 0: Preparation (Test Reorganization + End-State Documentation)
**Rationale:** Before any API change, the test suite must be restructured so failures are immediately localizable. Current test organization (Phase4ToolsTests.swift, 197 lines for 63 tools) produces "8 failures" without indicating which protocol member change caused them.
**Delivers:** One-test-file-per-concern for the 5 most-critical protocol members: name, call, searchHint, isEnabled, inputSchema. Migration end-state document (LLMClient -> REMOVED, LLMProvider -> MIGRATED, DeepSeekClient -> FOLDED).
**Avoids:** Pitfalls 6, 11 (three-abstraction-layer trap, test obscuring failures).
**Research flag:** Standard pattern. Mechanical, not domain-research-intensive.

### Phase 1: Foundation Types (Leaf Types)
**Rationale:** These types have zero internal dependencies. Building blocks for everything that follows.
**Delivers:** Transcript + Transcript.Entry, LanguageModelCapabilities, LanguageModelUsage, LanguageModelError, GenerationOptions.
**Addresses:** FEATURES TS-5, TS-9, DIFF-4.
**Research flag:** Standard pattern. Directly modeled on Apple FoundationModels documentation.

### Phase 2: Core Protocols
**Rationale:** LanguageModel, LanguageModelExecutor, Tool, and GenerationChannel define contract boundaries for everything that follows. Tool protocol simplification is the single highest-risk change in the entire project.
**Delivers:** LanguageModel protocol, LanguageModelExecutor protocol (internal), simplified Tool protocol (~4 members + compatibility extension), GenerationChannel protocol.
**Addresses:** FEATURES TS-1 (LanguageModel), TS-3 (Tool protocol).
**Avoids:** Pitfalls 1, 3, 4, 8, 10, 12.
**Research flag:** NEEDS DEEP RESEARCH. 43 members, 58 conformers, 8 consumer categories. Plan with /gsd-plan-phase --research-phase 2.

### Phase 3: LanguageModelSession
**Rationale:** Unified public API replacing QueryEngine + LLMClient. Validates agent loop before executors are built.
**Delivers:** LanguageModelSession with respond(to:), streamResponse(to:), transcript management, tool execution orchestration, snapshot emission.
**Addresses:** FEATURES TS-2, TS-4, DIFF-2.
**Research flag:** Standard pattern. Well-documented in WWDC25/26 sessions.

### Phase 4: AnthropicExecutor
**Rationale:** Primary provider and most complex executor. Validates the session/loop. Dissolves LLMClient (1079 lines) + LLMStreamParser into provider-internal code.
**Delivers:** Transcript-to-Anthropic API translation, SSE parsing, tool use handling, thinking/cache control.
**Avoids:** Pitfall 7 (preserve ContentBlockAccumulator verbatim).
**Research flag:** Standard pattern. Wrapping battle-tested internals, not rewriting them.

### Phase 5: DeepSeekExecutor
**Rationale:** Unifies dual DeepSeek code paths (App/DeepSeek/ standalone + LLMProvider path) into single executor. Deduplication cleanup, no new behavior.
**Delivers:** Transcript-to-Chat-Completions translation, stream chunk parsing, reasoning extraction. Handles known DeepSeek beta header suppression bug.
**Research flag:** Standard pattern. Code consolidation with existing working reference.

### Phase 6: OpenAIExecutor
**Rationale:** Replaces current OpenAIProvider stub with working executor. Lower priority than Anthropic and DeepSeek.
**Delivers:** Transcript-to-Chat-Completions translation, function calling format mapping, structured output support.
**Research flag:** Standard pattern. Well-documented OpenAI Chat Completions API.

### Phase 7: Tool Migration
**Rationale:** Convert all 58 existing tools to simplified Tool protocol. Extract metadata to registries. Largest mechanical change in the project.
**Delivers:** All 58 tools conforming to new protocol. ToolMetadataRegistry with search hints, feature flags, execution policies. ToolExecutionPolicyRegistry with concurrency safety, interrupt behavior. Old protocol members fully removed.
**Addresses:** FEATURES DIFF-7 (tool execution harness separation).
**Avoids:** Pitfalls 1, 4, 8, 12.
**Research flag:** NEEDS DEEP RESEARCH. Per-member migration plan for 8 categories across 58 tools. Plan with /gsd-plan-phase --research-phase 7.

### Phase 8: Entry Point Adapters + Cleanup
**Rationale:** Final integration. Wire LanguageModelSession into CLI (ChatCommand) and App (ThreadViewModel). Remove old abstractions, cut over all consumers.
**Delivers:** CLI ChatCommand adapter (replaces QueryEngine.run() + inline streaming). App ThreadViewModel adapter (replaces AgentSessionManager + AppAgentProvider). Removal of LLMClient, LLMProvider, ProviderRegistry, dual ModelInfo types, old StreamEvent enum from public API.
**Addresses:** FEATURES DIFF-5 (wire-format isolation), DIFF-6 (Transcript as canonical history).
**Avoids:** Pitfalls 2, 5, 6, 9.

### Phase Ordering Rationale

- **Phases 0-3 must be sequential**: each builds on the previous. Foundation types -> Protocols -> Session. No parallelism possible.
- **Phases 4-6 can be parallelized**: each executor is self-contained, depending only on Phase 2 protocols. They share no code or state.
- **Phase 7 depends on Phase 2** (simplified protocol must be stable) but can overlap with Phases 4-6 since tool migration and executor building are independent workstreams.
- **Phase 8 depends on all preceding phases**: needs session + at least one executor + migrated tools.

### Research Flags

**Needs deep research during planning:**
- **Phase 2 (Core Protocols):** Tool protocol simplification from 43 to ~4 members across 58 conformers. Requires call-site audit, category analysis, and per-member migration plan for 8 consumer categories. Plan with /gsd-plan-phase --research-phase 2.
- **Phase 7 (Tool Migration):** Individual tool migration for 58 tools with adapter fidelity testing. Per-member migration for search hints, feature flags (39 overrides), permission metadata, UI metadata, hook integration, and MCP integration. Plan with /gsd-plan-phase --research-phase 7.

**Standard patterns (skip research-phase):**
- Phases 0, 1, 3, 4, 5, 6, 8 -- Well-documented patterns, established APIs, or mechanical codebase-driven work. No domain research needed beyond what ARCHITECTURE.md already provides.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Existing Swift 6.3 stack is proven. No new dependencies needed. Verified from STACK.md (codebase analysis) + Package.swift + Package.resolved. |
| Features | HIGH | Table-stakes verified against Apple WWDC25/26 FoundationModels sessions (4 sessions), Claude Code architecture analysis (510K-line codebase study), and 4 practitioner analyses. Anti-features grounded in production failure patterns. |
| Architecture | HIGH | Component boundaries and data flow verified against WWDC sessions, OpenFoundationModels OSS (protocol viability confirmed), and SwiftAgent codebase analysis (295-file, 3-target architecture). Build order derived from dependency graph. |
| Pitfalls | HIGH | All critical pitfalls codebase-verified: Tool.swift (1156 lines, 43 members confirmed via grep), LLMClient.swift (1079 lines), 58 tool structs with override counts verified. Production failure patterns (Anthropic HelloHello bug, DeepSeek beta header issue) verified from req_llm issue tracker. |

**Overall confidence: HIGH.** All four research areas draw from verified sources: Apple's official FoundationModels documentation, SwiftAgent codebase analysis (directly inspected), and independently verified production failure patterns.

### Gaps to Address

- **Runtime schema derivation for @Generable:** Initial implementation uses Codable-based derivation. Validate against Apple's @Generable output format during Phase 2 research.
- **@Generable macro API design:** Design the macro API shape alongside Tool protocol to prevent rework. Include in Phase 2 research even though implementation is deferred.
- **Tool call pairing semantics:** LanguageModelCapabilities must capture per-provider pairing strategy (positional vs ID-based). Validate during executor implementation (Phases 4-6).
- **Cross-provider agent loop equivalence:** No existing test verifies equivalent tool call sequences across providers. Build during Phase 3 (LanguageModelSession).
- **Compaction on Transcript:** Existing Compactor operates on Anthropic content blocks. Validate compaction quality after Transcript-based rewrite.

## Sources

### Primary (HIGH confidence -- official Apple docs + codebase verification)
- WWDC26 Session 339: Bring an LLM provider to the Foundation Models framework
- WWDC26 Session 241: What's new in the Foundation Models framework
- WWDC25 Session 286: Meet the Foundation Models framework
- WWDC25 Session 301: Deep dive into the Foundation Models framework
- Foundation Models Developer Documentation
- OpenFoundationModels (GitHub) -- OSS implementation confirming protocol viability
- AnyLanguageModel (GitHub) -- Multi-provider executor isolation pattern
- SwiftAgent codebase: .planning/codebase/ARCHITECTURE.md, .planning/codebase/STRUCTURE.md, .planning/PROJECT.md, Tool.swift (1156 lines), LLMClient.swift (1079 lines), LLMStreamParser.swift, StreamEvent.swift

### Secondary (MEDIUM-HIGH confidence -- verified practitioner sources)
- Claude Code Agent Harness: Architecture Breakdown (wavespeed.ai)
- I Read Claude Code's 510K Lines of Source Code (dev.to)
- Claude Code June 2026 Features (sitepoint.com)
- What's New in Foundation Models at WWDC 2026 (dev.to)

### Tertiary (MEDIUM confidence -- independently converged practitioner wisdom)
- Cognition: Don't Build Multi-Agents
- Google: Production-Ready AI Agents -- 5 Lessons
- Common Sub-Agent Anti-Patterns (stevekinney.com)
- Context Window is RAM, Not Storage (mem0.ai)

### Production failure patterns (verified from req_llm issue tracker)
- req_llm #272 (streaming vs non-streaming code path divergence)
- req_llm #271 (Google finishReason conflated with tool calls)
- Anthropic SDK "HelloHello" duplication bug
- DeepSeek beta header injection failure mode

---
*Research completed: 2026-06-25*
*Ready for roadmap: yes*
