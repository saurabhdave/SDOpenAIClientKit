# Changelog

## [2.0.0] — 2026-03-18

### Added

- **Protocol abstraction** — `OpenAIClientProtocol` enables dependency injection; `MockOpenAIClient` actor provides a ready-made stub for tests.
- **Type-safe model identifiers** — `OpenAIModel` struct (`RawRepresentable`, `ExpressibleByStringLiteral`, `Codable`, `Hashable`) with built-in constants (`.gpt5_4`, `.gpt5_4Mini`, `.gpt5_4Nano`, `.gpt4o`, `.gpt4oMini`, `.o3Mini`, `.o4Mini`).
- **Secure API key wrapper** — `APIKey` type prevents accidental logging; `description` and `debugDescription` return `"APIKey([REDACTED])"`.
- **Configuration validation** — `OpenAIClientConfiguration.init` now `throws` a `ConfigurationError` for invalid API keys, temperature, timeout, or endpoint values.
- **Token usage metadata** — `sendWithMetadata(_:)` returns `(text: String, metadata: ResponseMetadata?)` with `inputTokens`, `outputTokens`, `totalTokens`.
- **Flexible history trimming** — `HistoryTrimmingStrategy` enum (`.characterCount`, `.itemCount`, `.both`, `.unlimited`) replaces the two separate `Int` properties.
- **URL-based plist loader** — `OpenAIClientConfiguration.loadFromPlist(at: URL)` works in SPM test targets and other contexts where `Bundle.main` is unavailable.
- **Logger hook** — `OpenAIClientLogger` protocol with `LogLevel` enum; built-in `NoOpLogger` (default) and `PrintLogger` implementations. Logger receives debug, info, warning, and error events throughout request lifecycle.
- **Cancellation support** — `Task.checkCancellation()` calls after every `await` in the send path; stream `onTermination` cancels the underlying task.
- **43 tests** across 5 test files covering networking, error handling, retry logic, configuration validation, protocol mocks, model types, history trimming, and instruction merging.

### Changed

- **Swift tools version** bumped to 6.0 with Swift 6 language mode.
- **Platform requirements** raised to iOS 18+, macOS 15+, tvOS 18+, watchOS 11+, visionOS 2+.
- **All public types** now conform to `Sendable`.
- `apiKey` property type changed from `String` to `APIKey`.
- `model` property type changed from `String` to `OpenAIModel`.
- Default model changed to `.gpt5_4Mini` (`gpt-5.4-mini`).
- `historyTrimmingStrategy` replaces `maxContextCharacters` and `maxHistoryItems` (deprecated computed properties remain for backwards compatibility).
- Internal helper methods (`validateHTTPResponse`, `decodeErrorMessage`, `collectErrorData`, `shouldRetry`, `retryDelay`) made `static` for `@Sendable` closure compatibility.
- Replaced deprecated `Task.sleep(nanoseconds:)` with `Task.sleep(for:)`.

### Removed

- `OpenAIClientError.missingAPIKey` — unused error case that was never thrown.

### Deprecated

- `OpenAIClientConfiguration.init(apiKey: String, model: String, ...)` — use `init(apiKey: APIKey, model: OpenAIModel, ...)` instead.
- `maxContextCharacters` and `maxHistoryItems` computed properties — use `historyTrimmingStrategy` instead.

## [1.0.0] — 2025-01-01

Initial release.
