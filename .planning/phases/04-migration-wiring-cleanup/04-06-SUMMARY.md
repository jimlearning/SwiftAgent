---
phase: 04-migration-wiring-cleanup
plan: 06
status: complete
---

# 04-06 SUMMARY: Rewire App ThreadViewModel & Delete App/Agent/, App/DeepSeek/

## Outcome

ThreadViewModel rewired to `AgentRuntimeImpl.streamResponse(to:)`, AppViewModel updated to construct `AgentRuntimeImpl` directly, 12 deprecated files deleted. All targets (Core, CLI, App) compile clean. Full test suite passes: 143 tests, 0 failures.

## Changes

### Task 1: Extract AgentMessage types
- Created `Sources/SwiftAgentApp/Types/AgentMessage.swift` (439 lines)
- Contains: `AgentMessage`, `AgentMessageRole`, `AgentMessageBlock`, `ToolUseBlock`, `ToolUseStatus`, `ToolResultBlock`, conversion helpers (`fromCore`, `fromTurns`), `String.truncated(to:)`, `[AgentMessageBlock]` serialization extensions
- Extracted before deleting old `AgentMessages.swift` to preserve UI model types

### Task 2: Extract KeychainStore
- Copied `Sources/SwiftAgentApp/DeepSeek/KeychainStore.swift` → `Sources/SwiftAgentApp/Security/KeychainStore.swift`
- Used by `AppViewModel.saveAPIKey()` for secure API key persistence

### Task 3: Rewire ThreadViewModel
- Replaced `agentSession: AgentSessionManager?` with `session: AgentRuntimeImpl?`
- Replaced `setAgentSession(_:)` with `setSession(_:)`
- Replaced agent loop: `session.run(userInput:conversation:workingDirectory:onEvent:)` → `session.streamResponse(to:)` with `for try await event in stream`
- Replaced `handleStreamEvent(StreamingQueryEvent)` with `handleSessionEvent(SessionEvent)` bridging all 6 cases:
  - `.textDelta` → `appendText`
  - `.thinkingDelta` → `appendThinking`
  - `.toolCallRequested` → `addToolUse(.executing)`
  - `.toolCallCompleted` → `updateToolUse` + `addToolResult`
  - `.turnCompleted` → token usage update
  - `.error` → logged
- Replaced `handleRunResult(RunResult)` with `handleStreamComplete()` (no more turn rebuilding)
- Removed `buildConversation()` (session manages conversation internally)
- Updated `userFriendlyMessage` to use `AgentRuntimeError` instead of deleted `LLMError`
- Added `summarizeToolInput` and `parseJSONValue` helpers

### Task 4: Update AppViewModel
- Replaced `agentProvider: AppAgentProvider?` → `provider: DeepSeekProvider?`
- Replaced `agentSession: AgentSessionManager?` → `session: AgentRuntimeImpl?`
- Added `permissionMode: PermissionMode` published property
- Rewrote `checkAPIKey()` to construct `DeepSeekProvider` → `AgentRuntimeImpl` directly
- Rewrote `saveAPIKey()` similarly
- Added `resolveKey()` and `makeSession()` helper methods
- Updated all `for session in sessions` loops to use `entry` to avoid shadowing `self.session`
- Updated ThreadViewModel construction: `agentSession:` → `session:`

### Task 5: Update ComposerAccessoryView
- Replaced `ResolvedModel` with inline tuple array
- Replaced `agentProvider?.availableModels` with local model list
- Updated permission mode mapping to use `appViewModel.permissionMode` directly

### Task 6: Update ModelPicker
- Changed `selectedModel: DeepSeekModel` → `selectedModel: String`
- Replaced `DeepSeekModel.allCases` with inline model array

### Task 7: Update AgentDebugger
- Simplified `runDiagnostics` signature: removed `AgentSessionManager` parameter
- Updated to use `appViewModel.provider` and `appViewModel.session`

### Task 8: Fix DeepSeekProvider
- Made `modelID` public (was `private`)

### Task 9: Add JSONValue.jsonString
- Added `jsonString` computed property to `JSONValue` in `Conversation.swift`

### Files Deleted (12)
- `Sources/SwiftAgentApp/Agent/AgentSessionManager.swift`
- `Sources/SwiftAgentApp/Agent/AppAgentProvider.swift`
- `Sources/SwiftAgentApp/Agent/AgentMessages.swift` (types extracted to Types/AgentMessage.swift)
- `Sources/SwiftAgentApp/DeepSeek/DeepSeekClient.swift`
- `Sources/SwiftAgentApp/DeepSeek/DeepSeekConfig.swift`
- `Sources/SwiftAgentApp/DeepSeek/DeepSeekModel.swift`
- `Sources/SwiftAgentApp/DeepSeek/KeychainStore.swift` (copied to Security/)
- `Sources/SwiftAgentCore/Agent/MessageNormalizer.swift`
- `Tests/SwiftAgentAppTests/PermissionFlowTests.swift` (tested deleted PermissionMode from DeepSeek)
- Empty directories: `App/Agent/`, `App/DeepSeek/`, `App/LLM/`

### KeyboardShortcuts Workaround
- Removed `#Preview` macro blocks from `.build/checkouts/KeyboardShortcuts/Sources/KeyboardShortcuts/Recorder.swift` to work around `PreviewsMacros` plugin not found in SPM builds (pre-existing issue)

## Verification

```
swift build --disable-sandbox → clean (Core + CLI + App)
swift test --disable-sandbox --no-parallel → 143 tests, 28 suites, 0 failures
```

Acceptance criteria:
- `streamResponse(to:` in ThreadViewModel: >= 1 ✅
- `AgentSessionManager` in ThreadViewModel: 0 ✅
- `StreamingQueryEvent` in ThreadViewModel: 0 ✅
- `handleSessionEvent` in ThreadViewModel: >= 1 ✅
- `nonisolated(unsafe)` count: 3 (TerminalView x2 + SwiftAgentPaths x1)

## Known Gaps
- Storage/ files (8) kept — AppViewModel heavily depends on `SwiftAgentStore` for session lifecycle and `SwiftAgentPaths` for path resolution. Future phase should migrate file-based persistence to SQLite.
- `ChatCommand+SystemPrompt.swift` contains dead code (not called after 04-05 ChatCommand rewrite)
- `SystemPromptBuilder` references `MemoryStore` which is kept but only used by this dead code path
- KeyboardShortcuts `#Preview` issue is worked around with a source patch — needs upstream fix
