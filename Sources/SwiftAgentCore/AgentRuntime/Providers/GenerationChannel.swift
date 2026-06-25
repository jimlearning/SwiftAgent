import Foundation

/// Streaming abstraction between executor and runtime.
/// Executor pushes typed events; runtime consumes them.
///
/// Abstracts over URLSession async bytes, WebSocket, or callback-based
/// delivery. The runtime never sees raw SSE token strings.
public protocol GenerationChannel: Sendable {
    /// Send a text delta to the consumer.
    func send(textDelta: String) async

    /// Send a thinking/reasoning delta to the consumer.
    func send(thinkingDelta: String) async

    /// Signal that a tool call has been requested by the model.
    func send(toolCallRequest id: String, name: String, input: Data) async

    /// Signal that a tool call has completed.
    func send(toolCallCompleted id: String, output: ToolOutputValue) async

    /// Signal turn completion with stop reason and usage.
    func complete(stopReason: String?, usage: Usage?) async

    /// Signal an error from the executor.
    func fail(with error: AgentRuntimeError) async
}
