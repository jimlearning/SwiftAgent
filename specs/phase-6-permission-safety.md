# Phase 6: 权限与安全引擎

## Requirements
- 实现完整的权限决策管道
- 支持多种权限模式 (default, plan, acceptEdits, bypass)
- 权限规则匹配引擎
- 自动审批的安全工具白名单

## Technical Notes
- 对应 Claude Code 权限系统 7 步决策管道
- 8 种规则来源，flatMap-first-match 语义
- 自动模式 3 层快通道

## Files to Create
| 文件 | 说明 |
|---|---|
| Core/PermissionEngine.swift | 权限决策管道 |
| Core/PermissionStore.swift | 权限规则存储 |
| Core/SafetyChecker.swift | 安全检查和危险模式检测 |

## Acceptance Criteria
- [ ] PermissionEngine 实现完整的 7 步决策管道
- [ ] 支持 deny > ask > allow 优先级聚合
- [ ] SafetyChecker 检测危险的 shell 命令模式
- [ ] 支持自动模式 (bypassPermissions)
- [ ] `swift build` + `swift test` 通过

**Output when complete:** `<promise>DONE</promise>`
