import Testing
import Foundation
@testable import SwiftAgentCore

let testCtx = ToolUseContext(workingDirectory: "/tmp", sessionID: "test")

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
        #expect(result.content.contains("line2"))
    }

    @Test
    func readWithOffsetLimit() async throws {
        let tool = FileReadTool()
        let testFile = "/tmp/swiftagent_test_offset_\(UUID().uuidString.prefix(8)).txt"
        let lines = (1...10).map { "line\($0)" }.joined(separator: "\n")
        try lines.write(toFile: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: testFile) }

        let result = try await tool.call(input: [
            "file_path": .string(testFile),
            "offset": .number(5),
            "limit": .number(2)
        ], context: testCtx)
        #expect(!result.isError)
        #expect(result.content.contains("line6"))
        #expect(!result.content.contains("line1"))
    }

    @Test
    func missingFileReturnsError() async throws {
        let tool = FileReadTool()
        let result = try await tool.call(input: ["file_path": .string("/nonexistent/path.txt")], context: testCtx)
        #expect(result.isError)
    }
}

struct WriteToolTests {
    @Test
    func writeNewFile() async throws {
        let tool = FileWriteTool()
        let testFile = "/tmp/swiftagent_test_write_\(UUID().uuidString.prefix(8)).txt"
        defer { try? FileManager.default.removeItem(atPath: testFile) }

        let result = try await tool.call(input: [
            "file_path": .string(testFile),
            "content": .string("hello world")
        ], context: testCtx)
        #expect(!result.isError)
        #expect(FileManager.default.fileExists(atPath: testFile))
        let content = try String(contentsOfFile: testFile, encoding: .utf8)
        #expect(content == "hello world")
    }
}

struct EditToolTests {
    @Test
    func replaceText() async throws {
        let tool = FileEditTool()
        let testFile = "/tmp/swiftagent_test_edit_\(UUID().uuidString.prefix(8)).txt"
        try "hello world".write(toFile: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: testFile) }

        let result = try await tool.call(input: [
            "file_path": .string(testFile),
            "old_string": .string("world"),
            "new_string": .string("SwiftAgent")
        ], context: testCtx)
        #expect(!result.isError)

        let content = try String(contentsOfFile: testFile, encoding: .utf8)
        #expect(content == "hello SwiftAgent")
    }

    @Test
    func missingOldStringReturnsError() async throws {
        let tool = FileEditTool()
        let testFile = "/tmp/swiftagent_test_edit2_\(UUID().uuidString.prefix(8)).txt"
        try "abc".write(toFile: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: testFile) }

        let result = try await tool.call(input: [
            "file_path": .string(testFile),
            "old_string": .string("xyz"),
            "new_string": .string("def")
        ], context: testCtx)
        #expect(result.isError)
    }
}

struct BashToolPermissionsTests {
    @Test
    func rejectsDangerousCommands() async {
        let tool = BashTool()
        let result = await tool.checkPermissions(input: ["command": .string("rm -rf /")], context: testCtx)
        guard case .deny = result else {
            Issue.record("Expected deny for rm -rf /")
            return
        }
    }

    @Test
    func warnsOnDestructiveCommands() async {
        let tool = BashTool()
        let result = await tool.checkPermissions(input: ["command": .string("rm -rf ./node_modules")], context: testCtx)
        guard case .ask = result else {
            Issue.record("Expected ask for destructive command")
            return
        }
    }

    @Test
    func allowsSafeCommands() async {
        let tool = BashTool()
        let result = await tool.checkPermissions(input: ["command": .string("echo hello")], context: testCtx)
        guard case .allow = result else {
            Issue.record("Expected allow for safe command")
            return
        }
    }
}

struct GlobToolTests {
    @Test
    func findsSwiftFiles() async throws {
        let tool = GlobTool()
        let dir = "/tmp/swiftagent_test_glob_\(UUID().uuidString.prefix(8))"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        try "".write(toFile: "\(dir)/a.swift", atomically: true, encoding: .utf8)
        try "".write(toFile: "\(dir)/b.swift", atomically: true, encoding: .utf8)
        try "".write(toFile: "\(dir)/c.txt", atomically: true, encoding: .utf8)

        let result = try await tool.call(input: ["pattern": .string("*.swift"), "path": .string(dir)], context: testCtx)
        #expect(!result.isError)
        #expect(result.content.contains("a.swift"))
        #expect(result.content.contains("b.swift"))
        #expect(!result.content.contains("c.txt"))
    }
}

struct GrepToolTests {
    @Test
    func findsPattern() async throws {
        let tool = GrepTool()
        let dir = "/tmp/swiftagent_test_grep_\(UUID().uuidString.prefix(8))"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        try "hello world\nfoo bar\nhello again".write(toFile: "\(dir)/test.txt", atomically: true, encoding: .utf8)

        let result = try await tool.call(input: ["pattern": .string("hello"), "path": .string(dir), "output_mode": .string("content")], context: testCtx)
        #expect(!result.isError)
        #expect(result.content.contains("hello"))
    }

    @Test
    func invalidRegexReturnsError() async throws {
        let tool = GrepTool()
        let result = try await tool.call(input: ["pattern": .string("[invalid"), "path": .string("/tmp")], context: testCtx)
        #expect(result.isError)
    }

    @Test
    func largeRipgrepOutputDoesNotDeadlockBeforeHeadLimit() async throws {
        let tool = GrepTool()
        let dir = "/tmp/swiftagent_test_grep_large_\(UUID().uuidString.prefix(8))"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let repeated = String(repeating: "highlight value value value value value value value value value\n", count: 20_000)
        try repeated.write(toFile: "\(dir)/large.txt", atomically: true, encoding: .utf8)

        let started = Date()
        let result = try await tool.call(input: [
            "pattern": .string("highlight"),
            "path": .string(dir),
            "output_mode": .string("content"),
            "-C": .number(1),
            "head_limit": .number(5),
        ], context: testCtx)

        #expect(!result.isError)
        #expect(result.content.contains("[Showing results with pagination = limit: 5]"))
        #expect(Date().timeIntervalSince(started) < 5)
    }
}
