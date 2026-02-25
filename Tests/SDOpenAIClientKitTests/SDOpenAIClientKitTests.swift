import Foundation
import XCTest
@testable import SDOpenAIClientKit

final class SDOpenAIClientKitTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocolMock.reset()
    }

    func testSendParsesOutputAndStoresHistory() async throws {
        URLProtocolMock.requestHandler = { _ in
            let json = #"{"output":[{"type":"message","content":[{"type":"output_text","text":"Hello from model"}]}]}"#
            let data = Data(json.utf8)
            return (HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let client = OpenAIClient(
            configuration: OpenAIClientConfiguration(
                apiKey: "test-key",
                endpoint: URL(string: "https://example.com/v1/responses")!
            ),
            session: makeMockedSession()
        )

        let text = try await client.send("Hi")
        let history = await client.conversationHistory()

        XCTAssertEqual(text, "Hello from model")
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0], OpenAIMessage(role: .user, content: "Hi"))
        XCTAssertEqual(history[1], OpenAIMessage(role: .assistant, content: "Hello from model"))
    }

    func testSecondRequestCarriesPriorHistory() async throws {
        var callCount = 0

        URLProtocolMock.requestHandler = { request in
            if let body = request.httpBody {
                URLProtocolMock.recordBody(body)
            }

            callCount += 1
            let modelText = callCount == 1 ? "First response" : "Second response"
            let json = "{\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"\(modelText)\"}]}]}"
            let data = Data(json.utf8)

            return (HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let client = OpenAIClient(
            configuration: OpenAIClientConfiguration(
                apiKey: "test-key",
                endpoint: URL(string: "https://example.com/v1/responses")!
            ),
            session: makeMockedSession()
        )

        _ = try await client.send("Question 1")
        _ = try await client.send("Question 2")

        let bodies = URLProtocolMock.recordedBodies
        XCTAssertEqual(bodies.count, 2)

        let firstRequest = try JSONDecoder().decode(ProbeResponsesRequest.self, from: bodies[0])
        let secondRequest = try JSONDecoder().decode(ProbeResponsesRequest.self, from: bodies[1])

        XCTAssertEqual(firstRequest.input.map(\.content), ["Question 1"])
        XCTAssertEqual(secondRequest.input.map(\.content), ["Question 1", "First response", "Question 2"])
        XCTAssertEqual(secondRequest.input.map(\.role), ["user", "assistant", "user"])
    }
}

private extension SDOpenAIClientKitTests {
    func makeMockedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolMock.self]
        return URLSession(configuration: config)
    }
}

private struct ProbeResponsesRequest: Decodable {
    let input: [ProbeInputItem]
}

private struct ProbeInputItem: Decodable {
    let role: String
    let content: String
}

private final class URLProtocolMock: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    private static let lock = NSLock()
    private static var _recordedBodies: [Data] = []

    static var recordedBodies: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return _recordedBodies
    }

    static func recordBody(_ data: Data) {
        lock.lock()
        _recordedBodies.append(data)
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        _recordedBodies = []
        requestHandler = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: OpenAIClientError.invalidResponse)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
