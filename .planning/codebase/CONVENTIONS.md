# Coding Conventions

**Analysis Date:** 2026-06-25

## Naming Patterns

**Files:**
- PascalCase for all Swift files (e.g., `ChatCommand.swift`, `ToolResultCache.swift`, `AppViewModel.swift`)
- Extension-decomposed files use `TypeName+Purpose.swift` (e.g., `ChatCommand+Types.swift`, `ChatCommand+SystemPrompt.swift`, `ChatCommand+UserPrompt.swift`)
- Tool files follow the pattern `{ToolName}Tool.swift` (e.g., `BashTool.swift`, `FileReadTool.swift`, `GrepTool.swift`)

**Types (structs, classes, enums, protocols, actors):**
- PascalCase (e.g., `Tool`, `AppError`, `LineEditor`, `ComposerState`, `MCPConnectionManager`)
- Protocols are named as nouns or noun phrases (e.g., `Tool`, `LLMProvider`, `TerminalRawReader`)
- Actor names are nouns describing the resource they manage (e.g., `ToolResultCache`, `PluginManager`, `MCPClient`, `AppState`)

**Functions and Methods:**
- camelCase (e.g., `readLine()`, `checkPermissions()`, `isReadOnly()`, `getToolUseSummary()`)
- Boolean-returning functions use `is`/`has`/`should` prefix (e.g., `isReadOnly`, `isMcp`, `isDestructive`, `shouldDefer`)
- Test functions use descriptive names describing the scenario (e.g., `readExistingFile()`, `historyNavigationDoesNotStackOnScreen()`)

**Variables and Properties:**
- camelCase (e.g., `conversationHistory`, `sidebarWidth`, `activeErrors`, `expandState`)
- Private stored properties may use `_` prefix for manual lock-guarded access (e.g., `_planModeActive`, `_totalTokensIn`)

**Constants:**
- camelCase — no `k` prefix or all-caps (e.g., `maxResultSizeChars`, `readOnlyPrefixes`, `dangerousPatterns`)
- Numeric literals use underscore separators: `30_000`, `200_000`, `180_000`

## Code Style

**Formatting:**
- No formatter tool detected (no `.swift-format`, `.swiftformat`, or `swiftlint.yml` config in the project)
- Consistent manual style: 4-space indentation, opening braces on same line
- Line length: varies widely; some files have long multi-line string literals (tool descriptions, JSON schemas)

**Linting:**
- No linting tool configured

**General Style:**
- Trailing closure syntax preferred when last parameter is a closure
- Multi-line string literals using `"""` for large text blocks (tool descriptions, JSON schema descriptions)
- Type annotations on public API properties; inferred where obvious in local scope
- `self.` used only when required by compiler (closures, escaping contexts)

## Import Organization

**Order (top to bottom):**
1. `import Foundation` (always first if present)
2. Platform frameworks (`import Darwin`, `import CoreGraphics`, `import PDFKit`)
3. Third-party dependencies (`import ArgumentParser`, `import SwiftUI`)
4. Internal modules (`import SwiftAgentCore`)

**Examples:**
```swift
// Core tool file:
import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

// CLI entry point:
import Foundation
import Darwin
import ArgumentParser
import SwiftAgentCore

// App view model:
import SwiftUI
import SwiftAgentCore
```

**Path Aliases:**
- No `@_exported import` or module aliases used. Direct import by target name.

## Section Organization (MARK Comments)

Code within large files is organized with `// MARK: - Section Name` comments. This is used consistently across all layers.

**Common sections observed:**
- `// MARK: - Tool Identity` — name, description, search hint
- `// MARK: - Input Schema` — JSON schema definitions
- `// MARK: - Tool Protocol Overrides` — isReadOnly, isConcurrencySafe, etc.
- `// MARK: - UI / Display Helpers` — getToolUseSummary, getActivityDescription
- `// MARK: - Cases` — enum case declarations
- `// MARK: - Identity` — enum identifiers
- `// MARK: - Severity` — classification
- `// MARK: - Display — Title` / `Message` / `Icon` — UI properties
- `// MARK: - Storage` / `LLM Provider` / `Layout` — view model sections
- `// MARK: - Persistence` / `Subsystems` / `Init` — class organization

## Error Handling

**Patterns:**

**1. Enum-based error taxonomy (App layer):**
```swift
// Sources/SwiftAgentApp/Errors/ErrorTaxonomy.swift
enum AppError: Identifiable, Equatable {
    case sandboxDenied(String)
    case networkReconnecting
    case rateLimit429(retryAfter: Int)
    // ... 13 more cases
    
    var id: String { /* stable string per case */ }
    var severity: ErrorSeverity { /* .fatal, .retryable, or .warning */ }
    var title: String { /* user-facing title */ }
    var message: String { /* user-facing message */ }
    var icon: String { /* SF Symbol name */ }
    var bannerColor: Color { /* .danger or .warning */ }
    var actionTitle: String? { /* primary action button label */ }
}
```
Each error case is a single source of truth for identity, severity, and user-visible copy. Views read display properties from the enum rather than switching on individual cases.

**2. Tool permission checks return typed decision:**
```swift
// Sources/SwiftAgentCore/Types/Tool.swift
func checkPermissions(input: [String: JSONValue], context: ToolUseContext) async -> PermissionResult
// Returns: .allow(PermissionAllowDecision()), .deny, or .ask
```

**3. Do/catch for network and I/O operations:**
```swift
// Sources/SwiftAgentCLI/ChatCommand.swift
do {
    try store.save(s)
} catch {
    // handle gracefully
}
```

**4. Guard-let early returns:**
```swift
guard let l = editor.readLine(prompt: "You: ") else { break }
guard !cwd.isEmpty else { continue }
```

**5. Result types with `.isError` flag:**
- `ToolResult` has an `.isError` property; tool execution does not throw for semantic errors but sets the flag on the result.

**6. Validation with concrete result types:**
```swift
public func validateInput(_ input: [String: JSONValue], context: ToolUseContext) async -> ValidationResult {
    .success  // or .failure with message
}
```

## Logging

**Framework:** `DebugLogger` class conforming to `LLMDebugLogger` and `DebugLogSink` protocols.

**Location:** `Sources/SwiftAgentCLI/DebugLogger.swift`

**Patterns:**
- `--debug` flag on CLI enables debug logging
- Logs written to `~/.swift-agent/debug/<session-uuid>.txt` (plain text, Claude Code-compatible format)
- API keys masked in log output
- JSONL debug logging format for structured operational logs

**No third-party logging framework used.** Console logging via `print()` used in tests.

## Comments

**When to comment:**
- Public API declarations require `///` documentation comments describing purpose, parameters, and behavior
- Complex algorithms or design decisions get inline `//` explanations
- Tool descriptions embedded as multi-line string literals (verbatim LLM instructions)
- `MARK:` comments organize sections within large files

**JSDoc-style doc comments (///):**
- Used on all public types, protocols, methods, and properties
- Multi-line `///` for struct/class/enum descriptions
- Parameter documentation inline with `/// - Parameters:` or descriptive prose

**Example:**
```swift
/// Execute the tool with the given input and context.
/// Matches Claude Code's call(args, context, canUseTool, parentMessage, onProgress).
/// - Parameters:
///   - input: Tool input arguments as a dictionary.
///   - context: Execution context (permission mode, working dir, session, etc.).
///   - canUseTool: Callback for sub-operation permission checks during execution.
///   - parentMessage: The parent assistant message that triggered this tool call.
///   - onProgress: Optional progress stream for streaming progress updates.
func call(...) async throws -> ToolResult
```

**Pattern from CLAUDE.md:**
> "Only add comments where the logic isn't self-evident."

## Function Design

**Size:**
- Most functions are small (5-40 lines). Tool files are typically 200-700 lines due to verbose JSON schema definitions
- Large files decomposed via extension files (e.g., `ChatCommand` split from 1,992 lines into main file + 5 extensions)
- Largest files: `ChatCommand.swift` (1,192 lines), `Tool.swift` (1,156 lines), `LLMClient.swift` (1,079 lines)

**Parameters:**
- Multiple parameters grouped into structs when there are more than 4 (e.g., `ToolUseContext`, `ToolDescriptionOptions`)
- Callback parameters use typealiases for readability: `CanUseToolFn`, `ToolCallProgress`
- Default values provided in protocol extensions rather than at call sites

**Return Values:**
- Async functions use `async throws` for I/O operations
- Computed properties for simple derived values
- `-> Bool` for predicates, `-> String?` for optional display text
- Explicit return types on all functions (no implicit `Void` for public API)

**Async Pattern:**
- All tool `call()` methods are `async throws`
- `await` used for actor-isolated operations
- `Task { @MainActor ... }` for UI updates from async contexts
- `NSLock` with `withLock {}` for thread-safe mutable state in `@unchecked Sendable` classes

## Module Design

**Exports:**
- `public` keyword used explicitly for cross-module API surface
- `internal` (implicit default) for module-internal code
- `private` for file-local helpers and implementation details
- `@testable import` used in tests to access `internal` APIs

**Barrel Files:**
- Not used. Each file is imported directly where needed.
- Module boundary: `SwiftAgentCore` is the reusable library; `SwiftAgentCLI` and `SwiftAgentApp` depend on it but not on each other

**Protocol Design:**
- Protocols marked `Sendable` when used across concurrency domains
- Default implementations provided via `extension` blocks (see `Tool` protocol with 30+ default property/method implementations)
- Protocol inheritance: `MCPTransport` is base, `MCPStreamingTransport: MCPTransport` extends it
- Mock implementations created as test structs conforming to protocols (no mocking framework)

## State Management

**Actors for mutable shared state:**
- `Sources/SwiftAgentCore/State/AppState.swift` — `public actor AppState`
- `Sources/SwiftAgentCore/Plugins/PluginManager.swift` — `public actor PluginManager`
- `Sources/SwiftAgentCore/MCP/MCPConnectionManager.swift` — `public actor MCPConnectionManager`
- `Sources/SwiftAgentCore/Tools/TodoWriteTool.swift` — `public actor TodoStore`
- `Sources/SwiftAgentCLI/ToolResultCache.swift` — `public actor ToolResultCache`

**@MainActor for UI-bound ViewModels:**
- `Sources/SwiftAgentApp/ViewModels/AppViewModel.swift` — `@MainActor final class AppViewModel: ObservableObject`
- `Sources/SwiftAgentApp/ViewModels/ThreadViewModel.swift` — `@MainActor`
- `Sources/SwiftAgentApp/ViewModels/ProjectViewModel.swift` — `@MainActor`
- `Sources/SwiftAgentApp/Errors/ErrorPresenter.swift` — `@MainActor final class ErrorPresenter: ObservableObject`

**@unchecked Sendable for CLI mutable state:**
- `Sources/SwiftAgentCLI/ChatCommand+Types.swift` — `ExpandState`, `SharedModel`, `SessionState`, etc. all `final class ... @unchecked Sendable` with `NSLock`-guarded access
- `Sources/SwiftAgentCLI/LineEditor.swift` — `public final class LineEditor: @unchecked Sendable`

## Swift Language Version

- `Package.swift` line 1: `// swift-tools-version: 6.2`
- Platform target: `.macOS(.v15)`
- Full Swift Concurrency enabled; strict Sendable checking enforced

---

*Convention analysis: 2026-06-25*
