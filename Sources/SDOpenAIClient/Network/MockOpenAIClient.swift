import Foundation

/// A mock implementation of `OpenAIClientProtocol` for testing and previews.
public actor MockOpenAIClient: OpenAIClientProtocol {
    /// The response returned by `send(_:)` and `sendWithMetadata(_:)`.
    public var stubbedResponse: String

    /// The deltas yielded by `stream(_:)`.
    public var stubbedStreamDeltas: [String]

    /// The metadata returned by `sendWithMetadata(_:)`.
    public var stubbedMetadata: ResponseMetadata?

    /// When `true`, both `send` and `stream` throw `OpenAIClientError.badResponse`.
    public var shouldThrow: Bool

    /// Number of times `send(_:)` or `sendWithMetadata(_:)` has been called.
    public private(set) var sendCallCount: Int = 0

    /// Number of times `stream(_:)` has been called.
    public private(set) var streamCallCount: Int = 0

    public init(
        stubbedResponse: String = "Mock response",
        stubbedStreamDeltas: [String] = ["Mock", " stream", " response"],
        stubbedMetadata: ResponseMetadata? = nil,
        shouldThrow: Bool = false
    ) {
        self.stubbedResponse = stubbedResponse
        self.stubbedStreamDeltas = stubbedStreamDeltas
        self.stubbedMetadata = stubbedMetadata
        self.shouldThrow = shouldThrow
    }

    public func send(_ prompt: String) async throws -> String {
        sendCallCount += 1
        if shouldThrow {
            throw OpenAIClientError.badResponse(statusCode: 500, message: "Mock error")
        }
        return stubbedResponse
    }

    public func sendWithMetadata(_ prompt: String) async throws -> (text: String, metadata: ResponseMetadata?) {
        sendCallCount += 1
        if shouldThrow {
            throw OpenAIClientError.badResponse(statusCode: 500, message: "Mock error")
        }
        return (text: stubbedResponse, metadata: stubbedMetadata)
    }

    public func stream(_ prompt: String) async throws -> AsyncThrowingStream<String, Error> {
        streamCallCount += 1
        if shouldThrow {
            throw OpenAIClientError.badResponse(statusCode: 500, message: "Mock error")
        }
        let deltas = stubbedStreamDeltas
        return AsyncThrowingStream { continuation in
            for delta in deltas {
                continuation.yield(delta)
            }
            continuation.finish()
        }
    }

    public func clearHistory() async {
        // No-op for mock
    }
}
