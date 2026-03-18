
<p align="center">
<img width="1408" height="768" alt="image_0" src="https://github.com/user-attachments/assets/57989062-1171-46a1-8af3-e22a6e497ad1" />
</p>

# SDOpenAIClient

A lightweight, zero-dependency Swift Package wrapper for OpenAI's `responses` API with:

- Non-stream and stream text generation
- Built-in multi-turn memory with flexible history trimming
- Robust HTTP and streaming error handling with retry support
- Type-safe API key and model handling
- Protocol-based dependency injection for easy testing
- Token usage metadata tracking
- Configurable logging
- Swift 6 strict concurrency compliance

## Platforms

iOS 18+ · macOS 15+ · tvOS 18+ · watchOS 11+ · visionOS 2+

## Installation

Use Swift Package Manager from any iOS project.

In Xcode:

1. `File` -> `Swift Packages` -> `Add Package Dependency...`
2. Enter `https://github.com/saurabhdave/SDOpenAIClientKit.git`
3. Choose dependency rule `Up to Next Major Version` and set `2.0.0`
4. Click `Add Package`
5. Import in your code:

```swift
import SDOpenAIClient
```

Or with SwiftPM:

```swift
.package(url: "https://github.com/saurabhdave/SDOpenAIClientKit.git", from: "2.0.0")
```

Then add the product to your target dependencies:

```swift
.product(name: "SDOpenAIClient", package: "SDOpenAIClientKit")
```

For local development:

```swift
.package(path: "./SDOpenAIClientKit")
```

## Quick Start

```swift
import SDOpenAIClient

let client = OpenAIClient(
    configuration: try OpenAIClientConfiguration(
        apiKey: APIKey("your-api-key"),
        model: .gpt5_4Mini,
        systemPrompt: "You are a concise assistant.",
        temperature: 0.4,
        requestTimeout: 45,
        retryPolicy: .standard
    )
)

let text = try await client.send("Summarize dependency injection in 3 bullet points.")
print(text)
```

## Streaming

```swift
let stream = try await client.stream("Write a short poem about rain.")
for try await delta in stream {
    print(delta, terminator: "")
}
```

## Token Usage Metadata

```swift
let (text, metadata) = try await client.sendWithMetadata("Hello!")
if let metadata {
    print("Input tokens: \(metadata.inputTokens)")
    print("Output tokens: \(metadata.outputTokens)")
    print("Total tokens: \(metadata.totalTokens)")
}
```

## Type-Safe Models

Use the `OpenAIModel` type for compile-time safety with built-in constants:

```swift
let config = try OpenAIClientConfiguration(
    apiKey: APIKey("key"),
    model: .gpt4o           // or .gpt5_4, .gpt5_4Mini, .gpt5_4Nano, .o3Mini, .o4Mini
)
```

Custom models are supported via string literals or `OpenAIModel(rawValue:)`:

```swift
let model: OpenAIModel = "my-fine-tuned-model"
```

## API Key Security

The `APIKey` type wraps your key and redacts it from logs:

```swift
let key = APIKey("sk-abc123")
print(key)       // "APIKey([REDACTED])"
debugPrint(key)  // "APIKey([REDACTED])"
```

## History Trimming

Control how conversation history is managed:

```swift
// Trim when total characters exceed 10,000
let config = try OpenAIClientConfiguration(
    apiKey: APIKey("key"),
    historyTrimmingStrategy: .characterCount(10_000)
)

// Keep at most 50 history items
let config2 = try OpenAIClientConfiguration(
    apiKey: APIKey("key"),
    historyTrimmingStrategy: .itemCount(50)
)

// Trim by whichever limit is hit first (default)
let config3 = try OpenAIClientConfiguration(
    apiKey: APIKey("key"),
    historyTrimmingStrategy: .both(maxCharacters: 16_000, maxItems: 100)
)

// Never trim (caller manages overflow)
let config4 = try OpenAIClientConfiguration(
    apiKey: APIKey("key"),
    historyTrimmingStrategy: .unlimited
)
```

## Logging

Attach a logger to receive lifecycle events:

```swift
// Built-in console logger
let config = try OpenAIClientConfiguration(
    apiKey: APIKey("key"),
    logger: PrintLogger()
)

// Custom logger — conform to OpenAIClientLogger
struct MyLogger: OpenAIClientLogger {
    func log(level: LogLevel, message: String, metadata: [String: String]?) {
        // Send to your logging backend
    }
}
```

## Protocol-Based Dependency Injection

`OpenAIClient` conforms to `OpenAIClientProtocol`, enabling easy mocking in tests:

```swift
protocol OpenAIClientProtocol: Sendable {
    func send(_ prompt: String) async throws -> String
    func sendWithMetadata(_ prompt: String) async throws -> (text: String, metadata: ResponseMetadata?)
    func stream(_ prompt: String) async throws -> AsyncThrowingStream<String, Error>
    func clearHistory() async
}
```

Use the built-in `MockOpenAIClient` in tests:

```swift
let mock = MockOpenAIClient()
mock.stubbedResponse = "Mocked response"
mock.stubbedMetadata = ResponseMetadata(inputTokens: 5, outputTokens: 10, totalTokens: 15)

let viewModel = MyViewModel(client: mock)
```

## Configure via Plist

Create `OpenAIClientConfiguration.plist` and add values like:

- `apiKey` (required)
- `model`
- `systemPrompt`
- `temperature`
- `maxContextCharacters`
- `maxHistoryItems`
- `requestTimeout`
- `endpoint`
- `retryMaxAttempts`
- `retryBaseDelay`
- `retryMaxDelay`
- `retryBackoffMultiplier`
- `retryJitterRatio`
- `retryableStatusCodes` (array of integers)

Load from a bundle:

```swift
let configuration = try OpenAIClientConfiguration.loadFromPlist(
    named: "OpenAIClientConfiguration",
    in: .main
)
```

Or load from a URL (useful in tests and SPM targets where `Bundle.main` is unavailable):

```swift
let url = Bundle.module.url(forResource: "OpenAIClientConfiguration", withExtension: "plist")!
let configuration = try OpenAIClientConfiguration.loadFromPlist(at: url)
```

## Source Layout

- `Sources/SDOpenAIClient/Models`: configuration, message, API key, model type, trimming strategy, and API payload/response models
- `Sources/SDOpenAIClient/Network`: client actor, protocol, mock client, and networking error types
- `Sources/SDOpenAIClient/Utilities`: plist loader, logger infrastructure, and shared utilities

## Notes

- All public types are `Sendable`-compliant for Swift 6 strict concurrency.
- Conversation history is stored inside the client actor for thread safety.
- History is automatically trimmed according to the configured `HistoryTrimmingStrategy`.
- Call `clearHistory()` to reset context.
- Configuration init is `throws` — invalid values are caught immediately.
- `requestTimeout` controls per-request timeout.
- `retryPolicy` supports exponential backoff with jitter for retryable failures.
