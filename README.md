# SDOpenAIClientKit

A lightweight Swift Package wrapper for OpenAI's `responses` API with:

- non-stream and stream text generation
- built-in multi-turn memory
- bounded context/history trimming
- robust HTTP and streaming error handling

## Installation

In Xcode:

1. `File` -> `Add Package Dependencies...`
2. Choose `Add Local...`
3. Select the `SDOpenAIClientKit` folder

Or with SwiftPM:

```swift
.package(path: "./SDOpenAIClientKit")
```

For a public GitHub repo:

```swift
.package(url: "https://github.com/<your-username>/SDOpenAIClientKit.git", from: "1.0.0")
```

## Quick Start

```swift
import SDOpenAIClientKit

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

## Notes

- Conversation history is stored inside the client actor for thread safety.
- History is automatically trimmed by `maxContextCharacters` and `maxHistoryItems`.
- Call `clearHistory()` to reset context.
- `requestTimeout` controls per-request timeout.
- `retryPolicy` supports exponential backoff with jitter for retryable failures.
