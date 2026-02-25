import Foundation

struct ResponsesRequest: Encodable {
    let model: String
    let instructions: String?
    let input: [ResponseInputItem]
    let stream: Bool
    let temperature: Double
}

struct ResponseInputItem: Encodable {
    let role: OpenAIMessage.Role
    let content: String
}

struct ResponsesAPIResponse: Decodable {
    let output: [ResponseOutputItem]
}

struct ResponseOutputItem: Decodable {
    let type: String?
    let content: [ResponseOutputContent]?
}

struct ResponseOutputContent: Decodable {
    let type: String?
    let text: String?
}

struct ResponsesStreamEvent: Decodable {
    let type: String
    let delta: String?
    let error: ErrorResponse?
}

struct ErrorRootResponse: Decodable {
    let error: ErrorResponse
}

struct ErrorResponse: Decodable {
    let message: String
    let type: String?
}
