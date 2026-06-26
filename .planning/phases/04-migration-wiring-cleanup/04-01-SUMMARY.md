# Plan 04-01 Summary: Foundation Plumbing

**Status:** Complete
**Date:** 2026-06-25

## Changes

### Task 1: Protocol Rename (D-07)
- `RuntimeAgentTool.Input` → `RuntimeAgentTool.Arguments` associatedtype
- `call(_ input:)` → `call(arguments:)` method
- Updated all doc comments and warnings
- Updated `TestTool` in AgentRuntimeImplTests

### Task 2: Type Extraction
- Created `Sources/SwiftAgentCore/Types/JSONSchema.swift` — JSONSchema, JSONSchemaItems, JSONSchemaProperty
- Created `Sources/SwiftAgentCore/Types/InterruptBehavior.swift` — InterruptBehavior enum
- Removed extracted types from `Types/Tool.swift`

### Task 3: Real Tool Execution
- Rewrote `DefaultToolEngine` with `RegistryEntry` struct and type-erased execute closure
- Generic `_register<T: RuntimeAgentTool>` helper opens existential, decodes `T.Arguments`, calls `call(arguments:)`
- Removed Phase 2 stub code
- Fixed `TestTool` Arguments type to `EmptyArguments: Codable` for real decode

## Verification
- `swift build --disable-sandbox --target SwiftAgentCore`: zero errors
- `swift test --disable-sandbox --no-parallel --filter LanguageModelSessionImplTests`: 8/8 pass
- `swift test --disable-sandbox --no-parallel --filter SwiftAgentCoreTests`: 225/225 pass
