import Foundation

/// A secure wrapper for OpenAI API keys that prevents accidental logging or serialization.
///
/// `APIKey` intentionally does not conform to `Encodable`, `Decodable`, or any protocol
/// that would expose the raw key value. Its `description` and `debugDescription` are redacted.
public struct APIKey: Sendable {
    private let value: String

    /// Creates an API key from a raw string value.
    public init(_ value: String) {
        self.value = value
    }

    /// Returns the full Authorization header value. Internal use only.
    internal func authorizationHeaderValue() -> String {
        "Bearer \(value)"
    }

    /// Returns `true` if the underlying key string (after trimming whitespace) is empty.
    internal var isEmpty: Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - CustomStringConvertible

extension APIKey: CustomStringConvertible {
    public var description: String { "APIKey([REDACTED])" }
}

// MARK: - CustomDebugStringConvertible

extension APIKey: CustomDebugStringConvertible {
    public var debugDescription: String { "APIKey([REDACTED])" }
}

// MARK: - Equatable

extension APIKey: Equatable {
    public static func == (lhs: APIKey, rhs: APIKey) -> Bool {
        lhs.value == rhs.value
    }
}

// MARK: - Hashable

extension APIKey: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
}
