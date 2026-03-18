import Foundation

public enum OpenAIClientError: LocalizedError, Equatable, Sendable {
    case invalidResponse
    case emptyResponse
    case badResponse(statusCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from OpenAI API."
        case .emptyResponse:
            return "OpenAI API returned an empty text response."
        case let .badResponse(statusCode, message):
            if message.isEmpty {
                return "OpenAI API request failed with status code \(statusCode)."
            }
            return "OpenAI API request failed with status code \(statusCode): \(message)"
        }
    }
}
