# Changelog

## [Unreleased]

### Added

- **Protocol abstraction** — `OpenAIClientProtocol` enables dependency injection; `MockOpenAIClient` actor provides a ready-made stub for tests.
- **Type-safe model identifiers** — `OpenAIModel` struct (`RawRepresentable`, `ExpressibleByStringLiteral`, `Codable`, `Hashable`) with built-in constants (`.gpt4o`, `.gpt5_4`, `.gpt5_4Mini`, `.gpt5_4Nano`, `.gpt4oMini`, `.o3Mini`, `.o4Mini`).
- **Secure API key wrapper** — `APIKey` type prevents accidental logging; `description` and `debugDescription` return `"APIKey([REDACTED])"`.
- **Configuration validation** — `OpenAIClientConfiguration.init` now `throws` a `ConfigurationError` for invalid API keys, temperature, timeout, or endpoint values.
- **Token usage metadata** — `sendWithMetadata(_:)` returns `(text: String, metadata: ResponseMetadata?)` with `inputTokens`, `outputTokens`, `totalTokens`.
- **Flexible history trimming** — `HistoryTrimmingStrategy` enum (`.characterCount`, `.itemCount`, `.both`, `.unlimited`) replaces the two separate `Int` properties.
- **URL-based plist loader** — `OpenAIClientConfiguration.loadFromPlist(at: URL)` works in SPM test targets and other contexts where `Bundle.main` is unavailable.
- **Logger hook** — `OpenAIClientLogger` protocol with `LogLevel` enum; built-in `NoOpLogger` (default) and `PrintLogger` implementations. Logger receives debug, info, warning, and error events throughout request lifecycle.
- **Cancellation support** — `Task.checkCancellation()` calls after every `await` in the send path; stream `onTermination` cancels the underlying task.
- **New test suites** — `OpenAIClientProtocolTests` (10 tests), `ConfigurationValidationTests` (9 tests), `HistoryTrimmingTests` (4 tests), `OpenAIModelTests` (7 tests). Total: 37 tests.

### Changed

- **Swift tools version** bumped from 5.7 to 5.10.
- **Platform requirements** raised to iOS 16+, macOS 13+, tvOS 16+, watchOS 9+, visionOS 1+.
- **Strict concurrency** enabled via `StrictConcurrency` experimental feature flag.
- **All public types** now conform to `Sendable`.
- `apiKey` property type changed from `String` to `APIKey`.
- `model` property type changed from `String` to `OpenAIModel`.
- `historyTrimmingStrategy` replaces `maxContextCharacters` and `maxHistoryItems` (deprecated computed properties remain for backwards compatibility).
- Internal helper methods (`validateHTTPResponse`, `decodeErrorMessage`, `collectErrorData`, `shouldRetry`, `retryDelay`) made `static` for `@Sendable` closure compatibility.

### Deprecated

- `OpenAIClientConfiguration.init(apiKey: String, model: String, ...)` — use `init(apiKey: APIKey, model: OpenAIModel, ...)` instead.
- `maxContextCharacters` and `maxHistoryItems` computed properties — use `historyTrimmingStrategy` instead.
