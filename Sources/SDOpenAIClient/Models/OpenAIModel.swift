import Foundation

/// A type-safe wrapper around OpenAI model identifiers.
///
/// Use one of the predefined static constants (e.g. `.gpt5_4Mini`) or create a custom model
/// using a string literal or `OpenAIModel(rawValue:)`.
public struct OpenAIModel: RawRepresentable, Sendable, Hashable, Codable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

// MARK: - Known Models

extension OpenAIModel {
    /// GPT-4o Mini — `gpt-4o-mini`
    public static let gpt4oMini: OpenAIModel = "gpt-4o-mini"

    /// GPT-4o — `gpt-4o`
    public static let gpt4o: OpenAIModel = "gpt-4o"

    /// GPT-5.4 — `gpt-5.4`
    public static let gpt5_4: OpenAIModel = "gpt-5.4"

    /// GPT-5.4 Mini — `gpt-5.4-mini`
    public static let gpt5_4Mini: OpenAIModel = "gpt-5.4-mini"

    /// GPT-5.4 Nano — `gpt-5.4-nano`
    public static let gpt5_4Nano: OpenAIModel = "gpt-5.4-nano"

    /// o3-mini — `o3-mini`
    public static let o3Mini: OpenAIModel = "o3-mini"

    /// o4-mini — `o4-mini`
    public static let o4Mini: OpenAIModel = "o4-mini"
}

// MARK: - CustomStringConvertible

extension OpenAIModel: CustomStringConvertible {
    public var description: String { rawValue }
}
