import Foundation

public enum OpenAIClientConfigurationError: LocalizedError, Equatable, Sendable {
    case plistNotFound(name: String)
    case invalidPlist(url: URL)
    case missingRequiredKey(String)
    case invalidValue(key: String, expected: String)

    public var errorDescription: String? {
        switch self {
        case let .plistNotFound(name):
            return "Could not find plist named \(name)."
        case let .invalidPlist(url):
            return "Could not decode plist at \(url.path)."
        case let .missingRequiredKey(key):
            return "Missing required plist key: \(key)."
        case let .invalidValue(key, expected):
            return "Invalid value for plist key \(key). Expected \(expected)."
        }
    }
}

public extension OpenAIClientConfiguration {
    enum PlistKey {
        public static let apiKey = "apiKey"
        public static let model = "model"
        public static let systemPrompt = "systemPrompt"
        public static let temperature = "temperature"
        public static let maxContextCharacters = "maxContextCharacters"
        public static let maxHistoryItems = "maxHistoryItems"
        public static let requestTimeout = "requestTimeout"
        public static let endpoint = "endpoint"
        public static let retryMaxAttempts = "retryMaxAttempts"
        public static let retryBaseDelay = "retryBaseDelay"
        public static let retryMaxDelay = "retryMaxDelay"
        public static let retryBackoffMultiplier = "retryBackoffMultiplier"
        public static let retryJitterRatio = "retryJitterRatio"
        public static let retryableStatusCodes = "retryableStatusCodes"
    }

    /// Creates a configuration from a plist dictionary.
    /// Throws `OpenAIClientConfigurationError` for plist-level issues
    /// and `ConfigurationError` for invalid configuration values.
    init(plistDictionary: [String: Any]) throws {
        let apiKeyString = try Self.requiredStringValue(for: PlistKey.apiKey, in: plistDictionary)

        let modelString = Self.stringValue(for: PlistKey.model, in: plistDictionary) ?? "gpt-5.4-mini"
        let systemPrompt = Self.stringValue(for: PlistKey.systemPrompt, in: plistDictionary) ?? ""
        let temperature = Self.doubleValue(for: PlistKey.temperature, in: plistDictionary) ?? 0.5
        let maxContextCharacters = Self.intValue(for: PlistKey.maxContextCharacters, in: plistDictionary) ?? 16_000
        let maxHistoryItems = Self.intValue(for: PlistKey.maxHistoryItems, in: plistDictionary) ?? 100
        let requestTimeout = Self.doubleValue(for: PlistKey.requestTimeout, in: plistDictionary) ?? 60

        let endpoint: URL
        if let endpointString = Self.stringValue(for: PlistKey.endpoint, in: plistDictionary) {
            guard let parsed = URL(string: endpointString) else {
                throw OpenAIClientConfigurationError.invalidValue(
                    key: PlistKey.endpoint,
                    expected: "a valid URL string"
                )
            }
            endpoint = parsed
        } else {
            endpoint = OpenAIClientConfiguration.defaultEndpoint
        }

        let retryPolicy = OpenAIClientRetryPolicy(
            maxAttempts: Self.intValue(for: PlistKey.retryMaxAttempts, in: plistDictionary) ?? 3,
            baseDelay: Self.doubleValue(for: PlistKey.retryBaseDelay, in: plistDictionary) ?? 0.4,
            maxDelay: Self.doubleValue(for: PlistKey.retryMaxDelay, in: plistDictionary) ?? 8.0,
            backoffMultiplier: Self.doubleValue(for: PlistKey.retryBackoffMultiplier, in: plistDictionary) ?? 2.0,
            jitterRatio: Self.doubleValue(for: PlistKey.retryJitterRatio, in: plistDictionary) ?? 0.2,
            retryableStatusCodes: Set(Self.intArrayValue(for: PlistKey.retryableStatusCodes, in: plistDictionary) ?? [408, 409, 429, 500, 502, 503, 504])
        )

        try self.init(
            apiKey: APIKey(apiKeyString),
            model: OpenAIModel(rawValue: modelString),
            systemPrompt: systemPrompt,
            temperature: temperature,
            historyTrimmingStrategy: .both(maxCharacters: max(1, maxContextCharacters), maxItems: max(1, maxHistoryItems)),
            requestTimeout: requestTimeout,
            retryPolicy: retryPolicy,
            endpoint: endpoint
        )
    }

    /// Creates a configuration from a plist file at the given URL.
    init(plistURL: URL) throws {
        try self.init(plistData: Data(contentsOf: plistURL), sourceURL: plistURL)
    }

    /// Loads a configuration from a plist file in the given bundle.
    ///
    /// - Note: `Bundle.main` is unavailable in Swift Package test targets.
    ///   For testing, use `loadFromPlist(at:)` with a direct file URL instead.
    static func loadFromPlist(
        named name: String = "OpenAIClientConfiguration",
        in bundle: Bundle = .main
    ) throws -> OpenAIClientConfiguration {
        // #if DEBUG
        // Note: Bundle.main does not resolve correctly in Swift Package test targets.
        // Prefer loadFromPlist(at:) with a file URL when writing tests.
        // #endif
        guard let url = bundle.url(forResource: name, withExtension: "plist") else {
            throw OpenAIClientConfigurationError.plistNotFound(name: name)
        }
        return try OpenAIClientConfiguration(plistURL: url)
    }

    /// Loads a configuration from a plist file at the given URL.
    /// Useful in tests or when the plist is not in a bundle.
    static func loadFromPlist(at url: URL) throws -> OpenAIClientConfiguration {
        try OpenAIClientConfiguration(plistURL: url)
    }
}

// MARK: - Private Helpers

private extension OpenAIClientConfiguration {
    init(plistData data: Data, sourceURL: URL) throws {
        let raw = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dictionary = raw as? [String: Any] else {
            throw OpenAIClientConfigurationError.invalidPlist(url: sourceURL)
        }
        try self.init(plistDictionary: dictionary)
    }

    static func stringValue(for key: String, in dictionary: [String: Any]) -> String? {
        guard let value = dictionary[key] as? String else {
            return nil
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func requiredStringValue(for key: String, in dictionary: [String: Any]) throws -> String {
        guard let value = stringValue(for: key, in: dictionary), !value.isEmpty else {
            throw OpenAIClientConfigurationError.missingRequiredKey(key)
        }
        return value
    }

    static func intValue(for key: String, in dictionary: [String: Any]) -> Int? {
        if let number = dictionary[key] as? NSNumber {
            return number.intValue
        }
        return dictionary[key] as? Int
    }

    static func doubleValue(for key: String, in dictionary: [String: Any]) -> Double? {
        if let number = dictionary[key] as? NSNumber {
            return number.doubleValue
        }
        return dictionary[key] as? Double
    }

    static func intArrayValue(for key: String, in dictionary: [String: Any]) -> [Int]? {
        if let values = dictionary[key] as? [Int] {
            return values
        }
        if let values = dictionary[key] as? [NSNumber] {
            return values.map(\.intValue)
        }
        return nil
    }
}
