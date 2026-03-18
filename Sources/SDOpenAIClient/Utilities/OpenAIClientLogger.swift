import Foundation

/// Log severity levels for `OpenAIClientLogger`.
public enum LogLevel: Sendable {
    case debug, info, warning, error
}

/// A protocol for receiving log output from `OpenAIClient`.
///
/// Implement this protocol and pass an instance via `OpenAIClientConfiguration.logger`
/// to observe request lifecycle events.
public protocol OpenAIClientLogger: Sendable {
    func log(level: LogLevel, message: String, metadata: [String: String]?)
}

/// Default logger that discards all messages.
public struct NoOpLogger: OpenAIClientLogger, Sendable {
    public init() {}
    public func log(level: LogLevel, message: String, metadata: [String: String]?) {}
}

/// A logger that prints messages to stdout. Useful during development.
public struct PrintLogger: OpenAIClientLogger, Sendable {
    public init() {}
    public func log(level: LogLevel, message: String, metadata: [String: String]?) {
        let meta = metadata.map { $0.map { "\($0.key)=\($0.value)" }.joined(separator: " ") } ?? ""
        print("[SDOpenAIClient][\(level)] \(message) \(meta)")
    }
}
