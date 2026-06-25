---
gsd_state_version: '1.0'
status: planning
progress:
  total_phases: 4
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-25)

**Core value:** Models are peripherals, not the CPU — `AgentRuntime` is the architecture's center; every Provider (Model, Memory, Permission) sits behind a protocol
**Current focus:** Phase 1 (AgentRuntime Core Protocols — 16 requirements, all type-level definitions)

## Current Position

Phase: 1 of 4 (AgentRuntime Core Protocols)
Plan: 0 of TBD in current phase
Status: Ready to plan
Last activity: 2026-06-25 — Roadmap updated for WWDC27 Agent OS direction; 29 requirements mapped across 4 phases

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: N/A
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. AgentRuntime Core Protocols | TBD | - | - |
| 2. Session, Streaming & Structured Output | TBD | - | - |
| 3. Provider Implementations | TBD | - | - |
| 4. Migration, Wiring & Cleanup | TBD | - | - |

**Recent Trend:**
- N/A (no plans executed yet)

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decision log lives in PROJECT.md Key Decisions table. Recent decisions affecting current work:

- **`AgentRuntime` as central abstraction** — not `LanguageModelSession`. Models are peripherals; the Runtime orchestrates Model, Memory, Permission, Tools, Context, Profile, Graph, and Hooks as co-equal subsystems
- **Three Provider protocols** — `LanguageModel` (inference), `MemoryStore` (persistent memory), `PermissionEngine` (runtime-level access control). Each with swappable implementations
- **WWDC27 type-slots reserved in Phase 1** — `AgentGraph`, `AgentNode`, `AgentState` protocol surface, `AgentPermission` taxonomy. Design surface only; implementations deferred to future phases when macOS 27+ enables `@Generable` / `AgentKit`
- **Tool → AgentIntent forward compatibility** — simplified `Tool` protocol (~6 members) designed so `AgentIntent` auto-discovery can be layered on without breaking changes
- **Shadow-mode migration for all consumer cutovers** — old path and new path run simultaneously; output equivalence validated before flag flip
- All v1 decisions carried forward: LanguageModel protocol, snapshot streaming, wire-format isolation, DeepSeek unification, type-driven output

### Pending Todos

None yet.

### Blockers/Concerns

- **Phase 1 risk: Tool protocol simplification** (PITFALLS.md Pitfall 1) — 55 `searchHint` overrides must be mapped to `ToolMetadata` before removal
- **Phase 1 risk: `isEnabled` feature flags** (39 overrides) must be preserved through `ToolEngine` migration (PITFALLS.md Pitfall 4)
- **Phase 1 scope risk** — 16 requirements in one phase is the largest phase in project history. Protocol surface design for `AgentGraph`, `AgentState`, and `AgentPermission` must not over-specify implementations that don't exist yet
- **Phase 2 risk: Double-render bug** (PITFALLS.md Pitfall 2) — snapshot vs delta semantics require parallel output comparison in shadow mode
- **Phase 3 risk: Leaky abstraction** (PITFALLS.md Pitfall 3) — `LanguageModelCapabilities` must be rich enough to prevent provider-specific workarounds
- **Phase 3 risk: DeepSeek dual-path deduplication** (PITFALLS.md Pitfall 8) — internal `APICompatibility` switch must handle edge cases from both paths
- **Cross-phase invariant:** `nonisolated(unsafe)` count must not increase from current 3 (PITFALLS.md Pitfall 13)

## Session Continuity

Last session: 2026-06-25
Stopped at: Roadmap restructured for WWDC27 Agent OS direction; PROJECT.md, REQUIREMENTS.md (29 REQs), ROADMAP.md (4 phases), STATE.md updated
Resume file: None
