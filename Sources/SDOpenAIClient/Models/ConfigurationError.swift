import Foundation

/// Validation errors thrown when constructing an `OpenAIClientConfiguration` with invalid values.
public enum ConfigurationError: Error, LocalizedError, Equatable {
    case emptyAPIKey
    case invalidTemperature(Double)
    case invalidTimeout(TimeInterval)
    case invalidMaxHistoryItems(Int)
    case invalidRetryAttempts(Int)
    case invalidBaseDelay(TimeInterval)
    case emptyEndpoint

    public var errorDescription: String? {
        switch self {
        case .emptyAPIKey:
            return "API key must not be empty."
        case .invalidTemperature(let t):
            return "Temperature \(t) is out of range. Must be between 0.0 and 2.0."
        case .invalidTimeout(let t):
            return "Request timeout \(t) must be greater than 0."
        case .invalidMaxHistoryItems(let n):
            return "maxHistoryItems \(n) must be at least 1."
        case .invalidRetryAttempts(let n):
            return "retryMaxAttempts \(n) must be 0 or greater."
        case .invalidBaseDelay(let d):
            return "retryBaseDelay \(d) must be greater than 0."
        case .emptyEndpoint:
            return "Endpoint URL string must not be empty."
        }
    }
}
