# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

This is a Swift Package (swift-tools-version 6.0). Build and test via Xcode or the command line:

```bash
swift build
swift test
```

Run a single test:
```bash
swift test --filter "NetworkTests/ClientTests/sendParsesOutputAndStoresHistory"
```

Platforms: iOS 18+, macOS 15+, tvOS 18+, watchOS 11+, visionOS 2+.

Swift 6 language mode is enabled on both the library and test targets.

## Architecture

SDOpenAIClientKit is a lightweight, zero-dependency Swift wrapper around OpenAI's **Responses API** (`/v1/responses`). The package name is `SDOpenAIClientKit`; the library product and import name is `SDOpenAIClient`.

### Core Design

`OpenAIClient` is a Swift **actor** that owns conversation state and conforms to `OpenAIClientProtocol`. It provides three public methods for text generation:
- `send(_:)` / `send(_:additionalInstructions:)` — single-shot request, returns full response text
- `sendWithMetadata(_:)` / `sendWithMetadata(_:additionalInstructions:)` — returns response text plus `ResponseMetadata` (token usage)
- `stream(_:)` / `stream(_:additionalInstructions:)` — SSE streaming, returns `AsyncThrowingStream<String, Error>` of text deltas

All methods automatically maintain multi-turn conversation history internally. History is trimmed according to the `HistoryTrimmingStrategy` (`.characterCount`, `.itemCount`, `.both`, or `.unlimited`). Trimming removes oldest messages first, in pairs.

### Request Flow

1. Validate API key (via `APIKey` type) → build conversation array (history + new user message) → encode `ResponsesRequest` body
2. Execute via `URLSession` with retry logic (`withRetry` + exponential backoff with jitter)
3. For non-streaming: decode `ResponsesAPIResponse`, extract text from output items, extract `ResponseMetadata` from `usage`
4. For streaming: parse SSE lines (`data: ` prefix), decode `ResponsesStreamEvent`, yield deltas, accumulate buffer
5. After success, append user+assistant turn to history
6. `Task.checkCancellation()` is called after every `await` point

### Key Types

- `OpenAIClientProtocol` — protocol for dependency injection; `MockOpenAIClient` actor provides a test stub.
- `OpenAIClientConfiguration` — all client settings. Throwing init validates API key, temperature, timeout, and endpoint. Can be loaded from a plist via `loadFromPlist(named:in:)` or `loadFromPlist(at:)`.
- `APIKey` — wraps the API key string; redacted in `description`/`debugDescription`.
- `OpenAIModel` — `RawRepresentable` struct with static constants (`.gpt4o`, `.gpt5_4`, `.gpt5_4Mini`, `.gpt5_4Nano`, etc.).
- `HistoryTrimmingStrategy` — enum controlling history trimming behavior.
- `ResponseMetadata` — token usage counts (`inputTokens`, `outputTokens`, `totalTokens`).
- `OpenAIClientRetryPolicy` — retry config with exponential backoff. Has `.none` and `.standard` presets.
- `OpenAIMessage` — simple role+content pair used for conversation history.
- `ConfigurationError` — validation error enum thrown from configuration init.
- `OpenAIClientError` / `OpenAIClientConfigurationError` — networking and plist error enums.
- `OpenAIClientLogger` — protocol for receiving lifecycle events; `NoOpLogger` (default) and `PrintLogger` built-in.
- Models in `OpenAIResponsesModels.swift` are internal types mapping to the Responses API JSON schema.

### Testing Approach

Tests use the **Swift Testing** framework (`import Testing`). `URLProtocolMock` (a custom `URLProtocol` subclass) is injected via a custom `URLSession` to intercept network calls. The mock captures request bodies for assertion. There are 37 tests across 4 test files:

- `SDOpenAIClientTests.swift` — contains two nested suites under a serialized parent `NetworkTests`:
  - `NetworkTests.ClientTests` — integration tests for send, stream, metadata, plist loading
  - `NetworkTests.HistoryTrimming` — trimming strategy behavior
- `OpenAIClientProtocolTests.swift` — mock client behavior
- `ConfigurationValidationTests.swift` — throwing init validation
- `OpenAIModelTests.swift` — model type conformances

Suites that share `URLProtocolMock` state are nested under `@Suite(.serialized)` to prevent parallel test interference. Other suites run in parallel.

Shared test infrastructure (helpers, mocks) lives in `TestSupport.swift`.

### JSON Decoding

The client uses `.convertFromSnakeCase` key decoding strategy throughout. Internal API models use camelCase property names that map to snake_case JSON keys automatically. Do **not** add custom `CodingKeys` with explicit snake_case strings — the decoder handles the conversion.

### Sendable Compliance

All public types conform to `Sendable`. The package uses Swift 6 language mode. Test helpers use `@unchecked Sendable` with `NSLock`-guarded mutable state and `nonisolated(unsafe)` for static properties, with safety documented in comments.
