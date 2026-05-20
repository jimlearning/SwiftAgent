# Phase 4: 工具系统

## Requirements
- 实现核心工具：Read, Write/Edit, Bash, Glob, Grep
- 每个工具实现 ToolProtocol
- 工具注册表 (ToolRegistry) 已存在
- Bash 工具需要基础安全校验

## Technical Notes
- 借鉴 Claude Code 工具系统的 `buildTool()` 构建器模式（已通过 ToolProtocol 实现）
- Bash 工具对应 Claude Code 的 `bashTool.ts` (12,400 行中最复杂的工具)
- 每个工具使用独立的文件，避免 god file

## Tools to Implement

| Tool | 文件 | 说明 |
|---|---|---|
| ReadTool | Tools/ReadTool.swift | 读取文件内容，支持 offset/limit |
| WriteTool | Tools/WriteTool.swift | 创建/覆写文件 |
| EditTool | Tools/EditTool.swift | 精确字符串替换 |
| BashTool | Tools/BashTool.swift | Shell 命令执行 + 基础安全 |
| GlobTool | Tools/GlobTool.swift | 文件模式匹配 |
| GrepTool | Tools/GrepTool.swift | 正则表达式内容搜索 |

## Acceptance Criteria
- [ ] 每个工具实现 ToolProtocol 完整接口
- [ ] ReadTool 支持 offset/limit 参数
- [ ] WriteTool 支持创建新文件和覆写
- [ ] EditTool 支持 old_string/new_string 精确替换
- [ ] BashTool 拒绝 `rm -rf /` 等危险命令
- [ ] GlobTool 返回匹配的文件列表
- [ ] GrepTool 支持正则表达式和 glob 过滤
- [ ] 所有工具注册到 ToolRegistry
- [ ] `swift build` + `swift test` 通过

**Output when complete:** `<promise>DONE</promise>`
