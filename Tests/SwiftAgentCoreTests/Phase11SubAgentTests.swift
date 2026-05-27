import Testing
import Foundation
@testable import SwiftAgentCore

// MARK: - TaskManager Tests

struct TaskManagerTests {
    @Test
    func createsTask() async {
        let manager = TaskManager()
        let task = await manager.create(name: "test-task", description: "A test task")
        #expect(task.name == "test-task")
        #expect(task.status == .pending)
        #expect(task.type == .localWorkflow)
    }

    @Test
    func createsLocalAgentTaskWithPrompt() async {
        let manager = TaskManager()
        let task = await manager.create(
            name: "Explore",
            description: "Search references",
            type: .localAgent,
            prompt: "Find highlighting implementation references."
        )

        #expect(task.type == .localAgent)
        #expect(task.prompt == "Find highlighting implementation references.")
    }

    @Test
    func marksTaskRunning() async {
        let manager = TaskManager()
        let task = await manager.create(name: "t1")
        await manager.markRunning(task.id)

        let updated = await manager.get(task.id)
        #expect(updated?.status == .running)
    }

    @Test
    func marksTaskDone() async {
        let manager = TaskManager()
        let task = await manager.create(name: "t1")
        await manager.markCompleted(task.id, result: "success")

        let updated = await manager.get(task.id)
        #expect(updated?.status == .completed)
        #expect(updated?.result == "success")
        #expect(updated?.finishedAt != nil)
    }

    @Test
    func marksTaskFailed() async {
        let manager = TaskManager()
        let task = await manager.create(name: "t1")
        await manager.markFailed(task.id, error: "boom")

        let updated = await manager.get(task.id)
        #expect(updated?.status == .failed)
        #expect(updated?.result == "boom")
    }

    @Test
    func killsTask() async {
        let manager = TaskManager()
        let task = await manager.create(name: "t1")
        await manager.kill(task.id)

        let updated = await manager.get(task.id)
        #expect(updated?.status == .killed)
        #expect(await manager.isKilled(task.id))
    }

    @Test
    func killedTaskCannotBeOverwrittenByLateCompletion() async {
        let manager = TaskManager()
        let task = await manager.create(name: "t1")
        await manager.markRunning(task.id)
        await manager.kill(task.id)
        await manager.markCompleted(task.id, result: "late success")
        await manager.markFailed(task.id, error: "late failure")

        let updated = await manager.get(task.id)
        #expect(updated?.status == .killed)
        #expect(updated?.result == nil)
    }

    @Test
    func listsAllTasks() async {
        let manager = TaskManager()
        _ = await manager.create(name: "a")
        _ = await manager.create(name: "b")
        let all = await manager.listAll()
        #expect(all.count == 2)
    }

    @Test
    func listsActiveTasks() async {
        let manager = TaskManager()
        let t1 = await manager.create(name: "a")
        let t2 = await manager.create(name: "b")
        await manager.markCompleted(t1.id, result: "ok")

        let active = await manager.listActive()
        #expect(active.count == 1)
        #expect(active.first?.id == t2.id)
    }

    @Test
    func storesStructuredProgressAndCapsRecentEvents() async {
        let manager = TaskManager()
        let task = await manager.create(name: "Explore", description: "Inspect references")
        await manager.markRunning(task.id)

        for index in 0..<60 {
            await manager.appendProgress(
                task.id,
                phase: .usingTool,
                message: "Explore started Read \(index)",
                toolName: "Read"
            )
        }

        let snapshot = await manager.progressSnapshot(task.id)
        #expect(snapshot?.summary.taskName == "Explore")
        #expect(snapshot?.summary.phase == .usingTool)
        #expect(snapshot?.summary.currentTool == "Read")
        #expect(snapshot?.recentEvents.count == AgentTask.progressEventLimit)
        #expect(snapshot?.recentEvents.first?.message == "Explore started Read 10")
    }

    @Test
    func toolInputSummaryIncludesUsefulSearchParameters() {
        let summary = ToolInputSummaryFormatter.summarize(
            toolName: "Grep",
            input: [
                "pattern": .string("TaskOutputProgressData"),
                "path": .string("Sources"),
                "glob": .string("*.swift"),
            ],
            registry: nil
        )

        #expect(summary == "pattern=TaskOutputProgressData path=Sources glob=*.swift")
    }

    @Test
    func toolInputSummaryPreservesLongPaths() {
        let path = "/Users/jim/SwiftAgent/Package.swift"
        let summary = ToolInputSummaryFormatter.summarize(
            toolName: "Read",
            input: ["file_path": .string(path)],
            registry: nil
        )

        #expect(summary == "file_path=\(path)")
    }

    @Test
    func toolInputSummaryRedactsSensitiveKeys() {
        let summary = ToolInputSummaryFormatter.summarize(
            toolName: "WebFetch",
            input: [
                "url": .string("https://example.com"),
                "authorization": .string("Bearer abc"),
            ],
            registry: nil
        )

        #expect(summary?.contains("authorization=<redacted>") == true)
        #expect(summary?.contains("Bearer abc") == false)
    }

    @Test
    func terminalStatesWriteFinalProgressEvents() async {
        let manager = TaskManager()
        let completed = await manager.create(name: "Explore")
        await manager.markCompleted(completed.id, result: "done")
        #expect(await manager.progressSnapshot(completed.id)?.summary.phase == .completed)

        let failed = await manager.create(name: "Codex")
        await manager.markFailed(failed.id, error: "boom")
        #expect(await manager.progressSnapshot(failed.id)?.summary.phase == .failed)

        let killed = await manager.create(name: "SwiftAgent")
        await manager.kill(killed.id)
        #expect(await manager.progressSnapshot(killed.id)?.summary.phase == .killed)
    }

    @Test
    func prunesOldTasks() async {
        let manager = TaskManager()
        let t1 = await manager.create(name: "old")
        await manager.markCompleted(t1.id, result: "ok")

        // Wait 1ms then prune
        let future = Date().addingTimeInterval(0.1)
        await manager.prune(before: future)
        // Task finished before the prune cutoff, so it should be removed
        let all = await manager.listAll()
        #expect(all.isEmpty)
    }
}

// MARK: - AgentTask Tests

struct AgentTaskTests {
    @Test
    func taskHasDefaultValues() {
        let task = AgentTask(name: "test")
        #expect(task.status == .pending)
        #expect(task.result == nil)
        #expect(task.finishedAt == nil)
    }

    @Test
    func taskMutationMethods() {
        var task = AgentTask(name: "test")
        task.markRunning()
        #expect(task.status == .running)

        task.markCompleted(result: "ok")
        #expect(task.status == .completed)
        #expect(task.result == "ok")
        #expect(task.finishedAt != nil)
    }

    @Test
    func taskKill() {
        var task = AgentTask(name: "test")
        task.kill()
        #expect(task.status == .killed)
    }
}

// MARK: - TaskOutputTool Tests

struct TaskOutputToolTests {
    @Test
    func taskOutputReportsLocalAgentTypeAndEscapesJSON() async throws {
        let manager = TaskManager()
        let task = await manager.create(
            name: "Explore",
            description: #"Search "references""#,
            type: .localAgent,
            prompt: "Find\nreferences"
        )
        await manager.appendOutput(task.id, "Started\n")
        await manager.markCompleted(task.id, result: #"Done with "quotes" and \slashes"#)

        let tool = TaskOutputTool(taskManager: manager)
        let result = try await tool.call(
            input: ["taskId": .string(task.id), "block": .bool(false)],
            context: ToolUseContext(workingDirectory: "/tmp", sessionID: "test"),
            canUseTool: nil,
            parentMessage: nil,
            onProgress: nil
        )

        let data = try #require(result.content.data(using: .utf8))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let taskJSON = try #require(json["task"] as? [String: Any])

        #expect(json["retrieval_status"] as? String == "success")
        #expect(taskJSON["task_type"] as? String == "local_agent")
        #expect(taskJSON["description"] as? String == #"Search "references""#)
        #expect(taskJSON["prompt"] as? String == "Find\nreferences")
        #expect(taskJSON["result"] as? String == #"Done with "quotes" and \slashes"#)
        #expect(json["progress_summary"] is [String: Any])
        #expect(json["recent_events"] is [[String: Any]])
    }

    @Test
    func taskOutputEmitsProgressWhileBlocking() async throws {
        let manager = TaskManager()
        let task = await manager.create(name: "Explore", description: "Search refs", type: .localAgent)
        await manager.markRunning(task.id)
        await manager.appendProgress(task.id, phase: .thinking, message: "Explore is thinking")

        let tool = TaskOutputTool(taskManager: manager)
        let progress = LockedProgressCollector()

        async let result = tool.call(
            input: ["taskId": .string(task.id), "timeout": .number(2_000)],
            context: ToolUseContext(workingDirectory: "/tmp", sessionID: "test", toolUseID: "task-output-1"),
            canUseTool: nil,
            parentMessage: nil,
            onProgress: { progress.append($0) }
        )

        try? await Task.sleep(nanoseconds: 700_000_000)
        await manager.markCompleted(task.id, result: "done")
        _ = try await result

        let events = progress.values()
        #expect(events.contains { $0.data is TaskOutputProgressData })
    }

    @Test
    func subAgentBackgroundProgressMappingIsStructured() {
        let started = SubAgentManager.backgroundProgress(
            .toolStarted(toolUseID: "1", toolName: "Read", inputSummary: "file_path=Sources/Foo.swift"),
            agentName: "Explore",
            taskDescription: "Inspect SwiftAgent renderer"
        )
        #expect(started.phase == .usingTool)
        #expect(started.toolName == "Read")
        #expect(started.message == "Explore [Inspect SwiftAgent renderer] reading: file_path=Sources/Foo.swift")

        let writing = SubAgentManager.backgroundProgress(.assistantTextStreaming, agentName: "Explore")
        #expect(writing.phase == .writingResults)

        let turn = SubAgentManager.backgroundProgress(.turnComplete(turnNumber: 2, toolCallCount: 3), agentName: "Explore")
        #expect(turn.phase == .turnComplete)
        #expect(turn.turnNumber == 2)
        #expect(turn.toolCallCount == 3)
    }

    @Test
    func subAgentBackgroundProgressPreservesFullToolParameters() {
        let path = "/Users/jim/SwiftAgent/Package.swift"
        let progress = SubAgentManager.backgroundProgress(
            .toolStarted(toolUseID: "1", toolName: "Read", inputSummary: "file_path=\(path)"),
            agentName: "Explore",
            taskDescription: "Inspect SwiftAgent renderer"
        )

        #expect(progress.message == "Explore [Inspect SwiftAgent renderer] reading: file_path=\(path)")
        #expect(progress.message.contains("...") == false)
    }
}

private final class LockedProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [ToolProgress] = []

    func append(_ progress: ToolProgress) {
        lock.withLock {
            events.append(progress)
        }
    }

    func values() -> [ToolProgress] {
        lock.withLock { events }
    }
}

// MARK: - AgentTool Tests

struct AgentToolTests {
    @Test
    func agentToolWithoutManagerFailsInsteadOfFakeDispatching() async throws {
        let tool = AgentTool()
        let result = try await tool.call(
            input: [
                "description": .string("Explore references"),
                "prompt": .string("Find highlighting implementation references."),
                "subagentType": .string("Explore"),
            ],
            context: ToolUseContext(workingDirectory: "/tmp", sessionID: "test"),
            canUseTool: nil,
            parentMessage: nil,
            onProgress: nil
        )

        #expect(result.isError)
        #expect(result.content.contains("sub-agent execution is not configured"))
        #expect(!result.content.contains("Agent Dispatch"))
        #expect(!result.content.contains("The agent should now execute"))
    }
}

// MARK: - WorktreeManager Tests

struct WorktreeManagerTests {
    @Test
    func worktreeInfoInitialization() {
        let info = WorktreeInfo(path: "/tmp/test", branch: "main")
        #expect(info.path == "/tmp/test")
        #expect(info.branch == "main")
    }

    @Test
    func worktreeErrorCases() {
        let err = WorktreeError.gitFailed(128)
        if case .gitFailed(let code) = err {
            #expect(code == 128)
        } else {
            Issue.record("Expected gitFailed error")
        }
    }
}
