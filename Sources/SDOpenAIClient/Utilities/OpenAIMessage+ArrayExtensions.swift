import Foundation

extension Array where Element == OpenAIMessage {
    var totalCharacterCount: Int {
        reduce(into: 0) { partialResult, message in
            partialResult += message.content.count
        }
    }
}
