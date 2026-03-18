import Foundation
@testable import SDOpenAIClient

// MARK: - URL Session Helpers

func makeMockedSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [URLProtocolMock.self]
    return URLSession(configuration: config)
}

// MARK: - Plist Helper

enum TestSupportError: Error {
    case plistWriteFailed
}

func makeTemporaryPlist(_ dictionary: [String: Any]) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("plist")
    guard (dictionary as NSDictionary).write(to: url, atomically: true) else {
        throw TestSupportError.plistWriteFailed
    }
    return url
}

// MARK: - Probe types for request body decoding

struct ProbeResponsesRequest: Decodable {
    let input: [ProbeInputItem]
}

struct ProbeInputItem: Decodable {
    let role: String
    let content: String
}

// MARK: - AtomicCounter

final class AtomicCounter: @unchecked Sendable {
    // SAFETY: All access to `_value` is guarded by `lock`.
    private let lock = NSLock()
    private var _value = 0

    /// Increments the counter and returns the new value.
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        _value += 1
        return _value
    }
}

// MARK: - URLProtocolMock

final class URLProtocolMock: URLProtocol, @unchecked Sendable {
    // SAFETY: All mutable static state is guarded by `lock`.
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _recordedBodies: [Data] = []

    static var recordedBodies: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return _recordedBodies
    }

    static func recordBody(_ data: Data) {
        lock.lock()
        _recordedBodies.append(data)
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        _recordedBodies = []
        requestHandler = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: OpenAIClientError.invalidResponse)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
