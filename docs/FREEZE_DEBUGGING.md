# SwiftAgentApp — UI 卡顿调试指南

诊断和防止 SwiftUI + AppKit macOS 应用中的主线程挂起。

## 快速诊断

当 UI 卡顿时：

```bash
# 捕获 1 秒进程采样 — 显示每个线程的调用栈。
sample SwiftAgentApp 1 -file /tmp/hang-sample.txt
open /tmp/hang-sample.txt
```

查看**主线程**（`Thread 0x...  DispatchQueue: com.apple.main-thread`）。其栈顶的函数就是阻塞 UI 的原因。

如果卡顿持续 2 秒以上，内置的 `HangDetector`（`Sources/SwiftAgentApp/Content/MessageListView.swift`）会自动捕获采样到 `~/Library/Logs/SwiftAgent/hang-*.txt`。

## 已知卡顿模式

### 1. Streaming 响应卡顿

**触发条件:** 任何较长的 LLM 响应（~100 tokens/sec streaming）。

**根因:** `persistMessageWithBlocks` 在 `@MainActor` 上每 5 个 streaming 事件调用一次 `TranscriptStore.append()`。内部实现中，`append()` 调用 `writeQueue.sync { FileHandle.write(...) }`——在主线程上阻塞文件 I/O。同时 100 tokens/sec 在其后堆积，使 MainActor 执行器饱和。再加上 `AgentSessionManager.run()` 将整个 agent loop 包装在 `Task { @MainActor }` 中，以及 `AppKitChatBridge` 缺少 Combine throttle。

**涉及文件:**
- `ViewModels/ThreadViewModel.swift` — `persistMessageWithBlocks`, `handleStreamEvent`
- `Agent/AgentSessionManager.swift` — `run()` 使用 `Task { @MainActor }`
- `Content/AppKitChatBridge.swift` — 缺少 `.throttle(16ms)` 用于消息观察

**修复:** 持久化卸载到 `Task.detached`。Agent loop 卸载到 `Task.detached`，配合显式的 `MainActor.run` 跳转。消息观察 throttled 到 16ms (~60fps)。

### 2. 焦点模式切换 + 文件选择卡顿

**触发条件:** 多次切换焦点模式，然后选择一个文件。

**根因:** `ChatScrollContainer.setFrameSize` 在 **AppKit 布局流程内同步**调用 `updateLayoutWidth` → `noteHeightOfRows`。`noteHeightOfRows` 触发 NSTableView 重新测量行高，这可能通过 AppKit 的内部布局触发另一次 `setFrameSize`，形成**无限重入布局循环**。

**涉及文件:**
- `Content/ChatScrollContainer.swift` — `setFrameSize` 同步调用 `updateLayoutWidth`
- `Content/ChatTableView.swift` — `updateLayoutWidth` 调用 `noteHeightOfRows`

**修复:** `setFrameSize` 将 `updateLayoutWidth` 延迟到 `DispatchQueue.main.async`——布局流程完成后再重新测量行高。`updateLayoutWidth` 增加重入防护（`isUpdatingLayout` 标志）。

### 3. 文件面板滚动卡顿

**触发条件:** 打开文件面板，展开一个包含 200+ 条目的目录（如 `Sources/SwiftAgentApp`），快速滚动。

**根因:** 文件树在 `FileTreeRow` 中使用了**递归 `VStack`+`ForEach`**。每个展开的目录会急切地为所有子项实例化 SwiftUI 视图——200+ 个 `FileTreeRow` 实例 × ~15 个内部视图节点每个 = 3000+ 个视图层级节点。在滚动期间，SwiftUI 在这棵树上的布局差异计算阻塞了主线程。`LazyVStack` 仅懒加载顶层的行，而非嵌套的子项。

**涉及文件:**
- `RightTabs/panels/FilesPanelView.swift` — 递归 `FileTreeRow` 使用急切子项渲染

**修复:** 将 `ScrollView` + `LazyVStack` + 递归 `VStack` 树替换为 `List` + `DisclosureGroup`。`List` 内置 cell 复用（类似 NSTableView）；`DisclosureGroup` 仅在展开时创建子视图。无论总条目数有多少，只有约 30 个可见行被实例化。

## 反模式（绝对不要这样做）

| 反模式 | 原因 | 示例 |
|-------------|-----|---------|
| **在 AppKit 布局回调中调用触发布局的方法** | 重入布局循环 | `setFrameSize` → `noteHeightOfRows` → `setFrameSize` → ... |
| **在主线程上阻塞 I/O** | 卡顿 UI 直到 I/O 完成；随并发而放大 | `FileManager.contentsOfDirectory` 在 `@MainActor` 上；`writeQueue.sync` 在 `@MainActor` 上 |
| **急切创建大规模 SwiftUI 视图树** | SwiftUI 布局差异计算与视图数量成 O(n) | 200+ 个递归 `FileTreeRow` 实例 |
| **不必要地用 `Task { @MainActor }` 包装异步工作** | 使 MainActor 串行执行器饱和 | Agent loop 在 `@MainActor` 上，而实际上可以用 `Task.detached` |
| **对高频发布者跳过 Combine throttle** | 每次变更都触发完整 UI 重新计算 | `$messages.sink { ... }` 没有 `.throttle(16ms)` |
| **对大型列表使用递归 View** | 无 cell 复用，无虚拟化 | `ForEach(children) { FileTreeRow(...) }` 处理 200 个条目 |

## 检查-修复-验证工作流

当遇到卡顿时：

1. **检查** `~/Library/Logs/SwiftAgent/` 中自动捕获的 `hang-*.txt` 采样文件
2. **阅读** 主线程的栈——哪个函数在栈顶？
3. **匹配** 上述已知模式，或识别新模式
4. **修复** 根因而非症状（永远不要在没有理解原因的情况下仅添加 `DispatchQueue.main.async` 作为创可贴）
5. **验证** 再现触发场景——UI 必须保持响应
6. **更新** 本文档，如果你发现了新的卡顿模式

## HangDetector

`Sources/SwiftAgentApp/Content/MessageListView.swift` 包含 `HangDetector`——一个后台线程，每 50ms 通过 `DispatchQueue.main.async` + semaphore 对主线程进行 ping：

- **100ms+ 往返时间:** 软性微卡顿（默认不记录）
- **500ms+ 往返时间:** 记录为警告——队列饱和
- **2000ms+ 超时:** 记录为严重，自动捕获 1 秒 `sample` 到 `~/Library/Logs/SwiftAgent/`

从 `MessageListView.onAppear` 启动（幂等——全局启动一次）。

## 布局重入：无声杀手

最危险的一类卡顿是**重入布局**——当一个布局操作在同一 runloop 迭代中触发另一个布局操作时。栈轨迹如下：

```
setFrameSize → updateLayoutWidth → noteHeightOfRows → layout → setFrameSize → ...
```

**规则:** 永远不要在 `setFrameSize`、`layout()`、`updateConstraints()` 或 `viewDidLayout()` 内部调用任何会触发 `layoutSubtreeIfNeeded()`、`noteHeightOfRows()` 或 `layout()` 的方法。通过 `DispatchQueue.main.async` 延迟到下一个 runloop 迭代。
