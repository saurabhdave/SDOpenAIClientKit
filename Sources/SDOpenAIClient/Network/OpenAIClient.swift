import Foundation

public actor OpenAIClient: OpenAIClientProtocol {
    private enum Header {
        static let contentType = "Content-Type"
        static let authorization = "Authorization"
        static let accept = "Accept"

        static let json = "application/json"
        static let jsonAndSSE = "application/json, text/event-stream"
    }

    private var configuration: OpenAIClientConfiguration
    private var history: [OpenAIMessage] = []

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        configuration: OpenAIClientConfiguration,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session

        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    /// Replaces the current configuration and trims history according to the new strategy.
    public func updateConfiguration(_ configuration: OpenAIClientConfiguration) {
        self.configuration = configuration
        trimHistoryIfNeeded()
    }

    public func clearHistory() {
        history.removeAll(keepingCapacity: true)
    }

    /// Returns a snapshot of the current conversation history.
    public func conversationHistory() -> [OpenAIMessage] {
        history
    }

    // MARK: - OpenAIClientProtocol conformance (single-parameter signatures)

    public func send(_ text: String) async throws -> String {
        try await send(text, additionalInstructions: nil)
    }

    public func sendWithMetadata(_ text: String) async throws -> (text: String, metadata: ResponseMetadata?) {
        try await sendWithMetadata(text, additionalInstructions: nil)
    }

    public func stream(_ text: String) async throws -> AsyncThrowingStream<String, Error> {
        try await stream(text, additionalInstructions: nil)
    }

    // MARK: - Full-signature public methods

    /// Sends a prompt and returns the full response text.
    public func send(_ text: String, additionalInstructions: String?) async throws -> String {
        let (responseText, _) = try await performSend(text, additionalInstructions: additionalInstructions)
        return responseText
    }

    /// Sends a prompt and returns both the response text and token usage metadata.
    public func sendWithMetadata(_ text: String, additionalInstructions: String?) async throws -> (text: String, metadata: ResponseMetadata?) {
        try await performSend(text, additionalInstructions: additionalInstructions)
    }

    /// Streams a prompt response, yielding text deltas as they arrive.
    public func stream(_ text: String, additionalInstructions: String?) async throws -> AsyncThrowingStream<String, Error> {
        let authHeader = configuration.apiKey.authorizationHeaderValue()
        let conversation = buildConversation(withUserText: text)
        let body = try makeBody(
            conversation: conversation,
            stream: true,
            additionalInstructions: additionalInstructions
        )

        let logger = configuration.logger
        let model = configuration.model
        logger.log(level: .debug, message: "Stream request start", metadata: [
            "model": model.rawValue,
            "promptCharacters": "\(text.count)"
        ])

        let bytes = try await executeStreamRequest(authHeader: authHeader, body: body)

        return AsyncThrowingStream<String, Error> { continuation in
            let streamTask = Task(priority: .userInitiated) { [weak self] in
                let streamDecoder = Self.makeDecoder()

                do {
                    var buffer = ""

                    for try await line in bytes.lines {
                        try Task.checkCancellation()

                        guard line.hasPrefix("data: ") else { continue }

                        let payload = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                        if payload.isEmpty {
                            continue
                        }
                        if payload == "[DONE]" {
                            break
                        }

                        guard let data = payload.data(using: .utf8) else {
                            continue
                        }

                        if let errorEnvelope = try? streamDecoder.decode(ErrorRootResponse.self, from: data) {
                            throw OpenAIClientError.badResponse(statusCode: 500, message: errorEnvelope.error.message)
                        }

                        let event = try streamDecoder.decode(ResponsesStreamEvent.self, from: data)
                        if event.type.contains("error"), let message = event.error?.message {
                            throw OpenAIClientError.badResponse(statusCode: 500, message: message)
                        }

                        guard event.type == "response.output_text.delta",
                              let delta = event.delta,
                              !delta.isEmpty else {
                            continue
                        }

                        buffer += delta
                        logger.log(level: .debug, message: "Stream delta received", metadata: [
                            "deltaLength": "\(delta.count)"
                        ])
                        continuation.yield(delta)
                    }

                    await self?.appendTurn(userText: text, assistantText: buffer)
                    logger.log(level: .info, message: "Stream request complete", metadata: [
                        "model": model.rawValue,
                        "responseCharacters": "\(buffer.count)"
                    ])
                    continuation.finish()
                } catch {
                    logger.log(level: .error, message: "Stream request failed", metadata: [
                        "error": error.localizedDescription
                    ])
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                streamTask.cancel()
            }
        }
    }
}

// MARK: - Private Helpers

private extension OpenAIClient {
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    func performSend(_ text: String, additionalInstructions: String?) async throws -> (text: String, metadata: ResponseMetadata?) {
        let authHeader = configuration.apiKey.authorizationHeaderValue()
        let conversation = buildConversation(withUserText: text)
        let body = try makeBody(
            conversation: conversation,
            stream: false,
            additionalInstructions: additionalInstructions
        )

        let logger = configuration.logger
        let model = configuration.model
        logger.log(level: .debug, message: "Request start", metadata: [
            "model": model.rawValue,
            "promptCharacters": "\(text.count)"
        ])

        let startTime = CFAbsoluteTimeGetCurrent()
        let data = try await executeDataRequest(authHeader: authHeader, body: body)
        try Task.checkCancellation()

        let (responseText, metadata) = try decodeResponseTextAndMetadata(from: data)
        appendTurn(userText: text, assistantText: responseText)

        let latencyMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        var logMeta: [String: String] = [
            "model": model.rawValue,
            "latencyMs": "\(latencyMs)"
        ]
        if let metadata {
            logMeta["totalTokens"] = "\(metadata.totalTokens)"
        }
        logger.log(level: .info, message: "Request complete", metadata: logMeta)

        return (text: responseText, metadata: metadata)
    }

    func makeURLRequest(authHeader: String) -> URLRequest {
        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.requestTimeout
        request.setValue(Header.json, forHTTPHeaderField: Header.contentType)
        request.setValue(authHeader, forHTTPHeaderField: Header.authorization)
        request.setValue(Header.jsonAndSSE, forHTTPHeaderField: Header.accept)
        return request
    }

    func makeBody(conversation: [OpenAIMessage], stream: Bool, additionalInstructions: String?) throws -> Data {
        let request = ResponsesRequest(
            model: configuration.model.rawValue,
            instructions: mergedInstructions(with: additionalInstructions),
            input: makeInputItems(from: conversation),
            stream: stream,
            temperature: configuration.temperature
        )
        return try encoder.encode(request)
    }

    func executeDataRequest(authHeader: String, body: Data) async throws -> Data {
        let session = self.session
        let request = makeDataURLRequest(authHeader: authHeader, body: body)
        let decoder = self.decoder

        return try await withRetry { [decoder] in
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            try Self.validateHTTPResponse(response, data: data, decoder: decoder)
            return data
        }
    }

    func executeStreamRequest(authHeader: String, body: Data) async throws -> URLSession.AsyncBytes {
        let session = self.session
        let request = makeDataURLRequest(authHeader: authHeader, body: body)
        let decoder = self.decoder

        return try await withRetry { [decoder] in
            let (bytes, response) = try await session.bytes(for: request)
            try Task.checkCancellation()

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                let errorData = try await Self.collectErrorData(from: bytes)
                try Self.validateHTTPResponse(response, data: errorData, decoder: decoder)
            }

            return bytes
        }
    }

    func makeDataURLRequest(authHeader: String, body: Data) -> URLRequest {
        var request = makeURLRequest(authHeader: authHeader)
        request.httpBody = body
        return request
    }

    func withRetry<T>(_ operation: @Sendable () async throws -> T) async throws -> T {
        let policy = configuration.retryPolicy
        let logger = configuration.logger
        var attempt = 1

        while true {
            do {
                return try await operation()
            } catch {
                guard attempt < policy.maxAttempts, Self.shouldRetry(error, with: policy) else {
                    logger.log(level: .error, message: "Request failed after all retries", metadata: [
                        "attempts": "\(attempt)",
                        "error": error.localizedDescription
                    ])
                    throw error
                }

                let delay = Self.retryDelay(forAttempt: attempt, policy: policy)

                var statusCode = "unknown"
                if let clientError = error as? OpenAIClientError,
                   case let .badResponse(code, _) = clientError {
                    statusCode = "\(code)"
                }

                logger.log(level: .warning, message: "Retrying request", metadata: [
                    "attempt": "\(attempt + 1)",
                    "statusCode": statusCode,
                    "delayMs": "\(Int(delay * 1000))"
                ])

                if delay > 0 {
                    try await Task.sleep(for: .seconds(delay))
                }

                attempt += 1
            }
        }
    }

    static func shouldRetry(_ error: Error, with policy: OpenAIClientRetryPolicy) -> Bool {
        if error is CancellationError {
            return false
        }

        if let urlError = error as? URLError {
            return urlError.code != .cancelled
        }

        if let clientError = error as? OpenAIClientError,
           case let .badResponse(statusCode, _) = clientError {
            return policy.retryableStatusCodes.contains(statusCode)
        }

        return false
    }

    static func retryDelay(forAttempt attempt: Int, policy: OpenAIClientRetryPolicy) -> TimeInterval {
        let exponent = pow(policy.backoffMultiplier, Double(max(0, attempt - 1)))
        let baseDelay = min(policy.maxDelay, policy.baseDelay * exponent)
        let jitter = baseDelay * policy.jitterRatio
        let randomized = baseDelay + Double.random(in: -jitter...jitter)
        return max(0, randomized)
    }

    func mergedInstructions(with additionalInstructions: String?) -> String? {
        let base = configuration.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let extra = (additionalInstructions ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        switch (base.isEmpty, extra.isEmpty) {
        case (true, true):
            return nil
        case (false, true):
            return base
        case (true, false):
            return extra
        case (false, false):
            return "\(base)\n\n\(extra)"
        }
    }

    func buildConversation(withUserText text: String) -> [OpenAIMessage] {
        let userMessage = OpenAIMessage(role: .user, content: text)
        var trimmedHistory = history
        var messages = trimmedHistory + [userMessage]

        switch configuration.historyTrimmingStrategy {
        case .characterCount(let maxChars):
            while messages.totalCharacterCount > maxChars, !trimmedHistory.isEmpty {
                trimmedHistory.removeFirst(min(2, trimmedHistory.count))
                messages = trimmedHistory + [userMessage]
            }

        case .itemCount(let maxItems):
            while trimmedHistory.count > maxItems, !trimmedHistory.isEmpty {
                trimmedHistory.removeFirst(min(2, trimmedHistory.count))
                messages = trimmedHistory + [userMessage]
            }

        case .both(let maxChars, let maxItems):
            while (messages.totalCharacterCount > maxChars || trimmedHistory.count > maxItems),
                  !trimmedHistory.isEmpty {
                trimmedHistory.removeFirst(min(2, trimmedHistory.count))
                messages = trimmedHistory + [userMessage]
            }

        case .unlimited:
            break
        }

        history = trimmedHistory
        return messages
    }

    func makeInputItems(from messages: [OpenAIMessage]) -> [ResponseInputItem] {
        messages.map { message in
            ResponseInputItem(role: message.role, content: message.content)
        }
    }

    func appendTurn(userText: String, assistantText: String) {
        history.append(OpenAIMessage(role: .user, content: userText))
        history.append(OpenAIMessage(role: .assistant, content: assistantText))
        trimHistoryIfNeeded()
    }

    func trimHistoryIfNeeded() {
        switch configuration.historyTrimmingStrategy {
        case .characterCount(let maxChars):
            while history.totalCharacterCount > maxChars, !history.isEmpty {
                history.removeFirst(min(2, history.count))
            }

        case .itemCount(let maxItems):
            if history.count > maxItems {
                let overflow = history.count - maxItems
                history.removeFirst(overflow)
            }

        case .both(let maxChars, let maxItems):
            if history.count > maxItems {
                let overflow = history.count - maxItems
                history.removeFirst(overflow)
            }
            while history.totalCharacterCount > maxChars, !history.isEmpty {
                history.removeFirst(min(2, history.count))
            }

        case .unlimited:
            break
        }
    }

    static func validateHTTPResponse(_ response: URLResponse, data: Data, decoder: JSONDecoder) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponse
        }

        guard 200...299 ~= httpResponse.statusCode else {
            throw OpenAIClientError.badResponse(
                statusCode: httpResponse.statusCode,
                message: Self.decodeErrorMessage(from: data, decoder: decoder)
            )
        }
    }

    static func decodeErrorMessage(from data: Data, decoder: JSONDecoder) -> String {
        if let decoded = try? decoder.decode(ErrorRootResponse.self, from: data) {
            return decoded.error.message
        }

        if let raw = String(data: data, encoding: .utf8) {
            return raw
        }

        return ""
    }

    func decodeResponseTextAndMetadata(from data: Data) throws -> (text: String, metadata: ResponseMetadata?) {
        let response = try decoder.decode(ResponsesAPIResponse.self, from: data)
        let messageItems = response.output.filter { $0.type == nil || $0.type == "message" }
        let outputContents = messageItems.flatMap { $0.content ?? [] }
        let outputTextItems = outputContents.filter { $0.type == nil || $0.type == "output_text" }
        let text = outputTextItems.compactMap(\.text).joined()

        guard !text.isEmpty else {
            throw OpenAIClientError.emptyResponse
        }

        return (text: text, metadata: response.usage)
    }

    static func collectErrorData(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var payloads: [String] = []

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            if payload.isEmpty || payload == "[DONE]" {
                continue
            }
            payloads.append(payload)
        }

        return payloads.joined(separator: "\n").data(using: .utf8) ?? Data()
    }
}
