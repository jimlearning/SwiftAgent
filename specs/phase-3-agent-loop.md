# Phase 3: Agent Loop (核心对话循环)

## Requirements
- 实现完整的 agent 对话循环，这是整个项目的"心跳"
- 对应 Claude Code `query.ts` (1,729 行) + `QueryEngine.ts` (1,295 行)
- 核心模式：发送 prompt → 流式接收 → 解析 tool_use → 执行工具 → 循环

## Technical Notes
- 使用 AsyncStream 对应 TypeScript 的 AsyncGenerator 模式
- 错误恢复：模型回退、工具调用排空、上下文压缩触发
- System prompt 组装借鉴 `SystemPromptBuilder`，支持静态/动态边界

## Core Loop Pseudocode
```
AgentEngine.run(userInput):
    messages = [systemPrompt] + history + [userInput]
    while true:
        stream = llmClient.send(messages)
        textOutput = ""
        toolCalls = []
        for event in stream:
            case .textDelta(let text): textOutput.append(text)
            case .toolUse(let tool): toolCalls.append(tool)
            case .contentBlockStop: if tool block, prepare execute
        if toolCalls.isEmpty: break
        for tool in toolCalls:
            permission → execute → result
        messages.append(assistant + toolResults)
    return textOutput
```

## Files to Create
| 文件 | 说明 |
|---|---|
| `AgentEngine.swift` | 主循环引擎 |
| `SystemPromptBuilder.swift` | 系统 prompt 组装 |
| `ContextManager.swift` | Token 预算跟踪 |
| `ToolExecutor.swift` | 工具调度执行 |
| `StreamRenderer.swift` | 流输出格式化 |

## Acceptance Criteria
- [ ] `AgentEngine.run()` 接收用户输入，返回最终 AI 输出
- [ ] 支持多轮 tool use 循环（AI 调用工具 → 获取结果 → 继续思考）
- [ ] `SystemPromptBuilder` 支持静态/动态 prompt 组装
- [ ] `ContextManager` 跟踪 token 使用量，接近上限时触发警告
- [ ] `ToolExecutor` 支持并发和串行两种工具执行模式
- [ ] 用 mock LLM 做单元测试（不依赖真实 API）
- [ ] `swift build` + `swift test` 通过

**Output when complete:** `<promise>DONE</promise>`
