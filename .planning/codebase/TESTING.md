# Testing Patterns

**Analysis Date:** 2026-06-25

## Test Framework

**Two frameworks used in parallel:**

| Framework | Used In | Import |
|-----------|---------|--------|
| `Swift Testing` (new, macro-based) | `SwiftAgentCoreTests`, `SwiftAgentCLITests` | `import Testing` |
| `XCTest` (legacy, class-based) | `SwiftAgentAppTests`, `SwiftAgentAppUITests` | `import XCTest` |

**No separate test dependency packages.** Both frameworks are built into the Swift toolchain.

**Assertions:**

```swift
// Swift Testing macros (Core/CLI tests)
#expect(condition)            // Non-fatal assertion
#expect(condition, "message") // With description
#require(optional)            // Fatal — unwraps or stops test
Issue.record("message")       // Manual failure in guard-let branches

// XCTest assertions (App tests)
XCTAssertTrue(condition)
XCTAssertEqual(a, b)
XCTAssertNotNil(optional)
XCTAssertNil(optional)
```

**Run Commands:**
```bash
swift test --disable-sandbox --no-parallel    # Run all tests
swift test --disable-sandbox --no-parallel \
  --filter SwiftAgentCoreTests                 # Run one test target
```

Always use `--disable-sandbox` (file system tests create temp files) and `--no-parallel` (shared state between tests).

## Test File Organization

**Location:**
- Tests co-located by target in `Tests/` directory, mirroring `Sources/` structure
- `Tests/SwiftAgentCoreTests/` — 24 Swift files, 13 suites
- `Tests/SwiftAgentCLITests/` — 7 Swift files
- `Tests/SwiftAgentAppTests/` — 6 Swift files
- `Tests/SwiftAgentAppUITests/` — 5 Swift files

**Naming:**
- Core tests: `Phase{N}{Topic}Tests.swift` — e.g., `Phase1TypesTests.swift`, `Phase4ToolsTests.swift`, `Phase9StorageTests.swift`
- CLI tests: `{Component}Tests.swift` — e.g., `LineEditorReadLineTests.swift`, `TerminalRenderingTests.swift`
- App tests: `{Topic}Tests.swift` — e.g., `ThreadRepositoryTests.swift`, `PersistenceRoundTripTests.swift`
- UI tests: `{ActionDescription}.swift` — e.g., `LaunchAndSeeLayout.swift`, `NewThreadSendsMessage.swift`

**Total test lines: ~4,653 across 29 test files** (plus additional files not counted).

## Test Structure

**Swift Testing pattern (Core/CLI):**

```swift
import Testing
import Foundation
@testable import SwiftAgentCore

// Top-level shared test context
let testCtx = ToolUseContext(workingDirectory: "/tmp", sessionID: "test")

// Struct-based test suite
struct ReadToolTests {
    @Test
    func readExistingFile() async throws {
        let tool = FileReadTool()
        let testFile = "/tmp/swiftagent_test_read_\(UUID().uuidString.prefix(8)).txt"
        try "line1\nline2\nline3".write(toFile: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: testFile) }

        let result = try await tool.call(input: ["file_path": .string(testFile)], context: testCtx)
        #expect(!result.isError)
        #expect(result.content.contains("line1"))
    }
}
```

**With @Suite annotation (for named suites):**
```swift
@Suite struct LineEditorReadLineTests {
    @Test
    func historyNavigationDoesNotStackOnScreen() { ... }
}
```

**XCTest pattern (App tests):**

```swift
import XCTest
@testable import SwiftAgentApp

final class ThreadRepositoryTests: XCTestCase {
    var db: Database!
    var repo: ThreadRepository!
    var tempPath: String!

    override func setUp() {
        super.setUp()
        tempPath = NSTemporaryDirectory() + "test-threads-\(UUID().uuidString).db"
        db = Database(path: tempPath)
        try! db.open()
        // Create tables needed
        try! db.execute("""
            CREATE TABLE IF NOT EXISTS threads (...)
        """)
        repo = ThreadRepository(database: db)
    }

    override func tearDown() {
        db?.close()
        if let path = tempPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        super.tearDown()
    }

    func testCreateThread() throws {
        let thread = PersistedThread(title: "Test Thread")
        try repo.create(thread)
        let fetched = try repo.get(id: thread.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.title, "Test Thread")
    }
}
```

**Key structural patterns:**
- `@MainActor` on XCTest classes that interact with `ObservableObject` view models (`PersistenceRoundTripTests`)
- Test structs/classes define multiple `@Test`/`func test*` methods testing related functionality
- Each test method creates its own input data and asserts independently

**Setup pattern:**
- Core/CLI tests: Inline temp file creation with `defer` cleanup at test method level
- App tests: `setUp()`/`tearDown()` with `override` at suite level, using `NSTemporaryDirectory()` + UUID

**Teardown pattern:**
- `defer { try? FileManager.default.removeItem(atPath: ...) }` for inline cleanup
- `tearDown()` override with `try?` for class-level cleanup (App tests)

**Assertion pattern:**
- `#expect(condition)` for simple boolean checks
- `#expect(value == expected)` for equality
- `guard case .expected(let val) = actual else { Issue.record(...); return }` for enum matching (early-exit failure)

## Mocking

**No third-party mocking framework.** The codebase uses protocol-based manual fakes.

**Protocol-based Mock pattern:**

```swift
// Define a mock struct conforming to the protocol
struct MockReadTool: Tool {
    var name: String { "View" }
    func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String {
        "Read files"
    }
    var inputSchema: JSONSchema {
        JSONSchema(type: "object", properties: ["path": JSONSchemaProperty(type: "string")])
    }
    var isReadOnly: Bool { true }
    var isConcurrencySafe: Bool { true }

    func call(input: [String: JSONValue], context: ToolUseContext,
              canUseTool: CanUseToolFn?, parentMessage: Message?,
              onProgress: ToolCallProgress?) async throws -> ToolResult {
        return ToolResult(content: "file contents")
    }
}
```

**Fake adapter for terminal I/O (CLI tests):**

```swift
final class FakeTerminalReader: TerminalRawReader, @unchecked Sendable {
    private let input: [UInt8]
    private var index = 0
    private(set) var output: [UInt8] = []
    private let lock = NSLock()

    init(input: String) { self.input = Array(input.utf8) }

    func readByte() -> UInt8? {
        lock.lock(); defer { lock.unlock() }
        guard index < input.count else { return nil }
        let b = input[index]; index += 1
        return b
    }

    var captured: String { String(bytes: output, encoding: .utf8) ?? "" }
}
```

This `FakeTerminalReader` in `Tests/SwiftAgentCLITests/LineEditorReadLineTests.swift` captures stdout bytes and provides pre-scripted input for deterministic CLI rendering tests.

**What to mock:**
- External I/O (terminal, file system — use temp directories, don't mock Foundation)
- LLM clients (not mocked in existing tests; tests exercise types/parsing/tools directly)
- Database connections (use temp `.db` files for SQLite)

**What NOT to mock:**
- Plain data types and value structs — test them directly
- System APIs like `FileManager` — use temp directories instead

## Fixtures and Factories

**Test data is created inline in each test method.** There are no shared fixture files or factory modules.

**Pattern:**
```swift
// Inline file creation for tool tests
let testFile = "/tmp/swiftagent_test_read_\(UUID().uuidString.prefix(8)).txt"
try "line1\nline2\nline3".write(toFile: testFile, atomically: true, encoding: .utf8)
defer { try? FileManager.default.removeItem(atPath: testFile) }
```

**Location:**
- Temp directory (`/tmp/` or `NSTemporaryDirectory()`) with UUID-based unique filenames
- Each test creates and cleans up its own data — no shared state between tests

**App-level fixtures:**
- `PersistenceRoundTripTests` creates ephemeral `SwiftAgentStore` instances pointed at temp directories
- `ThreadRepositoryTests` creates in-memory SQLite databases (`Database(path:)`) with explicit schema

## Coverage

**No coverage configuration detected:**
- No `.xcresult` or coverage targets in `Package.swift`
- No coverage threshold or enforcement

**View coverage manually (Xcode):**
- Use Xcode's Test navigator with Code Coverage enabled
- Not integrated into CI/build pipeline

## Test Types

**Unit Tests (the majority):**
- `SwiftAgentCoreTests/` — Domain type serialization/deserialization, tool behavior, JSON schema correctness, storage CRUD operations, context manager math, message normalization, stream parser logic, retry policy
- Files: `Phase1TypesTests.swift` through `Phase12AdvancedTests.swift`, plus `SyntaxHighlightingTests.swift`, `CoreTypesTests.swift`
- Scope: Pure logic, no external dependencies beyond temp files

**Integration Tests:**
- `SwiftAgentCLITests/` — Terminal rendering output verification, composer popup rendering, line editor history navigation, paste detection
- `SwiftAgentAppTests/PersistenceRoundTripTests.swift` — Full create-session, append-message, reload cycle through the file-based store
- `SwiftAgentAppTests/ThreadRepositoryTests.swift` — SQLite repository with real database

**E2E Tests:**
- `SwiftAgentAppUITests/` — XCUITest-based app launch and layout verification (5 lightweight tests)
- Tests: `LaunchAndSeeLayout.swift`, `NewThreadSendsMessage.swift`, `SettingsOpens.swift`, `SwitchPanel.swift`, `ThemeSwitch.swift`
- Framework: XCUITest with `XCUIApplication`
- Note: Documentation states these "serve as documentation and can run when configured in Xcode"

## Common Patterns

**Async Testing:**
```swift
// Swift Testing uses async test methods directly
@Test
func readExistingFile() async throws {
    let result = try await tool.call(input: [...], context: testCtx)
    #expect(!result.isError)
}

// XCTest uses async with expectation/wait or throws
func testCreateThread() throws {
    let thread = PersistedThread(title: "Test Thread")
    try repo.create(thread)
    // Direct try for synchronous-looking repos
}
```

**Error Testing:**
```swift
// Asserting error results via isError flag
@Test
func missingFileReturnsError() async throws {
    let tool = FileReadTool()
    let result = try await tool.call(input: ["file_path": .string("/nonexistent/path.txt")], context: testCtx)
    #expect(result.isError)
}

// Asserting error states via enum matching
@Test
func parsesTextDelta() {
    let event = parser.parse(data: data)
    guard case .textDelta(let text) = event else {
        Issue.record("Expected textDelta, got \(String(describing: event))")
        return
    }
    #expect(text == "Hello")
}
```

**Permission testing:**
```swift
@Test
func rejectsDangerousCommands() async {
    let tool = BashTool()
    let result = await tool.checkPermissions(input: ["command": .string("rm -rf /")], context: testCtx)
    guard case .deny = result else {
        Issue.record("Expected deny for rm -rf /")
        return
    }
}
```

## Test Target Registration (Package.swift)

Each test target is defined in `Package.swift`:

```swift
.testTarget(
    name: "SwiftAgentCoreTests",
    dependencies: ["SwiftAgentCore"],
    path: "Tests/SwiftAgentCoreTests"
),
.testTarget(
    name: "SwiftAgentCLITests",
    dependencies: ["SwiftAgentCLI"],
    path: "Tests/SwiftAgentCLITests"
),
.testTarget(
    name: "SwiftAgentAppTests",
    dependencies: ["SwiftAgentApp"],
    path: "Tests/SwiftAgentAppTests"
),
.testTarget(
    name: "SwiftAgentAppUITests",
    dependencies: ["SwiftAgentApp"],
    path: "Tests/SwiftAgentAppUITests"
),
```

---

*Testing analysis: 2026-06-25*
