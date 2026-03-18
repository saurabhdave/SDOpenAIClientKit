import Foundation
import Testing
@testable import SDOpenAIClient

// Both NetworkTests.ClientTests and NetworkTests.HistoryTrimmingTests share
// URLProtocolMock static state, so they must run serially to avoid interference.
@Suite(.serialized)
struct NetworkTests {

    @Suite struct ClientTests {

        init() {
            URLProtocolMock.reset()
        }

        @Test func sendParsesOutputAndStoresHistory() async throws {
            URLProtocolMock.requestHandler = { _ in
                let json = #"{"output":[{"type":"message","content":[{"type":"output_text","text":"Hello from model"}]}]}"#
                let data = Data(json.utf8)
                return (HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }

            let client = OpenAIClient(
                configuration: try OpenAIClientConfiguration(
                    apiKey: APIKey("test-key"),
                    endpoint: URL(string: "https://example.com/v1/responses")!
                ),
                session: makeMockedSession()
            )

            let text = try await client.send("Hi")
            let history = await client.conversationHistory()

            #expect(text == "Hello from model")
            #expect(history.count == 2)
            #expect(history[0] == OpenAIMessage(role: .user, content: "Hi"))
            #expect(history[1] == OpenAIMessage(role: .assistant, content: "Hello from model"))
        }

        @Test func sendWithMetadataReturnsUsage() async throws {
            URLProtocolMock.requestHandler = { _ in
                let json = #"{"output":[{"type":"message","content":[{"type":"output_text","text":"Hi"}]}],"usage":{"input_tokens":10,"output_tokens":5,"total_tokens":15}}"#
                let data = Data(json.utf8)
                return (HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }

            let client = OpenAIClient(
                configuration: try OpenAIClientConfiguration(
                    apiKey: APIKey("test-key"),
                    endpoint: URL(string: "https://example.com/v1/responses")!
                ),
                session: makeMockedSession()
            )

            let (text, metadata) = try await client.sendWithMetadata("Hi")

            #expect(text == "Hi")
            #expect(metadata != nil)
            #expect(metadata?.inputTokens == 10)
            #expect(metadata?.outputTokens == 5)
            #expect(metadata?.totalTokens == 15)
        }

        @Test func secondRequestCarriesPriorHistory() async throws {
            let counter = AtomicCounter()

            URLProtocolMock.requestHandler = { request in
                // httpBody may be nil when URLSession converts it to httpBodyStream;
                // read from the stream if needed.
                let body: Data? = request.httpBody ?? {
                    guard let stream = request.httpBodyStream else { return nil }
                    stream.open()
                    defer { stream.close() }
                    var data = Data()
                    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                    defer { buffer.deallocate() }
                    while stream.hasBytesAvailable {
                        let read = stream.read(buffer, maxLength: 4096)
                        guard read > 0 else { break }
                        data.append(buffer, count: read)
                    }
                    return data
                }()

                if let body {
                    URLProtocolMock.recordBody(body)
                }

                let callCount = counter.increment()
                let modelText = callCount == 1 ? "First response" : "Second response"
                let json = "{\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"\(modelText)\"}]}]}"
                let data = Data(json.utf8)

                return (HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }

            let client = OpenAIClient(
                configuration: try OpenAIClientConfiguration(
                    apiKey: APIKey("test-key"),
                    endpoint: URL(string: "https://example.com/v1/responses")!
                ),
                session: makeMockedSession()
            )

            _ = try await client.send("Question 1")
            _ = try await client.send("Question 2")

            let bodies = URLProtocolMock.recordedBodies
            #expect(bodies.count == 2)

            let firstRequest = try JSONDecoder().decode(ProbeResponsesRequest.self, from: bodies[0])
            let secondRequest = try JSONDecoder().decode(ProbeResponsesRequest.self, from: bodies[1])

            #expect(firstRequest.input.map(\.content) == ["Question 1"])
            #expect(secondRequest.input.map(\.content) == ["Question 1", "First response", "Question 2"])
            #expect(secondRequest.input.map(\.role) == ["user", "assistant", "user"])
        }

        @Test func configurationLoadsFromPlistURL() throws {
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

            #expect(configuration.apiKey == APIKey("plist-key"))
            #expect(configuration.model == OpenAIModel(rawValue: "gpt-4o-mini"))
            #expect(configuration.systemPrompt == "Be concise.")
            #expect(configuration.temperature == 0.25)
            #expect(configuration.historyTrimmingStrategy == .both(maxCharacters: 7_500, maxItems: 24))
            #expect(configuration.requestTimeout == 15)
            #expect(configuration.endpoint == URL(string: "https://example.com/v1/responses"))
            #expect(configuration.retryPolicy.maxAttempts == 4)
            #expect(configuration.retryPolicy.baseDelay == 0.2)
            #expect(configuration.retryPolicy.maxDelay == 1.5)
            #expect(configuration.retryPolicy.backoffMultiplier == 1.8)
            #expect(configuration.retryPolicy.jitterRatio == 0.1)
            #expect(configuration.retryPolicy.retryableStatusCodes == [408, 429, 500])
        }

        @Test func configurationLoadFromPlistAtURL() throws {
            let plist: [String: Any] = [
                OpenAIClientConfiguration.PlistKey.apiKey: "url-key",
                OpenAIClientConfiguration.PlistKey.model: "gpt-4o"
            ]
            let url = try makeTemporaryPlist(plist)
            defer { try? FileManager.default.removeItem(at: url) }

            let configuration = try OpenAIClientConfiguration.loadFromPlist(at: url)

            #expect(configuration.apiKey == APIKey("url-key"))
            #expect(configuration.model == OpenAIModel.gpt4o)
        }

        @Test func configurationPlistMissingAPIKeyThrows() throws {
            let plist: [String: Any] = [
                OpenAIClientConfiguration.PlistKey.model: "gpt-5.4-mini"
            ]

            #expect(throws: OpenAIClientConfigurationError.self) {
                try OpenAIClientConfiguration(plistDictionary: plist)
            }
        }

        @Test func configurationPlistInvalidEndpointThrows() throws {
            let plist: [String: Any] = [
                OpenAIClientConfiguration.PlistKey.apiKey: "plist-key",
                OpenAIClientConfiguration.PlistKey.endpoint: ""
            ]

            #expect(throws: OpenAIClientConfigurationError.self) {
                try OpenAIClientConfiguration(plistDictionary: plist)
            }
        }

        @Test func badResponseThrowsWithStatusCodeAndMessage() async throws {
            URLProtocolMock.requestHandler = { _ in
                let json = #"{"error":{"message":"Rate limit exceeded","type":"rate_limit"}}"#
                let data = Data(json.utf8)
                return (HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 429, httpVersion: nil, headerFields: nil)!, data)
            }

            let client = OpenAIClient(
                configuration: try OpenAIClientConfiguration(
                    apiKey: APIKey("test-key"),
                    retryPolicy: .none,
                    endpoint: URL(string: "https://example.com/v1/responses")!
                ),
                session: makeMockedSession()
            )

            do {
                _ = try await client.send("Hi")
                Issue.record("Expected badResponse error")
            } catch let error as OpenAIClientError {
                guard case let .badResponse(statusCode, message) = error else {
                    Issue.record("Expected badResponse, got \(error)")
                    return
                }
                #expect(statusCode == 429)
                #expect(message.contains("Rate limit exceeded"))
            }
        }

        @Test func emptyResponseThrows() async throws {
            URLProtocolMock.requestHandler = { _ in
                let json = #"{"output":[{"type":"message","content":[]}]}"#
                let data = Data(json.utf8)
                return (HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }

            let client = OpenAIClient(
                configuration: try OpenAIClientConfiguration(
                    apiKey: APIKey("test-key"),
                    endpoint: URL(string: "https://example.com/v1/responses")!
                ),
                session: makeMockedSession()
            )

            await #expect(throws: OpenAIClientError.self) {
                try await client.send("Hi")
            }
        }

        @Test func clearHistoryRemovesAllMessages() async throws {
            URLProtocolMock.requestHandler = { _ in
                let json = #"{"output":[{"type":"message","content":[{"type":"output_text","text":"Reply"}]}]}"#
                return (HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
            }

            let client = OpenAIClient(
                configuration: try OpenAIClientConfiguration(
                    apiKey: APIKey("test-key"),
                    endpoint: URL(string: "https://example.com/v1/responses")!
                ),
                session: makeMockedSession()
            )

            _ = try await client.send("Hello")
            let historyBefore = await client.conversationHistory()
            #expect(historyBefore.count == 2)

            await client.clearHistory()
            let historyAfter = await client.conversationHistory()
            #expect(historyAfter.isEmpty)
        }

        @Test func updateConfigurationAppliesNewModel() async throws {
            URLProtocolMock.requestHandler = { _ in
                let json = #"{"output":[{"type":"message","content":[{"type":"output_text","text":"OK"}]}]}"#
                return (HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
            }

            let originalConfig = try OpenAIClientConfiguration(
                apiKey: APIKey("test-key"),
                model: .gpt5_4Mini,
                endpoint: URL(string: "https://example.com/v1/responses")!
            )

            let client = OpenAIClient(
                configuration: originalConfig,
                session: makeMockedSession()
            )

            var newConfig = originalConfig
            newConfig.model = .gpt5_4

            await client.updateConfiguration(newConfig)

            // Send after reconfiguration should succeed
            let text = try await client.send("Test")
            #expect(text == "OK")
        }

        @Test func additionalInstructionsMergedWithSystemPrompt() async throws {
            URLProtocolMock.requestHandler = { request in
                let body: Data? = request.httpBody ?? {
                    guard let stream = request.httpBodyStream else { return nil }
                    stream.open()
                    defer { stream.close() }
                    var data = Data()
                    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                    defer { buffer.deallocate() }
                    while stream.hasBytesAvailable {
                        let read = stream.read(buffer, maxLength: 4096)
                        guard read > 0 else { break }
                        data.append(buffer, count: read)
                    }
                    return data
                }()

                if let body {
                    URLProtocolMock.recordBody(body)
                }

                let json = #"{"output":[{"type":"message","content":[{"type":"output_text","text":"Done"}]}]}"#
                return (HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
            }

            let client = OpenAIClient(
                configuration: try OpenAIClientConfiguration(
                    apiKey: APIKey("test-key"),
                    systemPrompt: "You are helpful.",
                    endpoint: URL(string: "https://example.com/v1/responses")!
                ),
                session: makeMockedSession()
            )

            _ = try await client.send("Hi", additionalInstructions: "Be brief.")

            let bodies = URLProtocolMock.recordedBodies
            #expect(!bodies.isEmpty)

            let bodyString = String(data: bodies[0], encoding: .utf8) ?? ""
            #expect(bodyString.contains("You are helpful."))
            #expect(bodyString.contains("Be brief."))
        }

        @Test func retrySucceedsAfterTransientFailure() async throws {
            let counter = AtomicCounter()

            URLProtocolMock.requestHandler = { _ in
                let callCount = counter.increment()
                if callCount == 1 {
                    // First attempt: 429
                    let json = #"{"error":{"message":"Rate limited","type":"rate_limit"}}"#
                    return (HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 429, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
                } else {
                    // Second attempt: success
                    let json = #"{"output":[{"type":"message","content":[{"type":"output_text","text":"Recovered"}]}]}"#
                    return (HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
                }
            }

            let client = OpenAIClient(
                configuration: try OpenAIClientConfiguration(
                    apiKey: APIKey("test-key"),
                    retryPolicy: OpenAIClientRetryPolicy(
                        maxAttempts: 3,
                        baseDelay: 0.01,
                        maxDelay: 0.05,
                        backoffMultiplier: 1.0,
                        jitterRatio: 0.0
                    ),
                    endpoint: URL(string: "https://example.com/v1/responses")!
                ),
                session: makeMockedSession()
            )

            let text = try await client.send("Hi")
            #expect(text == "Recovered")
        }
    }

    @Suite struct HistoryTrimming {

        init() {
            URLProtocolMock.reset()
        }

        @Test func characterCountTrimsWhenExceeded() async throws {
            URLProtocolMock.requestHandler = { _ in
                let text = String(repeating: "X", count: 50)
                let json = "{\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"\(text)\"}]}]}"
                return (HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
            }

            let client = OpenAIClient(
                configuration: try OpenAIClientConfiguration(
                    apiKey: APIKey("key"),
                    historyTrimmingStrategy: .characterCount(100),
                    endpoint: URL(string: "https://example.com/v1/responses")!
                ),
                session: makeMockedSession()
            )

            _ = try await client.send("Hello")
            _ = try await client.send("World")
            _ = try await client.send("Third")

            let history = await client.conversationHistory()
            let totalChars = history.reduce(0) { $0 + $1.content.count }
            #expect(totalChars <= 100)
        }

        @Test func itemCountTrimsWhenExceeded() async throws {
            URLProtocolMock.requestHandler = { _ in
                let json = #"{"output":[{"type":"message","content":[{"type":"output_text","text":"OK"}]}]}"#
                return (HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
            }

            let client = OpenAIClient(
                configuration: try OpenAIClientConfiguration(
                    apiKey: APIKey("key"),
                    historyTrimmingStrategy: .itemCount(4),
                    endpoint: URL(string: "https://example.com/v1/responses")!
                ),
                session: makeMockedSession()
            )

            _ = try await client.send("A")
            _ = try await client.send("B")
            _ = try await client.send("C")

            let history = await client.conversationHistory()
            #expect(history.count <= 4)
        }

        @Test func unlimitedNeverTrims() async throws {
            URLProtocolMock.requestHandler = { _ in
                let json = #"{"output":[{"type":"message","content":[{"type":"output_text","text":"Reply"}]}]}"#
                return (HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
            }

            let client = OpenAIClient(
                configuration: try OpenAIClientConfiguration(
                    apiKey: APIKey("key"),
                    historyTrimmingStrategy: .unlimited,
                    endpoint: URL(string: "https://example.com/v1/responses")!
                ),
                session: makeMockedSession()
            )

            for i in 0..<10 {
                _ = try await client.send("Message \(i)")
            }

            let history = await client.conversationHistory()
            #expect(history.count == 20)
        }

        @Test func bothStrategyTrims() async throws {
            URLProtocolMock.requestHandler = { _ in
                let json = #"{"output":[{"type":"message","content":[{"type":"output_text","text":"OK"}]}]}"#
                return (HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
            }

            let client = OpenAIClient(
                configuration: try OpenAIClientConfiguration(
                    apiKey: APIKey("key"),
                    historyTrimmingStrategy: .both(maxCharacters: 10_000, maxItems: 4),
                    endpoint: URL(string: "https://example.com/v1/responses")!
                ),
                session: makeMockedSession()
            )

            _ = try await client.send("A")
            _ = try await client.send("B")
            _ = try await client.send("C")

            let history = await client.conversationHistory()
            #expect(history.count <= 4)
        }
    }
}
