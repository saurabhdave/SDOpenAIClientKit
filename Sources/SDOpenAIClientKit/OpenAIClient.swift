import Foundation

public actor OpenAIClient {
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

    public func updateConfiguration(_ configuration: OpenAIClientConfiguration) {
        self.configuration = configuration
        trimHistoryIfNeeded()
    }

    public func clearHistory() {
        history.removeAll(keepingCapacity: true)
    }

    public func conversationHistory() -> [OpenAIMessage] {
        history
    }

    public func send(_ text: String, additionalInstructions: String? = nil) async throws -> String {
        let apiKey = try validatedAPIKey()
        let conversation = buildConversation(withUserText: text)
        let body = try makeBody(
            conversation: conversation,
            stream: false,
            additionalInstructions: additionalInstructions
        )
        let data = try await executeDataRequest(apiKey: apiKey, body: body)

        let responseText = try decodeResponseText(from: data)
        appendTurn(userText: text, assistantText: responseText)
        return responseText
    }

    public func stream(_ text: String, additionalInstructions: String? = nil) async throws -> AsyncThrowingStream<String, Error> {
        let apiKey = try validatedAPIKey()
        let conversation = buildConversation(withUserText: text)
        let body = try makeBody(
            conversation: conversation,
            stream: true,
            additionalInstructions: additionalInstructions
        )
        let bytes = try await executeStreamRequest(apiKey: apiKey, body: body)

        return AsyncThrowingStream<String, Error> { continuation in
            let streamTask = Task(priority: .userInitiated) {
                let streamDecoder = Self.makeDecoder()

                do {
                    var buffer = ""

                    for try await line in bytes.lines {
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
                        continuation.yield(delta)
                    }

                    self.appendTurn(userText: text, assistantText: buffer)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                streamTask.cancel()
            }
        }
    }
}

private extension OpenAIClient {
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    func validatedAPIKey() throws -> String {
        let trimmed = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OpenAIClientError.missingAPIKey
        }
        return trimmed
    }

    func makeURLRequest(apiKey: String) -> URLRequest {
        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.requestTimeout
        request.setValue(Header.json, forHTTPHeaderField: Header.contentType)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: Header.authorization)
        request.setValue(Header.jsonAndSSE, forHTTPHeaderField: Header.accept)
        return request
    }

    func makeBody(conversation: [OpenAIMessage], stream: Bool, additionalInstructions: String?) throws -> Data {
        let request = ResponsesRequest(
            model: configuration.model,
            instructions: mergedInstructions(with: additionalInstructions),
            input: makeInputItems(from: conversation),
            stream: stream,
            temperature: configuration.temperature
        )
        return try encoder.encode(request)
    }

    func executeDataRequest(apiKey: String, body: Data) async throws -> Data {
        try await withRetry {
            var request = makeURLRequest(apiKey: apiKey)
            request.httpBody = body

            let (data, response) = try await session.data(for: request)
            try validateHTTPResponse(response, data: data)
            return data
        }
    }

    func executeStreamRequest(apiKey: String, body: Data) async throws -> URLSession.AsyncBytes {
        try await withRetry {
            var request = makeURLRequest(apiKey: apiKey)
            request.httpBody = body

            let (bytes, response) = try await session.bytes(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                let errorData = try await collectErrorData(from: bytes)
                try validateHTTPResponse(response, data: errorData)
            }

            return bytes
        }
    }

    func withRetry<T>(_ operation: () async throws -> T) async throws -> T {
        let policy = configuration.retryPolicy
        var attempt = 1

        while true {
            do {
                return try await operation()
            } catch {
                guard attempt < policy.maxAttempts, shouldRetry(error, with: policy) else {
                    throw error
                }

                let delay = retryDelay(forAttempt: attempt, policy: policy)
                if delay > 0 {
                    let nanoseconds = UInt64((delay * 1_000_000_000).rounded())
                    try await Task.sleep(nanoseconds: nanoseconds)
                }

                attempt += 1
            }
        }
    }

    func shouldRetry(_ error: Error, with policy: OpenAIClientRetryPolicy) -> Bool {
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

    func retryDelay(forAttempt attempt: Int, policy: OpenAIClientRetryPolicy) -> TimeInterval {
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

        while messages.totalCharacterCount > configuration.maxContextCharacters,
              !trimmedHistory.isEmpty {
            trimmedHistory.removeFirst(min(2, trimmedHistory.count))
            messages = trimmedHistory + [userMessage]
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
        guard history.count > configuration.maxHistoryItems else {
            return
        }

        let overflow = history.count - configuration.maxHistoryItems
        history.removeFirst(overflow)
    }

    func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponse
        }

        guard 200...299 ~= httpResponse.statusCode else {
            throw OpenAIClientError.badResponse(
                statusCode: httpResponse.statusCode,
                message: decodeErrorMessage(from: data)
            )
        }
    }

    func decodeErrorMessage(from data: Data) -> String {
        if let decoded = try? decoder.decode(ErrorRootResponse.self, from: data) {
            return decoded.error.message
        }

        if let raw = String(data: data, encoding: .utf8) {
            return raw
        }

        return ""
    }

    func decodeResponseText(from data: Data) throws -> String {
        let response = try decoder.decode(ResponsesAPIResponse.self, from: data)
        let messageItems = response.output.filter { $0.type == nil || $0.type == "message" }
        let outputContents = messageItems.flatMap { $0.content ?? [] }
        let outputTextItems = outputContents.filter { $0.type == nil || $0.type == "output_text" }
        let text = outputTextItems.compactMap(\.text).joined()

        guard !text.isEmpty else {
            throw OpenAIClientError.emptyResponse
        }

        return text
    }

    func collectErrorData(from bytes: URLSession.AsyncBytes) async throws -> Data {
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
