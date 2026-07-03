# Foundation Models

使用专精于语言理解、结构化输出和工具调用的模型来执行任务。

- **Framework**: FoundationModels
- **Kind**: Framework
- **Module**: Foundation Models

## Overview

Foundation Models 框架提供对任何大型语言模型的访问，例如为 Apple Intelligence 设计的设备端和 Private Cloud Compute 模型。
这些模型帮助你执行特定于用例的智能任务。

设备端模型擅长各种文本生成任务，例如摘要、实体提取、文本和图像理解、润色、游戏对话、创意内容生成等。当你需要更强的推理能力和更大的上下文大小时，使用 Private Cloud Compute 或任何服务器模型提供商。

动态 profile API 提供了灵活性，可以为你的任务选择最佳模型配置，并让你构建许多有用的抽象，例如 agents 或 skills。

使用 guided generation 生成完整的 Swift 数据结构。通过 `@Generable` 宏，你可以定义自定义数据结构，框架提供强大的保证，确保模型生成你类型的实例。

使用 `Tool` 创建自定义工具，模型可以调用这些工具来协助处理你的请求。例如，模型可以调用一个搜索本地或在线数据库信息的工具，或调用你应用中的某项服务。

要使用 Apple Foundation Models，用户需要在其设备上开启 Apple Intelligence。有关支持的设备列表，请参阅 [Apple Intelligence](https://www.apple.com/apple-intelligence/)。

### What's new

- [Adding server-side intelligence with Private Cloud Compute](https://developer.apple.com/documentation/FoundationModels/adding-server-side-intelligence-with-private-cloud-compute) — 通过 Private Cloud Compute 路由 session 请求，以访问更大的上下文窗口和更强的推理能力。

- [Composing dynamic sessions with instructions and profiles](https://developer.apple.com/documentation/FoundationModels/composing-dynamic-sessions-with-instructions-and-profiles) — 根据应用状态在运行时加载 instructions 和 tools，动态调整 sessions。

- [Analyzing images with multimodal prompting](https://developer.apple.com/documentation/FoundationModels/analyzing-images-with-multimodal-prompting) — 通过将图像与描述性文本提示组合来分析并提取图像中的信息。

## Topics

### Essentials

- [Generating content and performing tasks with Foundation Models](https://developer.apple.com/documentation/FoundationModels/generating-content-and-performing-tasks-with-foundation-models) — 通过提示设备端大型语言模型来增强应用中的体验。

- [Adding intelligent app features with generative models](https://developer.apple.com/documentation/FoundationModels/adding-intelligent-app-features-with-generative-models) — 采用 Foundation Models 框架，使用 guided generation 和 tool calling 构建健壮的应用。

### Sessions and prompts

- [Prompting an on-device foundation model](https://developer.apple.com/documentation/FoundationModels/prompting-an-on-device-foundation-model) — 定制你的 prompts，从设备端模型获得有效的结果。

- [Managing the context window](https://developer.apple.com/documentation/FoundationModels/managing-the-context-window) — 在 Foundation Models 框架中提示模型时，优化应用的 token 使用。

- [Updating prompts for new model versions](https://developer.apple.com/documentation/FoundationModels/updating-prompts-for-new-model-versions) — 通过版本化 prompts 来管理应用使用的 prompts，以充分利用模型改进。

- `LanguageModelSession` — 代表与语言模型交互的 session 的对象。
- `Instructions` — 你提供的定义模型在 prompts 上的预期行为的详细信息。
- `Prompt` — 从用户到模型的提示。
- `Transcript` — 反映与 session 交互的线性历史记录条目。
- `TranscriptErrorHandlingPolicy` — 控制语言模型 session 在发生错误时如何管理 transcript 的选项。
- `GenerationOptions` — 控制模型如何生成对 prompt 的响应的选项。
- `ContextOptions` — 配置应在 prompt 中出现的详细信息的选项。

### Prompt attachments

- [Analyzing images with multimodal prompting](https://developer.apple.com/documentation/FoundationModels/analyzing-images-with-multimodal-prompting) — 通过将图像与描述性文本提示组合来分析并提取图像中的信息。

- `Attachment` — 提供给模型的资产。
- `AttachmentContent` — 用作 attachment 内容的类型。
- `ImageAttachmentContent` — 持有图像数据的类型。
- `ImageReference` — session transcript 中对图像的引用。

### Dynamic profiles

- [Composing dynamic sessions with instructions and profiles](https://developer.apple.com/documentation/FoundationModels/composing-dynamic-sessions-with-instructions-and-profiles) — 根据应用状态在运行时加载 instructions 和 tools，动态调整 sessions。

- [Origami: Crafting a dynamic tutorial for Apple Intelligence](https://developer.apple.com/documentation/FoundationModels/origami-crafting-a-dynamic-tutorial-for-apple-intelligence) — 使用多模态 prompts 通过 Foundation Models 和 Private Cloud Compute 构建交互式体验。

- `DynamicInstructions` — 代表动态 instructions 的类型。
- `DynamicInstructionsForEach` —
- `LanguageModelSession.DynamicProfile` — 包含一个或多个 profiles 的动态 profile。
- `LanguageModelSession.DynamicProfileModifier` — 用于在动态 profile 内容周围创建可重用包装器的协议。
- `LanguageModelSession.Profile` — 包含动态 instructions 的 profile。

### Structured output

- [Generating Swift data structures with guided generation](https://developer.apple.com/documentation/FoundationModels/generating-swift-data-structures-with-guided-generation) — 通过程序化描述你想要的输出来创建健壮的应用。

- `Generable` — 模型在响应 prompts 时使用的类型。
- `GenerationSchema` — 描述对象属性及其值上任何指导的类型。
- `DynamicGenerationSchema` — generation schema 类型的动态对应物，用于在运行时构造 schemas。
- `GeneratedContent` — 代表结构化、生成内容的类型。
- `ConvertibleToGeneratedContent` — 可以转换为 generated content 的类型。
- `ConvertibleFromGeneratedContent` — 可以从 generated content 初始化的类型。

### Tools

- [Expanding generation with tool calling](https://developer.apple.com/documentation/FoundationModels/expanding-generation-with-tool-calling) — 构建工具，使模型能够执行特定于用例的任务。

- [Generate dynamic game content with guided generation and tools](https://developer.apple.com/documentation/FoundationModels/generate-dynamic-game-content-with-guided-generation-and-tools) — 通过 AI 生成的对话和针对玩家个性化的遭遇使游戏玩法更加生动。

- `Tool` — 模型可以调用以在运行时收集信息或执行副作用的工具。

### System language model

- [Supporting languages and locales with Foundation Models](https://developer.apple.com/documentation/FoundationModels/supporting-languages-and-locales-with-foundation-models) — 以用户与应用交互时偏好的语言生成内容。

- [Categorizing and organizing data with content tags](https://developer.apple.com/documentation/FoundationModels/categorizing-and-organizing-data-with-content-tags) — 使用 content tagging 模型识别输入文本中的主题、动作、对象和情感。

- `SystemLanguageModel` — 能够执行文本生成任务的设备端 Apple Foundation Model。
- `LanguageModelError` — 使用任何语言模型时生成响应可能发生的故障。

### Private Cloud Compute

- [Adding server-side intelligence with Private Cloud Compute](https://developer.apple.com/documentation/FoundationModels/adding-server-side-intelligence-with-private-cloud-compute) — 通过 Private Cloud Compute 路由 session 请求，以访问更大的上下文窗口和更强的推理能力。

- `PrivateCloudComputeLanguageModel` — Apple Foundation Models 的一种变体，在 Private Cloud Compute (PCC) 上运行，提供增强的能力同时维护隐私保证。

### Custom language model provider

- [Optimizing key-value caching in language model sessions](https://developer.apple.com/documentation/FoundationModels/optimizing-key-value-caching-in-language-model-sessions) — 通过在多个回合之间保留缓存状态来防止重复 token 处理。

- `LanguageModel` — 用于与模型交互的协议。
- `LanguageModelCapabilities` — 语言模型提供的一组功能。
- `LanguageModelExecutor` — 定义响应 session 请求的接口的协议。
- `LanguageModelExecutorGenerationChannel` — 用于向框架发送模型输出增量和更新的类型。
- `LanguageModelExecutorGenerationRequest` — 包含 generation 请求详情的类型。

### Custom session properties

- `LanguageModelSession.SessionProperty` — 一个属性包装器，提供从 profiles、dynamic instructions 和 tools 中访问属性的能力。
- `SessionPropertyKey` — 定义自定义 session 属性 key 的协议。
- `SessionPropertyValues` — 属性值的容器。
- `@SessionPropertyEntry` — 定义自定义 key 的宏。

### Safety

- [Improving the safety of generative model output](https://developer.apple.com/documentation/FoundationModels/improving-the-safety-of-generative-model-output) — 创建能够适当处理敏感输入并尊重用户的生成式体验。

### Performance and evaluation

- [Evaluating prompts to measure performance and improve model responses](https://developer.apple.com/documentation/FoundationModels/evaluating-prompts-to-measure-performance-and-improve-model-responses) — 通过使用结构化评估，系统地衡量和改进 prompts 的质量。

- [Analyzing the runtime performance of your Foundation Models app](https://developer.apple.com/documentation/FoundationModels/analyzing-the-runtime-performance-of-your-foundation-models-app) — 在 Instruments 中衡量 prompts、responses 和 tool calls 如何影响 token 消耗和响应时间。

---

Source: <https://developer.apple.com/documentation/foundationmodels>
Copyright &copy; 2026 Apple Inc. All rights reserved.
