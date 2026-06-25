---
phase: 03-provider-implementations
reviewed: 2026-06-25T00:00:00Z
depth: standard
files_reviewed: 23
files_reviewed_list:
  - Sources/SwiftAgentCore/AgentRuntime/Providers/Anthropic/AnthropicContentAccumulator.swift
  - Sources/SwiftAgentCore/AgentRuntime/Providers/Anthropic/AnthropicProvider.swift
  - Sources/SwiftAgentCore/AgentRuntime/Providers/Anthropic/AnthropicRequestBuilder.swift
  - Sources/SwiftAgentCore/AgentRuntime/Providers/Anthropic/AnthropicRetryPolicy.swift
  - Sources/SwiftAgentCore/AgentRuntime/Providers/Anthropic/AnthropicSSEParser.swift
  - Sources/SwiftAgentCore/AgentRuntime/Providers/Anthropic/AnthropicToolTranslator.swift
  - Sources/SwiftAgentCore/AgentRuntime/Providers/Anthropic/AnthropicTranscriptTranslator.swift
  - Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/DeepSeekAPICompatibility.swift
  - Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/DeepSeekProvider.swift
  - Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/DeepSeekSSEParser.swift
  - Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/DeepSeekToolTranslator.swift
  - Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/DeepSeekTranscriptTranslator.swift
  - Sources/SwiftAgentCore/AgentRuntime/Providers/Memory/SQLiteMemoryStore.swift
  - Sources/SwiftAgentCore/AgentRuntime/Providers/OpenAI/OpenAIProvider.swift
  - Sources/SwiftAgentCore/AgentRuntime/Providers/OpenAI/OpenAISSEParser.swift
  - Sources/SwiftAgentCore/AgentRuntime/Providers/OpenAI/OpenAIToolTranslator.swift
  - Sources/SwiftAgentCore/AgentRuntime/Providers/OpenAI/OpenAITranscriptTranslator.swift
  - Sources/SwiftAgentCore/AgentRuntime/Providers/Permission/AgentPermissionBridge.swift
  - Tests/SwiftAgentCoreTests/AgentPermissionBridgeTests.swift
  - Tests/SwiftAgentCoreTests/AnthropicProviderTests.swift
  - Tests/SwiftAgentCoreTests/DeepSeekProviderTests.swift
  - Tests/SwiftAgentCoreTests/OpenAIProviderTests.swift
  - Tests/SwiftAgentCoreTests/SQLiteMemoryStoreTests.swift
findings:
  critical: 1
  warning: 6
  info: 7
  total: 14
status: issues_found
---

# Phase 3: Code Review Report — Provider Implementations

**Reviewed:** 2026-06-25
**Depth:** standard
**Files Reviewed:** 23
**Status:** issues_found

## Summary

Reviewed 18 source files and 5 test files across four provider subsystems: Anthropic, DeepSeek, OpenAI, Memory (SQLite), and Permission bridging. The provider implementations are well-structured with clean separation of concerns (translator, parser, accumulator, provider). SSE parsing is correct for all three providers with proper snapshot semantics (accumulated text/thinking values rather than raw deltas). The AgentPermissionBridge has a correct exhaustive 13-case switch. SQLiteMemoryStore uses parameterized queries throughout with no SQL injection risk.

One BLOCKER-level issue was found: request body encoding failures are silently swallowed via `try?` in four locations across three providers. Six warnings cover silent directory creation failure, misleading error types, unconditional strict mode, deny-by-default without override, and duplicated Anthropic-compat SSE parsing. Seven info items cover dead code, misleading headers, inconsistent parser architecture, and weak test assertions.

## Critical Issues

### CR-01: Request body JSON encoding failures silently swallowed in four provider locations

**Files:**
- `Sources/SwiftAgentCore/AgentRuntime/Providers/Anthropic/AnthropicRequestBuilder.swift:80-82`
- `Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/DeepSeekProvider.swift:165`
- `Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/DeepSeekProvider.swift:211`
- `Sources/SwiftAgentCore/AgentRuntime/Providers/OpenAI/OpenAIProvider.swift:135`

**Issue:** Request body JSON serialization uses `try?` in all four locations, silently discarding the body when encoding fails. The request is sent with `httpBody = nil`, producing a malformed API call that will fail obscurely (likely a 400 error with no diagnostics pointing to the real cause). If a non-JSON-serializable type enters the body dictionary (e.g., through tool schema translation producing `Float.infinity` or a custom type), the bug triggers silently.

All four locations follow this pattern:
```swift
if let bodyData = try? JSONSerialization.data(withJSONObject: body, options: .sortedKeys) {
    request.httpBody = bodyData
}
// On failure: request is sent with httpBody = nil, no error logged
```

**Fix:** Promote the encoding failure to a proper error that propagates to the channel:
```swift
guard let bodyData = try? JSONSerialization.data(withJSONObject: body, options: .sortedKeys) else {
    await channel.fail(with: .invalidRequest(reason: "Failed to encode request body to JSON"))
    return
}
request.httpBody = bodyData
```

Or, for `AnthropicRequestBuilder.build()` which returns a `URLRequest` directly and has no channel, throw or use a `throws` signature with a Result type to surface the failure to the caller (`AnthropicProvider.respond()`).

## Warnings

### WR-01: `SQLiteMemoryStore` silently ignores directory creation failure

**File:** `Sources/SwiftAgentCore/AgentRuntime/Providers/Memory/SQLiteMemoryStore.swift:49-53`

**Issue:** `try? FileManager.default.createDirectory(at:withIntermediateDirectories:)` silently ignores failure. If the `~/.swift-agent/` directory cannot be created (permissions, disk full, path too long), `dbPath` points to a non-existent location and `sqlite3_open_v2` may either fail (caught by the guard below) or create the DB in an unexpected location. The root cause is masked.

**Fix:** Either throw on directory creation failure, or at minimum log the failure:
```swift
do {
    try FileManager.default.createDirectory(
        at: swiftAgentDir,
        withIntermediateDirectories: true
    )
} catch {
    throw AgentRuntimeError.storageFull(availableBytes: 0)
}
```

### WR-02: `SQLiteMemoryStore.init` throws misleading `storageFull` for any open failure

**File:** `Sources/SwiftAgentCore/AgentRuntime/Providers/Memory/SQLiteMemoryStore.swift:63-65`

**Issue:** The error thrown on `sqlite3_open_v2` failure is always `AgentRuntimeError.storageFull(availableBytes: 0)`, regardless of actual cause. The failure could be a permission error, corrupt database, invalid path, or actual disk-full condition. Callers cannot distinguish the root cause.

**Fix:** Use `sqlite3_errmsg()` to get the actual error message and wrap it:
```swift
guard rc == SQLITE_OK, let handle = handle else {
    let msg = String(cString: sqlite3_errmsg(handle))
    if let h = handle { sqlite3_close(h) }
    throw AgentRuntimeError.storageFull(availableBytes: 0)
}
```
At minimum, differentiate between permission errors (`SQLITE_CANTOPEN`, `SQLITE_PERM`) and disk-full (`SQLITE_FULL`), or include the SQLite error code/msg in the thrown error.

### WR-03: `OpenAIToolTranslator` sets `strict: true` unconditionally

**File:** `Sources/SwiftAgentCore/AgentRuntime/Providers/OpenAI/OpenAIToolTranslator.swift:49`

**Issue:** `function["strict"] = true` is applied to every tool schema regardless of whether the schema meets OpenAI's strict-mode requirements. Strict mode requires all properties to have `additionalProperties: false`, all object properties to be listed in `required`, and prohibits `default` values. Arbitrary tool schemas (e.g., from MCP servers) will likely violate these constraints, causing OpenAI to reject the request with a 400 error.

**Fix:** Either make strict mode opt-in (via a configuration flag or per-tool metadata) or validate the schema against strict-mode requirements before enabling it:
```swift
// Option A: Conditional on schema compatibility
let isStrictCompatible = tool.inputSchema.additionalProperties == false
    && tool.inputSchema.properties.allSatisfy { /* meet strict criteria */ }
if isStrictCompatible {
    function["strict"] = true
}

// Option B: Configuration-driven
function["strict"] = options.enableStrictMode
```

### WR-04: `AgentPermissionBridge` deny-by-default cases have no override mechanism

**File:** `Sources/SwiftAgentCore/AgentRuntime/Providers/Permission/AgentPermissionBridge.swift:76-79`

**Issue:** The six deny-by-default permissions (`contacts`, `calendar`, `location`, `camera`, `microphone`, `delete`) always return `false` with no path through the `PermissionEngine` or any configuration mechanism. Even the `.all` permission bypasses this logic (line 68) and returns `true`, but individual checks for these permissions are permanently denied. If a use case requires granting `.delete` permission (e.g., a file-cleanup tool), there is no mechanism to allow it.

**Fix:** Route these permissions through the `PermissionEngine` similar to `runCommands`/`readFiles`/`writeFiles`, using appropriate tool-name mappings:
```swift
case .delete:
    let verdict = await engine.check(
        toolName: "Delete",
        input: [:],
        mode: mode,
        context: .default
    )
    return verdict.decision == .allow
```

### WR-05: Duplicate Anthropic-compat SSE parsing logic between two parsers

**Files:**
- `Sources/SwiftAgentCore/AgentRuntime/Providers/Anthropic/AnthropicSSEParser.swift:25-109`
- `Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/DeepSeekSSEParser.swift:36-118`

**Issue:** `AnthropicSSEParser.parse()` and `DeepSeekSSEParser.parseAnthropicCompat()` contain nearly identical logic (same event types, same accumulation, same content_block_start/stop handling). A bug fix or improvement in one parser must be manually duplicated in the other, creating a maintenance hazard. The only difference is that `AnthropicSSEParser` tracks `receivedMessageDelta` and `lastEventTime` (unused in the current implementation), while `DeepSeekSSEParser` does not.

**Fix:** Extract the shared SSE parsing logic into a single component. Options:
- Make `AnthropicSSEParser` reusable and have `DeepSeekSSEParser.parseAnthropicCompat()` delegate to it
- Extract a shared `parseAnthropicSSE(lines:channel:accumulator:)` function

### WR-06: Two independent tool call accumulator implementations for OpenAI format

**Files:**
- `Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/DeepSeekSSEParser.swift:229-256` (`OpenAIToolCallAccumulator`)
- `Sources/SwiftAgentCore/AgentRuntime/Providers/OpenAI/OpenAISSEParser.swift:27-33` (`ToolCallAccumulator`)

**Issue:** The same concept (per-index tool call fragment accumulation for OpenAI Chat Completions SSE) is implemented twice with different data structures and parse semantics. `OpenAIToolCallAccumulator` uses `AnthropicContentAccumulator.safeParseJSON` for argument parsing (with double-stringification support), while `OpenAISSEParser.ToolCallAccumulator` does a manual JSON parse + re-encode. If a double-stringified arguments payload arrives from OpenAI, the `ToolCallAccumulator` might lose data that `OpenAIToolCallAccumulator` would correctly preserve.

**Fix:** Unify into a single implementation exported from one of the providers or a shared utility location. Prefer the `safeParseJSON`-based approach from `OpenAIToolCallAccumulator` as it is more robust against double-stringification.

## Info

### IN-01: `AnthropicRetryPolicy` is dead code — never used by any provider

**File:** `Sources/SwiftAgentCore/AgentRuntime/Providers/Anthropic/AnthropicRetryPolicy.swift`

**Issue:** `AnthropicRetryPolicy` defines `shouldRetry` and `backoffDelay` static methods, but `AnthropicProvider.respond()` does not call them. The retry logic is not integrated. Only the test file references this type. The `DeepSeekProvider` and `OpenAIProvider` also lack retry logic.

**Fix:** Either integrate retry into the provider `respond()` methods or remove the file and its tests until retry is implemented.

### IN-02: Misleading `x-stainless-*` headers claim JavaScript/Node runtime

**File:** `Sources/SwiftAgentCore/AgentRuntime/Providers/Anthropic/AnthropicRequestBuilder.swift:71-77`

**Issue:** The request headers claim `x-stainless-lang: js`, `x-stainless-runtime: node`, `x-stainless-runtime-version: v24.3.0`, and `x-stainless-package-version: 0.94.0`. These are copy-pasted from the TypeScript SDK and misrepresent the client as a JavaScript/Node runtime running version 0.94.0. While the API may not enforce these headers today, they provide inaccurate telemetry to Anthropic and could cause issues if the API introduces runtime-specific behavior.

**Fix:** Set accurate values or omit optional headers:
```swift
request.setValue("swift", forHTTPHeaderField: "x-stainless-lang")
request.setValue("swift", forHTTPHeaderField: "x-stainless-runtime")
// Omit x-stainless-package-version and x-stainless-runtime-version until versioned
```

### IN-03: Inconsistent parser architecture (struct vs actor)

**Files:**
- `Sources/SwiftAgentCore/AgentRuntime/Providers/Anthropic/AnthropicSSEParser.swift:12` (`struct: Sendable`)
- `Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/DeepSeekSSEParser.swift:14` (`actor`)
- `Sources/SwiftAgentCore/AgentRuntime/Providers/OpenAI/OpenAISSEParser.swift:19` (`actor`)

**Issue:** `AnthropicSSEParser` is a `Sendable` struct with all state in local `var` scoped to the `parse()` method. `DeepSeekSSEParser` and `OpenAISSEParser` are actors (which is necessary for the latter since `OpenAISSEParser` stores `toolCallAccumulators` as mutable actor state across loop iterations). The inconsistency makes the codebase harder to reason about — a developer might not realize that Anthropic parser state is method-local while OpenAI parser state is actor-scoped.

**Fix:** Not urgent. When refactoring the duplicate Anthropic-compat SSE logic (WR-05), align the architecture. If the shared parser needs no persisted state beyond the parsing loop, a struct is appropriate. If persistent state is needed, use an actor consistently.

### IN-04: Duplicated stream-and-parse boilerplate across three providers

**Files:**
- `Sources/SwiftAgentCore/AgentRuntime/Providers/Anthropic/AnthropicProvider.swift:117-142`
- `Sources/SwiftAgentCore/AgentRuntime/Providers/DeepSeek/DeepSeekProvider.swift:226-261`
- `Sources/SwiftAgentCore/AgentRuntime/Providers/OpenAI/OpenAIProvider.swift:139-175`

**Issue:** The pattern of creating an `AsyncStream<String>` from `URLSession.AsyncBytes.lines`, checking HTTP status, and forwarding errors to the channel is repeated verbatim across all three providers. The `catch` blocks are identical except for the error wrapping.

**Fix:** Extract into a shared helper, e.g., `func streamSSE(request: URLRequest, session: URLSession, channel: GenerationChannel, parse: (AsyncStream<String>) async throws -> Void)`.

### IN-05: `AgentRuntimeImpl` integration test uses real `PermissionEngine()` with no rules

**File:** `Tests/SwiftAgentCoreTests/AgentPermissionBridgeTests.swift:167-168`

**Issue:** The integration test creates `PermissionEngine()` (no rules) and wraps it in `AgentPermissionBridge`. Any tool call attempted during the test will be denied since no rules are configured. The test passes only because `MockLanguageModel` returns a canned text response without attempting tool calls. This makes the test fragile — if the mock model's behavior changes or if the runtime validates permissions before responding, the test will break without a clear signal.

**Fix:** Either configure rules on the `PermissionEngine` that match the test scenario, or use `MockPermissionEngine(shouldAllow: true)` for the bridge:
```swift
let bridge = AgentPermissionBridge(
    engine: PermissionEngine(),
    mode: .default
)
// Add a rule so tool checks don't silently fail:
// Or use MockPermissionEngine(shouldAllow: true) and wrap it differently
```

### IN-06: Tautological and non-test assertions

**Files:**
- `Tests/SwiftAgentCoreTests/AnthropicProviderTests.swift:553` — `XCTAssertTrue(true, ...)` instead of asserting the return value of `finalizeToolCall`
- `Tests/SwiftAgentCoreTests/AnthropicProviderTests.swift:652` — `XCTAssertTrue(events.count >= 0, ...)` is tautological (count is always >= 0)
- `Tests/SwiftAgentCoreTests/DeepSeekProviderTests.swift:265` — `XCTAssertTrue(true, ...)` with comment "verified by source grep"

**Issue:** These assertions provide no test coverage. The `truncatedJSON_noCrash` test should assert the return value (nil or partial input dict). The `respond_withFixtures` test should assert specific error types. The `noBetaHeader` test should actually inspect the request headers rather than relying on a comment.

**Fix:** Replace with meaningful assertions. For `truncatedJSON_noCrash`: assert that `result` is non-nil but contains empty input, or is nil depending on the intended behavior. For `noBetaHeader`: construct a request via the builder and verify `request.value(forHTTPHeaderField: "anthropic-beta")` is nil.

### IN-07: Error message exposes `error.localizedDescription` through channel

**File:** `Sources/SwiftAgentCore/AgentRuntime/Providers/Anthropic/AnthropicProvider.swift:140`, `DeepSeekProvider.swift:259`, `OpenAIProvider.swift:173`

**Issue:** The generic `catch` block passes `error.localizedDescription` directly to `channel.fail(with: .serverError(body:))`. This can leak internal implementation details (framework error messages, file paths, etc.) to downstream consumers of the error event.

**Fix:** Use a fixed error message and log the full description separately:
```swift
await channel.fail(with: .serverError(statusCode: 0, body: "Network request failed"))
```

---

_Reviewed: 2026-06-25T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
