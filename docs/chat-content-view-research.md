# Chat Content View — 深度调研与重构方案

## 1. 现状分析

### 1.1 当前架构

项目存在两套并行的 Chat View 实现：

| 组件 | 实现方式 | 状态 |
|------|----------|------|
| `MessageListView` + `MessageBubbleView` | 纯 SwiftUI (VStack + ForEach) | 已废弃 — 注释说明 LazyVStack 在 macOS 26.0 导致死锁 |
| `AppKitChatView` + `ChatScrollView` + `ChatMessageCell` | AppKit (NSViewRepresentable + 自定义 NSView 栈) | 当前生产使用 |

### 1.2 当前 AppKit 实现的核心问题

1. **无 Cell 复用**: `ChatDocumentView` 维护 `[ChatMessageCell]` 数组，所有消息 cell 常驻内存。1000+ 条消息时内存压力显著。
2. **手动布局系统**: 使用 `isFlipped = true` + 手动 `layout()` 覆盖。每帧 streaming 触发 `layoutSubtreeIfNeeded()`，在快速 token 到达时容易产生 layout loop。
3. **Combine 驱动更新**: Coordinator 通过 `sink` 订阅 `$messages`，在 streaming 时 delta=0 的情况下做 in-place 文本更新，存在 block count diff 判断逻辑脆弱的问题。
4. **折叠能力有限**: 仅有 thinking block 的 toggle，不支持多层级折叠（如 tool-use → tool-result 组折叠、连续同类 tool 的批量折叠）。
5. **无自动折叠**: 历史消息中的 tool result 始终展开，占用大量垂直空间。
6. **动画缺失**: 折叠/展开没有过渡动画，消息增删也没有动画。

### 1.3 线程模型风险

- `Coordinator.startObserving()` 中 `messages.publisher.sink` 在 `@MainActor` 上下文中执行，但 streaming 期间消息更新频率极高（每 token 一次），容易与 AppKit 布局周期产生竞争。
- `DispatchQueue.main.async` 延迟布局是 workaround，但引入了不确定性。

---

## 2. 框架/方案对比

### 方案 A: NSTableView (View-Based) ⭐ 推荐

| 维度 | 评价 |
|------|------|
| Cell 复用 | ✅ `makeView(withIdentifier:owner:)` 原生支持，reuse queue 自动管理 |
| 自适配高度 | ✅ `NSView` + Auto Layout 或 `tableView(_:heightOfRow:)` 手动计算 |
| Streaming 更新 | ✅ 保持 streaming cell 引用，调用 `view(atColumn:row:makeIfNecessary:)` 直接更新 |
| 折叠/展开 | ✅ `NSAnimationContext` + `noteHeightOfRows(withIndexesChanged:)` |
| 多层级折叠 | ✅ Cell 内部管理折叠状态 + tableView reload |
| macOS 原生度 | ✅ 最高，所有 AppKit 应用标准组件 |
| 动画 | ✅ `insertRows`/`removeRows` 自带动画 |
| 复杂度 | 中等 |

**推荐理由**: 最适合 macOS 聊天应用的方案。Cell 复用、自适配行高、内建动画、成熟的 API。

### 方案 B: NSCollectionView (Compositional Layout)

| 维度 | 评价 |
|------|------|
| Cell 复用 | ✅ `makeItem(withIdentifier:for:)` |
| 灵活布局 | ✅ Compositional layout 支持多列、分组 |
| Streaming 更新 | ⚠️ 需要 `NSDiffableDataSource` snapshot 更新 |
| 折叠/展开 | ⚠️ Snapshot 操作可以实现但较复杂 |
| macOS 原生度 | ✅ 但 API 更偏向 iOS |

**评价**: 布局能力更强但 API 复杂。如果未来需要多列/画廊布局可考虑。对于线性聊天列表，NSTableView 更简洁。

### 方案 C: 自定义 Virtualized Scroll + CoreAnimation Layers

| 维度 | 评价 |
|------|------|
| 性能 | ✅✅ 极致，手动管理可见区域 |
| 复杂度 | ❌ 极高，需要自己实现复用池、布局引擎、事件处理 |
| 维护成本 | ❌ 高 |

**评价**: 仅在极端性能需求下考虑（如 Infinite Scroll + 100K 消息）。当前场景不必要。

### 方案 D: IGListKit / Texture (AsyncDisplayKit)

| 维度 | 评价 |
|------|------|
| macOS 支持 | ❌ 主要面向 iOS |
| 迁移成本 | ❌ 高 |

**评价**: 不推荐，macOS 支持不足。

### 方案 E: SwiftUI LazyVStack (等待 macOS 修复)

| 维度 | 评价 |
|------|------|
| 声明式 | ✅ |
| 折叠/展开 | ✅ matchedGeometryEffect / DisclosureGroup |
| Streaming | ⚠️ 当前有 main-thread deadlock bug |
| 成熟度 | ❌ macOS 26.0 已验证不可用 |

**评价**: 等 Apple 修好 bug 后是未来方向，当前不可用。

---

## 3. 推荐方案详细设计: NSTableView + Cell Reuse

### 3.1 架构总览

```
ChatContentView (SwiftUI NSViewRepresentable 壳)
└── ChatTableView (NSTableView)
    ├── Data Source: ChatTableDataSource (NSObject, NSTableViewDataSource)
    ├── Delegate: ChatTableController (NSObject, NSTableViewDelegate)
    ├── Row View: ChatMessageRowView (NSTableRowView 子类)
    │   └── ChatMessageContentView (NSView, 每个消息的内容)
    │       ├── UserBubbleView (用户消息气泡)
    │       ├── AssistantTextView (助手文本, 可选)
    │       ├── ThinkingBlockView (思考块, 可折叠)
    │       │   └── 展开时显示 thinking text
    │       ├── ToolGroupView (工具组, 可折叠)
    │       │   ├── ToolUseCardView (工具调用卡片)
    │       │   └── ToolResultCardView (工具结果卡片)
    │       └── SystemReminderView (系统提示)
    └── Fold Model: ChatFoldState (每线程的折叠状态)
```

### 3.2 Cell 复用策略

```
NSTableView
├── Row 0 (user message)     → reuse "UserMessageRow"
├── Row 1 (assistant text)   → reuse "AssistantMessageRow"
├── Row 2 (thinking block)   → reuse "ThinkingBlockRow" (collapsed)
├── Row 3 (tool use)         → reuse "ToolUseRow"
├── Row 4 (tool result)      → reuse "ToolResultRow"  ← 折叠时此 row 不渲染
└── Row 5 (system reminder)  → reuse "SystemReminderRow"
```

复用标识符:
- `"Chat.UserMessage"` — 用户消息气泡
- `"Chat.AssistantMessage"` — 助手消息（含文本+thinking折叠+tool组折叠）
- `"Chat.SystemMessage"` — 系统消息/提醒

### 3.3 Streaming 更新方案

```swift
// Streaming 期间：保持对当前可见 cell 的引用
func updateStreamingCell(_ message: AgentMessage) {
    let lastRow = tableView.numberOfRows - 1
    guard let cell = tableView.view(
        atColumn: 0, row: lastRow, makeIfNecessary: false
    ) as? ChatMessageRowView else { return }
    
    // 直接更新 cell 内容（不触发 reload）
    cell.updateContent(with: message)
    
    // 更新行高
    tableView.noteHeightOfRows(withIndexesChanged: [lastRow])
}
```

### 3.4 多层级折叠设计 (Codex-style)

```
📨 Assistant Message
├── 💭 Thinking...              [▶ 展开/折叠]
│   └── "Let me analyze this..."
├── 📝 Response text
├── 🔧 Tool: Read file.swift    [▶ 展开/折叠]
│   ├── Args: {"path": "..."}
│   └── Result: "content..."    [▶ 展开/折叠]
├── 🔧 Tool: Bash ls -la        [▶ 展开/折叠]
│   ├── Args: {"command": "ls"}
│   └── Result: "total 48..."   [▶ 展开/折叠]
└── 📝 More text...
```

折叠层级:
1. **Thinking block** — 单层折叠，toggle 切换 `isThinkingExpanded`
2. **Tool Group** — 将 tool_use + tool_result 视为一组，toggle 切换 `isToolGroupExpanded`
3. **Tool Result** — 在 tool group 内部，折叠长结果（>6 行时默认折叠）
4. **ConsecutiveToolGroup** — 连续多个 tool use 合并为一个可折叠组

### 3.5 自动折叠策略 (Auto-Collapse)

参考 CLI 的 `CollapseDetector` 逻辑:

1. **Tool results 超过 3 轮后自动折叠**: 当前 view 滚动到上方超出 N 个 turn 的 tool results 自动折叠
2. **同类工具合并**: 连续的 Read/Glob/Grep 结果合为一个折叠组
3. **Threshold-based**: 单条结果超过 500 字符自动折叠为摘要

### 3.6 折叠动画

```swift
NSAnimationContext.runAnimationGroup { ctx in
    ctx.duration = 0.2
    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    ctx.allowsImplicitAnimation = true
    
    tableView.beginUpdates()
    // 插入/移除 rows
    tableView.endUpdates()
}
```

---

## 4. 文件结构

```
Sources/SwiftAgentApp/Content/
├── ChatTableView.swift           # NSTableView 封装（替代 ChatScrollView）
├── ChatTableRowView.swift        # 行视图（替代 ChatMessageCell）
├── ChatBlockViews.swift          # 可复用 block 子视图
├── ChatFoldModel.swift           # 折叠状态模型 + 自动折叠策略
├── ChatTableController.swift     # Data Source + Delegate（替代 Coordinator）
├── ChatContentBridge.swift       # SwiftUI NSViewRepresentable 桥接（替代 AppKitChatView）
├── ChatAutoCollapsePolicy.swift  # 自动折叠策略
└── (保留) ComposerView.swift
```

## 5. 实现路线

### Phase 1: Core Table View (本次实现)
- [x] `ChatTableView` — NSTableView 子类，配置行高、选中、滚动
- [x] `ChatTableRowView` — 行容器视图，flipped coordinate
- [x] `ChatBlockViews` — 各种 block 类型视图
- [x] `ChatFoldModel` — 折叠状态管理
- [x] `ChatTableController` — Data Source + Delegate
- [x] `ChatContentBridge` — SwiftUI 桥接

### Phase 2: Streaming 优化
- [ ] Token-level in-place 更新（不触发 reloadData）
- [ ] 异步行高计算缓存
- [ ] Auto-scroll 抑制逻辑迁移

### Phase 3: 折叠与动画
- [ ] Thinking block 折叠/展开动画
- [ ] Tool group 折叠/展开动画
- [ ] Auto-collapse 策略集成
- [ ] 折叠状态持久化

### Phase 4: 高级特性
- [ ] 消息选中/Copy 支持
- [ ] 代码块 syntax highlighting
- [ ] Inline diff 显示
- [ ] 拖拽选择文本

---

## 5. 本次实现记录 (2026-06-21)

采用 **方案 A: NSTableView (View-Based)** 完整实现，新增 5 个文件，修改 1 个文件：

### 新增文件

| 文件 | 职责 | 行数 |
|------|------|------|
| `ChatFoldModel.swift` | 多层级折叠状态机 + 自动折叠策略 | ~160 |
| `ChatBlockViews.swift` | 可复用的 block 视图 (TextBlock / ThinkingBlock / ToolUseBlock / ToolResultBlock / SystemReminderBlock) | ~590 |
| `ChatTableRowView.swift` | NSTableRowView — 组装 block 视图，管理折叠交互 | ~265 |
| `ChatTableView.swift` | NSTableView 子类 — cell 复用、streaming 更新、scroll 管理 | ~280 |
| `AppKitChatBridge.swift` | SwiftUI bridge (NSViewRepresentable) — 连接 ThreadViewModel 到 ChatTableView | ~180 |

### 修改文件

| 文件 | 变更 |
|------|------|
| `ContentView.swift` | `AppKitChatView` → `AppKitChatBridge` |

### 架构亮点

1. **Cell 复用**: `makeView(withIdentifier:owner:)` 自动回收离屏 cell，1000+ 消息时只有可见 cell 在内存中
2. **Streaming 更新**: `ChatTableRowView.updateStreamingBlocks(_:)` 通过 `ChatBlockView` 协议的 `updateContent(with:)` 实现 in-place 文本更新，不重建视图
3. **多层级折叠**: `FoldTarget` 枚举支持 thinking / toolUse / toolResult / turn / message 五级折叠目标，通过 `FoldState` ObservableObject 管理
4. **自动折叠**: `AutoCollapseEngine` 根据消息距离末端的距离自动折叠旧的 tool 调用和结果
5. **行高缓存**: 基于 `messageID + blockCount + isStreaming` 的缓存 key，避免重复计算
6. **Scroll 管理**: 基于 `didLiveScrollNotification` 的 auto-scroll 抑制逻辑，用户上滚阅读历史时不会自动跳到底部

### 与旧实现的对比

| 维度 | 旧实现 (ChatScrollView) | 新实现 (ChatTableView) |
|------|------------------------|------------------------|
| Cell 复用 | ❌ 所有 cell 常驻内存 | ✅ NSTableView reuse pool |
| 更新机制 | 手动 subview 管理 + layout() | NSTableView 原生 reload/insert/noteHeight |
| 折叠能力 | 仅 thinking toggle | thinking / toolUse / toolResult / 多层 |
| 自动折叠 | ❌ | ✅ AutoCollapseEngine |
| 动画 | ❌ | ✅ insertRows/removeRows 自带动画 |
| 行高计算 | 手动 layoutSubtreeIfNeeded() | NSTableView heightOfRow + 缓存 |
| 代码量 | ~730 行 (3 文件) | ~1475 行 (5 文件) |
