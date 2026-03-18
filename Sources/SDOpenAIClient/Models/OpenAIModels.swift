import Foundation

public struct OpenAIClientConfiguration: Sendable, Equatable {
    public static let defaultEndpoint = URL(string: "https://api.openai.com/v1/responses")!

    /// The API key used for authentication. Wrapped in `APIKey` to prevent accidental logging.
    public var apiKey: APIKey

    /// The model to use for requests.
    public var model: OpenAIModel

    /// System prompt prepended to every request as `instructions`.
    public var systemPrompt: String

    /// Sampling temperature (0.0–2.0).
    public var temperature: Double

    /// Maximum total character count across all history messages before trimming.
    @available(*, deprecated, renamed: "historyTrimmingStrategy")
    public var maxContextCharacters: Int {
        get {
            switch historyTrimmingStrategy {
            case .characterCount(let n):
                return n
            case .both(let maxChars, _):
                return maxChars
            default:
                return 16_000
            }
        }
        set {
            switch historyTrimmingStrategy {
            case .both(_, let maxItems):
                historyTrimmingStrategy = .both(maxCharacters: newValue, maxItems: maxItems)
            case .characterCount:
                historyTrimmingStrategy = .characterCount(newValue)
            default:
                break
            }
        }
    }

    /// Maximum number of history items before trimming.
    @available(*, deprecated, renamed: "historyTrimmingStrategy")
    public var maxHistoryItems: Int {
        get {
            switch historyTrimmingStrategy {
            case .itemCount(let n):
                return n
            case .both(_, let maxItems):
                return maxItems
            default:
                return 100
            }
        }
        set {
            switch historyTrimmingStrategy {
            case .both(let maxChars, _):
                historyTrimmingStrategy = .both(maxCharacters: maxChars, maxItems: newValue)
            case .itemCount:
                historyTrimmingStrategy = .itemCount(newValue)
            default:
                break
            }
        }
    }

    /// Per-request timeout interval in seconds.
    public var requestTimeout: TimeInterval

    /// Retry policy for transient failures.
    public var retryPolicy: OpenAIClientRetryPolicy

    /// The API endpoint URL.
    public var endpoint: URL

    /// Strategy controlling how conversation history is trimmed.
    public var historyTrimmingStrategy: HistoryTrimmingStrategy

    /// Logger receiving lifecycle events from the client.
    public var logger: any OpenAIClientLogger

    /// Creates a validated configuration. Throws `ConfigurationError` if any value is invalid.
    public init(
        apiKey: APIKey,
        model: OpenAIModel = .gpt5_4Mini,
        systemPrompt: String = "",
        temperature: Double = 0.5,
        historyTrimmingStrategy: HistoryTrimmingStrategy = .both(maxCharacters: 16_000, maxItems: 100),
        requestTimeout: TimeInterval = 60,
        retryPolicy: OpenAIClientRetryPolicy = .standard,
        endpoint: URL = OpenAIClientConfiguration.defaultEndpoint,
        logger: any OpenAIClientLogger = NoOpLogger()
    ) throws {
        guard !apiKey.isEmpty else {
            throw ConfigurationError.emptyAPIKey
        }
        guard (0.0...2.0).contains(temperature) else {
            throw ConfigurationError.invalidTemperature(temperature)
        }
        guard requestTimeout > 0 else {
            throw ConfigurationError.invalidTimeout(requestTimeout)
        }
        guard !endpoint.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConfigurationError.emptyEndpoint
        }

        self.apiKey = apiKey
        self.model = model
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.historyTrimmingStrategy = historyTrimmingStrategy
        self.requestTimeout = requestTimeout
        self.retryPolicy = retryPolicy
        self.endpoint = endpoint
        self.logger = logger
    }

    /// Backwards-compatible initializer accepting `String` for `apiKey` and `model`.
    @available(*, deprecated, message: "Use init(apiKey: APIKey, model: OpenAIModel, ...) instead")
    public init(
        apiKey: String,
        model: String = "gpt-5.4-mini",
        systemPrompt: String = "",
        temperature: Double = 0.5,
        maxContextCharacters: Int = 16_000,
        maxHistoryItems: Int = 100,
        requestTimeout: TimeInterval = 60,
        retryPolicy: OpenAIClientRetryPolicy = .standard,
        endpoint: URL = OpenAIClientConfiguration.defaultEndpoint
    ) throws {
        try self.init(
            apiKey: APIKey(apiKey),
            model: OpenAIModel(rawValue: model),
            systemPrompt: systemPrompt,
            temperature: temperature,
            historyTrimmingStrategy: .both(maxCharacters: max(1, maxContextCharacters), maxItems: max(1, maxHistoryItems)),
            requestTimeout: requestTimeout,
            retryPolicy: retryPolicy,
            endpoint: endpoint
        )
    }

    // Equatable — logger is excluded from comparison since protocols aren't Equatable
    public static func == (lhs: OpenAIClientConfiguration, rhs: OpenAIClientConfiguration) -> Bool {
        lhs.apiKey == rhs.apiKey &&
        lhs.model == rhs.model &&
        lhs.systemPrompt == rhs.systemPrompt &&
        lhs.temperature == rhs.temperature &&
        lhs.historyTrimmingStrategy == rhs.historyTrimmingStrategy &&
        lhs.requestTimeout == rhs.requestTimeout &&
        lhs.retryPolicy == rhs.retryPolicy &&
        lhs.endpoint == rhs.endpoint
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
