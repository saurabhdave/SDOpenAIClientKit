import Foundation

/// Protocol abstraction for the OpenAI client, enabling dependency injection and testing.
public protocol OpenAIClientProtocol: Sendable {
    /// Sends a prompt and returns the full response text.
    func send(_ prompt: String) async throws -> String

    /// Sends a prompt and returns the response text along with token usage metadata.
    func sendWithMetadata(_ prompt: String) async throws -> (text: String, metadata: ResponseMetadata?)

    /// Streams a prompt response, yielding text deltas as they arrive.
    func stream(_ prompt: String) async throws -> AsyncThrowingStream<String, Error>

    /// Clears the conversation history.
    func clearHistory() async
}
