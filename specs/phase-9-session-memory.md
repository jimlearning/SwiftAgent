# Phase 9: 会话持久化与记忆

## Requirements
- Session CRUD 操作 (创建/读取/更新/删除)
- 对话历史持久化到磁盘 (JSON)
- 会话列表和恢复

## Files to Create
| 文件 | 说明 |
|---|---|
| Core/SessionStore.swift | 会话持久化和查询 |
| Core/MemoryStore.swift | 项目/用户记忆管理 |

## Acceptance Criteria
- [ ] SessionStore 保存/加载会话到 JSON 文件
- [ ] 列出最近会话
- [ ] MemoryStore 读写 CLAUDE.md 格式
- [ ] `swift build` + `swift test` 通过

**Output when complete:** `<promise>DONE</promise>`
