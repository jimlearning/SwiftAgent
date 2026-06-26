# Foundation Models

Perform tasks with models that specialize in language understanding, structured output, and tool calling.

- **Framework**: FoundationModels
- **Kind**: Framework
- **Module**: Foundation Models

## Overview

The Foundation Models framework provides access to any large language model, like
the on-device and Private Cloud Compute models designed for Apple
Intelligence. These models help you perform intelligent tasks specific to your use case.

On-device models excel at a diverse range of text generation tasks, like
summarization, entity extraction, text and image understanding, refinement,
dialog for games, generating creative content, and more. When you need more
reasoning capabilities and context size, use Private Cloud Compute
or any server model provider.

The dynamic profile API provides the flexibility to select the best model configuration
for your task, and lets you build many useful abstractions, such as agents or skills.

Generate entire Swift data structures with guided generation. With the `@Generable`
macro, you can define custom data structures and the framework provides strong
guarantees that the model generates instances of your type.

Use `Tool` to create custom tools that the model can call to assist with handling
your request. For example, the model can call a tool that searches a local or
online database for information, or calls a service in your app.

To use Apple Foundation Models, people need to turn on Apple Intelligence on
their device. For a list of supported devices, see [Apple Intelligence](https://www.apple.com/apple-intelligence/).

### What's new

- [Adding server-side intelligence with Private Cloud Compute](https://developer.apple.com/documentation/FoundationModels/adding-server-side-intelligence-with-private-cloud-compute) — Access a larger context window and stronger reasoning by routing session requests through Private Cloud Compute.

- [Composing dynamic sessions with instructions and profiles](https://developer.apple.com/documentation/FoundationModels/composing-dynamic-sessions-with-instructions-and-profiles) — Adapt sessions dynamically at runtime by loading instructions and tools based on the state of your app.

- [Analyzing images with multimodal prompting](https://developer.apple.com/documentation/FoundationModels/analyzing-images-with-multimodal-prompting) — Analyze and extract information from images by combining them with descriptive text prompts.

## Topics

### Essentials

- [Generating content and performing tasks with Foundation Models](https://developer.apple.com/documentation/FoundationModels/generating-content-and-performing-tasks-with-foundation-models) — Enhance the experience in your app by prompting an on-device large language model.

- [Adding intelligent app features with generative models](https://developer.apple.com/documentation/FoundationModels/adding-intelligent-app-features-with-generative-models) — Build robust apps with guided generation and tool calling by adopting the Foundation Models framework.

### Sessions and prompts

- [Prompting an on-device foundation model](https://developer.apple.com/documentation/FoundationModels/prompting-an-on-device-foundation-model) — Tailor your prompts to get effective results from an on-device model.

- [Managing the context window](https://developer.apple.com/documentation/FoundationModels/managing-the-context-window) — Optimize your app's token usage when prompting a model with the Foundation Models framework.

- [Updating prompts for new model versions](https://developer.apple.com/documentation/FoundationModels/updating-prompts-for-new-model-versions) — Manage the prompts your app uses by versioning them to make the most out of model improvements.

- `LanguageModelSession` — An object that represents a session that interacts with a language model.
- `Instructions` — Details you provide that define the model's intended behavior on prompts.
- `Prompt` — A prompt from a person to the model.
- `Transcript` — A linear history of entries that reflect an interaction with a session.
- `TranscriptErrorHandlingPolicy` — Options for controlling how a language model session manages the transcript when errors occur.
- `GenerationOptions` — Options that control how the model generates its response to a prompt.
- `ContextOptions` — Options that configure details that should appear in the prompt.

### Prompt attachments

- [Analyzing images with multimodal prompting](https://developer.apple.com/documentation/FoundationModels/analyzing-images-with-multimodal-prompting) — Analyze and extract information from images by combining them with descriptive text prompts.

- `Attachment` — An asset provided to the model.
- `AttachmentContent` — A type that you use as the content of an attachment.
- `ImageAttachmentContent` — A type that holds image data.
- `ImageReference` — A reference to an image in a session's transcript.

### Dynamic profiles

- [Composing dynamic sessions with instructions and profiles](https://developer.apple.com/documentation/FoundationModels/composing-dynamic-sessions-with-instructions-and-profiles) — Adapt sessions dynamically at runtime by loading instructions and tools based on the state of your app.

- [Origami: Crafting a dynamic tutorial for Apple Intelligence](https://developer.apple.com/documentation/FoundationModels/origami-crafting-a-dynamic-tutorial-for-apple-intelligence) — Build interactive experiences with Foundation Models and Private Cloud Compute using multimodal prompts.

- `DynamicInstructions` — A type that represents dynamic instructions.
- `DynamicInstructionsForEach` —
- `LanguageModelSession.DynamicProfile` — A dynamic profile that contains one or more profiles.
- `LanguageModelSession.DynamicProfileModifier` — A protocol for creating reusable wrappers around dynamic profile content.
- `LanguageModelSession.Profile` — A profile that contains dynamic instructions.

### Structured output

- [Generating Swift data structures with guided generation](https://developer.apple.com/documentation/FoundationModels/generating-swift-data-structures-with-guided-generation) — Create robust apps by describing output you want programmatically.

- `Generable` — A type that the model uses when responding to prompts.
- `GenerationSchema` — A type that describes the properties of an object and any guides on their values.
- `DynamicGenerationSchema` — The dynamic counterpart to the generation schema type that you use to construct schemas at runtime.
- `GeneratedContent` — A type that represents structured, generated content.
- `ConvertibleToGeneratedContent` — A type that can be converted to generated content.
- `ConvertibleFromGeneratedContent` — A type that can be initialized from generated content.

### Tools

- [Expanding generation with tool calling](https://developer.apple.com/documentation/FoundationModels/expanding-generation-with-tool-calling) — Build tools that enable the model to perform tasks that are specific to your use case.

- [Generate dynamic game content with guided generation and tools](https://developer.apple.com/documentation/FoundationModels/generate-dynamic-game-content-with-guided-generation-and-tools) — Make gameplay more lively with AI generated dialog and encounters personalized to the player.

- `Tool` — A tool that a model can call to gather information at runtime or perform side effects.

### System language model

- [Supporting languages and locales with Foundation Models](https://developer.apple.com/documentation/FoundationModels/supporting-languages-and-locales-with-foundation-models) — Generate content in the language people prefer when they interact with your app.

- [Categorizing and organizing data with content tags](https://developer.apple.com/documentation/FoundationModels/categorizing-and-organizing-data-with-content-tags) — Identify topics, actions, objects, and emotions in input text with a content tagging model.

- `SystemLanguageModel` — An on-device Apple Foundation Model capable of text generation tasks.
- `LanguageModelError` — A failure that may occur while generating a response when using any language model.

### Private Cloud Compute

- [Adding server-side intelligence with Private Cloud Compute](https://developer.apple.com/documentation/FoundationModels/adding-server-side-intelligence-with-private-cloud-compute) — Access a larger context window and stronger reasoning by routing session requests through Private Cloud Compute.

- `PrivateCloudComputeLanguageModel` — A variant of Apple Foundation Models that runs on Private Cloud Compute (PCC) to provide enhanced capabilities while maintaining privacy guarantees.

### Custom language model provider

- [Optimizing key-value caching in language model sessions](https://developer.apple.com/documentation/FoundationModels/optimizing-key-value-caching-in-language-model-sessions) — Prevent repeated token processing by preserving the cached state across turns.

- `LanguageModel` — A protocol that you use to interface with a model.
- `LanguageModelCapabilities` — A set of capabilities that a language model provides.
- `LanguageModelExecutor` — A protocol that defines the interface for responding to session requests.
- `LanguageModelExecutorGenerationChannel` — A type you use to send model output deltas and updates to the framework.
- `LanguageModelExecutorGenerationRequest` — A type that contains the details for a generation request.

### Custom session properties

- `LanguageModelSession.SessionProperty` — A property wrapper that provides access to properties from within profiles, dynamic instructions, and tools.
- `SessionPropertyKey` — A protocol for defining a custom session property key.
- `SessionPropertyValues` — A container for property values.
- `@SessionPropertyEntry` — A macro for defining a custom key.

### Safety

- [Improving the safety of generative model output](https://developer.apple.com/documentation/FoundationModels/improving-the-safety-of-generative-model-output) — Create generative experiences that appropriately handle sensitive inputs and respect people.

### Performance and evaluation

- [Evaluating prompts to measure performance and improve model responses](https://developer.apple.com/documentation/FoundationModels/evaluating-prompts-to-measure-performance-and-improve-model-responses) — Systematically measure and improve the quality of your prompts by using structured evaluation.

- [Analyzing the runtime performance of your Foundation Models app](https://developer.apple.com/documentation/FoundationModels/analyzing-the-runtime-performance-of-your-foundation-models-app) — Measure how prompts, responses, and tool calls affect token consumption and response times in Instruments.

---

Source: <https://developer.apple.com/documentation/foundationmodels>
Copyright &copy; 2026 Apple Inc. All rights reserved.
