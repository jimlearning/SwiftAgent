# SwiftAgent for macOS — 产品文档

> **目标读者**：要让 AI（或其他开发者）可以根据这份文档，**无偏差**地实现一个 macOS 桌面 App，
> 界面与交互功能跟 Codex App 26.609.41114 高度相仿，但模型层使用 **DeepSeek**，
> 工程层基于现有 **SwiftAgent** Swift 包（Core / CLI 复用 + 新增 SwiftAgentApp SwiftUI 模块）。
>
> **文档原则**：
> 1. **每条规范 = `目的 → 实现细节 → 反例`**——AI 看完知道"为什么做 + 怎么做 + 不要做什么"
> 2. **关键参数给具体值**——颜色 hex、间距 pt、动画时长 ms、快捷键、API endpoint
> 3. **截图佐证**——所有视觉规范都对应 §A 截图
> 4. **不写"通用最佳实践"**——只写"SwiftAgent 必须这么做"
>
> **关键差异（与 Codex App）**：
> - ❌ Codex Cloud 任务页（Cloud-only） → ✅ DeepSeek API 直连
> - ❌ Codex Skills 官方库 → ✅ SwiftAgentCore 已有 Skills 引擎（复用）
> - ❌ Codex MCP 90+ 插件市场 → ✅ SwiftAgentCore 已有 MCP 引擎（复用 + 用户自配）
> - ❌ Codex Pets / 桌面宠物 → 暂不实现（差异化减少）
> - ❌ Codex for OSS / ChatGPT 账号 → ✅ DeepSeek API Key（BYOK）

---

## 0. 文档导读

> **v1.2 修订（2026-06-15 23:38）**：基于用户反馈，把 §2.4 / §3.3 / §6.3 / §13.2 / §17 的右侧栏定义**从"5 entry 互斥单选 list"回退到"多 Tab 并存工作区"**。v1.1 的修正以截图 26.609 为依据，但用户已确认 v1.0 的多 Tab 模型是想要的产品形态。后续所有引用 §2.4 / §3.3 的章节同步更新。

| 章节 | 内容 | 何时读 |
|------|------|--------|
| §1 | 愿景、定位、用户故事 | 产品决策时 |
| §2 | 信息架构 + 顶层导航 | 搭骨架时 |
| §3 | 窗口与布局 | 搭骨架时 |
| §4 | 视觉系统（design tokens）| 写组件时 |
| §5 | 核心交互模式 | 写交互时 |
| §6 | 键盘快捷键全集 | 写快捷键时 |
| §7 | 状态机 | 写 thread/agent 状态时 |
| §8 | 动效规范 | 写动效时 |
| §9 | 错误与边界态 | 写错误处理时 |
| §10 | 8 个核心功能模块 | 写模块时 |
| §11 | DeepSeek 模型集成 | 接入 LLM 时 |
| §12 | 状态持久化 | 写存储时 |
| §13 | SwiftAgentCore 复用接口 | 接入现有 CLI/Core 时 |
| §14 | 沙箱与权限 | 写安全层时 |
| §15 | 可访问性 | 写 a11y 时 |
| §16 | 实现顺序（推荐分 5 阶段）| 排期时 |
| §17 | 反例清单 | Code Review 时 |
| §A | 截图索引 | 任何时候 |

---

## 1. 愿景、定位、用户故事

### 1.1 一句话定位

> **SwiftAgent for macOS** 是一款"为多 agent 协作而生的 macOS 原生 SwiftUI 应用"——把 SwiftAgent Core 的 Skills/MCP/工具引擎，包装成跟 Codex App 26.609 视觉一致的桌面指挥中心。

### 1.2 区别于同类产品

| 维度 | ChatGPT macOS | Cursor | Claude Code | **SwiftAgent for macOS** |
|------|---------------|--------|-------------|--------------------------|
| 模型 | GPT-5.x | 多 | Claude | **DeepSeek V3 / R1**（BYOK）|
| 多 Agent | 单对话 | Tab | 单线程 | **多 Project → 多 Thread** |
| Skills | ❌ | ❌ | ✅ | ✅（**复用 SwiftAgentCore Skills 引擎**）|
| MCP | ❌ | 部分 | ✅ | ✅（**复用 SwiftAgentCore MCP 引擎**）|
| Worktree 隔离 | ❌ | ❌ | 手动 | ✅（自动 + 复用 Core 的 git 工具）|
| Appshots（屏幕感知）| ❌ | ❌ | ❌ | ✅（macOS 无障碍 API）|
| Computer Use | ❌ | ❌ | ❌ | ❌ v1.0 不做（v1.1 评估）|
| 本地优先 | ❌ | ❌ | ✅ | ✅（**DeepSeek API Key 存 Keychain**）|

### 1.3 三条不可违反的 UI 原则

1. **始终显示"agent 在做什么"**——状态行比聊天内容更重要（"Thought for 3s"、"Using skills X"）
2. **把审批动作做成"轻点"而不是"重审"**——权限弹窗只问"是否允许 X"——绝不暴露工程概念
3. **每个 Thread 独立"上下文 + 沙箱 + 模式"**——禁止跨 Thread 共享状态（除非显式 /fork）

### 1.4 用户故事（4 个核心场景）

| 场景 | 用户故事 |
|------|----------|
| **S1 — 日常编码** | 作为 Swift 开发者，我想在 IDE 外圈选代码片段后让 SwiftAgent 帮我"加单元测试" |
| **S2 — 多任务并行** | 作为 Team Lead，我想同时跑"PR 评审"和"重构"两个 agent，互不干扰 |
| **S3 — 跨会话复用** | 作为独立开发者，我让 SwiftAgent 跑一个 3 天的迁移任务，过程中我随时能介入和暂停 |
| **S4 — 屏幕取上下文** | 作为 UI 调试者，我用快捷键把当前 Mac 窗口截图喂给 SwiftAgent，让它直接修 UI |

### 1.5 范围边界（v1.0 vs 后续）

| 功能 | v1.0 | 后续 |
|------|------|------|
| 三栏 + 右侧功能入口栏 | ✅ | — |
| DeepSeek V3 + R1 模型切换 | ✅ | — |
| Skills / MCP / Worktree / Appshots | ✅ | — |
| Composer `+` 菜单 / 权限 4 档 | ✅ | — |
| 多 Project → 多 Thread | ✅ | — |
| Computer Use | ❌ | v1.1 评估 |
| Pets 浮窗 | ❌ | ❌ |
| 6 款岗位插件 | ❌ | v1.1 评估 |
| Sites 部署 | ❌ | ❌（本地优先不需要托管）|
| Face ID / 密码锁 | ❌ | v1.1（macOS 本地解锁） |
| Mobile 端 | ❌ | v1.2（独立 App） |
| iOS Live Activities | ❌ | ❌ |

---

## 2. 信息架构 + 顶层导航

### 2.1 顶层布局 ASCII 图

```
┌─ macOS 标题栏（traffic light + 前后导航 + sidebar 收起）─┐
│ 左 Sidebar              │ 中部主区（对话流）    │ 右侧多 Tab 工作区         │
│ 240-280pt               │ 弹性                  │ 380-440pt                │
│ 中等深灰                │ 更深灰                │ 最深纯黑                  │
├─────────────────────────┼───────────────────────┼──────────────────────────┤
│ [ New chat ]            │ ┌─────────────────┐   │ [Review×][Terminal×][+]  │
│ [ Search ]              │ │ thread 标题       │   ├──────────────────────────┤
│ [ Plugins ]             │ │ breadcrumb         │   │                          │
│ [ Automations ]         │ │         [Z⌄][⚙️✓] │   │  当前激活 Tab 的内容     │
│                         │ └─────────────────┘   │  (Review / Terminal /     │
│                         │ └─────────────────┘   │   Browser / Files /       │
│                         │                        │   Side chat)              │
│ Projects                │ 思考过程...           │                          │
│  📁 forge               │ 验证已通过...         │                          │
│  📁 SwiftAgent          │ 文档列表（CLAUDE.md） │                          │
│  📁 swift-film-prototype│ Edited 9 files +85 -3 │                          │
│  📁 project-scaffold    │  ┌─输入框──────────┐  │                          │
│  📁 Waterdrop           │  │ + ⚙️Custom⌄ ↑   │  │                          │
│  📁 Marea               │  │      5.5 High⌄ ↑ │  │                          │
│  ...                    │  └──────────────────┘  │                          │
│                         │                        │                          │
│ Chats（全局）            │                        │                          │
│  💬 中国国内，我的 macOS│                        │                          │
│                         │                        │                          │
│ [Settings] ⚙            │                        │                          │
└─────────────────────────┴───────────────────────┴──────────────────────────┘
```
┌─ macOS 标题栏（traffic light + 前后导航 + sidebar 收起）─┐
│ 左 Sidebar              │ 中部主区（对话流）    │ 右侧功能入口栏        │
│ 240-280pt               │ 弹性                  │ 380-440pt           │
│ 中等深灰                │ 更深灰                │ 最深纯黑            │
├─────────────────────────┼───────────────────────┼──────────────────────┤
│ [ New chat ]            │ ┌─────────────────┐   │ ▣ Review      ⌃⇧G  │
│ [ Search ]              │ │ thread 标题       │   │ >_ Terminal          │
│ [ Plugins ]             │ │ breadcrumb         │   │ 🌐 Browser     ⌘T   │
│ [ Automations ]         │ │         [Z⌄][⚙️✓] │   │ 📁 Files       ⌘P   │
│                         │ └─────────────────┘   │ ⊕ Side chat   ⌥⌘S  │
│                         │ └─────────────────┘   │                      │
│ Projects                │ 思考过程...           │  5 个功能入口         │
│  📁 forge               │ 验证已通过...         │  Review  ⌃⇧G         │
│  📁 SwiftAgent          │ 文档列表（CLAUDE.md） │  Terminal  ^`         │
│  📁 swift-film-prototype│ Edited 9 files +85 -3 │  Browser  ⌘T         │
│  📁 project-scaffold    │  ┌─输入框──────────┐  │  Files  ⌘P          │
│  📁 Waterdrop           │  │ + ⚙️Custom⌄ ↑   │  │  Side chat  ⌥⌘S    │
│  📁 Marea               │  │      5.5 High⌄ ↑ │  │                      │
│  ...                    │  └──────────────────┘  │                      │
│                         │                        │                      │
│ Chats（全局）            │                        │                      │
│  💬 中国国内，我的 macOS│                        │                      │
│                         │                        │                      │
│ [Settings] ⚙            │                        │                      │
└─────────────────────────┴───────────────────────┴──────────────────────┘
```

### 2.2 左 Sidebar 入口清单

**顶部 4 基础入口**（图标 + 文字，左对齐）：

| 入口 | 图标 | 快捷键 | 作用 |
|------|------|--------|------|
| New chat | 手写笔+方框 | `⌘N` | 全局新建 Thread |
| Search | 放大镜 | `⌘F` | 全局搜索 Thread 标题 |
| Plugins | @符号 | — | 打开插件市场（MCP / Skills）|
| Automations | 时钟 | — | 打开 Automations 列表 |

**Projects 列表**：
- 每个 Project = 文件夹级别
- Project 标题：左 SF Symbol `folder` + 项目名 + 缩进 8pt
- Project 下挂载 Thread：再缩进 24pt
- Thread 项：标题 + 右对齐相对时间戳（`2w` / `1w` / `3w` / `1mo`）
- 选中态：整行浅灰高亮 + 左侧 8pt 蓝色未读圆点（仅未读时显示）
- 空 Project 显示 "No chats" 灰字
- Project 标题旁有 `+` 按钮（推测位置）——点击新建 Project

**Chats（全局）**：
- 不属于任何 Project 的 thread 放这里
- 同 Project 的 Thread 视觉规范

**底部 Settings**：
- `⚙ Settings` 链接
- 点击在新窗口打开设置页（详见 §10.5 / §A 截图）

### 2.3 中部主区元素清单

**顶部 48pt 工具栏**：
- 左侧：thread 标题（可点击重命名）+ breadcrumb（项目名 / 分支名）
- 右侧 2 按钮：
  - `Z⌄` 按钮（推测 = 环境切换：Local / Worktree / Cloud）
  - `⚙️+✓` 按钮（点击弹出 Environment 浮层，详见 §3.6）

**对话流**：
- 思考过程行（小号灰字：`Thought for 3s` / `Using skills X` / `Explored 3 files`）
- 验证步骤（`scripts/forge-validate` 等带 monospace 标签的代码片段）
- 文档列表（CLAUDE.md / SKILL.md / distill-me.md，每行 = 文件图标 + 文档标题 + `Open in ⌄` 下拉）
- "Edited N files" 卡片（详见 §5.6）

**Composer 输入框**（固定在主区底部约 80pt）：
- 完整控件清单详见 §5.7

### 2.4 右侧多 Tab 工作区（v1.2 回退到 v1.0 模型）

**v1.2 回退**：v1.1 把右侧栏改成"5 entry 互斥单选 list"，但用户反馈要的是**多 Tab 并存工作区**（v1.0 模型）。本节回到 v1.0 形态，行为接近 Chrome / VS Code 侧栏 / iTerm2。

**核心行为**：
- 顶部 tab 栏：横向排列，每个 Tab = 标题 + 关闭 × 按钮
- Tab 可同时打开多个（并存），用户可主动关闭
- `+` 按钮：弹出"添加 Tab"菜单（5 种 panel 类型可叠加）
- 切换 Tab：点击 tab 标签，content swap 到对应 panel
- ESC：关闭当前激活 Tab（无 Tab 时不响应）
- 右侧栏默认状态 = 空 + `+` 按钮（无任何激活 Tab）

**5 种 panel 类型**（可同时存在多个实例）：

| Panel | 图标 | 作用 | 默认快捷键 |
|-------|------|------|----------|
| **Review** | `checklist` | 代码审查 + Diff | `⌃⇧G` |
| **Terminal** | `terminal` | 命令行终端 | `⌃\`` |
| **Browser** | `globe` | 内嵌网页浏览器 | `⌘T` |
| **Files** | `folder` | 工作区文件树 | `⌘P` |
| **Side chat** | `plus.circle` | 旁路对话（不污染主上下文） | `⌥⌘S` |

**Tab 视觉规格**：
- Tab 高度约 32-36pt，宽度自适应内容（最小 80pt，最大 200pt）
- 激活 tab：背景 = `bgRightPanel` (#000000)，底边 2pt `accentPrimary` (#339CFF) 指示器
- 非激活 tab：背景透明 + 1pt 边框
- 关闭 × 按钮：hover 时显示，红色仅在 hover
- 文本 13pt 常规，激活态白色，非激活态 `#999999`
- Tab 过多（>5）时：tab 栏横向滚动，不收缩

**`+` 按钮**：
- 固定在 tab 栏最右
- 点击弹出菜单：5 种 panel 类型（icon + 文字）
- 选中的 panel 类型 = 创建新 Tab 实例（同一类型可多次添加 → 多个 Terminal Tab 等）

**Tab 关闭**：
- × 按钮在 hover 时显示
- 点击关闭该 Tab
- 关闭最后一个 Tab → 右侧栏恢复空状态（只显示 `+` 按钮）

**panel 内容**（每个 Tab 实例独立）：
- `review` → `ReviewPanelView`：当前 Thread 的 Diff
- `terminal` → `TerminalPanelView`：内嵌 PTY 终端（每个 Tab 独立 session）
- `browser` → `BrowserPanelView`：WKWebView
- `files` → `FilesPanelView`：工作区文件树 + 内容查看
- `sideChat` → `SideChatPanelView`：独立对话窗口

**为什么用多 Tab**（v1.2 论证）：
| 特征 | Tab 系统预期 | v1.2 行为 | 结论 |
|------|------------|---------|------|
| 横向 tab 标签栏 | 有 | **有** | ✅ 是 tab |
| Tab 关闭 × 按钮 | 有 | **有** | ✅ 是 tab |
| Tab 并存（多激活态）| 允许 | **允许** | ✅ 是 tab |
| + 新建 tab 按钮 | 有 | **有** | ✅ 是 tab |

**目的**：允许用户同时打开"Diff + Terminal + Files"等组合（实际工作流常见），不被互斥单选束缚。每个 panel 是独立内容空间（多个 Terminal = 多个 shell session）。

**反例**（v1.2 全面重写）：
- ❌ **不要做成"5 entry 互斥单选"模式**（v1.1 错误）—— 必须多 Tab 并存
- ❌ **不要让 Tab 数量硬性限制** —— 浏览器模式可开 10-20 个 Tab
- ❌ **不要让 Tab 标题截断后无法查看** —— hover 显示完整 title
- ❌ **不要做"全局单一内容区"** —— content 必须随 tab swap

### 2.5 URL Scheme 唤起

```swift
// 注册到 Info.plist
CFBundleURLTypes:
  - CFBundleURLSchemes: ["swiftagent"]
```

支持的 URL（可被外部脚本/快捷指令唤起）：
```
swiftagent://threads/new?prompt=...&path=...
swiftagent://threads/<uuid>
swiftagent://settings
swiftagent://settings/appearance
swiftagent://skills
swiftagent://automations
```

---

## 3. 窗口与布局

### 3.1 macOS 窗口规范

```swift
// SwiftUI 实现
Window("SwiftAgent", id: "main") {
    MainContentView()
        .frame(minWidth: 980, minHeight: 640)
}
.windowStyle(.titleBar)  // 标准 macOS 标题栏
.windowResizability(.contentMinSize)
```

| 维度 | 规范 |
|------|------|
| 窗口类 | `NSWindow` 单实例，多窗口允许（Cmd+N 新窗口） |
| 标题栏 | 标准 macOS，未启用 hidden titlebar |
| Traffic light | 最左，圆形，标准 macOS 行为 |
| 最小尺寸 | `980 × 640pt` |
| Vibrancy | **左 Sidebar 用 NSVisualEffectView**（.sidebar 材质）—— **关键**（详 §4.1） |
| 窗口圆角 | 12-16pt |
| Drop shadow | 极轻 diffuse |

### 3.2 三栏 + 右侧多 Tab 工作区（SwiftUI 实现）

```swift
// SwiftUI NavigationSplitView 三栏 + 自定义右侧多 Tab 工作区
NavigationSplitView {
    SidebarView()              // 左 240-280pt
        .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 320)
} content: {
    ContentView()              // 中弹性
        .navigationSplitViewColumnWidth(min: 480, ideal: 720)
} detail: {
    RightTabsView()            // 右 380-440pt 多 Tab 工作区
        .navigationSplitViewColumnWidth(min: 380, ideal: 420, max: 520)
}
```

**v1.2 回退**：detail 区域是**多 Tab 并存工作区**（v1.0 模型）——不是 v1.1 写的"5 entry 互斥单选 list"。Tab 可同时存在多个，每个 Tab 独立内容。详见 §3.3。

### 3.3 右侧多 Tab 工作区（v1.2 回退到 v1.0 模型）

**v1.2 关键**：右侧是**多 Tab 并存工作区**，不是 v1.1 写的"5 entry 互斥单选 list"。

```swift
// Tab 类型枚举
enum RightTabType: String, CaseIterable, Identifiable, Codable {
    case review, terminal, browser, files, sideChat
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .review: return "Review"
        case .terminal: return "Terminal"
        case .browser: return "Browser"
        case .files: return "Files"
        case .sideChat: return "Side chat"
        }
    }
    
    var icon: String {
        switch self {
        case .review: return "checklist"
        case .terminal: return "terminal"
        case .browser: return "globe"
        case .files: return "folder"
        case .sideChat: return "plus.circle"
        }
    }
    
    var shortcut: String? {
        switch self {
        case .review: return "⌃⇧G"
        case .terminal: return "⌃`"
        case .browser: return "⌘T"
        case .files: return "⌘P"
        case .sideChat: return "⌥⌘S"
        }
    }
}

// 单个 Tab 实例（同一类型可有多个）
struct RightTab: Identifiable, Equatable {
    let id: UUID
    let type: RightTabType
    var title: String  // 用户可编辑
    let createdAt: Date
}

// 多 Tab 工作区容器
struct RightTabsView: View {
    @ObservedObject var tabsStore: RightTabsStore  // 持有所有打开的 tab
    @ObservedObject var thread: ThreadViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // 1. Tab 栏
            TabBarView(tabsStore: tabsStore)
                .frame(height: 36)
            
            Divider().background(Color.borderStrong)
            
            // 2. 当前激活 Tab 的内容
            if let activeTab = tabsStore.activeTab {
                TabContentView(tab: activeTab, thread: thread)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else {
                EmptyTabPlaceholder()  // 无 Tab 时的空状态
            }
        }
        .background(Color.bgRightPanel)  // #000000
    }
}

// Tab 栏（横向 tab + + 按钮）
struct TabBarView: View {
    @ObservedObject var tabsStore: RightTabsStore
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 1) {
                ForEach(tabsStore.tabs) { tab in
                    TabLabel(
                        tab: tab,
                        isActive: tabsStore.activeTabID == tab.id
                    ) {
                        tabsStore.activate(tab.id)
                    } onClose: {
                        tabsStore.close(tab.id)
                    }
                }
                // + 新建按钮
                Button {
                    tabsStore.showAddMenu()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $tabsStore.showAddPopover) {
                    AddTabMenu(tabsStore: tabsStore)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

// 单个 Tab 标签
struct TabLabel: View {
    let tab: RightTab
    let isActive: Bool
    let onTap: () -> Void
    let onClose: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: tab.type.icon)
                .frame(width: 14)
            Text(tab.title)
                .font(.system(size: 13))
                .lineLimit(1)
            if isHovering || isActive {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(isHovering ? .red : .secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isActive ? Color.bgRightPanel : Color.clear)
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(Color.accentPrimary)
                    .frame(height: 2)
            }
        }
        .foregroundColor(isActive ? .white : Color.textSecondary)
        .onTapGesture(perform: onTap)
        .onHover { isHovering = $0 }
    }
}

// Tab 状态存储（actor / @MainActor ObservableObject）
@MainActor
final class RightTabsStore: ObservableObject {
    @Published var tabs: [RightTab] = []
    @Published var activeTabID: UUID?
    @Published var showAddPopover: Bool = false
    
    var activeTab: RightTab? {
        tabs.first(where: { $0.id == activeTabID })
    }
    
    func openTab(type: RightTabType) {
        let tab = RightTab(id: UUID(), type: type, title: type.title, createdAt: Date())
        tabs.append(tab)
        activeTabID = tab.id
    }
    
    func close(_ id: UUID) {
        tabs.removeAll(where: { $0.id == id })
        if activeTabID == id {
            activeTabID = tabs.last?.id
        }
    }
    
    func activate(_ id: UUID) {
        activeTabID = id
    }
    
    func showAddMenu() { showAddPopover.toggle() }
}
```

**键盘快捷键绑定**（全局 hotkey → 打开新 Tab 实例）：
```swift
.commands {
    CommandGroup(after: .windowArrangement) {
        Button("New Review Tab") { rightTabsStore.openTab(type: .review) }
            .keyboardShortcut("g", modifiers: [.control, .shift])
        Button("New Terminal Tab") { rightTabsStore.openTab(type: .terminal) }
            .keyboardShortcut("`", modifiers: [.control])
        Button("New Browser Tab") { rightTabsStore.openTab(type: .browser) }
            .keyboardShortcut("t", modifiers: .command)
        Button("New Files Tab") { rightTabsStore.openTab(type: .files) }
            .keyboardShortcut("p", modifiers: .command)
        Button("New Side chat Tab") { rightTabsStore.openTab(type: .sideChat) }
            .keyboardShortcut("s", modifiers: [.command, .option])
    }
}
```

**Tab 内容**（多 Tab 并存，每个独立）：
- `review` → `ReviewPanelView`：当前 Thread 的 Diff
- `terminal` → `TerminalPanelView`：内嵌 PTY 终端（每个 Tab 独立 shell session）
- `browser` → `BrowserPanelView`：WKWebView
- `files` → `FilesPanelView`：工作区文件树
- `sideChat` → `SideChatPanelView`：独立对话窗口

**目的**：允许用户同时打开"Diff + 2 个 Terminal + Files"等组合，符合 IDE / 浏览器多 Tab 习惯。

### 3.4 顶部工具栏（中部主区上方 48pt）

```swift
struct ThreadToolbar: View {
    @ObservedObject var thread: ThreadViewModel
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(thread.title).font(.headline)
                Text(thread.breadcrumb).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            // Z⌄ 按钮
            Menu {
                Button("Local") { ... }
                Button("Worktree") { ... }
                Button("Cloud") { ... }
            } label: {
                Image(systemName: "Z.square")  // 占位，需实拍确认
            }
            // ⚙️+✓ Environment 浮层触发器
            Button(action: { showEnv = true }) {
                Image(systemName: "gearshape.checkmark")
            }
            .popover(isPresented: $showEnv) { EnvironmentPopover() }
        }
        .frame(height: 48)
        .padding(.horizontal, 16)
    }
}
```

### 3.5 Environment 浮层（点击 ⚙️+✓ 按钮后弹出）

**位置**：浮在中部主区右上角

**5 字段**（自上而下）：
1. `+ Changes`（带方框+号图标）
2. `🖥 Local ⌄`（下拉）
3. `🔀 main ⌄`（git 分支下拉）
4. `📤 Commit or push`
5. `🐙 Pull request status unavailable`

分割线

6. `Sources` 区块标题
7. `No sources yet` 空状态文字

**关闭**：点击浮层外部任意区域

### 3.6 底部状态条（Composer 内部嵌入）

```swift
// 没有独立 NSStatusBar，状态条全部嵌在 Composer 内
struct Composer: View {
    @State private var prompt: String = ""
    
    var body: some View {
        VStack {
            // 思考状态行（"Thought for 3s"）—— hover 才显示
            // 主输入框
            TextEditor(text: $prompt)
                .placeholder("Ask for follow-up changes")
            
            // 控件行
            HStack {
                // 左侧：+ 加号 + ⚙️ Custom⌄
                Button(action: showAddMenu) {
                    Image(systemName: "plus")
                }
                Menu {
                    Button("Ask for approval") { ... }
                    Button("Approve for me") { ... }
                    Button("Full access") { ... }
                    Button("Custom (config.toml)") { ... }
                } label: {
                    Label("Custom", systemImage: "gearshape")
                }
                
                Spacer()
                
                // 右侧：5.5 High⌄ + ↑
                Menu {
                    // Reasoning: Low/Medium/High✓/Extra High
                    // Model: GPT-5.5✓/GPT-5.4/...
                } label: {
                    Text("5.5 High")
                }
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .padding(8)
                        .background(.thinMaterial, in: Circle())
                }
            }
        }
        .frame(minHeight: 80)
    }
}
```

### 3.7 状态条 Composer 极简化的反例

- ❌ 不要做"5 档权限 pill"——实测是 4 档 toggle（在 General）+ 第 4 档隐藏在 Composer 弹窗
- ❌ 不要做"上下文使用量环形"——实测未在 Composer 主区域显示
- ❌ 不要让 Z⌄ 按钮位置固定到右下角——它应该在工具栏右侧

---

## 4. 视觉系统（Design Tokens）

### 4.1 配色（深色模式 + 浅色模式）

**深色模式（默认）**：

```swift
extension Color {
    // 背景（26.609 实测）
    static let bgSidebar      = Color(red: 0.165, green: 0.165, blue: 0.165)  // #2A2A2A
    static let bgContent      = Color(red: 0.110, green: 0.110, blue: 0.110)  // #1C1C1C
    static let bgRightPanel   = Color(red: 0.000, green: 0.000, blue: 0.000)  // #000000
    static let bgElevated     = Color(red: 0.165, green: 0.165, blue: 0.165)  // #2A2A2A（卡片）
    static let bgInput        = Color(red: 0.122, green: 0.122, blue: 0.122)  // #1F1F1F
    
    // 文字
    static let textPrimary    = Color(red: 0.961, green: 0.961, blue: 0.961)  // #F5F5F5
    static let textSecondary  = Color(red: 0.600, green: 0.600, blue: 0.600)  // #999999
    static let textTertiary   = Color(red: 0.400, green: 0.400, blue: 0.400)  // #666666
    
    // 强调
    static let accentPrimary  = Color(red: 0.200, green: 0.612, blue: 1.000)  // #339CFF（实测）
    static let success        = Color(red: 0.247, green: 0.725, blue: 0.314)  // #3FB950
    static let danger         = Color(red: 0.973, green: 0.318, blue: 0.286)  // #F85149
    static let warning        = Color(red: 0.890, green: 0.702, blue: 0.255)  // #E3B341
    
    // 边框
    static let borderSubtle   = Color(red: 0.165, green: 0.165, blue: 0.165)  // #2A2A2A
    static let borderStrong   = Color(red: 0.227, green: 0.227, blue: 0.227)  // #3A3A3A
}
```

**浅色模式**（Light theme）：

```swift
extension Color {
    static let bgSidebar      = Color(red: 1.000, green: 1.000, blue: 1.000)  // #FFFFFF
    static let bgContent      = Color(red: 1.000, green: 1.000, blue: 1.000)  // #FFFFFF
    static let bgRightPanel   = Color(red: 0.941, green: 0.941, blue: 0.969)  // #F0F0F7
    static let bgElevated     = Color(red: 0.969, green: 0.969, blue: 0.972)  // #F7F7F8
    static let bgInput        = Color(red: 1.000, green: 1.000, blue: 1.000)  // #FFFFFF
    
    static let textPrimary    = Color(red: 0.102, green: 0.110, blue: 0.122)  // #1A1C1F
    static let textSecondary  = Color(red: 0.376, green: 0.376, blue: 0.392)  // #606064
    static let textTertiary   = Color(red: 0.643, green: 0.643, blue: 0.659)  // #A4A4A8
    
    static let accentPrimary  = Color(red: 0.200, green: 0.612, blue: 1.000)  // #339CFF
    static let success        = Color(red: 0.102, green: 0.498, blue: 0.220)  // #1A7F37
    static let danger         = Color(red: 0.812, green: 0.133, blue: 0.180)  // #CF222E
    
    static let borderSubtle   = Color(red: 0.929, green: 0.929, blue: 0.929)  // #EDEDED
    static let borderStrong   = Color(red: 0.816, green: 0.816, blue: 0.816)  // #D0D0D0
}
```

### 4.2 字体

```swift
extension Font {
    // UI 字体（系统字体栈 + 苹果原生）
    static let uiBody    = Font.system(size: 13, weight: .regular)
    static let uiLabel   = Font.system(size: 13, weight: .medium)
    static let uiHeadline = Font.system(size: 17, weight: .semibold)
    static let uiTitle   = Font.system(size: 28, weight: .semibold)
    static let uiCaption = Font.system(size: 12, weight: .regular)
    
    // 代码字体（等宽）
    static let codeMono  = Font.system(size: 13, design: .monospaced)
    static let codeTag   = Font.system(size: 12, weight: .medium, design: .monospaced)
}
```

### 4.3 圆角

```swift
extension View {
    func swiftRadius(_ radius: CGFloat) -> some View {
        self.clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

// 使用
.cornerRadius(4)    // 用户消息气泡右上角（"指向发送方"暗示）
.cornerRadius(8)    // 卡片 / Composer 按钮
.cornerRadius(12)   // 主按钮 / 输入框
.cornerRadius(16)   // 容器
.cornerRadius(20)   // 弹窗
.cornerRadius(999)  // Pill（全圆）
```

### 4.4 间距

```swift
// 8pt 基础栅格
extension CGFloat {
    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 20
    static let space6: CGFloat = 24
    static let space7: CGFloat = 32
    static let space8: CGFloat = 40
}
```

### 4.5 Icon 体系

**100% SF Symbols**（1.5pt 描边 outlined 风格）—— **不**用 fill 风格，**不**用定制 icon。

例外：可让 Logo 用 SVG 定制（OpenAI 用鸟 + `>_`，SwiftAgent 可用 `>_` 终端提示符）。

### 4.6 主题切换

`Appearance` 标签下实现：
- Theme 三选一：Light / Dark / System（默认 System）
- Light theme / Dark theme 各 8 字段：
  - Theme preset（默认 Codex）
  - Accent / Background / Foreground（带圆形色卡预览）
  - UI font / Code font
  - **Translucent sidebar**（Toggle ON → 启用 NSVisualEffectView vibrancy）
  - Contrast（滑块 0-100，控制 vibrancy 透出度）

**反例**：❌ 不要让 Light/Dark 共用同一个 Accent——实测两者独立可配（虽然默认相同）

### 4.7 13 个核心组件（SwiftUI 实现）

| 组件 | SwiftUI 实现 |
|------|--------------|
| 主按钮 (filled) | `.buttonStyle(.borderedProminent)` + 圆角 12 |
| 次按钮 (outlined) | `.buttonStyle(.bordered)` + 圆角 12 |
| 文字按钮 | `.buttonStyle(.plain)` + chevron |
| 输入框 | `TextField` / `TextEditor` + 圆角 12-16 |
| Pill | 自定义 `Capsule()` |
| Card | `RoundedRectangle` + 描边 1px |
| Status dot | `Circle().fill()` + 8pt |
| Avatar | `Circle()` + 蓝紫渐变 |
| Badge | `RoundedRectangle` + 圆角 6 |
| Tooltip | `.help()` modifier |
| Popover | `.popover()` modifier |
| Modal | `.sheet()` 或独立 Window |
| Toast | 自定义 overlay + 2-3s 自动消失 |

---

## 5. 核心交互模式

### 5.1 对话流（输入 → 思考 → 工具调用 → 结果）

**视觉规范**（深色模式）：

```
[用户消息]    深灰气泡（bgElevated），右上角略小圆角 (4pt)，右对齐
              右下角"+"加号 → 添加附件/Plugins
[AI 响应]     直接铺陈在主区背景（bgContent）上，无气泡，左对齐
              等宽字体（codeMono）
[状态行]      小号灰字（textSecondary 12pt）左对齐
              "Thought for 3s"
              "Using skills $openai-image"（紫色 pill #5E35B1 文字 + 淡紫 #EDE7F6 底）
              "Explored 3 files"
[生成内容]    圆角卡片 16pt 嵌入
[代码块]      等宽字体 + 浅深色背景 + 1px 边框
```

**目的**：让用户一眼分辨"我说的"（带气泡）vs "AI 说的"（无气泡）vs "AI 在工作"（灰字状态行）。

**反例**：
- ❌ 不要把状态行做成彩色——会喧宾夺主
- ❌ 不要让 AI 响应也带气泡——会显得"和用户在并列说话"而不是"AI 为主用户为辅"

### 5.2 多 Agent 并行（Projects + Threads 两层）

**Sidebar 结构**（实测 10 个 Project 实测）：

```
┌─ New chat / Search / Plugins / Automations ─┐
│                                                │
│ Projects                                       │
│   📁 forge        (含 thread: 构建 forge 体系) │
│   📁 SwiftAgent    (含 3+ thread)              │
│   📁 swift-film-prototype                      │
│   ...                                          │
│                                                │
│ Chats (全局)                                    │
│   💬 中国国内，我的 macOS 现在 GitHu...        │
│                                                │
│ ⚙ Settings                                     │
└────────────────────────────────────────────────┘
```

**视觉规范**（实测 26.609）：
- **Project 标题**：左侧 SF Symbol `folder` + 项目名（小号灰字 + 缩进 8pt）
- **Thread 项**：比 Project 缩进 24pt，纯白文字 + 右对齐时间戳
- **选中态**：Thread 项整行背景色变浅灰（约 8% 透明叠加）+ 左侧 8pt 蓝色实心圆点（仅未读时显示）
- **时间戳格式**：相对时间（"2w" / "1w" / "3w" / "1mo"），右对齐，浅灰色
- **无水平分隔线**：靠 4-6pt 垂直空白分组
- **空 Project**：显示 "No chats" 灰字

**反例**：
- ❌ 不要显示 Project 的"设置 / 成员"等管理界面——Project 只是个文件夹的概念
- ❌ 不要给 Thread 加"已读/未读"badge 之外的状态

### 5.3 Diff Review 模式

**视觉规范**：
- 顶栏：左侧 `2 files edited +123 −42`（+ 绿、- 红），右侧 `Review ↗` 灰色文字 + 右上箭头
- 文件列表行：文件名 + 单文件 +/− 计数 + 状态蓝点 + 折叠 chevron
- 展开后：unified diff，绿底红字（+ 行 `#3FB950` 文字、`-` 行 `#F85149` 文字）
- 行内评论：在 diff 行号旁 `+` 按钮 → 弹小输入框 → 评论以 Thread 形式回灌到对话区

**反例**：
- ❌ **不做**逐行 Accept/Reject 按钮——SwiftAgent 设计哲学是"agent 已经把变更写完并通过测试，用户的角色是审阅而不是拒绝"

### 5.4 沙箱权限弹窗

**触发场景**：
- 联网（默认 `sandbox_mode = workspace-write`，`network_access = false`）
- 读沙箱外的文件
- 写沙箱外的文件
- 执行非内置 shell 命令

**视觉规范**：
- **独立浮层**（不是 Composer 内的 toggle）—— 点击 `⚙️ Custom⌄` 按钮触发
- 标题 `How should Codex actions be approved?`（实测文案——SwiftAgent 改为 `How should SwiftAgent actions be approved?`）
- 右侧 `Learn more` 链接
- 4 个选项（图标 + 主文字 + 副文字）：
  - ✋ **Ask for approval** — Always ask to edit external files and use the internet
  - ⏱ **Approve for me** — Only ask for actions detected as potentially unsafe
  - 🛡 **Full access** — Unrestricted access to the internet and any file on your computer
  - ⚙ **Custom (config.toml)** — Uses permissions defined in config.toml ✓ 默认

**反例**：
- ❌ 不要让"Custom"选项消失——实测它是默认勾选
- ❌ 不要让权限弹窗做成系统级弹窗

### 5.5 跨会话复用（Thread Reuse）

**目的**：让 Thread 不再是"一次性会话"——60 秒内对同一 Thread 互动会复用上下文。

**视觉规范**：
- 60s 内对同一 Thread 互动 → Appshots 自动续接到该 Thread
- 不互动则开新 Thread

**状态机**（详见 §7.2）。

### 5.6 屏幕感知（Appshots）— v1.0 实现

**目的**：把"用户当前屏幕上看到的内容"一键喂给 AI。

**触发方式**：
- **macOS 全局**：双击 Cmd 键（`Cmd+Cmd`，同时按左右两个 Command）
- 成功反馈：右下角"✓"动效，1.2 秒
- 捕获范围：当前活跃应用窗口（含视野外文字）

**实现**：

```swift
// 注册全局快捷键
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let appshotCapture = Self("appshotCapture", default: .init(
        key: .command, modifiers: [.command]
    ))
}

// 在 AppDelegate 监听
KeyboardShortcuts.onKeyUp(for: .appshotCapture) { _ in
    // 双击 Cmd 才触发（避免单击误触）
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 200_000_000)
        if KeyboardShortcuts.isPressed(.command) {
            AppState.shared.captureAppshot()
        }
    }
}

// Appshot 捕获
func captureAppshot() async throws {
    // 1. 截屏当前应用窗口
    let image = try await screenCapture.captureActiveWindow()
    
    // 2. 通过无障碍 API 提取文字
    let text = try await axApi.extractTextFromActiveWindow()
    
    // 3. 注入当前活跃 Thread
    await ThreadViewModel.active.addAttachment(.appshot(image: image, text: text))
    
    // 4. 显示成功动效
    showSuccessCheckmark()  // 1.2s
}
```

**反例**：
- ❌ 不要做"全屏截图"——只截当前窗口
- ❌ 不要让 Appshots 跨应用切换

### 5.7 Composer 输入框完整控件

**布局**：

```
┌─────────────────────────────────────────────────────────────┐
│ (ask for follow-up changes)                                   │
│                                                               │
│ [+] [⚙️ Custom⌄]                    [5.5 High⌄] [↑]          │
└─────────────────────────────────────────────────────────────┘
```

#### `+` 加号菜单（6 项 + 子菜单）

弹出的菜单分两部分（带分割线）：

| 区块 | 项 | 形态 | 触发 |
|------|----|------|------|
| **基础** | Add photos & files | 文字 + 回形针 icon | 弹出文件选择器 |
| | Create | 文字 + `>` 箭头 | 推测子菜单：新建文件 / 项目 |
| **高级** | Plan mode | 文字 + toggle | 切换 Plan 模式（只规划不执行）|
| | Pursue goal | 文字 + toggle | 切换 Goal 模式（持久目标）|
| | **Plugins** | 文字 + `>` 箭头 | 子菜单：3 installed plugins（PDF / Browser / Chrome）|

#### `⚙️ Custom⌄` 权限档位菜单

点击弹出"权限档位"独立浮层，详见 §5.4。按钮上的"Custom"文字 = 当前生效的档位。

#### `5.5 High⌄` 模型选择（双层菜单）

**左面板 Reasoning**：
- Low
- Medium
- **High** ✓
- Extra High
- **GPT-5.5 >**（触发右侧子菜单）

**右面板 Model**（实测）：

> ⚠️ **SwiftAgent 必须改为 DeepSeek 模型**（不是 OpenAI 家族）

- **DeepSeek-V3** ✓
- DeepSeek-R1
- DeepSeek-V3-0324
- DeepSeek-Coder-V2

> 注：DeepSeek 模型是 OpenAI API 兼容的（`https://api.deepseek.com/v1`），可用 OpenAI Swift client 替换 baseURL。

#### `↑` 发送按钮

- 深灰色实心圆形（约 32pt 直径）
- 中间浅色向上箭头
- 禁用态 = 更深灰色；可用态（输入文字）= 更亮

### 5.8 "Edited N files" 卡片（inline 在主区底部）

**实测卡片**：
- 卡片背景 `bgElevated`（同 sidebar #2A2A2A）
- 1px 边框 `borderStrong`（#3A3A3A）
- 圆角 8pt
- 内边距 12-16pt

**内容**（自上而下）：
- 左：`[+]` 图标 + "Edited 9 files" 文字 + 下一行小字 `+85 -3`（绿/红 diff stat）
- 右：`Undo⟲` 文字按钮 + `Review` 文字按钮（带边框）
- 下方：折叠的文件列表（每行 = 文件名 + `+X -Y`）+ `Show 6 more files ⌄` 折叠提示

**反例**：
- ❌ 不要让这个卡片跨页（paging）显示——必须能一键 Review 看到完整 diff

---

## 6. 键盘快捷键全集

### 6.1 Chat / Thread 管理

| 操作 | 快捷键 | 第二快捷键 |
|------|--------|-------------|
| New chat | `⌘N` | `⇧⌘O` |
| New quick chat | `⌥⌘N` | — |
| Open side chat | `⌥⌘S` | — |
| Open in new window | (Unassigned) | — |
| Pin chat | `⌥⌘P` | — |
| Rename chat | `⌥⌘R` | — |
| Archive chat | `⇧⌘A` | — |
| Find | `⌘F` | — |

### 6.2 搜索 / 导航

| 操作 | 快捷键 | 第二快捷键 |
|------|--------|-------------|
| Focus browser address bar | `⌘L` | — |
| Back (navigation history) | `⌘[` | Mouse Back |
| Forward (navigation history) | `⌘]` | Mouse Forward |
| Next recently viewed chat or tab | `^Tab` | — |
| Next chat or tab | `⇧⌘]` | `⌥⌘Right` |
| Previous recently viewed chat or tab | `^⇧Tab` | — |
| Previous chat or tab | `⇧⌘[` | `⌥⌘Left` |

### 6.3 右侧多 Tab 工作区（v1.2 回退到 v1.0 多 Tab 模型）

| 操作 | 快捷键 |
|------|--------|
| Open new Review tab | `^⇧G` |
| Open new Browser tab | `⌘T` |
| Open new Files tab | `⌘P` |
| Open new Side chat tab | `⌥⌘S` |
| Open new Terminal tab | `^`` (Ctrl + `) |
| Close current tab | `⌘W` |
| Next tab | `^⇧}` / `⌥⌘→` |
| Previous tab | `^⇧{` / `⌥⌘←` |
| Move tab right | `^⇧⌘→` |
| Move tab left | `^⇧⌘←` |
| Toggle bottom Composer | `⌘J` |
| Toggle right panel | `⇧⌘B` |
| Toggle left sidebar | `⌘B` |

**v1.2 修正**：上表快捷键是"打开新 Tab 实例"（多 Tab 并存），不是 v1.1 写的"激活 5 entry 中的某一个"。每个快捷键按下 = 创建新 Tab + 切换到该 Tab。详见 §2.4 / §3.3。

### 6.4 环境快捷键

| 操作 | 快捷键 |
|------|--------|
| Environment action 1 | `⇧⌘D` |
| Environment action 2 | (Unassigned) |

### 6.5 全局 / Appshots

| 操作 | 快捷键 |
|------|--------|
| **Appshots**（双击 Cmd 触发）| `Cmd+Cmd` |
| Send message | `Enter` / `Cmd+Enter` |
| New line | `Shift+Enter` |
| Edit last message | `Esc+Esc`（双击 Esc）|
| Voice input | `^M` (Ctrl+M) |

### 6.6 斜杠命令（输入框 `/` 触发）

| 命令 | 作用 |
|------|------|
| `/help` | 显示所有命令 |
| `/goal` | 启动持久目标模式（数小时~数天）|
| `/plan` | 切换 Plan 模式 |
| `/skills` | 打开 Skills 库 |
| `/mcp` | 打开 MCP 服务器列表 |
| `/status` | 显示 thread ID、上下文使用量、模型 |
| `/compact` | 压缩对话历史 |
| `/clear` | 清空上下文 |
| `/personality` | 切换 Friendly / Pragmatic 风格 |
| `/exit` / `/quit` | 退出（仅 CLI 模式）|

### 6.7 URL Scheme

```
swiftagent://threads/new?prompt=...&path=...
swiftagent://threads/<uuid>
swiftagent://settings
```

---

## 7. 状态机

### 7.1 单个 Thread 的状态机

```swift
enum ThreadState {
    case idle
    case planning
    case executing
    case awaitingToolPermission
    case awaitingUserInput
    case compacting
    case done
    case failed
    case cancelled
}
```

**视觉规范**：
- `idle`：无状态图标
- `planning`：列表项显示转圈图标 + 进度文字
- `executing`：转圈图标持续旋转 + Composer 上方显示进度行
- `awaitingToolPermission`：绿色 `exclamationmark.bubble` 标签
- `awaitingUserInput`：琥珀色感叹号 + Composer 高亮
- `compacting`：进度条 + 百分比
- `done`：蓝色实心圆点 + 列表项右对齐时间戳
- `failed`：红色实心圆点
- `cancelled`：灰色实心圆点

### 7.2 跨会话复用（Thread Reuse）

```swift
enum ThreadReuseState {
    case new             // 全新对话
    case active          // 用户互动中
    case idle            // 60s 静默
    case resumed         // 再次互动
    case pausedViaGoal   // /goal 暂停
    case pausedViaAutomation  // 自动化定时唤醒
}
```

**60s 自动续接规则**：
- 60s 内对同一 Thread 互动 → 复用（Appshot 自动续接）
- 60s 静默 → 归档候选

### 7.3 四维叠加模型

任意时刻，一个 Thread 的状态由以下 6 维共同决定：

| 维度 | 取值 |
|------|------|
| **1. 主状态** | `idle / planning / executing / awaiting-tool-permission / awaiting-user-input / compacting / done / failed / cancelled` |
| **2. 模式** | `Code / Plan / Goal / Side` |
| **3. 沙箱权限** | `workspace-write`（默认） / `read-only` / `danger-full-access` / `config.toml` |
| **4. 执行环境** | `Local / Worktree / Cloud` |
| **5. 复用状态** | `New / Active / Idle / Resumed / Paused-via-Goal / Paused-via-Automation` |
| **6. Appshot 状态** | `off / requested / active / paused-by-input` |

### 7.4 跨设备线程同步

v1.0 仅 macOS，本节留给 v1.2 Mobile 端。

---

## 8. 动效规范

### 8.1 已确认动效（带 SwiftUI 实现）

| 动效 | 触发 | 时长 | SwiftUI 实现 |
|------|------|------|--------------|
| Appshots 捕获成功 "✓" | `Cmd+Cmd` 捕获后 | 1.2s | `.transition(.scale.combined(with: .opacity))` + 1.2s timer |
| Thread 列表项进入/退出 | 添加/删除 Thread | 200-300ms | `.animation(.easeInOut, value: threads)` |
| Diff 行展开/收起 | 点击 chevron | 150-200ms | `.animation(.easeOut, value: isExpanded)` |
| 主按钮悬浮反馈 | 鼠标进入按钮 | 100ms | `.animation(.linear, value: isHovered)` |
| Composer 输入框聚焦 | focus | 150ms | `.animation(.linear, value: isFocused)` |
| 状态行 "Thought for Xs" | 思考步骤完成 | 200ms | `.transition(.opacity.combined(with: .move(edge: .top)))` |
| 模态弹出 | 触发权限/环境 | 250ms | SwiftUI 默认 spring |
| Toast 出现/消失 | 通知事件 | 进入 200ms / 消失 300ms | `.transition(.move(edge: .bottom).combined(with: .opacity))` |

### 8.2 设计哲学

**"do not get in the way"** —— 动效永远不应该让用户"等"。

- 时长 < 300ms（除 Appshots 1.2s 反馈外）
- 缓动避免 spring bounce（除非特殊场景）
- 不阻塞用户输入
- 失败时静默回退到"瞬时切换"

### 8.3 动效反例

- ❌ 不要让模态弹出用 spring bounce 0.5+
- ❌ 不要让 Thread 切换转场超过 500ms
- ❌ 不要在用户输入时显示任何动效

---

## 9. 错误与边界态（16 大类）

### 9.1 错误分类与处理

| 类别 | 触发场景 | UI 表现 | 恢复策略 |
|------|----------|---------|----------|
| **沙箱拒绝** | Agent 尝试写沙箱外文件 / 联网 | 模态弹窗 | 用户批准/拒绝 |
| **网络重连** | 断网 / DeepSeek API 超时 | 顶部条 | 自动重试 3 次 |
| **限流（429）** | DeepSeek API 限流 | 顶部条 "Rate limit hit" | 退避重试 |
| **模型异常（5xx）** | DeepSeek API 故障 | 顶部条 | 自动重试 / 切模型 |
| **Worktree 冲突** | 多 agent 改同一文件 | 列表项冲突标记 | 用户选 base |
| **DeepSeek API Key 失效** | 401 Unauthorized | 顶部条 + 设置页跳转 | 用户重新输入 |
| **DeepSeek 余额不足** | 402 Payment Required | 顶部条 | 跳转充值页 |
| **Appshot 权限未授** | 无障碍权限被吊销 | Toast 错误 | 引导去系统设置 |
| **Appshot 捕获失败** | 窗口被遮挡 | Toast "无法访问屏幕内容" | 提示重试 |
| **MCP 服务器断开** | MCP 连接失败 | 输入框上方提示 | 自动重连 |
| **Skill 加载失败** | SKILL.md 格式错误 | 日志行 | 跳过该 skill |
| **Diff 合并失败** | patch 不适用 | 错误气泡 | 用户手动合并 |
| **/goal 持久化失败** | 数据库写失败 | 提示 | 退到内存态 |
| **Project 切换数据丢失** | 频繁切换 | 自动暂存 | 恢复后回填 |
| **Thread 列表性能** | > 1000 个 Thread | 虚拟滚动 | 自动加载 |
| **网络代理问题** | 用户在企业代理后 | 提示 | 引导配置 HTTP_PROXY |

### 9.2 错误态视觉规范

- **致命错误**（必须用户决策）：模态弹窗 + 红色图标 + 清晰文案
- **可重试错误**（自动恢复）：顶部条 + 输入框仍可用 + 列表项状态变红
- **警告**（可忽略）：底部 toast + 自动消失（2-3s）
- **网络/限流**：顶部持久条 + 倒计时

---

## 10. 8 个核心功能模块

### 10.1 Skills（技能）

**目的**：把"反复要交代的工作流"打包成 AI 可按需加载的操作手册。

**触发方式**：
- **自动调用（隐式）**：用户发任务时，AI 根据 SKILL.md 的 `description` 匹配决定是否加载
- **显式调用**：Composer 中用 `$skill-name`
- **Skills Creator**：设置 → Plugins → 创作

**入口位置**：
- 左 Sidebar `Plugins` 入口
- 三种作用域：
  - 用户级 `~/.swiftagent/skills/`（个人私有）
  - 项目级 `.swiftagent/skills/`（随仓库走，团队共享）
  - 系统级 `/etc/swiftagent/skills/`（管理员/容器）

**SKILL.md 标准结构**：

```markdown
---
name: skill-name
description: 一句话描述这个 skill 的用途（AI 据此决定是否加载）
---

# Skill 标题

## When to use
- 触发条件 1
- 触发条件 2

## When NOT to use
- 反例场景

## Workflow
1. 步骤 1
2. 步骤 2

## Output format
- 期望产出

## Notes
- 注意事项
```

**目的**：复用 SwiftAgentCore 已有的 Skills 引擎——**不重新发明**。

**反例**：
- ❌ 不要让用户手动勾选"用哪些 skill"——AI 自动路由
- ❌ 不要把 Skill 库做成"插件市场"风格

### 10.2 Automations（自动化）

**目的**：让 SwiftAgent 在后台按周期执行重复任务，结果写到 Inbox 等用户审。

**触发方式**：
- 左 Sidebar `Automations` 入口
- 调度语法：自然语言（"每天 15:00"、"每周一 09:30"）

**核心 UI**：
- Inbox 三段式：Up next（pending 空心圆圈）/ Unread（实心蓝色圆点）/ Read（灰圆 + 白对勾）
- 任务卡片：白底圆角 + 时间戳 + 模型来源标签

**目的**：复用 SwiftAgentCore 的 hooks + scheduler 引擎。

### 10.3 Worktree（工作树）

**目的**：多 agent 在同一仓库并行不冲突。

**三种运行模式**：
- **Local**：直接在当前工作目录运行
- **Worktree**：在 git worktree 隔离舱运行
- **Cloud**：在远程开发机运行（v1.0 暂不实现）

**UI 表现**：
- Thread 创建时选择执行环境（在 `Z⌄` 按钮里）
- 切换到 Worktree 后，UI 不显示 git ref——只显示 `Branch: swiftagent/thread-3c7e`
- 合并回主分支：用户在 Thread 中点"Apply to main" → 提示合并策略

**反例**：
- ❌ 不要让用户手动选"用哪个 worktree"
- ❌ 不要显示 `.git/worktrees/` 路径

### 10.4 Appshots（屏幕感知）

**目的**：把"用户当前屏幕上看到的内容"一键喂给 AI。

**触发方式**：
- macOS 全局：双击 Cmd 键（`Cmd+Cmd`）
- 成功反馈：右下角"✓"动效 1.2 秒
- 捕获范围：当前活跃应用窗口（含视野外文字）

**实现细节**：详见 §5.6

### 10.5 /goal / /plan 斜杠命令

**/goal**：
- **触发**：Composer 输入 `/goal`
- **目的**：给高阶目标，让 AI 持续跑到完成
- **UI**：Composer 上方显示进度行
  ```
  [objective] status: running | tokens used: 1.2M / 2M budget | [pause] [edit] [clear]
  ```

**/plan**：
- **触发**：`⇧⌘` 或 `/plan`
- **目的**：进入只规划不执行的模式

**反例**：
- ❌ 不要把 `/goal` 当作"长任务按钮"——它是"目标"概念

### 10.6 /personality

| 风格 | 副文字 | 适合 |
|------|--------|------|
| **Pragmatic** | Concise, task-focused, and direct | 默认 - 工程师 |
| Friendly | Warm, collaborative, and helpful | 非工程师 / 团队协作 |

**入口**：设置 → Personalization → Personality 下拉

### 10.7 沙箱与权限

4 档（详见 §5.4）：
- **Ask for approval**（最严）
- **Approve for me**（默认 - 智能判断）
- **Full access**（危险 - 仅高级用户）
- **Custom (config.toml)**（开发者 - 自定义规则）

项目级 rules（`.swiftagent/rules/`）可声明式地放开/收紧权限。

### 10.8 MCP 集成

**复用 SwiftAgentCore 已有 MCP 引擎**——`Sources/SwiftAgentCore/MCP/`。

**入口**：
- 设置 → Integrations → MCP servers
- Composer `+` → Plugins 子菜单

**支持**：
- stdio MCP 服务器
- SSE/HTTP MCP 服务器
- Apple 平台（Xcode 26.3 已内置 Codex 集成；SwiftAgent 可参考其协议）

### 10.9 设置页（4 大类 13 标签）

**Personal（个人设置）**：
- General（工作模式 / 权限 / 通用）
- Appearance（主题 / 配色 / 字体 / Vibrancy）
- Configuration（推测 = 模型 / 推理）
- Personalization（Personality / Custom instructions / Memory）
- Keyboard shortcuts（完整快捷键表 + 自定义）

**Integrations（集成设置）**：
- Appshots（Cmd+Cmd 屏幕感知）
- MCP servers（MCP 集成）
- Browser（内置浏览器）
- Computer use（v1.0 不做，留 v1.1）

**Coding（编码设置）**：
- Hooks（git hooks / SwiftAgent hooks）
- Connections（SSH / 远程连接）
- Git（git 集成）
- Environments（多环境）
- Worktrees（worktree 配置）

**Archived（归档）**：
- Archived chats（历史归档）

**视觉规范**：
- 左侧 Sidebar 分类列表（4 组 13 项）
- 右侧内容区（每个标签独立）
- 顶部 `← Back to app` + `Search settings...` 搜索框
- 设置页是 **独立新窗口**（不是应用内弹窗）

---

## 11. DeepSeek 模型集成

### 11.1 API 配置

**DeepSeek API 端点**：
```
Base URL: https://api.deepseek.com/v1
Models: deepseek-chat (V3), deepseek-reasoner (R1)
Auth: Bearer Token (DeepSeek API Key)
```

**OpenAI SDK 兼容**——SwiftAgent 可用 `swift-openai` 或自实现。

```swift
// Configuration
struct DeepSeekConfig: Codable {
    let baseURL: URL = URL(string: "https://api.deepseek.com/v1")!
    let apiKey: String  // 存 Keychain
    let defaultModel: DeepSeekModel = .v3
}

enum DeepSeekModel: String, CaseIterable {
    case v3 = "deepseek-chat"
    case r1 = "deepseek-reasoner"
    case v3_0324 = "deepseek-chat-0324"
    case coderV2 = "deepseek-coder-v2"
}
```

**Keychain 存储**：

```swift
import KeychainAccess

let keychain = Keychain(service: "com.swiftagent.api")
try keychain.set(deepseekAPIKey, key: "deepseek-api-key")
```

### 11.2 模型选择（Composer `5.5 High⌄` 双层菜单）

**左面板 Reasoning 强度**（DeepSeek 适配）：
- Low（弱推理，省 token）
- Medium
- **High** ✓（默认）
- Extra High（最强推理，最贵）

**右面板 Model 替换**（实测 4 模型）：

> ⚠️ **必须替换为 DeepSeek 模型**

| SwiftAgent | 替代 OpenAI |
|------------|------------|
| ~~GPT-5.5~~ | **DeepSeek-V3** ✓（chat）|
| ~~GPT-5.4~~ | **DeepSeek-R1**（reasoner）|
| ~~GPT-5.4-Mini~~ | **DeepSeek-V3-0324** |
| ~~GPT-5.3-Codex~~ | **DeepSeek-Coder-V2** |

**反例**：
- ❌ 不要保留 OpenAI 家族模型——SwiftAgent 是 DeepSeek only
- ❌ 不要让用户能输入"自定义模型名"——只列 4 个固定选项

### 11.3 请求适配

DeepSeek API 兼容 OpenAI Chat Completions 协议，**只需换 baseURL 和 model 名**：

```swift
// OpenAIClient.swift
class DeepSeekClient {
    let config: DeepSeekConfig
    let session: URLSession
    
    func chat(messages: [Message], model: DeepSeekModel) async throws -> AsyncStream<String> {
        var request = URLRequest(url: config.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ChatRequest(
            model: model.rawValue,
            messages: messages,
            stream: true,
            temperature: 0.7  // R1 不支持 temperature
        )
        request.httpBody = try JSONEncoder().encode(body)
        
        // SSE 流式响应（同 OpenAI）
        let (dataStream, response) = try await session.bytes(for: request)
        return AsyncStream { continuation in
            Task {
                for try await line in dataStream.lines {
                    if line.hasPrefix("data: ") {
                        let json = String(line.dropFirst(6))
                        if json == "[DONE]" { break }
                        if let chunk = try? JSONDecoder().decode(StreamChunk.self, from: Data(json.utf8)),
                           let content = chunk.choices.first?.delta.content {
                            continuation.yield(content)
                        }
                    }
                }
                continuation.finish()
            }
        }
    }
}
```

**R1 模型特殊处理**：
- R1（reasoner）**不支持** `temperature` / `top_p` 参数
- R1 返回 `reasoning_content` 字段（思维链）+ `content` 字段（最终回答）
- 建议：把 R1 的 `reasoning_content` 显示在 Composer 上方（折叠默认），让用户能"看到 AI 在想什么"

### 11.4 与 SwiftAgentCore 集成

**复用现有 Agent 引擎**（`Sources/SwiftAgentCore/Agent/`），只替换 LLM 层：

```swift
// Sources/SwiftAgentCore/LLM/Provider.swift
protocol LLMProvider {
    func stream(messages: [Message]) -> AsyncStream<LLMEvent>
}

// Sources/SwiftAgentCore/LLM/DeepSeekProvider.swift
class DeepSeekProvider: LLMProvider {
    let config: DeepSeekConfig
    
    func stream(messages: [Message]) -> AsyncStream<LLMEvent> {
        // 调用 DeepSeek API
        // 返回 LLMEvent 流（.token / .toolCall / .toolResult / .done）
    }
}
```

**LLMEvent 类型**（与 Codex 类似）：
```swift
enum LLMEvent {
    case token(String)              // 流式 token
    case reasoningToken(String)     // R1 思维链
    case toolCall(ToolCall)          // 工具调用
    case toolResult(ToolResult)     // 工具结果
    case done                        // 完成
    case error(Error)
}
```

### 11.5 推理强度映射

DeepSeek 没有"reasoning 强度"概念，但 R1（reasoner）天然就是"强推理"。

**SwiftAgent 适配**：

| Composer Reasoning | 实际模型 | 说明 |
|-------------------|----------|------|
| Low | DeepSeek-V3 | 弱推理，聊天模式 |
| Medium | DeepSeek-V3 | 中推理 |
| **High** ✓ | DeepSeek-V3 | 强推理（V3 也可）|
| Extra High | DeepSeek-R1 | 强制用 R1 |

### 11.6 配额与计费

DeepSeek API 价格（2026 年）：
- V3: ¥1/M input tokens, ¥2/M output tokens
- R1: ¥4/M input tokens, ¥16/M output tokens
- 比 OpenAI 便宜 30-50 倍

**UI 表现**：
- 设置 → General → "Token usage"（本月累计）
- 输入过多时显示警告 toast

---

## 12. 状态持久化

### 12.1 数据存储位置

| 数据 | 存储位置 | 格式 |
|------|----------|------|
| Thread 列表 | `~/Library/Application Support/SwiftAgent/threads.db` | SQLite（vapor/sqlite-kit）|
| Project 列表 | `~/Library/Application Support/SwiftAgent/projects.db` | SQLite |
| Skill 库 | `~/.swiftagent/skills/` | 文件夹 |
| MCP 配置 | `~/.swiftagent/config.toml` | TOML |
| 设置 | `~/Library/Preferences/com.swiftagent.app.plist` | UserDefaults |
| DeepSeek API Key | Keychain | Secure |
| 调试日志 | `~/.swiftagent/logs/` | JSONL |

### 12.2 Thread 持久化 schema

```sql
CREATE TABLE threads (
    id TEXT PRIMARY KEY,
    project_id TEXT REFERENCES projects(id),
    title TEXT NOT NULL,
    state TEXT NOT NULL,          -- 'idle' / 'planning' / 'executing' / ...
    reuse_state TEXT NOT NULL,     -- 'new' / 'active' / 'idle' / 'resumed'
    mode TEXT NOT NULL,             -- 'code' / 'plan' / 'goal' / 'side'
    sandbox_mode TEXT NOT NULL,     -- 'workspace-write' / 'read-only' / ...
    execution_env TEXT NOT NULL,    -- 'local' / 'worktree' / 'cloud'
    model TEXT NOT NULL,            -- 'deepseek-chat' / 'deepseek-reasoner'
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL
);

CREATE TABLE messages (
    id TEXT PRIMARY KEY,
    thread_id TEXT REFERENCES threads(id) ON DELETE CASCADE,
    role TEXT NOT NULL,             -- 'user' / 'assistant' / 'tool'
    content TEXT NOT NULL,
    metadata TEXT,                  -- JSON: tool calls, file refs, etc.
    created_at REAL NOT NULL
);

CREATE INDEX idx_messages_thread ON messages(thread_id, created_at);
```

### 12.3 自动保存策略

- 每条消息创建后立即写入
- Thread 状态变化（idle → executing → done）立即写入
- 每 30 秒 fsync（防崩溃丢数据）
- 应用退出前强制 sync

### 12.4 同步冲突解决

v1.0 仅 macOS 本地，**无云同步**——多窗口共享同一 SQLite（用 WAL 模式）。

---

## 13. SwiftAgentCore 复用接口

### 13.1 必须复用的核心模块

SwiftAgentCore 已经实现的引擎，必须在新 App 中复用，**不重新发明**：

| 模块 | 路径 | 用途 |
|------|------|------|
| **Agent 引擎** | `Sources/SwiftAgentCore/Agent/` | 主对话循环 + 工具调度 |
| **Skills 引擎** | `Sources/SwiftAgentCore/Skills/` | SKILL.md 加载 + 路由 |
| **MCP 引擎** | `Sources/SwiftAgentCore/MCP/` | MCP 服务器连接 + 工具注册 |
| **Tools 引擎** | `Sources/SwiftAgentCore/Tools/` | 文件读写 / shell / git 等工具 |
| **Hooks 系统** | `Sources/SwiftAgentCore/Hooks/` | 事件钩子 |
| **Storage** | `Sources/SwiftAgentCore/Storage/` | 持久化 |
| **Safety** | `Sources/SwiftAgentCore/Safety/` | 沙箱 + 权限 |
| **Workspace** | `Sources/SwiftAgentCore/Workspace/` | 工作区路径解析 |
| **Plugins** | `Sources/SwiftAgentCore/Plugins/` | 插件加载 |
| **State** | `Sources/SwiftAgentCore/State/` | 状态机 |

### 13.2 新增 SwiftAgentApp 模块

**目录结构**：

```
Sources/
├── SwiftAgentCore/         # 已有 - 复用
├── SwiftAgentCLI/          # 已有 - 复用
└── SwiftAgentApp/          # 新增 - SwiftUI macOS App
    ├── EntryPoint.swift     # @main App
    ├── Window/
    │   ├── MainWindow.swift
    │   └── WindowState.swift
    ├── Sidebar/
    │   ├── SidebarView.swift
    │   ├── ProjectListView.swift
    │   └── ThreadListView.swift
    ├── Content/
    │   ├── ContentView.swift
    │   ├── ThreadView.swift
    │   ├── MessageListView.swift
    │   └── ComposerView.swift
    ├── RightTabs/                        // v1.2 重命名：RightPanel → RightTabs（多 Tab 并存）
    │   ├── RightTabsView.swift            // Tab 栏 + 内容容器
    │   ├── RightTab.swift                 // 单个 Tab 数据模型
    │   ├── RightTabType.swift             // 5 种 panel 类型枚举
    │   ├── RightTabsStore.swift           // tabs 状态存储
    │   ├── TabBarView.swift               // 横向 tab 栏
    │   ├── TabLabel.swift                 // 单个 tab 标签
    │   ├── TabContentView.swift           // 内容分发（按 tab.type）
    │   ├── AddTabMenu.swift               // + 按钮弹出的菜单
    │   ├── EmptyTabPlaceholder.swift      // 无 tab 时的空状态
    │   ├── TabShortcutCommands.swift      // 全局快捷键 → 新建 Tab
    │   └── panels/
    │   │   ├── ReviewPanelView.swift      // Diff / hunk 列表
    │   │   ├── TerminalPanelView.swift    // PTY 内嵌终端
    │   │   ├── BrowserPanelView.swift     // WKWebView 内嵌浏览器
    │   │   ├── FilesPanelView.swift       // 文件树 + 内容查看
    │   │   └── SideChatPanelView.swift    // 旁路对话窗口
    ├── Modals/
    │   ├── EnvironmentPopover.swift       // 顶部 ⚙️+✓ 浮层（v1.1 实测完整字段）
    │   ├── ApprovalModal.swift
    │   ├── ModelPicker.swift
    │   ├── AddMenu.swift
    │   └── ThreadContextMenu.swift
    ├── Settings/
    │   ├── SettingsWindow.swift
    │   ├── GeneralSettings.swift
    │   ├── AppearanceSettings.swift
    │   ├── PersonalizationSettings.swift
    │   └── KeyboardShortcutsSettings.swift
    ├── DesignSystem/
    │   ├── Color.swift
    │   ├── Typography.swift
    │   ├── Spacing.swift
    │   ├── Radius.swift
    │   └── Components/
    │       ├── PillButton.swift
    │       ├── StatusDot.swift
    │       ├── Card.swift
    │       └── ...
    ├── DeepSeek/
    │   ├── DeepSeekClient.swift
    │   ├── DeepSeekConfig.swift
    │   ├── DeepSeekModels.swift
    │   └── KeychainStore.swift
    ├── Appshots/
    │   ├── AppshotCapture.swift
    │   ├── GlobalHotkey.swift
    │   └── AXTextExtractor.swift
    └── ViewModels/
        ├── AppViewModel.swift
        ├── ThreadViewModel.swift
        ├── ProjectViewModel.swift
        └── ComposerViewModel.swift
```

### 13.3 Package.swift 新增产物

```swift
// Package.swift 新增
let package = Package(
    name: "SwiftAgent",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "swift-agent", targets: ["SwiftAgentCLI"]),
        .library(name: "SwiftAgentCore", targets: ["SwiftAgentCore"]),
        .executable(name: "SwiftAgentApp", targets: ["SwiftAgentApp"]),  // 新增
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-collections", from: "1.0.0"),  // 新增 - 用于 Sidebar 性能
        .package(url: "https://github.com/kean/KeychainAccess", from: "4.2.0"),  // 新增 - API Key 存储
    ],
    targets: [
        .target(name: "SwiftAgentCore", path: "Sources/SwiftAgentCore"),
        .executableTarget(
            name: "SwiftAgentCLI",
            dependencies: ["SwiftAgentCore", .product(name: "ArgumentParser", package: "swift-argument-parser")],
            path: "Sources/SwiftAgentCLI"
        ),
        .executableTarget(  // 新增
            name: "SwiftAgentApp",
            dependencies: [
                "SwiftAgentCore",
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "KeychainAccess", package: "KeychainAccess"),
            ],
            path: "Sources/SwiftAgentApp"
        ),
        .testTarget(name: "SwiftAgentCoreTests", ...),
        .testTarget(name: "SwiftAgentAppTests", dependencies: ["SwiftAgentApp"], path: "Tests/SwiftAgentAppTests"),  // 新增
    ]
)
```

### 13.4 核心 API 调用示例

```swift
import SwiftAgentCore

// 1. 创建 Thread
let thread = try await agent.createThread(
    projectPath: "/Users/jim/forge",
    mode: .code,
    sandbox: .workspaceWrite,
    model: .deepseekChat
)

// 2. 发送消息
let stream = try await thread.sendMessage("帮我加单元测试")

for try await event in stream {
    switch event {
    case .token(let s):
        composerViewModel.appendToken(s)
    case .toolCall(let call):
        composerViewModel.showToolCall(call)
    case .toolResult(let result):
        composerViewModel.showToolResult(result)
    case .done:
        composerViewModel.markComplete()
    }
}

// 3. 加载 Skill
let skills = try await SkillsEngine.loadAll()
let matched = skills.filter { $0.matches(message: "加单元测试") }

// 4. 调用 MCP 工具
let result = try await MCPClient.invoke(tool: "git_diff", args: ["path": "src/"])
```

---

## 14. 沙箱与权限

### 14.1 三档沙箱

```swift
enum SandboxMode: String, CaseIterable, Codable {
    case readOnly = "read-only"               // 只能读
    case workspaceWrite = "workspace-write"   // 默认 - 只能写 workspace
    case fullAccess = "danger-full-access"     // 危险 - 完全访问
}
```

**每档配 `network_access` 开关**（默认 false）。

### 14.2 权限弹窗触发条件

| 操作 | 触发权限弹窗？ |
|------|---------------|
| 读 workspace 内文件 | ❌ |
| 写 workspace 内文件 | ❌（除非 readOnly 模式）|
| 读 workspace 外文件 | ✅ 询问 |
| 写 workspace 外文件 | ✅ 询问 |
| 联网（fetch） | ✅ 询问（默认禁）|
| 执行非内置 shell 命令 | ✅ 询问 |

### 14.3 实现

**复用 SwiftAgentCore 已有 Safety 模块**（`Sources/SwiftAgentCore/Safety/`）——**不重新发明**。

```swift
// 在 App 层只是把权限决定显示给用户
let decision = try await safetyEngine.requestApproval(
    action: .writeFile(path: "/tmp/foo.txt", content: "..."),
    sandbox: .workspaceWrite,
    projectPath: currentProject.path
)

switch decision {
case .approved:
    try await tool.execute()
case .denied(let reason):
    composerViewModel.showError("Permission denied: \(reason)")
}
```

### 14.4 项目级 rules

`/Users/jim/forge/.swiftagent/rules/` 目录：

```toml
# .swiftagent/rules/file-write.toml
[allow]
patterns = [
    "src/**/*.swift",
    "tests/**/*.swift",
    "*.md"
]

[deny]
patterns = [
    ".env",
    "**/secrets/**"
]
```

---

## 15. 可访问性

### 15.1 必做项

- **键盘可达**：所有交互必须能通过键盘完成
- **VoiceOver 支持**：每个交互元素都有 `accessibilityLabel`
- **动态字体**：支持 macOS 系统字号缩放
- **深色模式**：跟随系统（默认深色）
- **高对比度**：支持 macOS 增加对比度设置
- **减弱动效**：支持 macOS 减少动效设置

### 15.2 SwiftUI 实现

```swift
extension View {
    func a11yLabel(_ text: String) -> some View {
        self.accessibilityLabel(text)
            .accessibilityHint(Text("Press enter to activate"))
    }
}

// Composer 输入框
TextField("Ask for follow-up changes", text: $prompt)
    .a11yLabel("Send a message to SwiftAgent")
    .accessibilityAddTraits(.isKeyboardKey)
```

### 15.3 避免项

- ❌ 不要用纯颜色传达信息（必须配合 icon 或文字）
- ❌ 不要让动效成为必要交互
- ❌ 不要在小屏窗口里塞太多信息

---

## 16. 实现顺序（推荐 5 阶段）

### 16.1 阶段 1 — 骨架（1-2 周）

**目标**：能跑起来的空壳，看到 Codex App 的三栏布局。

- [ ] Package.swift 新增 SwiftAgentApp target
- [ ] EntryPoint.swift 写 `@main App` + 主 Window
- [ ] NavigationSplitView 三栏基础布局
- [ ] 设计 Color/Font 主题
- [ ] 左 Sidebar 显示空 Project 列表
- [ ] 中部 ContentView 显示 "Hello, SwiftAgent"
- [ ] 右侧 RightPanelView 显示 5 个空 entry（Review/Terminal/Browser/Files/Side chat）

**验收**：编译运行，看到三栏 UI + 深色配色

### 16.2 阶段 2 — DeepSeek 集成（1 周）

**目标**：能跟 DeepSeek V3 对话。

- [ ] DeepSeekConfig + Keychain 存储
- [ ] DeepSeekClient 实现 Chat Completions 流式响应
- [ ] 替换 SwiftAgentCore 的 LLMProvider
- [ ] Composer 4 控件（+ / Custom⌄ / 5.5 High⌄ / ↑）
- [ ] 简化的对话流（无 Skills / MCP）

**验收**：能发"你好" → 收到 DeepSeek V3 流式响应

### 16.3 阶段 3 — 多 Thread + 持久化（1-2 周）

**目标**：能开多 Thread，Thread 重启后还在。

- [ ] ThreadListView（Sidebar 列表）
- [ ] Thread 创建/重命名/归档
- [ ] SQLite 持久化（vapor/sqlite-kit）
- [ ] Project 管理
- [ ] Composer 输入框完整（slash command / 占位符 / 发送状态）

**验收**：开 3 个 Thread → 重启 App → 3 个 Thread 还在

### 16.4 阶段 4 — 高级功能（2 周）

**目标**：Skills / MCP / Worktree / Appshots 全部能跑。

- [ ] Skills 库 + 创建向导
- [ ] MCP 集成（复用 SwiftAgentCore 引擎）
- [ ] Worktree 隔离（git worktree 自动化）
- [ ] Appshots（Cmd+Cmd 全局快捷键 + 无障碍 API）
- [ ] Composer `+` 菜单完整 6 项

**验收**：跑通完整 SwiftAgent 体验

### 16.5 阶段 5 — 打磨（1-2 周）

**目标**：达到 Codex App 26.609 视觉与交互水准。

- [ ] 设置页完整（4 大类 13 标签）
- [ ] 完整快捷键表（25+ 条）
- [ ] 完整动效（SwiftUI 动画）
- [ ] 错误态 16 类
- [ ] a11y 完整
- [ ] 测试覆盖（Xcode UI Tests）

**验收**：可用性、稳定性、可访问性都达标

**总计**：约 7-10 周

---

## 17. 反例清单（Code Review 时必查）

| # | 反例 | 原因 |
|---|------|------|
| 1 | ❌ 不要做"5 档权限 pill" | 实测是 4 档 toggle，第 4 档在 Composer 弹窗 |
| 2 | ❌ 不要做"上下文使用量环形" | 实测未在 Composer 显示，hover 才出 |
| 3 | ❌ 不要做"逐行 Accept/Reject" | SwiftAgent 设计哲学是"AI 写完批量审" |
| 4 | ❌ 不要让右侧是"5 entry 互斥单选"系统（v1.1 错误） | 应该是"多 Tab 并存"（Chrome / VS Code 风格） |
| 5 | ❌ 不要做 Projects → Thread 以外的层级 | 不要加"工作空间" "文件夹"等中间层 |
| 6 | ❌ 不要让 Thread 列表显示圆点状态 | 用整行高亮 + 仅未读时蓝点 |
| 7 | ❌ 不要让键盘快捷键显示分组标题 | 连续扁平列表 |
| 8 | ❌ 不要让 Appshot 配置藏在 4 层菜单 | 设置 → Integrations → Appshots 独立入口 |
| 9 | ❌ 不要在 Project 切换时弹确认框 | sidebar 直接点击即切换 |
| 10 | ❌ 不要让"Custom"权限选项消失 | 默认勾选 |
| 11 | ❌ 不要让 AI 响应也带气泡 | 只用户消息带气泡 |
| 12 | ❌ 不要把状态行做成彩色 | 灰字小号 |
| 13 | ❌ 不要让 Z⌄ 按钮位置固定到右下角 | 应该在工具栏右侧 |
| 14 | ❌ 不要用 NSStatusBar（macOS 系统状态条）| 嵌在 Composer 内 |
| 15 | ❌ 不要做"全屏截图" | 只截当前窗口 |
| 16 | ❌ 不要让 Skills 库做成"插件市场" | Skill 是工作流模板 |
| 17 | ❌ 不要让 Project 显示"设置/成员" | Project 只是个文件夹 |
| 18 | ❌ 不要让 Thread 加"已读/未读"badge 之外的状态 | 视觉噪音 |
| 19 | ❌ 不要让 Edit 卡片跨页显示 | 必须能一键 Review |
| 20 | ❌ 不要做 macOS 系统弹窗 | 应用内 modal |
| 21 | ❌ 不要让 OpenAI 模型出现 | SwiftAgent 是 DeepSeek only |
| 22 | ❌ 不要让用户输入"自定义模型名" | 只列 4 个固定 DeepSeek 模型 |
| 23 | ❌ 不要让设置页是应用内弹窗 | 独立新窗口 |
| 24 | ❌ 不要 Light/Dark 共用 Accent | 两者独立可配 |
| 25 | ❌ 不要用 Material Design 风格 | 必须 macOS HIG + OpenAI 家族视觉语言 |

---

## 附录 A — 截图索引

**实测 12 张 26.609 真实截图**（基于 10 用户截图 + 2 我之前拉的）：

| # | 截图文件 | 显示内容 | 章节 |
|---|---------|---------|------|
| 1 | `截屏2026-06-15 22.15.48.png` | 默认主界面：Sidebar + Content + 右侧 5 entry + Environment 浮层（v1.1 修正截图）| §2.4 / §3.3 / §3.6 |
| 2 | `截屏2026-06-15 22.17.53.png` | Side chat entry 激活 + 新建 tab 下拉（v1.0 旧推断，v1.1 修正解读）| §3.3 |
| 3 | `截屏2026-06-15 22.29.24.png` | Composer `+` 菜单完整 6 项 + Plugins 子菜单 3 项 | §5.7 |
| 4 | `截屏2026-06-15 22.29.34.png` | 权限弹窗（"How should Codex actions be approved?"）| §5.4 |
| 5 | `截屏2026-06-15 22.29.40.png` | Composer `5.5 High⌄` 双层菜单（Reasoning × Model）| §5.7 |
| 6 | `截屏2026-06-15 22.29.56.png` | Open in 菜单（7 个应用：Cursor / Sublime / Zed / Finder / Terminal / Xcode / Android Studio）| §3.3 |
| 7 | `截屏2026-06-15 22.30.10.png` | Thread 上下文菜单（11 项 + 2 子菜单）| §3.5 |
| 8 | `截屏2026-06-15 22.30.26.png` | 设置页 → General（Work mode / Permissions / General 通用）| §10.9 |
| 9 | `截屏2026-06-15 22.30.42.png` | 设置页 → Appearance（Theme + Light/Dark 8 字段）| §10.9 |
| 10 | `截屏2026-06-15 22.31.36.png` | 设置页 → Personalization（Personality / Custom instructions / Memory）| §10.9 |
| 11 | `截屏2026-06-15 22.33.51.png` | 设置页 → Keyboard shortcuts 第一屏 | §6 |
| 12 | `截屏2026-06-15 22.34.03.png` | 设置页 → Keyboard shortcuts 第二屏 | §6 |

**截图存放位置**：
- 用户原图：`/Users/jim/Screenshots/截屏2026-06-15 *.png`
- 团队调研 16 张：原 Codex 官方 marketing + 社区评测（保存在 `/Users/jim/.mavis/plans/plan_97e5f0b2/outputs/track-*/screenshots/`）

---

## 附录 B — 复刻 Codex App 的 5 阶段 25 个反例对照表

**实现时按"先必做后可选"分 5 阶段**：

### B.1 阶段 1 — 必做骨架（v0.1）

1. ✅ 三栏布局（Sidebar / Content / Right Panel）
2. ✅ 深色模式配色（精确 hex）
3. ✅ Composer 4 控件（+ / Custom⌄ / 5.5 High⌄ / ↑）
4. ✅ 简化的对话流（无 Skills / MCP）
5. ✅ DeepSeek V3 单模型

### B.2 阶段 2 — 多 Thread（v0.2）

6. ✅ Sidebar 10+ Project 列表
7. ✅ Thread 创建/重命名/归档
8. ✅ SQLite 持久化
9. ✅ 5.5 High⌄ 双层菜单（DeepSeek 4 模型）
10. ✅ 完整 Composer 6 项 `+` 菜单

### B.3 阶段 3 — 高级功能（v0.3）

11. ✅ Skills 库（复用 SwiftAgentCore 引擎）
12. ✅ MCP 集成（复用 SwiftAgentCore 引擎）
13. ✅ Worktree 隔离（git worktree 自动化）
14. ✅ Appshots（Cmd+Cmd 全局快捷键）
15. ✅ 4 档沙箱权限（Ask / Approve / Full / Custom）

### B.4 阶段 4 — 打磨（v0.4）

16. ✅ 25+ 键盘快捷键
17. ✅ 设置页 4 大类 13 标签
18. ✅ 完整动效（SwiftUI 动画）
19. ✅ 16 类错误态
20. ✅ a11y 完整

### B.5 阶段 5 — 可选（v1.x）

21. ⚠️ 6 款岗位插件（v1.1 评估）
22. ⚠️ Computer Use（v1.1 评估）
23. ⚠️ Face ID 锁（v1.1）
24. ⚠️ Mobile 端（v1.2 独立 App）
25. ⚠️ 远程 SSH（v1.1 评估）

---

## 附录 C — 关键设计决策记录

| 决策 | 选项 | 选择 | 理由 |
|------|------|------|------|
| 模型 | OpenAI / Anthropic / DeepSeek | **DeepSeek** | 用户指定；BYOK；便宜 30-50 倍 |
| 框架 | SwiftUI / Electron / Tauri | **SwiftUI** | 现有 SwiftAgentCore 复用 |
| 状态存储 | SQLite / Core Data / 文件 | **SQLite** | 性能 + 易迁移 |
| 右侧栏框架 | 浏览器 tab / IDE tab / 入口 list | **5 entry 互斥单选 list** | Codex 26.609 范式 |
| 权限弹窗 | 系统 / 应用内 | **应用内 modal** | 不打断心流 |
| Vibrancy | 启用 / 关闭 | **启用 + 滑块** | 用户可调 |
| 主题切换 | Light / Dark / System | **System 默认** | 跟随 macOS |
| 审批档位 | 4 档 / 5 档 / 3 档 | **4 档** | 跟 Codex |
| 推理强度 | 4 档 / 3 档 | **4 档（映射 DeepSeek 模型）** | 跟 Codex |
| 模型选择 | OpenAI 家族 / DeepSeek | **DeepSeek 4 模型** | 跟用户 |

---

> **下一步建议**：
> 1. 把这份文档作为 `Sources/SwiftAgentApp/` 实现的唯一参考
> 2. 按 §16 的 5 阶段逐步实现，每阶段 1-2 周
> 3. 每阶段验收时对照 §17 的 25 条反例清单做 Code Review
> 4. v1.0 不做 §1.5 标注"v1.0 不做"的功能
> 5. 复用 SwiftAgentCore 全部已有引擎（§13）——这是最大优势
>
> ---
>
> **更新日志**：
> - **v1.0**（2026-06-15 23:00）：基于 Codex 调研指南 v1.3 完成主文档 18 章节 / ~35,000 字
> - **v1.1**（2026-06-15 23:20）：基于截图 `截屏2026-06-15 22.15.48.png` 重大修正右侧栏定义
>   - §2.1 ASCII 顶层布局图重绘（tab 栏 → 5 entry list）
>   - §2.4 标题与正文全面重写：从"右侧多 Tab 工作区"改为"右侧功能入口栏"
>   - §3.2 / §3.3 章节标题与 SwiftUI 代码重写：从 3 tab + 关闭/新建 改为 5 entry 互斥单选
>   - §6.3 "Tab / Panel 切换"改为"右侧功能入口栏 Panel 切换"，更新 9 个快捷键
>   - §13 文件结构 `RightTabs/` → `RightPanel/`（含 5 个 panel view 文件）
>   - §17 反例清单第 4 条改写：从"内容切换器" → "5 entry 互斥单选"
>   - §15 验收清单 + 附录 A 截图索引同步修正
>   - 全局替换"Tab"措辞残留（9 处）→ "Panel / 功能入口栏"
> - **v1.2**（2026-06-15 23:38）：用户反馈要把右侧改回多 Tab 并存，回退 v1.1 修正
>   - §0 文档导读追加 v1.2 修订说明
>   - §2.1 ASCII 顶层布局图右侧栏重绘（5 entry → Tab 栏 `[Review×][Terminal×][+]`）
>   - §2.4 标题与正文全面重写：从"右侧功能入口栏"改回"右侧多 Tab 工作区"
>   - §3.2 注释改为"detail 区域是多 Tab 并存工作区"
>   - §3.3 SwiftUI 代码全面重写：`RightPanel` 枚举 → `RightTabType` + `RightTab` 实例模型 + `RightTabsStore` 多 Tab 状态
>   - §6.3 章节标题改回"右侧多 Tab 工作区"，新增 ⌘W / tab 切换 / 移动 tab 等 6 个快捷键
>   - §13.2 文件结构 `RightPanel/` → `RightTabs/`（含 Tab 数据模型 / Store / Bar / Label 等）
>   - §17 反例清单第 4 条改回："不要做 5 entry 互斥单选"
