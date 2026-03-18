import Foundation
import Testing
@testable import SDOpenAIClient

@Suite
struct OpenAIClientProtocolTests {

    @Test func mockSendReturnsStubbedResponse() async throws {
        let mock = MockOpenAIClient(stubbedResponse: "Hello!")
        let result = try await mock.send("Hi")
        #expect(result == "Hello!")
    }

    @Test func mockSendCallCountIncrements() async throws {
        let mock = MockOpenAIClient()
        _ = try await mock.send("One")
        _ = try await mock.send("Two")
        let count = await mock.sendCallCount
        #expect(count == 2)
    }

    @Test func mockSendWithMetadataReturnsStubbedValues() async throws {
        let metadata = ResponseMetadata(inputTokens: 10, outputTokens: 5, totalTokens: 15)
        let mock = MockOpenAIClient(stubbedResponse: "Result", stubbedMetadata: metadata)

        let (text, returnedMetadata) = try await mock.sendWithMetadata("Test")

        #expect(text == "Result")
        #expect(returnedMetadata?.totalTokens == 15)
        let count = await mock.sendCallCount
        #expect(count == 1)
    }

    @Test func mockStreamYieldsAllDeltas() async throws {
        let mock = MockOpenAIClient(stubbedStreamDeltas: ["A", "B", "C"])
        let stream = try await mock.stream("Go")

        var collected: [String] = []
        for try await delta in stream {
            collected.append(delta)
        }

        #expect(collected == ["A", "B", "C"])
    }

    @Test func mockStreamCallCountIncrements() async throws {
        let mock = MockOpenAIClient()
        _ = try await mock.stream("One")
        _ = try await mock.stream("Two")
        let count = await mock.streamCallCount
        #expect(count == 2)
    }

    @Test func mockShouldThrowCausesSendToThrow() async throws {
        let mock = MockOpenAIClient(shouldThrow: true)
        await #expect(throws: OpenAIClientError.self) {
            try await mock.send("Fail")
        }
    }

    @Test func mockShouldThrowCausesStreamToThrow() async throws {
        let mock = MockOpenAIClient(shouldThrow: true)
        await #expect(throws: OpenAIClientError.self) {
            try await mock.stream("Fail")
        }
    }

    @Test func mockShouldThrowCausesSendWithMetadataToThrow() async throws {
        let mock = MockOpenAIClient(shouldThrow: true)
        await #expect(throws: OpenAIClientError.self) {
            try await mock.sendWithMetadata("Fail")
        }
    }

    @Test func mockClearHistoryDoesNotCrash() async {
        let mock = MockOpenAIClient()
        await mock.clearHistory()
    }

    @Test func protocolCanBeUsedAsDependency() async throws {
        let mock: any OpenAIClientProtocol = MockOpenAIClient(stubbedResponse: "Injected")
        let result = try await mock.send("Test")
        #expect(result == "Injected")
    }
}
