import Foundation

/// Controls how conversation history is trimmed before sending a new request.
public enum HistoryTrimmingStrategy: Sendable, Equatable {
    /// Trim when total character count across all history messages exceeds the limit.
    case characterCount(Int)

    /// Trim to keep at most N most-recent history items (pairs of user+assistant messages).
    case itemCount(Int)

    /// Trim by whichever limit is hit first.
    case both(maxCharacters: Int, maxItems: Int)

    /// Never trim. Use with caution — context window overflow is the caller's responsibility.
    case unlimited
}
