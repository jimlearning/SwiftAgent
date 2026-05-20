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
        #expect(err as? WorktreeError != nil)
    }
}
