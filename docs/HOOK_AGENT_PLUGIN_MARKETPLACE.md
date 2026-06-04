# Hook / Agent / Plugin / Marketplace 扩展体系

> Claude Code 扩展体系的 Swift/Apple-platform 1:1 复刻设计 + 实施计划
>
> **范围**：Hooks · Agent（子代理）· Plugin · Marketplace
> **不在范围**：MCP · Skill（两者已有独立实现，见 [ARCHITECTURE.md](ARCHITECTURE.md)）
> **基线**：build 通过，0 warning；243 tests，1 个环境相关预存失败
> **最后更新**：2026-06-03

---

## 阅读指南

| 角色 | 重点章节 |
|------|----------|
| 维护者 / Reviewer | §1 状态总览 → §2 CC 对齐 → §7 路线图 |
| 实施者 | §3-§6 各子系统的「修复方案 / 实施步骤 / 验收」 |
| 写测试 | §10 核心测试路径 |
| 风险审 | §9 风险登记表 |

---

## 1. 状态总览（TL;DR）

| 子系统 | 代码量 | 完整度 | P0 阻塞项 | 测试覆盖 |
|--------|-------:|:------:|-----------|:--------:|
| **Hooks** | 1,521 行（2 文件） | 60% | 3 个 stub hook 类型未实现；22/27 事件无 dispatch；stdin JSON 缺字段 | 0 / 243 |
| **Plugins** | 719 行（1 文件） | 35% | 组件不注入到注册表；Git 安装/CLI 不存在；MCPB/LSP 框架空 | 0 / 243 |
| **Agent** | 1,074 行（5 文件） | 70% | 用户自定义文件加载不存在；Worktree 隔离未串通；subagent 生命周期 hook 不 dispatch | 25 / 243（仅 Phase11） |
| **Marketplace** | 0 行 | 5% | 远端 stub；政策检查未触发；错误类型已定义但无触发逻辑 | 0 / 243 |
| **合计** | ~4,100 行 | — | **4 个 P0 + 5 个 P1 + 5 个 P2** | 25 / 243 ≈ 10% |

**判定**：4 个 P0 全部修复后，扩展体系基本可用；P1/P2 是体验与覆盖面。

---

## 2. CC 对齐核对

> 参考实现：`~/CLI/claude-code/`（`utils/hooks.ts`、`utils/plugins/`、`services/plugins/PluginInstallationManager.ts`）
>
> 对齐策略：**协议层 100% 对齐**（事件清单、stdin JSON 字段、退出码语义、matcher 语法），**策略层 80% 对齐**（必要时本地化，但保留 CC 行为作为兜底）。

### 2.1 协议层

| 协议点 | CC 行为 | SwiftAgent 现状 | 对齐 |
|--------|---------|-----------------|:----:|
| HookEvent 数量 | 27 个 | 27 个（`HookEvent` 枚举） | ✅ |
| HookType 数量 | 6 个 | 6 个 | ✅ |
| command 协议：stdin JSON 字段 | `session_id, transcript_path, cwd, permission_mode, hook_event_name, hook_name, input[, agent_id, agent_type]` | 仅 `hook_event_name, hook_name, input` | ⚠️ |
| command 协议：退出码 | 0=继续, 2=阻塞, 其他=非阻塞 | 已实现 | ✅ |
| command 协议：stdout JSON | 解析 `decision, reason, systemMessage, ...` | 已实现（`HookJSONOutputDecodable`） | ✅ |
| http 协议：状态码 | 200=继续, 400=停止, 410=修改 | 已实现 | ✅ |
| prompt 协议：占位符 | `$ARGUMENTS`、`$ARGUMENTS[N]`、`$N` | 已实现 | ✅ |
| prompt 协议：无占位符时 | 追加 `ARGUMENTS: {args}` | 已实现 | ✅ |
| matcher 语法 | `*` 通配、`|` 分隔精确、正则 | 已实现 | ✅ |
| 优先级聚合 | blocking > stop > nonBlocking > modify > continue | 已实现 | ✅ |
| 并行执行 | sync hooks 通过 Promise.all 并行 | 已实现（`withTaskGroup`） | ✅ |
| once 语义 | dispatch 前自注销 | 已实现 | ✅ |
| async 语义 | 后台运行，不阻塞当前轮 | 已实现（`Task.detached`） | ✅ |
| asyncRewake 语义 | 后台运行，exit 2 唤醒模型 | 仅"和 async 一样运行"（注释承认） | ⚠️ |
| PluginManifest 字段 | 26 个 | 26 个 | ✅ |
| PluginComponent | 5 种 | 5 种 | ✅ |
| PluginError 变体 | 25 种 | 25 种（已定义） | ✅ |
| Agent 加载优先级 | project → user → built-in | 仅 hardcode built-in | ❌ |
| SubagentStart/Stop | dispatch hooks | 未 dispatch | ❌ |

### 2.2 策略层（明确本地化）

| 策略点 | CC 行为 | SwiftAgent 策略 |
|--------|---------|-----------------|
| HookSource 字段 | `userSettings, projectSettings, localSettings, policySettings, plugin, builtin` | 完整支持 |
| `disableAllHooks` | 完全禁用所有 hook | 已实现 |
| `allowManagedHooksOnly` | 仅允许 policy/managed | 已实现（仅匹配 `policySettings`） |
| Marketplace 远端发现 | Anthropic 后端 CDN | **本地化**：仅 stub + 清晰错误 |
| 插件 `git clone --depth 1` | 强制 depth=1 | 对齐 |
| 子代理 `isolation: worktree` | 创建临时 worktree | 串通 `WorktreeManager`（已存在） |

---

## 3. Hooks

### 3.1 现状

**完整**：
- 类型层（`HookJSONTypes.swift`，969 行）：27 个事件特定 Input、14+ 个事件特定 Output、BaseHookInput、HookJSONOutputDecodable
- 引擎层（`HookSystem.swift`，552 行）：dispatch 并行执行 + 优先级聚合 + matcher 解析 + 占位符替换 + command/http/prompt 三种 hook 执行
- 配置层：`loadFromSettings()` 支持 `disableAllHooks` / `allowManagedHooksOnly`
- 5 个 dispatch 调用点：`PreToolUse`（`QueryEngine.swift:274`）、`PostToolUse`（`QueryEngine.swift:295`）、`PostToolUseFailure`（`QueryEngine.swift:293`）、`Stop`（`QueryEngine.swift:461`）、`StopFailure`（`QueryEngine.swift:500`）

**缺口**：
1. **3 个 stub hook 类型**：`agent` / `callback` / `function` 全部 `return .continue`
2. **22 个事件无 dispatch**：除上述 5 个外，其余 22 个事件（`UserPromptSubmit, SessionStart/End, SubagentStart/Stop, Pre/PostCompact, PermissionRequest/Denied, Setup, ConfigChange, CwdChanged, FileChanged, InstructionsLoaded, WorktreeCreate/Remove, Notification, TeammateIdle, TaskCreated/Completed, Elicitation, ElicitationResult`）从不在 `HookSystem.dispatch()` 被调用
3. **stdin JSON 缺字段**：缺 `session_id, transcript_path, cwd, permission_mode[, agent_id, agent_type]`
4. **asyncRewake 不完整**：当前等价于 async，未实现"exit 2 唤醒模型"语义
5. **0 个测试**

### 3.2 修复方案

#### 3.2.1 P0 — 实现 3 个 stub hook 类型

`HookSystem.swift:326-336`，替换为：

```swift
// Agent hook — 委托给 SubAgentManager 跑 subagent
case .agent:
    guard let agentType = hook.prompt, !agentType.isEmpty else { return .continue }
    return await runAgentHook(
        agentType: agentType,
        hook: hook,
        input: input
    )

// Callback hook — 进程内闭包
case .callback:
    guard let callback = callbackRegistry[hook.id] else { return .continue }
    return await callback(input)

// Function hook — 静态查找表
case .function:
    guard let fn = functionRegistry[hook.id] else { return .continue }
    return fn(input)
```

需要新增：
- `HookSystem.callbackRegistry: [String: @Sendable (String) async -> HookResult]`
- `HookSystem.functionRegistry: [String: @Sendable (String) -> HookResult]`
- `HookSystem.runAgentHook()`：基于现有 `SubAgentManager.run()` 包装

#### 3.2.2 P0 — 22 个 dispatch 点

每个事件需要确定「调用点位置 + 输入数据来源 + 输出影响什么」。详见 §3.3 实施步骤表。

**协议约束**：
- `UserPromptSubmit`：可在 LLM 调用前修改 prompt（CC: `additionalContext` 注入）；SwiftAgent 暂存为 system message 注入
- `SessionStart` / `SessionEnd`：lifecycle 事件，输入为 session metadata；不影响主流程
- `PreCompact` / `PostCompact`：compactor 边界
- `PermissionRequest` / `PermissionDenied`：与 `PermissionEngine` 串通
- `Notification`：通用通知，输出流式追加即可
- `SubagentStart` / `SubagentStop`：`SubAgentManager.run()` 入口/出口
- `WorktreeCreate` / `WorktreeRemove`：`WorktreeManager` 入口/出口
- `ConfigChange`：`ConfigLoader.load()` 后
- `InstructionsLoaded`：`SystemPromptBuilder.build()` 后
- `CwdChanged` / `FileChanged`：暂以 setter / DispatchSource 触发
- `TeammateIdle` / `TaskCreated` / `TaskCompleted`：Team 模式存在后再串通（团队模式未启用时可 stub 为 `.continue`）
- `Elicitation` / `ElicitationResult`：MCP elicitation 流程存在后再串通

#### 3.2.3 P0 — 补全 stdin JSON 字段

`HookSystem.executeCommandHook()` 行 368 替换为：

```swift
let jsonInput: [String: Any] = [
    "session_id": sessionContext.sessionId,
    "transcript_path": sessionContext.transcriptPath,
    "cwd": sessionContext.cwd,
    "permission_mode": sessionContext.permissionMode,
    "hook_event_name": hook.event.rawValue,
    "hook_name": command,
    "input": input,
    "agent_id": sessionContext.agentId as Any? ?? NSNull(),
    "agent_type": sessionContext.agentType as Any? ?? NSNull(),
]
```

**`dispatch()` 方法签名扩展**为：

```swift
public struct HookDispatchContext: Sendable {
    public let sessionId: String
    public let transcriptPath: String
    public let cwd: String
    public let permissionMode: String
    public let agentId: String?
    public let agentType: String?
}

public func dispatch(
    event: HookEvent,
    input: String = "",
    context: HookDispatchContext = HookDispatchContext(...)
) async -> HookResult
```

向后兼容：所有现有 5 个 dispatch 调用点都填默认空 context（仅缺字段，不影响行为）。

#### 3.2.4 P1 — asyncRewake 完整语义

`HookSystem.swift:208-212`，拆分 async 和 asyncRewake：

```swift
for hook in asyncHooks where !hook.asyncRewake {
    Task.detached { [self] in _ = await self.executeHook(hook, input: input) }
}

for hook in asyncHooks where hook.asyncRewake {
    Task.detached { [self] in
        let result = await self.executeHook(hook, input: input)
        if case .blockingError(let reason) = result {
            // 通过 NotificationCenter / AppState 注入"任务完成"信号，
            // 让空闲时 useQueueProcessor 看到、忙碌时入队到当前 turn。
            await self.notifyAsyncRewake(hook: hook, reason: reason)
        }
    }
}
```

依赖：`AppState` 增加 `pendingAsyncRewakeNotifications: AsyncStream<String>`，由 ChatCommand 消费。

### 3.3 实施步骤

| Step | 文件 | 行 | 改动 | DoD |
|------|------|---|------|-----|
| H1 | `HookSystem.swift` | 1-15 | 新增 `HookDispatchContext` struct | `swift build` 通过 |
| H2 | `HookSystem.swift` | 175 | `dispatch()` 签名扩展 | 5 个现有调用点编译通过 |
| H3 | `HookSystem.swift` | 326-336 | 实现 agent / callback / function 三 case | 编译通过 |
| H4 | `HookSystem.swift` | 326 | 新增 `runAgentHook()` 方法 | 编译通过 |
| H5 | `HookSystem.swift` | 368-376 | 补全 stdin JSON 字段 | 编译通过 |
| H6 | `QueryEngine.swift` | 274, 293, 295, 461, 500 | 5 个调用点补充 `context` | 行为不变 |
| H7 | `ChatCommand` 各处 | — | 补 7 个 lifecycle 事件：UserPromptSubmit, SessionStart, SessionEnd, Notification, Setup, CwdChanged, InstructionsLoaded | 编译通过 |
| H8 | `SubAgentManager.swift` | 46, 102 | 补 SubagentStart / SubagentStop dispatch | 编译通过 |
| H9 | `Compactor.swift` | — | 补 PreCompact / PostCompact | 编译通过 |
| H10 | `PermissionEngine` | — | 补 PermissionRequest / PermissionDenied | 编译通过 |
| H11 | `ConfigLoader.swift` | — | 补 ConfigChange | 编译通过 |
| H12 | `WorktreeManager` | — | 补 WorktreeCreate / WorktreeRemove | 编译通过 |
| H13 | `HookSystem.swift` | 208-212 | 拆分 async / asyncRewake 语义 | 编译通过 |
| H14 | 新增 `Tests/SwiftAgentCoreTests/Phase13HookTests.swift` | — | 5 个核心测试（见 §10） | `swift test` 通过 |
| H15 | `HookSystem.swift` | 285-296 | 升级 `matchesPattern` 实际用 `.regularExpression` 选项做正则 | 已有，需 review |

### 3.4 验收

```bash
swift build --disable-sandbox         # 0 error, 0 warning
swift test --disable-sandbox --no-parallel --filter Phase13HookTests
```

- [ ] `HookSystem.dispatch()` 对 27 个事件全部可达（即使只是 `.continue`，不再静默丢弃）
- [ ] 3 个 stub hook 类型的最小可工作路径（agent → SubAgentManager；callback → 注册表查找；function → 静态查找）
- [ ] stdin JSON 包含 9 个字段（CC 完整对齐）
- [ ] asyncRewake 在 exit 2 时产生通知

---

## 4. Plugins

### 4.1 现状

**完整**：
- 类型层（`PluginManager.swift`，719 行）：`PluginManifest` 26 字段、`PluginComponent` 5 枚举、`PluginAuthor/Repository`、25 种 `PluginErrorType`、`StructuredPluginError` 详细上下文
- 加载层：`load(from:)` 解析 3 种 manifest 路径（`.claude-plugin/plugin.json` → `plugin.json` → `manifest.json`）、`scanPluginsDirectory()`、`createPluginFromPath()` 自动探测 5 个组件目录、`loadAllPlugins(from:)` 返回 `PluginLoadResult`
- 内置：`BuiltinPluginDefinition`、`BundledSkillDefinition` 框架
- 验证：`PluginManager.validate(_:)` 检查 name 非空且无空格

**缺口**：
1. **组件不注入**：`LoadedPlugin` 解析出的 commands / agents / skills / hooks 路径**只保存**，不写入 `CommandRegistry` / `HookSystem` / `AgentFileLoader` / `SkillFileLoader`
2. **Git 安装不存在**：无 `git clone` / `git pull` / `git rev-parse` 调用
3. **Plugin CLI 不存在**：`/plugins install/list/remove/update` 没有
4. **依赖解析不存在**：`dependencies` 字段被忽略
5. **政策检查不触发**：`marketplaceBlockedByPolicy` 错误类型已定义但无触发
6. **MCPB / LSP 框架空**：`mcpbDownloadFailed` 等错误类型已定义但无实现
7. **Bundled plugin 加载器不存在**：`BuiltinPluginDefinition` 框架在但没有真正"内置"任何插件
8. **0 个测试**

### 4.2 修复方案

#### 4.2.1 P0 — 组件注入

`PluginManager` 新增 `integrate(into:)` 方法，把 `LoadedPlugin` 的各组件写入运行时注册表：

```swift
public actor PluginManager {
    public func integrate(
        commandRegistry: inout CommandRegistry,
        hookSystem: inout HookSystem,
        agentRegistry: inout [String: AgentDefinition],
        skillRegistry: inout [SkillManifest]
    ) async throws {
        for plugin in loadedPlugins.values where plugin.enabled {
            try await integrateOne(
                plugin,
                commandRegistry: &commandRegistry,
                hookSystem: &hookSystem,
                agentRegistry: &agentRegistry,
                skillRegistry: &skillRegistry
            )
        }
    }

    private func integrateOne(
        _ plugin: LoadedPlugin,
        commandRegistry: inout CommandRegistry,
        hookSystem: inout HookSystem,
        agentRegistry: inout [String: AgentDefinition],
        skillRegistry: inout [SkillManifest]
    ) async throws {
        // Commands: load commands/*.md → FullCommand
        for path in plugin.commandsPaths ?? [] {
            guard let cmd = PluginCommandLoader.load(from: path, pluginName: plugin.name) else { continue }
            commandRegistry.register(cmd)
        }

        // Agents: load agents/*.md → AgentDefinition
        for path in plugin.agentsPaths ?? [] {
            guard let agent = PluginAgentLoader.load(from: path, pluginName: plugin.name) else { continue }
            agentRegistry[agent.name] = agent
        }

        // Skills: load skills/<name>/SKILL.md → SkillManifest
        for path in plugin.skillsPaths ?? [] {
            guard let manifest = PluginSkillLoader.load(from: path) else { continue }
            skillRegistry.append(manifest)
        }

        // Hooks: parse plugin.hooksConfig → HookEntry, register
        if let hooksConfig = plugin.hooksConfig {
            for entry in PluginHookLoader.parse(hooksConfig, source: .plugin) {
                await hookSystem.register(entry)
            }
        }

        // MCP servers: load to MCPManager (defer to MCP team)
        // LSP servers: deferred (no LSPManager yet)
    }
}
```

**关键约束**：
- `integrate()` 必须在 `ChatCommand.startup` 中、所有 dispatcher 启动前调用一次
- 命名空间策略：plugin 提供的 command/skill 使用 `<pluginName>:<commandName>` 命名空间（对齐 CC `loadPluginCommands.ts:getCommandNameFromFile()`）
- 已存在的同名 built-in 命令不被 plugin 覆盖（CC: built-in 优先级最高）

#### 4.2.2 P0 — 命名空间策略

`CommandRegistry.register()` 检查：
- 如果是 built-in（同 name 已在 built-in 集合）→ 跳过 + 记录 warning
- 如果是 user-defined → 直接注册
- 如果是 plugin → 加上 `<pluginName>:` 前缀

**对应源文件改动**：
- `CommandRegistry.swift`：增加 `register(_ command: FullCommand, source: CommandSource)` 重载
- 新增 `CommandSource` 枚举：`builtIn / userDefined / plugin(pluginName)`
- `PluginCommandLoader.load()` 返回 `(FullCommand, CommandSource)`

#### 4.2.3 P1 — Git 安装引擎

新增 `Sources/SwiftAgentCore/Plugins/PluginInstaller.swift`：

```swift
public actor PluginInstaller {
    private let fm = FileManager.default
    private let shell = ShellRunner()  // 或 Process() 包装

    public static var defaultPluginsDir: String {
        "\(NSHomeDirectory())/.claude/plugins"
    }

    public func install(
        repository: String,
        name: String? = nil,
        branch: String? = nil
    ) async throws -> LoadedPlugin {
        let pluginName = name ?? URL(string: repository)?.lastPathComponent
            ?? UUID().uuidString
        let target = URL(fileURLWithPath: Self.defaultPluginsDir)
            .appendingPathComponent(pluginName)

        try fm.createDirectory(at: target.deletingLastPathComponent(),
                               withIntermediateDirectories: true)

        try await shell.run(
            "git",
            ["clone", "--depth", "1"]
                + (branch.map { ["--branch", $0] } ?? [])
                + [repository, target.path]
        )

        let manager = PluginManager()
        return try manager.createPluginFromPath(target, source: "user")
    }

    public func update(name: String) async throws {
        let path = URL(fileURLWithPath: Self.defaultPluginsDir)
            .appendingPathComponent(name)
        try await shell.run("git", ["-C", path.path, "pull", "--ff-only"])
    }

    public func remove(name: String) throws {
        let path = URL(fileURLWithPath: Self.defaultPluginsDir)
            .appendingPathComponent(name)
        try fm.removeItem(at: path)
    }

    public func list() throws -> [String] {
        let url = URL(fileURLWithPath: Self.defaultPluginsDir)
        return (try fm.contentsOfDirectory(atPath: url.path))
            .filter { !$0.hasPrefix(".") }
    }
}
```

**依赖**：可复用一个最小的 `ShellRunner`（或直接用 `Process`）。建议新建 `Sources/SwiftAgentCore/Util/Shell.swift`。

#### 4.2.4 P1 — Plugin CLI

新增 `Sources/SwiftAgentCLI/PluginsCommand.swift`，注册到 `ChatCommand+Commands.swift` 的 slash command 列表：

| 子命令 | 行为 | 对应 `PluginInstaller` 方法 |
|--------|------|---------------------------|
| `/plugins list` | 列出 `~/.claude/plugins/` 子目录 | `list()` |
| `/plugins install <repo> [name]` | git clone + integrate | `install()` |
| `/plugins update [name]` | git pull（全空则全量更新） | `update()` |
| `/plugins remove <name>` | 物理删除 + 从运行时卸载 | `remove()` |
| `/plugins enable <name>` | 标记 enabled=true，重新 integrate | — |
| `/plugins disable <name>` | 标记 enabled=false，运行时反注册 | — |

**对 AgentTool 的影响**：`AgentTool.call()` 第 97 行 `BuiltInAgents.resolve()` → 改为 `AgentFileLoader.resolve(subagentType)` 合并结果。

#### 4.2.5 P1 — 依赖解析

```swift
// PluginLoader 阶段
for plugin in discovered {
    if let deps = plugin.manifest.dependencies {
        for dep in deps {
            guard loadedPlugins[dep] != nil else {
                errors.append(StructuredPluginError(
                    type: .dependencyUnsatisfied,
                    source: "scanner",
                    plugin: plugin.name,
                    dependency: dep,
                    dependencyReason: "not-enabled"
                ))
                continue outer
            }
        }
    }
}
```

#### 4.2.6 P1 — Bundled plugin 加载

新建 `Sources/SwiftAgentCore/Plugins/BundledPluginRegistry.swift`：

```swift
public enum BundledPluginRegistry {
    /// 从 SwiftPackage 资源或 `~/.claude/bundled-plugins/` 加载内置插件清单
    public static func loadAll() -> [LoadedPlugin] {
        // 1. 检查 package resource 目录
        // 2. 检查用户级 bundled 目录
        // 3. 返回 LoadedPlugin 数组，isBuiltin = true
    }
}
```

### 4.3 实施步骤

| Step | 文件 | 改动 | DoD |
|------|------|------|-----|
| P1 | `PluginManager.swift` | 新增 `integrate(into:)` 方法 | 编译通过 |
| P2 | 新建 `Sources/SwiftAgentCore/Plugins/PluginCommandLoader.swift` | 解析 commands/*.md frontmatter | 编译通过 |
| P3 | 新建 `Sources/SwiftAgentCore/Plugins/PluginAgentLoader.swift` | 解析 agents/*.md frontmatter | 编译通过 |
| P4 | 新建 `Sources/SwiftAgentCore/Plugins/PluginSkillLoader.swift` | 复用 SkillYAMLParser | 编译通过 |
| P5 | 新建 `Sources/SwiftAgentCore/Plugins/PluginHookLoader.swift` | 把 hooksConfig 字典 → [HookEntry] | 编译通过 |
| P6 | `CommandRegistry.swift` | 增加 `CommandSource`、register 重载 | 编译通过 |
| P7 | `ChatCommand` startup | 在 dispatcher 启动前调用 `pluginManager.integrate()` | 编译通过 |
| P8 | 新建 `Sources/SwiftAgentCore/Util/Shell.swift` | 包装 Process 异步执行 | 编译通过 |
| P9 | 新建 `Sources/SwiftAgentCore/Plugins/PluginInstaller.swift` | install/update/remove/list | 编译通过 |
| P10 | 新建 `Sources/SwiftAgentCLI/PluginsCommand.swift` | 6 个子命令 | 编译通过 |
| P11 | `Sources/SwiftAgentCore/Agent/AgentFileLoader.swift` | 见 §5.2.1 | 编译通过 |
| P12 | `AgentTool.swift:97` | 改用 `AgentFileLoader.resolve()` | 编译通过 |
| P13 | 新建 `Tests/SwiftAgentCoreTests/Phase13PluginTests.swift` | 4 个核心测试（见 §10） | 测试通过 |
| P14 | `PluginManager.swift:621` | integrate 前做依赖解析 | 编译通过 |
| P15 | 新建 `Sources/SwiftAgentCore/Plugins/BundledPluginRegistry.swift` | 内置插件加载 | 编译通过 |

### 4.4 验收

```bash
swift build --disable-sandbox
swift test --disable-sandbox --no-parallel --filter Phase13PluginTests
# 手动：
# 1. 准备一个测试 plugin: ~/.claude/plugins/test-plugin/{plugin.json,commands/hello.md,agents/foo.md}
# 2. 启动 swift-agent chat
# 3. /plugins list  → 看到 test-plugin
# 4. /help          → 看到 test-plugin:hello
# 5. 用 Agent tool 选 foo 类型 → 加载到
```

- [ ] 一个测试 plugin 从磁盘被加载到 `CommandRegistry` / `AgentFileLoader` / `SkillFileLoader` / `HookSystem`
- [ ] `/plugins install` 从 git URL 拉取到 `~/.claude/plugins/`
- [ ] 同名 built-in 命令不被 plugin 覆盖
- [ ] plugin 提供的 command 名称带 `<pluginName>:` 前缀

---

## 5. Agent

### 5.1 现状

**完整**：
- 类型层（`Agent.swift`，249 行）：`AgentDefinition` 30 字段、`AgentRole` 枚举（5 种）、`AgentMemoryScope`（3 种）、`AgentMcpServerSpec`、`AgentContext`
- 工具层（`AgentTool.swift`，287 行）：完整 schema、参数解析、sync/background 两条路径、事件转发
- 管理器（`SubAgentManager.swift`，304 行）：`run()` / `startBackground()` / `effectiveTools()` 过滤
- 6 个内置代理（`BuiltInAgents.swift`，232 行）：general-purpose / Explore / Plan / verification / claude-code-guide / statusline-setup
- Worktree 基础设施（`WorktreeManager.swift`）：已存在，未被 SubAgentManager 使用
- 测试：25 个（Phase11SubAgentTests），但只覆盖 SubAgent 流程，不覆盖 Hook/Plugin/Worktree 集成

**缺口**：
1. **用户自定义文件加载不存在**：`AgentTool.swift:97` 硬编码 `BuiltInAgents.resolve()`，没扫描 `~/.claude/agents/` 和 `.claude/agents/`
2. **Worktree 隔离未串通**：`isolation: "worktree"` 参数在 schema 中存在但 `SubAgentManager.run()` 不调用 `WorktreeManager`
3. **subagent 生命周期 hook 不 dispatch**：`SubAgentStart` / `SubagentStop` 缺失
4. **Memory 持久化不存在**：`AgentMemoryScope` 类型已定义但 `MemoryStore` 未连接
5. **Team 协调不存在**：`teamName` schema 已声明但无团队路由

### 5.2 修复方案

#### 5.2.1 P1 — 用户自定义文件加载

新建 `Sources/SwiftAgentCore/Agent/AgentFileLoader.swift`：

```swift
public struct AgentFileLoader {
    public static let userAgentsDir: String = {
        "\(NSHomeDirectory())/.claude/agents"
    }()
    public static let projectAgentsRelativePath = ".claude/agents"

    /// 加载所有代理（project → user → built-in 优先级）
    public static func loadAllDefinitions(
        workingDirectory: String
    ) -> [AgentDefinition] {
        var seen: Set<String> = []
        var result: [AgentDefinition] = []

        // 1. 项目代理（最高优先级）
        let projectDefs = loadDefinitions(
            from: "\(workingDirectory)/\(projectAgentsRelativePath)",
            source: .project
        )
        for d in projectDefs where seen.insert(d.name).inserted { result.append(d) }

        // 2. 用户代理
        let userDefs = loadDefinitions(
            from: userAgentsDir,
            source: .user
        )
        for d in userDefs where seen.insert(d.name).inserted { result.append(d) }

        // 3. 内置代理（最低优先级）
        for (_, builtin) in BuiltInAgents.all {
            if seen.insert(builtin.name).inserted { result.append(builtin) }
        }
        return result
    }

    private static func loadDefinitions(
        from directory: String,
        source: AgentSource
    ) -> [AgentDefinition] {
        // 扫描 directory 下每个子目录或 .md 文件
        // - agent.json (JSON 格式)
        // - AGENT.md (YAML frontmatter + Markdown body)
        // 返回 [AgentDefinition]
    }

    /// 主入口：解析 + 去重 + 返回字典
    public static func resolveRegistry(
        workingDirectory: String
    ) -> [String: AgentDefinition] {
        var dict: [String: AgentDefinition] = [:]
        for d in loadAllDefinitions(workingDirectory: workingDirectory) {
            dict[d.name] = d
        }
        return dict
    }
}
```

**与 `AgentTool` 集成**：
```swift
// AgentTool.swift:97 改造
let registry = AgentFileLoader.resolveRegistry(
    workingDirectory: context.workingDirectory
)
guard let definition = registry[subagentType]
    ?? BuiltInAgents.resolve(subagentType) else {
    return ToolResult(content: "Unknown agent type \"\(subagentType)\"", isError: true)
}
```

**YAML frontmatter 解析**：
- 复用现有 `SkillYAMLParser`（`Sources/SwiftAgentCore/Skill/SkillYAMLParser.swift`），扩展支持 AgentDefinition 字段
- 若 parser 不接受当前字段，**降级**为 substring match（与 Hook matcher 现状一致）

#### 5.2.2 P1 — Worktree 隔离串通

`SubAgentManager.run()` 入口处：

```swift
public func run(
    definition: AgentDefinition,
    input: String,
    context: AgentContext,
    state: AppState,
    tools: [ToolDefinition]? = nil,
    worktreeManager: WorktreeManager? = nil,  // 新增
    onEvent: ((StreamingQueryEvent) -> Void)? = nil
) async throws -> SubAgentResult {
    var workingContext = context
    var createdWorktreePath: String? = nil

    // 串通 isolation: "worktree"
    if definition.isolation == "worktree" {
        let manager = worktreeManager ?? WorktreeManager(
            workingDirectory: context.workingDirectory
        )
        let worktreePath = try await manager.create(
            branch: "agent-\(UUID().uuidString.prefix(8))",
            base: nil
        )
        createdWorktreePath = worktreePath
        workingContext.workingDirectory = worktreePath

        // dispatch WorktreeCreate hook
        // ...
    }

    defer {
        if let path = createdWorktreePath {
            Task {
                try? await worktreeManager?.remove(path: path)
                // dispatch WorktreeRemove hook
            }
        }
    }

    // ... 原有 run 逻辑，使用 workingContext
}
```

**约束**：
- Worktree 失败应该 `throw` 而不是 `.continue`（CC: hard error）
- `defer` 清理必须在 result/throw 都跑

#### 5.2.3 P1 — Subagent 生命周期 hook

`SubAgentManager.run()` 第 46 行 + 第 100 行加 dispatch：

```swift
let startTime = Date()
await hookSystem?.dispatch(
    event: .subagentStart,
    input: definition.name,
    context: hookContext
)
defer {
    Task {
        await hookSystem?.dispatch(
            event: .subagentStop,
            input: definition.name,
            context: hookContext
        )
    }
}
```

**依赖**：§3.2.2 的 `HookSystem.dispatch()` 签名扩展。

#### 5.2.4 P3 — Memory 持久化

延迟实现：当前 `AgentMemoryScope` 是占位类型，CC 的 memory 持久化与 Hook/Plugin 体系弱耦合（独立组件）。本轮不做。

#### 5.2.5 P3 — Team 协调

延迟实现：CC 的 Team 模式涉及跨进程消息总线（Mailbox / Inbox），本项目无对应基础设施。

### 5.3 实施步骤

| Step | 文件 | 改动 | DoD |
|------|------|------|-----|
| A1 | 新建 `Agent/AgentFileLoader.swift` | 三级加载 + 解析 | 编译通过 |
| A2 | 扩展 `SkillYAMLParser.swift` | 支持 AgentDefinition frontmatter | 编译通过 |
| A3 | `AgentTool.swift:97` | 改用 `AgentFileLoader.resolveRegistry()` | 编译通过 |
| A4 | `SubAgentManager.swift:46` | 增加 `worktreeManager` 参数 + isolation 串通 | 编译通过 |
| A5 | `SubAgentManager.swift:46, 102` | SubagentStart / SubagentStop dispatch | 编译通过 |
| A6 | `AgentTool.swift:77` | 调用 manager 时传入 hookSystem 和 worktreeManager | 编译通过 |
| A7 | 新增 `Tests/SwiftAgentCoreTests/Phase13AgentTests.swift` | 3 个核心测试 | 测试通过 |

### 5.4 验收

```bash
swift build --disable-sandbox
swift test --disable-sandbox --no-parallel --filter "Phase13AgentTests|Phase11SubAgentTests"
# 手动：
# 1. 在 .claude/agents/foo/agent.json 放一个自定义 agent
# 2. swift-agent chat → Agent tool → subagentType=foo
# 3. 应加载到该 agent
# 4. Agent tool 调用 isolation=worktree → 应在 /tmp/<branch> 下有 worktree
```

- [ ] `~/.claude/agents/foo/AGENT.md` 中的自定义 agent 可被 `Agent tool` 调用
- [ ] `.claude/agents/foo/agent.json` 同上
- [ ] `isolation: "worktree"` 真的在临时 worktree 中运行
- [ ] `SubagentStart` / `SubagentStop` hook 被 dispatch

---

## 6. Marketplace

### 6.1 现状

**完整**：25 个 `PluginErrorType` 变体已定义（含 `marketplaceBlockedByPolicy`, `marketplaceNotFound`, `marketplaceLoadFailed`）。

**缺口**：除错误类型外，**完全空白**。无配置、无发现、无客户端。

**本地化判断**：CC 的 Marketplace 严重依赖 Anthropic 后端（CDN / 搜索服务 / 政策服务器）。SwiftAgent 作为本地 CLI，**完整复刻无业务价值**。本轮只做"基础类型 + 清晰错误"。

### 6.2 修复方案

#### 6.2.1 P2 — 配置字段

`PluginConfig.swift` 扩展：

```swift
public struct PluginConfig: Sendable, Codable {
    public let repositories: [String: PluginRepository]
    public let marketplaces: [String: MarketplaceConfig]
    public let policy: MarketplacePolicy?

    public init(
        repositories: [String: PluginRepository] = [:],
        marketplaces: [String: MarketplaceConfig] = [:],
        policy: MarketplacePolicy? = nil
    ) {
        self.repositories = repositories
        self.marketplaces = marketplaces
        self.policy = policy
    }
}

public struct MarketplaceConfig: Sendable, Codable {
    public let url: String
    public let enabled: Bool
    public let trust: TrustLevel  // .official / .verified / .unverified
    public init(url: String, enabled: Bool = true, trust: TrustLevel = .unverified) {
        self.url = url
        self.enabled = enabled
        self.trust = trust
    }
}

public enum TrustLevel: String, Sendable, Codable {
    case official      // anthropic 官方
    case verified      // 已签名验证
    case unverified    // 信任用户
}

public struct MarketplacePolicy: Sendable, Codable {
    public let blockedMarketplaces: [String]
    public let allowedMarketplaces: [String]?  // nil = 全部允许
    public let requireVerified: Bool
}
```

#### 6.2.2 P2 — 政策检查（集成到 PluginInstaller）

`PluginInstaller.install()` 入口：

```swift
public func install(
    repository: String,
    name: String? = nil,
    config: PluginConfig
) async throws -> LoadedPlugin {
    // 1. 政策检查
    if let policy = config.policy {
        if policy.blockedMarketplaces.contains(repository) {
            throw StructuredPluginError(
                type: .marketplaceBlockedByPolicy,
                source: "installer",
                marketplace: repository,
                blockedByBlocklist: true
            )
        }
        if let allowed = policy.allowedMarketplaces,
           !allowed.contains(repository) {
            throw StructuredPluginError(
                type: .marketplaceBlockedByPolicy,
                source: "installer",
                marketplace: repository,
                allowedSources: allowed
            )
        }
    }

    // 2. 安装
    return try await install(repository: repository, name: name)
}
```

#### 6.2.3 P3 — 客户端 stub（可选）

`MarketplaceClient.swift` 仅提供 URL 解析 + 错误抛出：

```swift
public actor MarketplaceClient {
    public init(config: PluginConfig) {}

    /// 列出 marketplace 中可用插件。本地后端未配置时抛 marketplaceLoadFailed。
    public func listAvailable(in marketplace: String) async throws -> [MarketplacePlugin] {
        throw StructuredPluginError(
            type: .marketplaceLoadFailed,
            source: "client",
            marketplace: marketplace,
            reason: "Marketplace remote discovery requires Anthropic backend, which is not configured in this build."
        )
    }
}
```

### 6.3 实施步骤

| Step | 文件 | 改动 | DoD |
|------|------|------|-----|
| M1 | `PluginConfig` / `MarketplaceConfig` / `MarketplacePolicy` | 新类型 | 编译通过 |
| M2 | `PluginInstaller.install()` | 加 policy 检查 | 编译通过 |
| M3 | 新增 `Sources/SwiftAgentCore/Plugins/MarketplaceClient.swift` | stub + 错误抛出 | 编译通过 |
| M4 | `ChatCommand+Config` 启动时初始化 `MarketplaceClient` | — | 编译通过 |

### 6.4 验收

- [ ] `settings.json` 中 `pluginConfig.marketplaces` 字段被解析
- [ ] 配置 `policy.blockedMarketplaces = ["evil"]` 时，`/plugins install evil/repo` 抛 `marketplaceBlockedByPolicy` 错误
- [ ] 调用 `MarketplaceClient.listAvailable()` 时返回清晰错误（不是 fatal）

---

## 7. 实施路线图

> 阶段划分原则：**先打通管道，再补体验，最后做覆盖**。
> 阶段间存在依赖：H 必须在 P 之前（A 依赖 H 的 dispatch 扩展）。

```
Phase 0: 文档基线                    ◀── 你在这里
   └─ 写完本文档，与 reviewer 达成一致

Phase 1: Hooks 引擎打通（必做）       估算 4-6 小时
   ├─ H1-H2: HookDispatchContext + dispatch 签名扩展
   ├─ H3-H5: 3 个 stub hook 类型 + stdin JSON 字段
   ├─ H6: 5 个现有 dispatch 点补 context
   ├─ H7-H12: 22 个新 dispatch 点（按文件分组并行）
   └─ H14: Phase13HookTests

Phase 2: Plugins 组件注入（必做）     估算 3-4 小时
   ├─ P1-P6: PluginManager.integrate + 4 个 Loader + CommandRegistry 改造
   ├─ P7: ChatCommand startup 串通
   └─ P13: Phase13PluginTests

Phase 3: Agent 集成（推荐）           估算 2-3 小时
   ├─ A1-A3: AgentFileLoader
   ├─ A4: Worktree 串通
   ├─ A5-A6: Subagent 生命周期 hook（依赖 Phase 1 的 dispatch 扩展）
   └─ A7: Phase13AgentTests

Phase 4: Marketplace stub（可推迟）   估算 1 小时
   └─ M1-M4

Phase 5: 测试覆盖（可推迟）           估算 4-6 小时
   ├─ Hooks 边界 / async / once
   ├─ Plugin command/skills 命名空间 / 冲突优先级
   └─ Agent isolation / 文件加载失败降级
```

**总工作量估算**：14-20 小时（4 个 P0 + 5 个 P1 + 5 个 P2）

---

## 8. 验证 checklist

> 每个阶段完成前必跑。

### 8.1 通用基线

```bash
cd /Users/jim/SwiftAgent
swift build --disable-sandbox         # 必须 0 error, 0 warning
swift test --disable-sandbox --no-parallel  # 必须 243 通过（1 个预存失败不变）
```

### 8.2 Phase 1（Hooks）

```bash
# 单元测试
swift test --disable-sandbox --no-parallel --filter Phase13HookTests

# 手测：command hook 端到端
cat > /tmp/test-hook.sh <<'EOF'
#!/bin/bash
cat > /dev/null  # consume stdin
echo '{"continue": true, "systemMessage": "hooked!"}'
exit 0
EOF
chmod +x /tmp/test-hook.sh
# 编辑 settings.json 加上：
# { "hooks": { "Stop": [{ "type": "command", "command": "/tmp/test-hook.sh" }] } }
swift-agent chat
# → 用户发送 "hi" → 退出前看到 "hooked!"
```

### 8.3 Phase 2（Plugins）

```bash
swift test --disable-sandbox --no-parallel --filter Phase13PluginTests

# 手测：加载测试 plugin
mkdir -p ~/.claude/plugins/test-plugin/commands
cat > ~/.claude/plugins/test-plugin/.claude-plugin/plugin.json <<'EOF'
{"name": "test-plugin", "version": "0.1.0"}
EOF
cat > ~/.claude/plugins/test-plugin/commands/hello.md <<'EOF'
---
description: "Test hello command"
---
Hello from test-plugin!
EOF
swift-agent chat
/help | grep test-plugin:hello   # 应输出匹配
```

### 8.4 Phase 3（Agent）

```bash
swift test --disable-sandbox --no-parallel --filter "Phase13AgentTests|Phase11SubAgentTests"

# 手测：自定义 agent
mkdir -p .claude/agents/foo
cat > .claude/agents/foo/AGENT.md <<'EOF'
---
name: foo
description: "Test custom agent"
tools: [Read, Grep]
---
You are foo.
EOF
swift-agent chat
# 让主 agent 调 Agent tool，subagentType=foo
# → 应加载到自定义 agent（系统提示包含 "You are foo."）
```

### 8.5 Phase 4（Marketplace）

```bash
swift test --disable-sandbox --no-parallel --filter Phase13MarketplaceTests

# 手测：policy 阻止
# 设置 policy.blockedMarketplaces = ["evil"]
swift-agent chat
/plugins install evil/some-repo
# → 错误：Marketplace 'evil/some-repo' is blocked by enterprise policy
```

---

## 9. 风险登记表

| ID | 风险 | 影响 | 缓解 |
|----|------|------|------|
| R1 | `dispatch()` 签名扩展会破坏现有 5 个调用点 | 编译失败 | 扩展加默认值；同步 5 个调用点（Step H6） |
| R2 | Plugin integrate 时若 `LoadedPlugin` 内部路径已失效（用户手动删除） | 启动崩溃 | 加载失败降级为 `PluginLoadResult.errors`，**不 throw** |
| R3 | Worktree 创建需要 git 环境 | CI / 沙箱失败 | `WorktreeManager.create()` 内部检查 git 存在性，失败 → `.continue` + 日志 |
| R4 | `asyncRewake` 实现需要 `AppState` 增加通知流，影响 CLI 流式渲染 | 流式 UI 闪烁 | 先复用现有 `appendStreamingOutput`，**不**引入新流 |
| R5 | Plugin YAML parser 复用 SkillYAMLParser，可能引入 Skill 专属 schema 校验 | Agent 加载失败 | Loader 内部 catch 解析错误并降级为系统提示注入 |
| R6 | 22 个新增 dispatch 点中部分（Elicitation/TeammateIdle）依赖未实现的子系统 | 调用永远返回 `.continue` 但产生噪音 | 在对应子系统未实现前，**不**加 dispatch（仅占位为 TODO 注释） |
| R7 | Hook 协议补全字段后，外部 hook 脚本依赖旧字段 | 兼容性 | CC 兼容脚本只读子集，缺字段不报错；不写破坏性变更 |
| R8 | `Integrate` 在 `ChatCommand.startup` 调用，重复启动会重复注入 | 内存泄漏 | `loadedPlugins` 是 actor 内部状态，加 `integrated: Set<String>` 防重 |
| R9 | subagent dispatch hook 时若有 hook 阻塞，会卡住主循环 | 主循环挂死 | subagentStart 接受 `.blockingError` 立即 throw（CC 行为） |
| R10 | `~/.claude/plugins/` 默认目录权限 | 多人系统 | 跳过权限检查，依赖 fs 行为；文档告知用户 |

---

## 10. 核心测试路径

> 「只为核心路径写测试」约束下，下表是**最小覆盖集**。
> 每个测试 ≤ 30 行；总目标 ~15 个 `@Test` 覆盖关键决策点。

### 10.1 Hooks（5 个 @Test）

| 测试 | 验证 | 输入 | 期望 |
|------|------|------|------|
| `dispatchAggregatesBlockingOverContinue` | 优先级聚合 | 2 个 hook，一个 `.continue`、一个 `.blockingError("x")` | 返回 `.blockingError("x")` |
| `dispatchRunsSyncHooksInParallel` | 并行执行 | 3 个 1s sleep hook + 时间戳 | 总时长 < 1.5s |
| `commandHookParsesStdoutJSON` | JSON 输出解析 | 进程输出 `{"continue": true, "systemMessage": "x"}` | 返回 `.continue` 且不显示 fallback |
| `commandHookExitCodeTwo` | 退出码协议 | 进程 `exit 2` | 返回 `.blockingError` |
| `matcherRegex` | matcher 正则 | matcher=`"Wri.*"`, input="Write" | 命中 |

### 10.2 Plugins（4 个 @Test）

| 测试 | 验证 | 输入 | 期望 |
|------|------|------|------|
| `integrateAddsCommandToRegistry` | 命令注入 | fake plugin with `commands/hello.md` | `CommandRegistry` 含 `test-plugin:hello` |
| `integrateRespectsBuiltInPriority` | 优先级 | built-in 有 `hello`，plugin 也有 `hello` | 注册表保留 built-in，plugin 被跳过 + warning |
| `integrateRegistersHook` | hook 注入 | fake plugin with `hooksConfig` | `HookSystem.listAll()` 包含 `source: .plugin` 的 hook |
| `loadAllPluginsFromFixtureDir` | 目录扫描 | 临时目录 + 2 个子目录 | 返回 2 个 manifest |

### 10.3 Agent（3 个 @Test）

| 测试 | 验证 | 输入 | 期望 |
|------|------|------|------|
| `agentFileLoaderPrioritizesProject` | 加载顺序 | project + user 都有 `foo` | 返回 project 版本 |
| `subagentManagerDispatchesLifecycle` | hook 串通 | spy hookSystem，调用 `run()` | spy 收到 `.subagentStart` + `.subagentStop` |
| `isolationWorktreeCreatesTemporaryDir` | worktree 隔离 | `definition.isolation = "worktree"` | `context.workingDirectory` 变化为 `/tmp/...` |

### 10.4 Marketplace（2 个 @Test）

| 测试 | 验证 | 输入 | 期望 |
|------|------|------|------|
| `policyBlocklistBlocksInstall` | 政策检查 | `policy.blockedMarketplaces = ["evil"]` | `PluginInstaller.install` 抛 `marketplaceBlockedByPolicy` |
| `marketplaceClientThrowsClearError` | stub 行为 | `client.listAvailable(in: "x")` | 抛 `marketplaceLoadFailed`，message 含 "Anthropic backend" |

### 10.5 不测试的部分（明确）

- 性能 / 加载速度
- 并发冲突（多个 integrate 同时调用）
- UI 渲染
- 实际 git clone 网络行为
- WorktreeManager 内部逻辑（已有其他测试覆盖）

---

## 11. 附录

### 11.1 当前代码量统计

| 子系统 | 源文件数 | 总行数 | 测试数 |
|--------|:-------:|:------:|:-----:|
| Hooks (类型 + 引擎) | 2 | 1,521 | 0 |
| Agent (类型 + 工具 + 管理器 + 内置) | 5 | 1,074 | 25 |
| Plugin (管理器 + 类型) | 1 | 719 | 0 |
| Marketplace | 0 | 0 | 0 |
| Skill (加载器 + 工具 + 解析器) | 4 | ~800 | 0 |
| **合计** | 12 | ~4,100 | 25 |

### 11.2 关键集成点图谱

```
PluginManager ──→ CommandRegistry (commands/, source: .plugin)
              ├──→ SkillFileLoader (skills/)
              ├──→ HookSystem (hooks/, source: .plugin)
              └──→ AgentFileLoader (agents/)  ── 合并内置代理

AgentTool ──→ SubAgentManager ──→ QueryEngine ──→ LLM + Tools
           │                    └──→ WorktreeManager
           │                    └──→ HookSystem (SubagentStart/Stop)
           └──→ AgentFileLoader.resolveRegistry()

HookSystem ←── QueryEngine (PreToolUse, PostToolUse, Stop, StopFailure, ...)
          ←── ChatCommand (UserPromptSubmit, SessionStart/End, ...)
          ←── SubAgentManager (SubagentStart/Stop)
          ←── Compactor (PreCompact, PostCompact)
          ←── PermissionEngine (PermissionRequest, PermissionDenied)
          ←── WorktreeManager (WorktreeCreate/Remove)
          ←── ConfigLoader (ConfigChange)
          ←── SystemPromptBuilder (InstructionsLoaded)
          ←── FileWatcher (FileChanged)
```

### 11.3 命名空间约定

| 来源 | Command 名称格式 | Skill 名称格式 | Agent 名称格式 |
|------|----------------|----------------|---------------|
| Built-in | `commit` | `commit` | `Explore` |
| User-defined | `commit` | `commit` | `commit-helper` |
| Plugin | `plugin-name:commit` | `plugin-name:commit` | `plugin-name:commit-helper` |

**冲突规则**：
- Built-in 优先级最高，Plugin 不覆盖
- User-defined 覆盖 Plugin（CC 行为：用户编辑 `~/.claude/commands` 优先于 plugin）
- Project 覆盖 User（同上）

### 11.4 CC 参考实现路径

| 主题 | 文件 |
|------|------|
| Hook engine | `~/CLI/claude-code/utils/hooks.ts`（5022 行，主引擎） |
| Hook events 定义 | `~/CLI/claude-code/entrypoints/sdk/coreTypes.ts:HOOK_EVENTS` |
| Hook execution events | `~/CLI/claude-code/utils/hooks/hookEvents.ts` |
| Hook configs snapshot | `~/CLI/claude-code/utils/hooks/hooksConfigSnapshot.ts` |
| Plugin loader | `~/CLI/claude-code/utils/plugins/pluginLoader.ts` |
| Plugin commands | `~/CLI/claude-code/utils/plugins/loadPluginCommands.ts` |
| Plugin agents | `~/CLI/claude-code/utils/plugins/loadPluginAgents.ts` |
| Plugin hooks | `~/CLI/claude-code/utils/plugins/loadPluginHooks.ts` |
| Plugin installation | `~/CLI/claude-code/services/plugins/PluginInstallationManager.ts` |
| Plugin CLI | `~/CLI/claude-code/services/plugins/pluginCliCommands.ts` |
| Marketplace | `~/CLI/claude-code/utils/plugins/marketplaceManager.ts` |

### 11.5 改动日志

| 日期 | 改动 | 作者 |
|------|------|------|
| 2026-06-03 | 初版：记录现状 + 修复方案 | Mavis（本文档作者） |
| 2026-06-03 | 重写为可执行实施计划 | Mavis |

---

*本文档与代码同步更新。任何子系统 P0 完成时，请同步更新对应章节的"现状"行 + 验证 checklist。*
