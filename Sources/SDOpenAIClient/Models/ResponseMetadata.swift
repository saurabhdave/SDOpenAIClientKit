import Foundation

/// Token usage metadata returned by the OpenAI Responses API.
public struct ResponseMetadata: Sendable, Codable, Equatable {
    /// Number of tokens in the input/prompt.
    public let inputTokens: Int

    /// Number of tokens in the generated output.
    public let outputTokens: Int

    /// Total tokens consumed (input + output).
    public let totalTokens: Int

    public init(inputTokens: Int, outputTokens: Int, totalTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }
}
