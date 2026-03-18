import Foundation
import Testing
@testable import SDOpenAIClient

@Suite
struct ConfigurationValidationTests {

    @Test func emptyAPIKeyThrows() throws {
        #expect(throws: ConfigurationError.self) {
            try OpenAIClientConfiguration(apiKey: APIKey(""))
        }
    }

    @Test func whitespaceOnlyAPIKeyThrows() throws {
        #expect(throws: ConfigurationError.self) {
            try OpenAIClientConfiguration(apiKey: APIKey("   "))
        }
    }

    @Test func temperatureBelowZeroThrows() throws {
        #expect(throws: ConfigurationError.self) {
            try OpenAIClientConfiguration(apiKey: APIKey("key"), temperature: -0.1)
        }
    }

    @Test func temperatureAboveTwoThrows() throws {
        #expect(throws: ConfigurationError.self) {
            try OpenAIClientConfiguration(apiKey: APIKey("key"), temperature: 2.1)
        }
    }

    @Test func temperatureAtBoundariesSucceeds() throws {
        let configZero = try OpenAIClientConfiguration(apiKey: APIKey("key"), temperature: 0.0)
        #expect(configZero.temperature == 0.0)

        let configTwo = try OpenAIClientConfiguration(apiKey: APIKey("key"), temperature: 2.0)
        #expect(configTwo.temperature == 2.0)
    }

    @Test func timeoutZeroThrows() throws {
        #expect(throws: ConfigurationError.self) {
            try OpenAIClientConfiguration(apiKey: APIKey("key"), requestTimeout: 0)
        }
    }

    @Test func negativeTimeoutThrows() throws {
        #expect(throws: ConfigurationError.self) {
            try OpenAIClientConfiguration(apiKey: APIKey("key"), requestTimeout: -5)
        }
    }

    @Test func validConfigurationSucceeds() throws {
        let config = try OpenAIClientConfiguration(
            apiKey: APIKey("test-key"),
            model: .gpt5_4Mini,
            temperature: 0.7,
            requestTimeout: 30
        )
        #expect(config.model == .gpt5_4Mini)
        #expect(config.temperature == 0.7)
        #expect(config.requestTimeout == 30)
    }

    @Test func apiKeyRedactedDescription() {
        let key = APIKey("sk-secret-key-12345")
        #expect("\(key)" == "APIKey([REDACTED])")
        #expect(String(reflecting: key) == "APIKey([REDACTED])")
    }
}
