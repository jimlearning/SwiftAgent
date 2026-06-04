import Testing
import Foundation
@testable import SwiftAgentCore

struct SessionStoreTests {
    @Test
    func saveAndLoadSession() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("swift-agent-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SessionStore(directory: dir)

        let session = Session(id: "test-1", title: "Test Session")
        try store.save(session)
        let loaded = try store.load("test-1")
        #expect(loaded?.id == "test-1")
        #expect(loaded?.title == "Test Session")
    }

    @Test
    func loadReturnsNilForMissing() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("swift-agent-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SessionStore(directory: dir)
        #expect(try store.load("nonexistent") == nil)
    }

    @Test
    func deleteRemovesSession() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("swift-agent-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SessionStore(directory: dir)

        try store.save(Session(id: "test-del"))
        #expect(try store.load("test-del") != nil)
        try store.delete("test-del")
        #expect(try store.load("test-del") == nil)
    }

    @Test
    func listRecentReturnsSessions() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("swift-agent-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SessionStore(directory: dir)

        try store.save(Session(id: "s1", title: "Session 1"))
        try store.save(Session(id: "s2", title: "Session 2"))

        let list = try store.listRecent()
        #expect(list.count == 2)
    }

    @Test
    func listRecentRespectsLimit() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("swift-agent-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SessionStore(directory: dir)

        for i in 1...5 {
            try store.save(Session(id: "s\(i)", title: "S\(i)"))
        }

        let list = try store.listRecent(limit: 3)
        #expect(list.count == 3)
    }
}

struct ClaudeMdLoaderTests {
    private func makeIsolatedLoaderRoot(_ name: String) throws -> (root: URL, work: URL, home: URL, managed: URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(name)-\(UUID())")
        let work = root.appendingPathComponent("work")
        let home = root.appendingPathComponent("home")
        let managed = root.appendingPathComponent("managed")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: true)
        return (root, work, home, managed)
    }

    @Test
    func loadAllReturnsEmptyForEmptyDirectory() throws {
        let dirs = try makeIsolatedLoaderRoot("test-empty")
        defer { try? FileManager.default.removeItem(at: dirs.root) }

        let loader = ClaudeMdLoader(managedDirectory: dirs.managed.path)
        let files = loader.loadAll(workingDirectory: dirs.work.path, homeDirectory: dirs.home.path)
        #expect(files.isEmpty)
    }

    @Test
    func loadAllFindsProjectCLAUDE() throws {
        let dirs = try makeIsolatedLoaderRoot("test-project")
        defer { try? FileManager.default.removeItem(at: dirs.root) }

        let mdPath = dirs.work.appendingPathComponent("CLAUDE.md")
        try "# Project instructions".write(to: mdPath, atomically: true, encoding: .utf8)

        let loader = ClaudeMdLoader(managedDirectory: dirs.managed.path)
        let files = loader.loadAll(workingDirectory: dirs.work.path, homeDirectory: dirs.home.path)

        let projectFiles = files.filter { $0.type == .project }
        #expect(projectFiles.count >= 1)
        #expect(projectFiles.contains(where: { $0.content.contains("Project instructions") }))
    }

    @Test
    func loadAllFindsDotClaudeMD() throws {
        let dirs = try makeIsolatedLoaderRoot("test-dotclaude")
        let dotClaudeDir = dirs.work.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: dotClaudeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dirs.root) }

        let mdPath = dotClaudeDir.appendingPathComponent("CLAUDE.md")
        try "# DotClaude instructions".write(to: mdPath, atomically: true, encoding: .utf8)

        let loader = ClaudeMdLoader(managedDirectory: dirs.managed.path)
        let files = loader.loadAll(workingDirectory: dirs.work.path, homeDirectory: dirs.home.path)

        let projectFiles = files.filter { $0.type == .project }
        #expect(projectFiles.contains(where: { $0.content.contains("DotClaude instructions") }))
    }

    @Test
    func loadAllFindsLocalCLAUDE() throws {
        let dirs = try makeIsolatedLoaderRoot("test-local")
        defer { try? FileManager.default.removeItem(at: dirs.root) }

        let localPath = dirs.work.appendingPathComponent("CLAUDE.local.md")
        try "# Local overrides".write(to: localPath, atomically: true, encoding: .utf8)

        let loader = ClaudeMdLoader(managedDirectory: dirs.managed.path)
        let files = loader.loadAll(workingDirectory: dirs.work.path, homeDirectory: dirs.home.path)

        let localFiles = files.filter { $0.type == .local }
        #expect(localFiles.count >= 1)
        #expect(localFiles.contains(where: { $0.content.contains("Local overrides") }))
    }

    @Test
    func loadOrderManagedBeforeUserBeforeProject() throws {
        let dirs = try makeIsolatedLoaderRoot("test-order")
        defer { try? FileManager.default.removeItem(at: dirs.root) }

        let mdPath = dirs.work.appendingPathComponent("CLAUDE.md")
        try "# Project".write(to: mdPath, atomically: true, encoding: .utf8)
        let userDir = dirs.home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        try "# User".write(to: userDir.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
        try "# Managed".write(to: dirs.managed.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)

        let loader = ClaudeMdLoader(managedDirectory: dirs.managed.path)
        let files = loader.loadAll(workingDirectory: dirs.work.path, homeDirectory: dirs.home.path)

        // Verify ordering: each file's type should be >= previous
        var lastPriority = -1
        for f in files {
            let p = MemoryType.priority(f.type)
            #expect(p >= lastPriority)
            lastPriority = p
        }
    }

    @Test
    func loadMergedCombinesContent() throws {
        let dirs = try makeIsolatedLoaderRoot("test-merged")
        defer { try? FileManager.default.removeItem(at: dirs.root) }

        try "# File A".write(to: dirs.work.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
        try "# File B".write(to: dirs.work.appendingPathComponent("CLAUDE.local.md"), atomically: true, encoding: .utf8)

        let loader = ClaudeMdLoader(managedDirectory: dirs.managed.path)
        let merged = loader.loadMerged(workingDirectory: dirs.work.path, homeDirectory: dirs.home.path)

        #expect(merged.contains("File A"))
        #expect(merged.contains("File B"))
    }

    @Test
    func resolveIncludesAddsIncludedFiles() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-include-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let helperPath = dir.appendingPathComponent("helper.md")
        try "# Helper content".write(to: helperPath, atomically: true, encoding: .utf8)

        let mainFile = MemoryFileInfo(
            path: dir.appendingPathComponent("CLAUDE.md").path,
            type: .project,
            content: "@helper.md\n# Main"
        )

        let loader = ClaudeMdLoader()
        let resolved = loader.resolveIncludes(in: [mainFile])

        #expect(resolved.count >= 2)
        #expect(resolved.contains(where: { $0.content.contains("Helper content") }))
    }

    @Test
    func resolveIncludesSkipsCodeBlocks() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-codeblock-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let content = """
        # Main
        ```
        @should-be-skipped.md
        ```
        @real-include.md
        """

        try "# Included".write(to: dir.appendingPathComponent("real-include.md"), atomically: true, encoding: .utf8)

        let mainFile = MemoryFileInfo(
            path: dir.appendingPathComponent("CLAUDE.md").path,
            type: .project,
            content: content
        )

        let loader = ClaudeMdLoader()
        let resolved = loader.resolveIncludes(in: [mainFile])

        #expect(resolved.contains(where: { $0.content.contains("Included") }))
        #expect(!resolved.contains(where: { $0.path.contains("should-be-skipped") }))
    }

    @Test
    func loadRulesDirectoryFindsMdFiles() throws {
        let dirs = try makeIsolatedLoaderRoot("test-rules")
        let rulesDir = dirs.work.appendingPathComponent(".claude/rules")
        try FileManager.default.createDirectory(at: rulesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dirs.root) }

        try "# Rule 1".write(to: rulesDir.appendingPathComponent("rule1.md"), atomically: true, encoding: .utf8)
        try "# Rule 2".write(to: rulesDir.appendingPathComponent("rule2.md"), atomically: true, encoding: .utf8)

        let loader = ClaudeMdLoader(managedDirectory: dirs.managed.path)
        let files = loader.loadAll(workingDirectory: dirs.work.path, homeDirectory: dirs.home.path)

        let projectFiles = files.filter { $0.type == .project }
        #expect(projectFiles.contains(where: { $0.content.contains("Rule 1") }))
        #expect(projectFiles.contains(where: { $0.content.contains("Rule 2") }))
    }

    @Test
    func loadAllFindsUserClaudeFromExplicitHomeDirectory() throws {
        let dirs = try makeIsolatedLoaderRoot("test-user")
        let userDir = dirs.home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dirs.root) }

        try "# User instructions".write(to: userDir.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)

        let loader = ClaudeMdLoader(managedDirectory: dirs.managed.path)
        let files = loader.loadAll(workingDirectory: dirs.work.path, homeDirectory: dirs.home.path)

        let userFiles = files.filter { $0.type == .user }
        #expect(userFiles.count == 1)
        #expect(userFiles.first?.content.contains("User instructions") == true)
    }
}

struct MemoryStoreTests {
    @Test
    func readProjectReturnsNilWhenMissing() throws {
        let tmp = NSTemporaryDirectory()
        let store = MemoryStore(projectDir: tmp)
        #expect(try store.readProject() == nil)
    }

    @Test
    func writeAndReadProject() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-project-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = MemoryStore(projectDir: dir.path)
        try store.writeProject("# Hello\nWorld")
        let content = try store.readProject()
        #expect(content == "# Hello\nWorld")
    }

    @Test
    func parseFrontmatterReturnsBodyOnly() {
        let store = MemoryStore(projectDir: "/tmp")
        let (fm, body) = store.parseFrontmatter("Hello world")
        #expect(fm.isEmpty)
        #expect(body == "Hello world")
    }

    @Test
    func parseFrontmatterExtractsYAML() {
        let store = MemoryStore(projectDir: "/tmp")
        let content = """
        ---
        key1: value1
        key2: value2
        ---
        Body text here.
        """
        let (fm, body) = store.parseFrontmatter(content)
        #expect(fm["key1"] == "value1")
        #expect(fm["key2"] == "value2")
        #expect(body.trimmingCharacters(in: .whitespacesAndNewlines) == "Body text here.")
    }
}
