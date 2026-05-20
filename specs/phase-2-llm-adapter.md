# Phase 2: LLM Adapter & Streaming

## Requirements
- 实现 Anthropic Messages API 客户端
- 支持流式响应（SSE 解析）
- 实现指数退避重试策略
- Token 计数估算

## Technical Notes
- 对应 Claude Code `services/api/claude.ts` (3,419 行)
- 核心流模式：`AsyncSequence<StreamEvent>` 对应 TypeScript 的 AsyncGenerator
- SSE 解析器需要处理 `data:`, `event:`, `id:` 等字段
- 重试策略：500ms 基础退避，32s 上限，25% jitter，429/529 特殊处理
- 模型注册表包含 Haiku/Sonnet/Opus 的 capability 和 context window 信息

## Files to Create
| 文件 | 说明 |
|---|---|
| `LLMClient.swift` | HTTP 客户端，消息发送，SSE 流接收 |
| `LLMStreamParser.swift` | AsyncSequence 实现，逐块解析 SSE |
| `RetryPolicy.swift` | withRetry 实现，指数退避 |
| `ModelRegistry.swift` | 模型列表，capability 查询 |
| `TokenCounter.swift` | Token 估算（字符/单词基准） |

## Acceptance Criteria
- [ ] `LLMClient.send()` 返回 `AsyncStream<StreamEvent>`
- [ ] SSE 解析器正确处理所有事件类型（message_start, content_block_start, content_block_delta, content_block_stop, message_delta, message_stop, ping, error）
- [ ] `RetryPolicy` 支持最多 5 次重试
- [ ] `ModelRegistry` 包含至少 claude-sonnet-4-6, claude-opus-4-7, claude-haiku-4-5
- [ ] `TokenCounter` 能估算给定文本的 token 数（误差 < 50%）
- [ ] `swift test` 全部通过（使用 mock HTTP 服务）

**Output when complete:** `<promise>DONE</promise>`
