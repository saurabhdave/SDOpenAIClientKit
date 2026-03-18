import Foundation

struct ResponsesRequest: Encodable, Sendable {
    let model: String
    let instructions: String?
    let input: [ResponseInputItem]
    let stream: Bool
    let temperature: Double
}

struct ResponseInputItem: Encodable, Sendable {
    let role: OpenAIMessage.Role
    let content: String
}

struct ResponsesAPIResponse: Decodable, Sendable {
    let output: [ResponseOutputItem]
    let usage: ResponseMetadata?
}

struct ResponseOutputItem: Decodable, Sendable {
    let type: String?
    let content: [ResponseOutputContent]?
}

struct ResponseOutputContent: Decodable, Sendable {
    let type: String?
    let text: String?
}

struct ResponsesStreamEvent: Decodable, Sendable {
    let type: String
    let delta: String?
    let error: ErrorResponse?
}

struct ErrorRootResponse: Decodable, Sendable {
    let error: ErrorResponse
}

struct ErrorResponse: Decodable, Sendable {
    let message: String
    let type: String?
}
