# Phase 7: 配置系统

## Requirements
- 多源配置加载 (5+1 层)
- JSON 配置解析和合并
- 配置变更检测

## Technical Notes
- 对应 Claude Code 5+1 层配置架构
- 优先级: Plugin < User < Project < Local < Flags < Policy
- 数组合并而非替换

## Files to Create
| 文件 | 说明 |
|---|---|
| Core/ConfigLoader.swift | 多源配置加载和合并 |
| Core/ConfigSchema.swift | Zod-like 运行时校验 |

## Acceptance Criteria
- [ ] ConfigLoader 从 json 文件加载配置
- [ ] 多源合并 (低优先级 -> 高优先级)
- [ ] 数组字段合并而非替换
- [ ] `swift build` + `swift test` 通过

**Output when complete:** `<promise>DONE</promise>`
