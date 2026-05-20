# Phase 11: Sub-Agent & Task System

## Requirements
- Sub-agent creation and context isolation
- Background task status tracking (TaskManager)
- Git worktree isolation for sub-agents (WorktreeManager)

## Files to Create
| File | Description |
|---|---|
| Core/Agent/SubAgentManager.swift | Sub-agent spawn, context isolation, result collection |
| Core/Agent/TaskManager.swift | Background task creation, status tracking, cancellation |
| Core/Agent/WorktreeManager.swift | Git worktree creation and cleanup for isolated sub-agent work |

## Acceptance Criteria
- [ ] SubAgentManager creates and runs sub-agents with isolated context
- [ ] TaskManager tracks background task state (pending/running/done/failed)
- [ ] WorktreeManager creates and cleans up git worktrees
- [ ] `swift build` + `swift test` pass

**Output when complete:** `<promise>DONE</promise>`
