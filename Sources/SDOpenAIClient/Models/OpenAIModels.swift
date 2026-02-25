import Foundation

public struct OpenAIClientConfiguration: Sendable, Equatable {
    public static let defaultEndpoint = URL(string: "https://api.openai.com/v1/responses")!

    public var apiKey: String
    public var model: String
    public var systemPrompt: String
    public var temperature: Double
    public var maxContextCharacters: Int
    public var maxHistoryItems: Int
    public var requestTimeout: TimeInterval
    public var retryPolicy: OpenAIClientRetryPolicy
    public var endpoint: URL

    public init(
        apiKey: String,
        model: String = "gpt-4.1-mini",
        systemPrompt: String = "",
        temperature: Double = 0.5,
        maxContextCharacters: Int = 16_000,
        maxHistoryItems: Int = 100,
        requestTimeout: TimeInterval = 60,
        retryPolicy: OpenAIClientRetryPolicy = .standard,
        endpoint: URL = OpenAIClientConfiguration.defaultEndpoint
    ) {
        self.apiKey = apiKey
        self.model = model
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.maxContextCharacters = max(1, maxContextCharacters)
        self.maxHistoryItems = max(1, maxHistoryItems)
        self.requestTimeout = max(1, requestTimeout)
        self.retryPolicy = retryPolicy
        self.endpoint = endpoint
    }
}

public struct OpenAIClientRetryPolicy: Sendable, Equatable {
    public static let none = OpenAIClientRetryPolicy(maxAttempts: 1)
    public static let standard = OpenAIClientRetryPolicy(
        maxAttempts: 3,
        baseDelay: 0.4,
        maxDelay: 8.0,
        backoffMultiplier: 2.0,
        jitterRatio: 0.2,
        retryableStatusCodes: [408, 409, 429, 500, 502, 503, 504]
    )

    public var maxAttempts: Int
    public var baseDelay: TimeInterval
    public var maxDelay: TimeInterval
    public var backoffMultiplier: Double
    public var jitterRatio: Double
    public var retryableStatusCodes: Set<Int>

    public init(
        maxAttempts: Int = 3,
        baseDelay: TimeInterval = 0.4,
        maxDelay: TimeInterval = 8.0,
        backoffMultiplier: Double = 2.0,
        jitterRatio: Double = 0.2,
        retryableStatusCodes: Set<Int> = [408, 409, 429, 500, 502, 503, 504]
    ) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = max(0, baseDelay)
        self.maxDelay = max(0, maxDelay)
        self.backoffMultiplier = max(1, backoffMultiplier)
        self.jitterRatio = min(max(0, jitterRatio), 1)
        self.retryableStatusCodes = retryableStatusCodes
    }
}

public struct OpenAIMessage: Codable, Hashable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
        case system
        case developer
        case tool
    }

    public var role: Role
    public var content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}
