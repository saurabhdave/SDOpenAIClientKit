import Foundation
import XCTest
@testable import SDOpenAIClient

final class SDOpenAIClientTests: XCTestCase {
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

    func testConfigurationLoadsFromPlistURL() throws {
        let plist: [String: Any] = [
            OpenAIClientConfiguration.PlistKey.apiKey: "plist-key",
            OpenAIClientConfiguration.PlistKey.model: "gpt-4o-mini",
            OpenAIClientConfiguration.PlistKey.systemPrompt: "Be concise.",
            OpenAIClientConfiguration.PlistKey.temperature: 0.25,
            OpenAIClientConfiguration.PlistKey.maxContextCharacters: 7_500,
            OpenAIClientConfiguration.PlistKey.maxHistoryItems: 24,
            OpenAIClientConfiguration.PlistKey.requestTimeout: 15,
            OpenAIClientConfiguration.PlistKey.endpoint: "https://example.com/v1/responses",
            OpenAIClientConfiguration.PlistKey.retryMaxAttempts: 4,
            OpenAIClientConfiguration.PlistKey.retryBaseDelay: 0.2,
            OpenAIClientConfiguration.PlistKey.retryMaxDelay: 1.5,
            OpenAIClientConfiguration.PlistKey.retryBackoffMultiplier: 1.8,
            OpenAIClientConfiguration.PlistKey.retryJitterRatio: 0.1,
            OpenAIClientConfiguration.PlistKey.retryableStatusCodes: [408, 429, 500]
        ]
        let url = try makeTemporaryPlist(plist)
        defer { try? FileManager.default.removeItem(at: url) }

        let configuration = try OpenAIClientConfiguration(plistURL: url)

        XCTAssertEqual(configuration.apiKey, "plist-key")
        XCTAssertEqual(configuration.model, "gpt-4o-mini")
        XCTAssertEqual(configuration.systemPrompt, "Be concise.")
        XCTAssertEqual(configuration.temperature, 0.25)
        XCTAssertEqual(configuration.maxContextCharacters, 7_500)
        XCTAssertEqual(configuration.maxHistoryItems, 24)
        XCTAssertEqual(configuration.requestTimeout, 15)
        XCTAssertEqual(configuration.endpoint, URL(string: "https://example.com/v1/responses"))
        XCTAssertEqual(configuration.retryPolicy.maxAttempts, 4)
        XCTAssertEqual(configuration.retryPolicy.baseDelay, 0.2)
        XCTAssertEqual(configuration.retryPolicy.maxDelay, 1.5)
        XCTAssertEqual(configuration.retryPolicy.backoffMultiplier, 1.8)
        XCTAssertEqual(configuration.retryPolicy.jitterRatio, 0.1)
        XCTAssertEqual(configuration.retryPolicy.retryableStatusCodes, [408, 429, 500])
    }

    func testConfigurationPlistMissingAPIKeyThrows() {
        let plist: [String: Any] = [
            OpenAIClientConfiguration.PlistKey.model: "gpt-4.1-mini"
        ]

        XCTAssertThrowsError(try OpenAIClientConfiguration(plistDictionary: plist)) { error in
            XCTAssertEqual(
                error as? OpenAIClientConfigurationError,
                .missingRequiredKey(OpenAIClientConfiguration.PlistKey.apiKey)
            )
        }
    }

    func testConfigurationPlistInvalidEndpointThrows() {
        let plist: [String: Any] = [
            OpenAIClientConfiguration.PlistKey.apiKey: "plist-key",
            OpenAIClientConfiguration.PlistKey.endpoint: "not a url"
        ]

        XCTAssertThrowsError(try OpenAIClientConfiguration(plistDictionary: plist)) { error in
            XCTAssertEqual(
                error as? OpenAIClientConfigurationError,
                .invalidValue(
                    key: OpenAIClientConfiguration.PlistKey.endpoint,
                    expected: "a valid URL string"
                )
            )
        }
    }
}

private extension SDOpenAIClientTests {
    func makeMockedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolMock.self]
        return URLSession(configuration: config)
    }

    func makeTemporaryPlist(_ dictionary: [String: Any]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("plist")
        let didWrite = (dictionary as NSDictionary).write(to: url, atomically: true)
        XCTAssertTrue(didWrite)
        return url
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
