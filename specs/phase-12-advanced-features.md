# Phase 12: Advanced Features

## Requirements
- Hooks system with lifecycle events (sessionStart, sessionEnd, preToolUse, postToolUse, etc.)
- Plugin manager for loading and managing plugins
- Feature flags for compile-time and runtime feature control

## Files to Create
| File | Description |
|---|---|
| Core/Hooks/HookSystem.swift | Hook registration, event dispatch, result handling |
| Core/Plugins/PluginManager.swift | Plugin loading, validation, lifecycle |
| Core/Features/FeatureFlags.swift | Compile-time and runtime feature flags |

## Acceptance Criteria
- [ ] HookSystem dispatches events to registered hooks
- [ ] PluginManager loads and validates plugin manifests
- [ ] FeatureFlags supports compile-time DCE and runtime overrides
- [ ] `swift build` + `swift test` pass

**Output when complete:** `<promise>DONE</promise>`
