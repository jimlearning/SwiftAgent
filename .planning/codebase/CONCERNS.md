# Codebase Concerns

**Analysis Date:** 2026-06-25

## Tech Debt

**OpenAI Provider Stub:**
- Issue: `OpenAIProvider.stream()` returns an immediate error stream with `OpenAIError.notImplemented`. The entire provider is a non-functional stub despite advertising 4 models and 6 capabilities.
- Files: `Sources/SwiftAgentApp/LLM/OpenAIProvider.swift`
- Impact: Multi-provider support is blocked; users with `OPENAI_API_KEY` get a hard error with no graceful fallback. DeepSeek is the actual primary provider.
- Fix approach: Implement OpenAI Chat Completions SSE parsing to convert `chat.completion.chunk` events into Core's `StreamEvent` format. Alternatively, remove the stub entirely until it can be fully implemented.

**MCP Config Duplication:**
- Issue: Two competing MCP server config representations coexist — the legacy flat `MCPServerConfig` struct in `Config.swift` and the new discriminated union `MCPDiscriminatedServerConfig` in `MCPServerConfig.swift`. Two `TODO` comments at lines 22 and 60 of `MCPServerConfig.swift` explicitly flag this.
- Files: `Sources/SwiftAgentCore/Types/Config.swift` (line ~700+), `Sources/SwiftAgentCore/Types/MCPServerConfig.swift`
- Impact: Developers must maintain both representations; future consumers may pick the wrong one; serialization compat risks.
- Fix approach: Complete the migration to `MCPDiscriminatedServerConfig`, remove the legacy struct, and update all call sites.

**Dual Logging Protocols:**
- Issue: Legacy `LLMDebugLogger` protocol coexists alongside new `DebugLogSink`, bridged by `LegacyDebugLoggerAdapter`. The legacy protocol has different method signatures and caller patterns.
- Files: `Sources/SwiftAgentCore/LLM/LLMClient.swift:28-67`, `Sources/SwiftAgentCLI/DebugLogger.swift`
- Impact: All new code must implement two interfaces or use the adapter; increases onboarding friction.
- Fix approach: Finish migrating all callers to `DebugLogSink` and remove `LLMDebugLogger`.

**Debug Print Statements in Production:**
- Issue: Widespread `print()` statements with diagnostic prefixes throughout production code, particularly in ViewModels and SystemPromptBuilder.
- Files: `Sources/SwiftAgentApp/ViewModels/AppViewModel.swift` (50+ print calls), `Sources/SwiftAgentApp/ViewModels/ThreadViewModel.swift` (30+ print calls), `Sources/SwiftAgentCore/Agent/SystemPromptBuilder.swift:53` (debug print in `build()` method)
- Impact: Console noise in production; no structured log levels; potential performance degradation in hot paths.
- Fix approach: Replace `print()` calls with OSLog (`Logger`) using appropriate log levels. Route to `DebugLogSink` for structured debug output.

**Large Files Exceeding Decomposition Targets:**
- Issue: Several files exceed the project's stated decomposition goal (CLAUDE.md: "No god files"). Key offenders:
  - `Sources/SwiftAgentCLI/ChatCommand.swift` — 1192 lines (CLI orchestrator, already decomposed via extensions but still large)
  - `Sources/SwiftAgentCore/Types/Tool.swift` — 1156 lines (core Tool protocol + ToolExecutor + ToolRegistry + result types)
  - `Sources/SwiftAgentCore/LLM/LLMClient.swift` — 1079 lines (Anthropic API client + stream parser integration)
  - `Sources/SwiftAgentCore/Types/HookJSONTypes.swift` — 968 lines (Hook JSON event types)
  - `Sources/SwiftAgentCore/Types/SDKTypes.swift` — 922 lines (SDK-related types)
  - `Sources/SwiftAgentCore/Agent/MessageNormalizer.swift` — 848 lines (schema normalization)
- Impact: Harder to navigate, test, and review; single-responsibility principle strain.
- Fix approach: Prioritize `Tool.swift` (split `ToolExecutor` and `ToolRegistry` into separate files) and `HookJSONTypes.swift` (split into per-domain files).

**Deprecated Legacy API:**
- Issue: `AgentSessionManager.cancel()` marked `@available(*, deprecated, renamed: "cancelRun()")` remains exposed.
- Files: `Sources/SwiftAgentApp/Agent/AgentSessionManager.swift:412-415`
- Impact: Callers may still use the old name; shipped in a public API.
- Fix approach: Remove after verifying no external callers remain.

## Known Bugs

**Working Directory FALLBACK (marked as bug in source):**
- Symptoms: ThreadViewModel falls back to the user's home directory when projectId cannot be resolved, with the comment "THIS IS A BUG."
- Files: `Sources/SwiftAgentApp/ViewModels/ThreadViewModel.swift:102`
- Trigger: Creating or loading a thread without a valid projectId/appViewModel reference.
- Workaround: Ensure projects are properly created before threads exist.

**Corrupt Session Index Recovery:**
- Symptoms: Session index gets corrupted, requiring fallback JSONL file scanning to rebuild. Logged with "[AppVM] loadAllData: CORRUPT INDEX" and "[AppVM] loadAllData: EMPTY INDEX but X JSONL files exist."
- Files: `Sources/SwiftAgentApp/ViewModels/AppViewModel.swift:266, 317`
- Trigger: Unknown — possible concurrent writes to `sessions-index.json` or crash during write.
- Workaround: Auto-recovery path exists (JSONL file scan), but this is a symptom of an underlying data integrity issue.

**Missing Transcript Handling:**
- Symptoms: Sessions are silently skipped during load if their transcript file is missing from disk, logged as "[AppVM] loadAllData: SKIPPING — transcript missing."
- Files: `Sources/SwiftAgentApp/ViewModels/AppViewModel.swift:288`
- Trigger: Deletion or corruption of JSONL transcript files without corresponding index update.
- Workaround: Sessions become invisible in the sidebar until the index is rebuilt.

## Security Considerations

**API Key Exposure Risk:**
- Risk: API keys are read from multiple sources (environment variables, macOS keychain, `~/.claude.json`) and passed through the system as plain strings. Key masking occurs only in `DebugLogger`, not universally.
- Files: `Sources/SwiftAgentCore/Config/APIKeyResolver.swift`, `Sources/SwiftAgentCLI/ChatCommand.swift:62-67`, `Sources/SwiftAgentApp/LLM/DeepSeekProvider.swift:66`, `Sources/SwiftAgentApp/LLM/OpenAIProvider.swift:61`
- Current mitigation: DebugLogger masks keys; `apiKey` stored as `String` in LLMClient.
- Recommendations: Wrap API key in a redactable type that masks its `description`/`debugDescription` by default. Ensure error messages never include the raw key.

**DangerouslyDisableSandbox Flag:**
- Risk: `BashTool` and `PowerShellTool` expose `dangerouslyDisableSandbox` as an input parameter that bypasses all sandbox restrictions.
- Files: `Sources/SwiftAgentCore/Tools/BashTool.swift`, `Sources/SwiftAgentCore/Tools/PowerShellTool.swift:26`
- Current mitigation: Flag is documented as dangerous; permission engine intercepts.
- Recommendations: Require explicit user consent with a one-time confirmation dialog when the flag is set. Add an audit log entry for every sandbox-disabled execution.

**Local OAuth Callback Server:**
- Risk: OAuth flow starts a local HTTP server on a random port for callback handling. The port range is bounded (max 100 attempts), and the server listens on localhost.
- Files: `Sources/SwiftAgentCore/MCP/OAuthCallbackServer.swift`, `Sources/SwiftAgentCore/MCP/OAuthPort.swift`
- Current mitigation: Server binds to localhost only; random port.
- Recommendations: Validate that the callback URL matches expected origin. Implement a strict timeout on the listening window. Consider using ASWebAuthenticationSession for supported platforms.

**nonisolated(unsafe) Escape Hatches:**
- Risk: Three uses of `nonisolated(unsafe)` bypass Swift 6 concurrency checking, indicating potential data races:
  - `LLMClient.activeStreamTask` — mutable state captured across structured concurrency boundaries.
  - `TerminalView.onTerminated` — callback stored in a `nonisolated(unsafe)` variable.
  - `SwiftAgentPaths.configHomeOverride` — global mutable state.
- Files: `Sources/SwiftAgentCore/LLM/LLMClient.swift:82`, `Sources/SwiftAgentApp/RightTabs/panels/TerminalView.swift:117-118`, `Sources/SwiftAgentCore/Storage/SwiftAgentPaths.swift:14`
- Current mitigation: Assumed safe by authors; `@unchecked Sendable` annotations.
- Recommendations: Audit each use. `activeStreamTask` should use an actor or `OSAllocatedUnfairLock`. `SwiftAgentPaths.configHomeOverride` should be replaced with task-local values or explicit dependency injection.

**Unsafe Flag Linker Settings:**
- Risk: `Package.swift` uses `unsafeFlags` for embedding Info.plist into the Mach-O binary — SwiftPM warns that these may not work across all build environments.
- Files: `Package.swift:53-58`
- Current mitigation: Required for CFBundleIdentifier in Xcode indexing.
- Recommendations: Document this as a known constraint. Explore using `Info.plist` via Xcode build settings instead of linker flags.

## Performance Bottlenecks

**BashTool Process Wait (Thread Pool Blocking):**
- Problem: `BashTool.waitForProcess()` offloads `process.waitUntilExit()` to `DispatchQueue.global()` using `withUnsafeContinuation`, then races against a `Task.sleep` timeout via `withTaskGroup`. This consumes an entire Dispatch thread for the duration of the process.
- Files: `Sources/SwiftAgentCore/Tools/BashTool.swift:372-403`
- Cause: Foundation's `Process` does not natively support Swift Concurrency; blocking wait is the only option.
- Improvement path: Already optimized with `TaskGroup` racing; consider process pool limiting to cap concurrent processes.

**MessageNormalizer Complexity:**
- Problem: 848-line schema normalization layer converting between multiple message formats (`SDKMessage`, `APIMessage`, `StreamEvent`, `Block`). Every message round-trips through this layer.
- Files: `Sources/SwiftAgentCore/Agent/MessageNormalizer.swift`
- Cause: Multiple API version compat layers accumulated over time.
- Improvement path: Benchmark normalization cost; consider lazy/cached normalization where possible.

**FileSearchIndex Rebuilds:**
- Problem: `FileSearchIndex` performs full file system enumeration when building the index, which can be expensive on large repositories.
- Files: `Sources/SwiftAgentCLI/FileSearchIndex.swift`
- Cause: No incremental update mechanism; full scan on every build.
- Improvement path: Implement file system event watching for incremental updates (`DispatchSource` or `FSEvents`).

**Compactor LLM Cost:**
- Problem: Compaction requires an expensive LLM call (up to 20k output tokens) for summarizing conversation history. Each compaction can cost real API credits.
- Files: `Sources/SwiftAgentCore/Agent/Compactor.swift`
- Cause: Inherent in the architecture — LLM-based summarization.
- Improvement path: Already aligned with Claude Code thresholds and circuit breaker (max 3 consecutive failures). Consider hybrid extraction-based fallback for simpler cases.

## Fragile Areas

**MCP Transport Layer:**
- Files: `Sources/SwiftAgentCore/MCP/MCPTransport.swift` (509 lines), `Sources/SwiftAgentCore/MCP/MCPWebSocketTransport.swift`, `Sources/SwiftAgentCore/MCP/MCPConnectionManager.swift`, `Sources/SwiftAgentCore/MCP/OAuthCallbackServer.swift`, `Sources/SwiftAgentCore/MCP/OAuthFlow.swift`
- Why fragile: Seven transport variants (stdio, SSE, SSE-IDE, WebSocket, WS-IDE, HTTP, SDK) with OAuth flows, reconnection logic, and callback servers. Each transport has unique error modes. Test coverage is minimal (147-line Phase10MCPTests for the entire MCP subsystem).
- Safe modification: Read `MCPTransport.swift` to understand the abstract protocol before touching concrete transports. Test with a local MCP server.
- Test coverage: Critical gap — no integration tests with actual MCP servers.

**Message Schema Compatibility:**
- Files: `Sources/SwiftAgentCore/Agent/MessageNormalizer.swift` (848 lines), `Sources/SwiftAgentCore/Types/SDKTypes.swift` (922 lines), `Sources/SwiftAgentCore/LLM/LLMStreamParser.swift`
- Why fragile: Message format is the contract between the agent and the LLM API. Normalization includes block merging, tool result merging, thinking block handling, and version compat. Breaking changes here cause cascading failures.
- Safe modification: Always add regression tests in `Phase2LLMTests.swift` (612 lines, most comprehensive test suite) before refactoring.
- Test coverage: Phase2LLMTests is 612 lines — the strongest test suite — but focused on LLM client rather than message normalization.

**ChatCommand Orchestrator:**
- Files: `Sources/SwiftAgentCLI/ChatCommand.swift` (1192 lines) + 5 extension files
- Why fragile: Central orchestrator wiring together LLM client, tool registry, terminal I/O, stream rendering, system prompt building, and escape handling. Changes here can affect everything.
- Safe modification: Use extension files (`+Types.swift`, `+SystemPrompt.swift`, `+ToolDisplay.swift`, `+SessionPicker.swift`, `+UserPrompt.swift`) for new functionality. The main file runs the core loop.
- Test coverage: CLI integration tests exist but are minimal compared to the orchestrator's scope.

## Scaling Limits

**Conversation History:**
- Current capacity: In-memory `[Message]` array, bounded by the LLM's context window (~200K tokens for Claude, ~256K for GPT-5.2). Compactor triggers at `contextWindow - 13000` tokens.
- Limit: No disk-backed overflow; history lost on crash. Large conversations strain memory.
- Scaling path: Already uses Compactor for context window management. Add checkpoint persistence for crash recovery.

**Single LLMClient per Run:**
- Current capacity: One `LLMClient` instance with one active streaming task per agent run.
- Limit: No provider pooling, no load balancing, no multi-API-key rotation. Rate limiting affects the entire session.
- Scaling path: Implement provider chain with fallback ordering. The `RetryPolicy` already has fallback model support.

**Tool Execution Concurrency:**
- Current capacity: `ChatToolExecutionScheduler` groups independent tools for parallel execution, but many tools are marked `isConcurrencySafe: false`.
- Limit: Sequential execution of most tools (Bash, file writes, etc.) creates latency under heavy tool-use scenarios.
- Scaling path: Audit all tools for concurrency safety. `ToolSearchTool` already uses `withTaskGroup` for parallel tool description generation.

## Dependencies at Risk

**Local Packages Dependency:**
- Risk: `Packages` is resolved via `.package(path: "Packages")` — a relative path. Moving or renaming the directory breaks the build. The package provides `ClarcCore` and `ClarcChatKit` (AppKit bridging for chat table view).
- Files: `Package.swift:20, 43-44`
- Impact: Build would fail with unresolved package.
- Migration plan: Document the dependency; consider pinning to a git tag via URL if `ClarcCore`/`ClarcChatKit` are published.

**SwiftTerm (1.3.0):**
- Risk: Third-party terminal emulator library used for the app's Terminal panel. Single maintainer project.
- Files: `Package.swift:19`, `Sources/SwiftAgentApp/RightTabs/panels/TerminalView.swift`
- Impact: Terminal panel would need rewrite if the dependency becomes unmaintained.
- Migration plan: Monitor upstream activity. The terminal panel is an auxiliary feature (not the main chat interface).

**KeychainAccess (4.2.0):**
- Risk: Third-party Keychain wrapper for API key storage. Not an Apple-maintained library.
- Files: `Package.swift:17`, `Sources/SwiftAgentApp/DeepSeek/KeychainStore.swift`
- Impact: API key storage would need a replacement (raw Security framework calls or another library).
- Migration plan: The Security framework API is stable. Migration would be straightforward but tedious.

**DeepSeek API as Default Provider:**
- Risk: The CLI defaults to `deepseek-v4-pro` model and `api.deepseek.com/anthropic` base URL. The app uses DeepSeek as primary provider. This is a single-vendor dependency that is not Anthropic (Claude Code's vendor).
- Files: `Sources/SwiftAgentCLI/ChatCommand.swift:13`, `Sources/SwiftAgentCLI/ChatCommand.swift:71`
- Impact: API changes or outages affect all users.
- Migration plan: Provider abstraction exists (`LLMProvider` protocol). Adding Anthropic as primary and DeepSeek as fallback is architecturally supported but needs the Anthropic provider to be fully implemented (currently uses DeepSeek's Anthropic-compatible endpoint).

## Missing Critical Features

**No Anthropic-First Provider:**
- Problem: Despite being a Claude Code reimplementation, the codebase defaults to DeepSeek. The Anthropic Messages API client (`LLMClient`) exists but targets DeepSeek's Anthropic-compatible endpoint by default. The base URL is hardcoded to `api.deepseek.com/anthropic`.
- Blocks: Claude API features like prompt caching, extended thinking, and computer use.
- Files: `Sources/SwiftAgentCLI/ChatCommand.swift:13, 71`, `Sources/SwiftAgentApp/Agent/AppAgentProvider.swift:80-109`

**No Vision/Image Support:**
- Problem: Model definitions advertise `supportsVision: true` (GPT-5.2, DeepSeek models), but the streaming message pipeline has no image content block handling.
- Blocks: Multimodal agent use cases; screenshot analysis; image-based tool results.
- Files: `Sources/SwiftAgentCore/LLM/LLMClient.swift`, `Sources/SwiftAgentCore/LLM/LLMStreamParser.swift`

**No Computer Use Implementation:**
- Problem: `LLMProvider.supports(.computerUse)` returns false for all providers. No tool implementation for computer use actions.
- Blocks: Desktop automation use cases.
- Files: `Sources/SwiftAgentApp/LLM/OpenAIProvider.swift:99`, `Sources/SwiftAgentCore/Tools/` (no ComputerUseTool)

**No Memory Warning Handling:**
- Problem: Zero references to memory pressure notifications, `UIApplication.didReceiveMemoryWarning` equivalents, or proactive cache clearing.
- Blocks: Stability under memory pressure, especially on 8GB Macs.
- Files: No file implements memory pressure handling.

## Test Coverage Gaps

**Tool-Specific Tests:**
- What's not tested: 63 tool implementations have only 197 lines of tool-specific tests (Phase4ToolsTests). Most tools lack dedicated unit tests.
- Files: `Tests/SwiftAgentCoreTests/Phase4ToolsTests.swift` (197 lines), `Sources/SwiftAgentCore/Tools/` (63 files)
- Risk: Tool behavior regressions go undetected. Sandbox bypasses, permission checks, and execution paths are untested.
- Priority: High — tools are the primary surface for security and correctness.

**MCP Integration Tests:**
- What's not tested: MCP server connection lifecycle, transport negotiation, OAuth flow, resource listing, tool invocation via MCP.
- Files: `Tests/SwiftAgentCoreTests/Phase10MCPTests.swift` (147 lines), `Sources/SwiftAgentCore/MCP/` (14 source files)
- Risk: Broken MCP connections go undetected until runtime.
- Priority: Medium — MCP is a key integration surface.

**App End-to-End Flows:**
- What's not tested: Full agent loop from user message to LLM response to tool execution. Permission flow end-to-end. Session persistence and resume.
- Files: `Tests/SwiftAgentAppTests/` (6 files, 674 total lines), `Tests/SwiftAgentAppUITests/` (5 files, 132 total lines)
- Risk: Integration regressions between Core and App layers.
- Priority: High — the app target is the primary delivery surface.

**BashTool Security:**
- What's not tested: Sandbox bypass prevention, danger-pattern detection, command injection vectors, timeout edge cases, background execution cleanup.
- Files: No dedicated BashTool test file exists.
- Risk: Security-critical tool with no test coverage.
- Priority: Critical — BashTool is the highest-risk tool in the system.

**Compactor Integration:**
- What's not tested: Compaction triggering logic, circuit breaker behavior, invalid JSON responses from compaction LLM, token counting accuracy.
- Files: `Tests/SwiftAgentCoreTests/Phase3AgentTests.swift` (322 lines) likely covers some compaction but not exhaustively.
- Risk: Context window overflow during long sessions; conversation data loss.
- Priority: Medium — Compactor prevents catastrophic session failure.

---

*Concerns audit: 2026-06-25*
