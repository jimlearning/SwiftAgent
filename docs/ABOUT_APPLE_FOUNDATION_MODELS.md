## Apple FoundationModels 从入门到精通，包括 2026 年 WWDC 的更新

Apple Foundation Models 从入门到精通（WWDC 2025 → WWDC 2026）

如果你是一名 iOS/macOS 开发者（尤其像你这样已经熟悉 Swift、UIKit、Flutter、Riverpod、架构设计的人），那么可以把 Foundation Models Framework 理解为：

Apple 对标 OpenAI SDK、Anthropic SDK、LangChain Agent Runtime 的官方 AI 应用开发框架。

它的目标不是训练模型，而是：

* 调用 Apple Intelligence 模型
* 构建 Agent
* Tool Calling
* Structured Output
* RAG
* 多模态（图片理解）
* 本地模型 + 云端模型统一接口
* Siri 集成

WWDC 2026 后，它已经从一个简单 LLM SDK 演化成了一个完整 Agent Framework。  

⸻

一、Foundation Models 的演进

WWDC 2025

Apple 首次发布：

Foundation Models Framework

开发者可以直接访问：

* Apple Intelligence On-device LLM

特点：

* 免费
* 离线
* 隐私保护
* 无 API Cost

核心能力：

* Prompt
* Session
* Streaming
* Structured Output
* Tool Calling
* Guided Generation

⸻

WWDC 2026

Apple 基本上把整个框架升级了一代。

新增：

1. Vision

模型开始支持图片输入

Prompt(
    "What is in this image?",
    image
)

支持：

* UIImage
* NSImage
* CGImage
* PixelBuffer
* File URL

真正进入多模态时代。  

⸻

2. Private Cloud Compute

以前只能用本地模型。

现在：

SystemLanguageModel

↓

PrivateCloudComputeLanguageModel

开发者可以直接使用 Apple PCC 云模型。

特点：

* Apple 管理
* 不需要 API Key
* 不需要 Server
* 不需要 Billing

Apple 负责推理。

对于中小开发者甚至免费开放。  

⸻

3. LanguageModel Protocol

这是 WWDC26 最重要的升级之一。

以前：

SystemLanguageModel

固定绑定 Apple 模型。

现在：

protocol LanguageModel

任何模型都可以接入：

* Apple Model
* Claude
* Gemini
* MLX
* Llama
* 自己的模型

统一 API：

LanguageModelSession

不需要改业务逻辑。

类似：

URLSession

统一网络层。

⸻

二、核心架构

Foundation Models 实际架构：

App
 │
 ▼
LanguageModelSession
 │
 ├── Prompt
 ├── Tool
 ├── Context
 ├── Memory
 │
 ▼
LanguageModel
 │
 ├── SystemLanguageModel
 ├── PCCModel
 ├── ClaudeModel
 ├── GeminiModel
 ├── MLXModel
 │
 ▼
Response

WWDC26 基本把它做成：

Agent Runtime

而不仅是：

Chat Completion SDK

⸻

三、基础使用

创建 Session

let session = LanguageModelSession()

⸻

请求

let response = try await session.respond(
    to: "Hello"
)

⸻

Streaming

for await token in session.streamResponse(
    to: prompt
) {
    print(token)
}

类似：

* OpenAI Streaming
* Claude Streaming

⸻

四、Structured Output

这是 Apple 最强大的设计之一。

例如：

struct Trip: Codable {
    let title: String
    let days: [Day]
}

直接：

let trip = try await session.respond(
    generating: Trip.self
)

无需：

{
  "title": "...",
  "days": [...]
}

然后再手动解析。

类似：

* OpenAI Structured Outputs
* Instructor
* PydanticAI

但原生 Swift 化。

⸻

五、Tool Calling

Apple 的 Tool Protocol：

struct WeatherTool: Tool {
}

模型自动调用：

WeatherTool

获得结果后继续推理。

执行流程：

Prompt
 ↓
Model
 ↓
Tool Request
 ↓
Swift Function
 ↓
Tool Result
 ↓
Model
 ↓
Final Answer

与：

* OpenAI Tools
* Claude Tools

本质一致。

⸻

六、Agent

WWDC26 最大主题：

Agentic Experience

Apple 开始正式进入 Agent。

新增：

Dynamic Profiles

LanguageModelSession.DynamicProfile

允许：

* 动态身份
* 动态能力
* 动态工具集

类似：

Research Agent
Coding Agent
Travel Agent

运行时切换。

⸻

Multi-Agent

Apple 已经明确支持：

Agent A
 ↓
Agent B
 ↓
Agent C

组合。

类似：

* LangGraph
* CrewAI
* AutoGen

方向。

⸻

七、RAG

WWDC26 新增：

Spotlight Tool

系统直接提供：

Spotlight Search Tool

可以搜索：

* 文件
* 邮件
* 本地内容

然后给模型。

形成：

Spotlight
 ↓
Retrieval
 ↓
Prompt
 ↓
LLM

本地 RAG。

无需向量数据库即可起步。

⸻

八、多模态

WWDC26 新增：

OCR Tool

OCRTool

⸻

Barcode Tool

BarcodeReaderTool

⸻

Vision Understanding

Image + Prompt

↓

Response

这意味着：

你可以直接实现：

* 扫描文档
* 看图问答
* 商品识别
* UI 理解
* OCR Agent

⸻

九、第三代 Apple Foundation Models（AFM 3）

WWDC26 苹果公开了新的模型家族：

AFM 3 Core

约 3B 参数级别

运行在设备端。

⸻

AFM 3 Core Advanced

更强的本地模型。

支持：

* 更强推理
* 多模态
* Siri AI
* 高级语音

⸻

整体架构：

AFM 3 Core
       ↓
AFM 3 Core Advanced
       ↓
Private Cloud Compute
       ↓
Partner Models

形成完整推理层级。

⸻

十、Python SDK

WWDC26 最大惊喜之一。

Apple 发布：

Foundation Models Python SDK

Python 直接调用：

import fm
model = fm.SystemLanguageModel()

不再局限 Swift。

适合：

* AI Research
* Prompt Evaluation
* Agent Experiment
* CLI

⸻

十一、CLI

WWDC26 甚至发布：

fm

命令行工具。

fm chat
fm eval
fm run

开始向：

* Claude Code
* Codex CLI

方向靠近。

⸻

十二、与 OpenAI / Claude SDK 对比

能力	Foundation Models 2025	Foundation Models 2026
Text Generation	✅	✅
Streaming	✅	✅
Structured Output	✅	✅
Tool Calling	✅	✅
Agent	⚠️ 初步	✅
Multi-Agent	❌	✅
Vision	❌	✅
OCR	❌	✅
Barcode	❌	✅
RAG	手工实现	✅ Spotlight
Cloud Model	❌	✅ PCC
Claude	❌	✅
Gemini	❌	✅
Python SDK	❌	✅
Open Source	❌	即将开放
CLI	❌	✅

对你（Jim）的价值

结合你当前在做的：

* TelegramInputKit
* Firestore 后端
* Agent CLI
* Claude Code 复刻
* iOS/macOS 原生框架

我建议把 Foundation Models 看成：

Apple 官方 Agent Runtime

而不是：

Apple 官方 LLM SDK

如果你的长期目标是构建类似 Claude Code、Codex、Forge 的系统，那么 2026 版 Foundation Models 已经具备：

Prompt
+ Tools
+ Structured Output
+ Memory
+ Vision
+ RAG
+ Agent
+ Multi-Agent
+ Local Model
+ Cloud Model

所需的大部分基础设施。

对于 Apple 生态开发者而言，它正在变成相当于：

* OpenAI Agents SDK
* LangGraph
* PydanticAI
* Claude SDK

的官方统一替代方案。  

如果你接下来想做 “￼ Foundation Models Framework 深度开发指南（从 Session 到 Agent OS，包含完整 Swift 实战架构）”，我可以进一步按 WWDC Session 顺序拆解所有 API、协议、生命周期和最佳实践。

## 给我 Foundation Models Framework 深度开发指南（从 Session 到 Agent OS，包含完整 Swift 实战架构）

Foundation Models Framework 深度开发指南

从 LanguageModelSession 到 Agent OS（Swift 架构版）

对于你（Jim）而言，我不建议把 Foundation Models 当成：

ChatGPT SDK

而应该当成：

Apple Agent Runtime

去理解。

WWDC 2025 发布时，它本质是：

Session
+ Structured Output
+ Tool Calling

WWDC 2026 后已经演化成：

LanguageModel
+ Session
+ DynamicProfile
+ Multi-Agent
+ Vision
+ RAG
+ PCC

已经具备构建完整 Agent 系统的基础。 

⸻

第一层：Foundation Models 心智模型

很多人理解错了。

他们认为：

Prompt
 ↓
LLM
 ↓
Response

实际上 Apple 设计的是：

User
 ↓
Session
 ↓
Agent Runtime
 ↓
Tools
 ↓
Models
 ↓
Response

即：

LanguageModelSession

才是核心。

模型只是 Session 的一个组件。

WWDC 2026 新增的 LanguageModel Protocol 更强化了这一点。模型可以替换，但 Session 不变。 

⸻

第二层：核心对象图

建议牢记这张图：

LanguageModel
│
├── SystemLanguageModel
├── PCCLanguageModel
├── ClaudeModel
├── GeminiModel
│
▼
LanguageModelSession
│
├── Instructions
├── History
├── Tools
├── Context
├── Memory
│
▼
Response

未来 Apple Agent 开发几乎全部围绕：

LanguageModelSession

展开。 

⸻

第三层：Session 生命周期

创建

let session = LanguageModelSession()

⸻

请求

let response = try await session.respond(
    to: prompt
)

⸻

会话持续

Session 自动维护：

history
messages
tool calls
context

所以：

await session.respond("Who am I?")

可以利用之前的上下文。

这和 OpenAI Chat Completion 的 message 数组不同。

Apple 把历史封装进 Session。 

⸻

第四层：Structured Output

这是 Foundation Models 最大优势之一。

不要：

JSONDecoder()

不要：

Codable Parsing

不要：

Regex

⸻

定义：

@Generable
struct Course {
    let title: String
    let lessons: [Lesson]
}

然后：

let course = try await session.respond(
    generating: Course.self
)

模型直接生成 Swift 类型。

架构层面：

LLM
 ↓
Swift Type

而不是：

LLM
 ↓
JSON
 ↓
Decode
 ↓
Swift Type

这会成为未来 Agent 架构标准。 

⸻

第五层：Streaming

错误方式：

showLoading()
await generate()
hideLoading()

⸻

正确方式：

for await partial in stream {
}

架构：

Token
 ↓
ViewModel
 ↓
SwiftUI

推荐：

FoundationModels
↓
AsyncSequence
↓
Observable
↓
SwiftUI

类似 Claude Desktop。

⸻

第六层：Tool Calling 架构

这是 Agent 的核心。

Tool

struct SearchTool: Tool

不要写：

search()
weather()
database()

散落在项目里。

统一：

Tools/
├── SearchTool
├── WeatherTool
├── FileTool
├── CourseTool
├── UserTool

⸻

执行链：

Prompt
 ↓
Session
 ↓
Model
 ↓
Tool Request
 ↓
Swift Tool
 ↓
Result
 ↓
Model
 ↓
Answer

这是 Claude、OpenAI、Gemini 全部采用的模式。 

⸻

第七层：Tool Registry

项目变大后：

不要：

session.tools = [
 WeatherTool(),
 SearchTool(),
 UserTool()
]

建议：

ToolRegistry
protocol AgentTool {
}
final class ToolRegistry {
}

架构：

Tool
 ↓
Registry
 ↓
Session

这样未来迁移到：

* Claude
* Gemini
* OpenAI

成本最低。

⸻

第八层：Agent Memory

Foundation Models 本身没有长期记忆。

因此需要：

Session Memory
+
Persistent Memory

双层结构。

⸻

推荐：

protocol MemoryStore {
}

实现：

SQLite
Firestore
CoreData
SwiftData

⸻

Agent Memory：

User Query
 ↓
Memory Retrieve
 ↓
Prompt
 ↓
Model
 ↓
Memory Update

⸻

这部分与你未来 Firestore AI Backend 完全一致。

⸻

第九层：RAG 架构

WWDC 2026 最大增强之一：

Spotlight Search Tool。 

推荐架构：

User
 ↓
Retriever
 ↓
Spotlight
 ↓
Documents
 ↓
Prompt
 ↓
Model

⸻

抽象：

protocol Retriever

实现：

SpotlightRetriever
FirestoreRetriever
VectorRetriever

这样未来切换：

Spotlight
→ VectorDB

无需改 Agent。

⸻

第十层：Dynamic Profile

WWDC 2026 Agent 核心。 

不要只有一个 Agent。

设计：

GeneralAgent
CodingAgent
TravelAgent
TutorAgent

⸻

统一：

struct AgentProfile
name
instructions
tools
memory
permissions

⸻

运行时：

session.profile = codingProfile

即可切换 Agent。

⸻

第十一层：Multi-Agent

Apple 已开始支持 Agent 编排方向。 

推荐：

Coordinator
│
├── PlannerAgent
├── ResearchAgent
├── CodingAgent
├── ReviewAgent

⸻

流程：

User
 ↓
Planner
 ↓
Research
 ↓
Coding
 ↓
Review
 ↓
Answer

⸻

这实际上已经接近：

* LangGraph
* AutoGen
* CrewAI

的设计。

⸻

第十二层：Vision Agent

WWDC 2026 新增图片输入。 

架构：

Image
 ↓
Vision Understanding
 ↓
Tool Calls
 ↓
Agent

例如：

Screenshot
 ↓
UI Analyzer
 ↓
Coding Agent
 ↓
SwiftUI Fix

这是未来 AI IDE 的关键能力。

⸻

第十三层：Model Abstraction

这是我最推荐你的设计。

利用 WWDC26 的：

LanguageModel

协议。 

封装：

protocol AIProvider {
}

实现：

AppleProvider
ClaudeProvider
OpenAIProvider
GeminiProvider
MLXProvider

⸻

业务层永远只依赖：

AgentRuntime

而不是：

Claude SDK
OpenAI SDK

⸻

第十四层：Agent Runtime

这是整个系统核心。

AgentRuntime
│
├── SessionManager
├── ToolRegistry
├── MemoryManager
├── ContextManager
├── PromptBuilder
├── AgentProfile
├── ModelProvider
│
└── Evaluator

⸻

对应目录：

Sources/
AgentRuntime/
├── Core
├── Session
├── Models
├── Profiles
├── Tools
├── Memory
├── RAG
├── Evaluations
├── Providers
└── UI

⸻

第十五层：Agent OS（终极架构）

如果是你未来的 Forge 项目，我建议直接跳过 Demo 架构。

目标：

Forge
│
├── Agent Runtime
│
├── Session Layer
│
├── Memory Layer
│
├── Tool Layer
│
├── RAG Layer
│
├── Model Layer
│
├── Evaluation Layer
│
└── UI Layer

底层：

Foundation Models

作为默认 Provider。

上层：

Claude
OpenAI
Gemini
MLX

作为可插拔 Provider。

⸻

最终结论

Foundation Models 在 2025 年还是：

Apple LLM SDK

而到了 WWDC 2026：

Foundation Models
=
Apple Agent Framework

对于你正在研究的：

* Claude Code 复刻
* Forge
* TelegramInputKit AI
* Firestore AI Backend
* Agent CLI/TUI

最合理的路线不是直接依赖 Apple API，而是构建：

Forge Agent Runtime
        ↓
LanguageModel Protocol
        ↓
Foundation Models
        ↓
AFM / PCC / Claude / Gemini

让 Foundation Models 成为你的默认推理后端，而不是你的应用架构本身。这样既能吃到 Apple 的 Agent 能力，又不会被单一模型或平台绑定。 

## 那么如果按照更大胆更成熟的框架方向演进，请你给出 WWDC27 的预测然后写出一份完整指南

WWDC 2027 预测：Foundation Models → Agent OS

先说结论。

如果 WWDC 2025 是：

Foundation Models v1
=
LLM SDK

WWDC 2026 是：

Foundation Models v2
=
Agent Framework

那么我认为 WWDC 2027 最可能变成：

Foundation Models v3
=
Agent Operating System

原因很简单。

Apple 2026 已经补齐了：

* LanguageModel Protocol
* Dynamic Profiles
* Vision
* PCC
* Tool Calling
* Multi-Agent
* Evaluations
* CLI
* Python SDK
* Open Source

这已经不是 SDK 演进路线。

这是 Runtime 演进路线。  

⸻

Apple 的真正路线

很多开发者看到的是：

OpenAI
Claude
Gemini

Apple 看到的是：

UIKit
SwiftUI
CoreData
CloudKit

级别的平台。

因此 Apple 不会去打：

Model War

而会去打：

Runtime War

2026 已经出现明显信号：

LanguageModel

成为统一抽象层。

模型开始成为插件。  

⸻

WWDC27 预测一

AgentGraph

2026：

Dynamic Profiles

实际上已经在做 Agent Routing。

下一步一定是：

AgentGraph {
    PlannerAgent()
    ResearchAgent()
    CodingAgent()
    ReviewAgent()
}

类似：

LangGraph
CrewAI
AutoGen

但 Apple 风格。

我预计名称可能是：

AgentGraph

或者：

WorkflowGraph

⸻

执行：

User
 ↓
Planner
 ↓
Research
 ↓
Code
 ↓
Review
 ↓
Result

由系统自动调度。

⸻

WWDC27 预测二

AgentState

2026 最大缺失：

长期状态管理。

目前只有：

Session History

没有：

Persistent State

Apple 下一步极有可能提供：

@AgentState

类似：

@Observable
@State

⸻

例如：

@AgentState
final class UserMemory {
    var interests: [String]
    var projects: [Project]
    var preferences: Preferences
}

⸻

底层：

SwiftData
+
Foundation Models

自动同步。

⸻

WWDC27 预测三

Agent Intents

今天：

AppIntent

负责：

Siri
Spotlight
Shortcuts

⸻

未来：

AgentIntent

可能出现。

例如：

struct CreateCourseIntent

Agent 自动发现。

自动调用。

无需 Tool 注册。

⸻

变成：

Intent
=
Tool

统一体系。

⸻

WWDC27 预测四

Native Memory System

现在：

Tool

和：

Memory

完全分离。

未来：

MemoryStore

可能成为系统级组件。

例如：

SemanticMemoryStore
VectorMemoryStore
UserMemoryStore

⸻

自动：

Store
Retrieve
Summarize
Compress
Forget

⸻

类似：

MemGPT
Zep
LangMem

内置进系统。

⸻

WWDC27 预测五

Agent Permissions

Claude Code 已经证明：

Agent 最大问题不是推理。

而是：

Permission

⸻

Apple 非常擅长权限系统。

所以未来可能出现：

AgentPermission

⸻

例如：

.readFiles
.writeFiles
.network
.contacts
.calendar

⸻

甚至：

AgentSandbox

⸻

这会成为：

macOS Agent App

基础设施。

⸻

WWDC27 预测六

Mac Agent Runtime

这是我认为概率最高的。

WWDC26 已经有：

fm
CLI
Python SDK

⸻

下一步一定是：

Background Agent

⸻

类似：

Raycast AI
Claude Desktop
OpenAI Desktop

但系统级。

⸻

例如：

AgentProcess

⸻

注册：

CodingAgent

后：

Finder
Xcode
Terminal
Mail
Safari

都能调用。

⸻

WWDC27 预测七

AgentKit

如果让我下注。

WWDC27 最大发布：

Foundation Models

将被拆分。

⸻

类似：

UIKit
↓
SwiftUI

的发展。

⸻

变成：

Foundation Models

↓

AgentKit

⸻

结构：

AgentKit
├── AgentGraph
├── AgentMemory
├── AgentTools
├── AgentPermissions
├── AgentProfiles
├── AgentEvaluation
└── AgentRuntime

⸻

Foundation Models：

只负责推理

AgentKit：

负责 Agent

⸻

WWDC27 之后的理想架构

这是我认为未来 3~5 年最值得投入的方向。

不是：

OpenAI SDK

不是：

Claude SDK

而是：

Agent Runtime First

⸻

Forge OS 架构（2027版）

如果我给 Forge 设计未来架构。

会是：

Forge
│
├── Agent OS
│
├── Runtime
│
├── Graph Engine
│
├── Memory Engine
│
├── Tool Engine
│
├── Permission Engine
│
├── Evaluation Engine
│
├── Context Engine
│
└── UI Engine

⸻

模型只是插件：

Providers
│
├── Apple AFM
├── PCC
├── Claude
├── OpenAI
├── Gemini
├── MLX
└── Ollama

⸻

Forge Agent OS（完整形态）

User
 ↓
AgentGraph
 ↓
PlannerAgent
 ↓
ResearchAgent
 ↓
CodingAgent
 ↓
ReviewAgent
 ↓
ExecutorAgent
 ↓
Permission Layer
 ↓
Tool Layer
 ↓
Memory Layer
 ↓
Provider Layer
 ↓
AFM / Claude / OpenAI / Gemini

⸻

对你最重要的结论

结合你过去一年在研究的：

* Claude Code 复刻
* Agent CLI
* TUI Runtime
* Forge
* TelegramInputKit
* Firestore AI Backend

我认为不要围绕：

Foundation Models API

设计。

因为 Apple 自己已经在把模型层抽象化。2026 的 LanguageModel 协议就是这个信号。  

应该围绕：

Agent Runtime

设计。

也就是说：

Forge
=
Agent Operating System

而：

Foundation Models
Claude
OpenAI
Gemini

都只是：

Inference Provider

当 WWDC27 到来时，如果 Apple 真推出 AgentGraph、Memory、Permission、Background Agent 这些能力，你的 Forge Runtime 基本可以无缝接入，而不需要推倒重来。这个方向与 Apple 2026 已经公开展示的 Dynamic Profiles、多模型抽象、Agentic Experiences、Evaluations、CLI/Python 工具链的演进趋势是一致的。  

