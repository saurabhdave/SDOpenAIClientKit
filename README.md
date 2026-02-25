# SDOpenAIClient

A lightweight Swift Package wrapper for OpenAI's `responses` API with:

- non-stream and stream text generation
- built-in multi-turn memory
- bounded context/history trimming
- robust HTTP and streaming error handling

## Installation

In Xcode:

1. `File` -> `Add Package Dependencies...`
2. Choose `Add Local...`
3. Select this package folder (for example: `SDOpenAIClientKit`)

Or with SwiftPM:

```swift
.package(path: "./SDOpenAIClientKit")
```

For a public GitHub repo:

```swift
.package(url: "[https://github.com/saurabhdave/SDOpenAIClient.git](https://github.com/saurabhdave/SDOpenAIClientKit)", from: "1.0.0")
```

## Quick Start

```swift
import SDOpenAIClient

let client = OpenAIClient(
    configuration: OpenAIClientConfiguration(
        apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "",
        model: "gpt-4.1-mini",
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

## Configure via Plist

Create `OpenAIClientConfiguration.plist` in your app bundle and add values like:

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

Then load it:

```swift
let configuration = try OpenAIClientConfiguration.loadFromPlist(
    named: "OpenAIClientConfiguration",
    in: .main
)

let client = OpenAIClient(configuration: configuration)
```

## Source Layout

- `Sources/SDOpenAIClient/Models`: configuration, message, and API payload/response models
- `Sources/SDOpenAIClient/Network`: client actor and networking error types
- `Sources/SDOpenAIClient/Utilities`: plist loader and shared model utilities

## Notes

- Conversation history is stored inside the client actor for thread safety.
- History is automatically trimmed by `maxContextCharacters` and `maxHistoryItems`.
- Call `clearHistory()` to reset context.
- `requestTimeout` controls per-request timeout.
- `retryPolicy` supports exponential backoff with jitter for retryable failures.
