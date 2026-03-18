import Foundation
import Testing
@testable import SDOpenAIClient

@Suite
struct OpenAIModelTests {

    @Test func knownModelRawValues() {
        #expect(OpenAIModel.gpt4oMini.rawValue == "gpt-4o-mini")
        #expect(OpenAIModel.gpt4o.rawValue == "gpt-4o")
        #expect(OpenAIModel.gpt5_4.rawValue == "gpt-5.4")
        #expect(OpenAIModel.gpt5_4Mini.rawValue == "gpt-5.4-mini")
        #expect(OpenAIModel.gpt5_4Nano.rawValue == "gpt-5.4-nano")
        #expect(OpenAIModel.o3Mini.rawValue == "o3-mini")
        #expect(OpenAIModel.o4Mini.rawValue == "o4-mini")
    }

    @Test func expressibleByStringLiteral() {
        let model: OpenAIModel = "custom-model"
        #expect(model.rawValue == "custom-model")
    }

    @Test func customStringConvertible() {
        let model = OpenAIModel.gpt4o
        #expect(model.description == "gpt-4o")
        #expect("\(model)" == "gpt-4o")
    }

    @Test func codableRoundTrip() throws {
        let original = OpenAIModel.gpt5_4Mini
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(OpenAIModel.self, from: data)
        #expect(original == decoded)
    }

    @Test func codableCustomModel() throws {
        let original = OpenAIModel(rawValue: "my-fine-tuned-model")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(OpenAIModel.self, from: data)
        #expect(decoded.rawValue == "my-fine-tuned-model")
    }

    @Test func hashableConformance() {
        var set: Set<OpenAIModel> = []
        set.insert(.gpt4o)
        set.insert(.gpt4o)
        set.insert(.gpt5_4Mini)
        #expect(set.count == 2)
    }

    @Test func equalityWithRawValue() {
        let a = OpenAIModel(rawValue: "gpt-4o")
        let b = OpenAIModel.gpt4o
        #expect(a == b)
    }
}
