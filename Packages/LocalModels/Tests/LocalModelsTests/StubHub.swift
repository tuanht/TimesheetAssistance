import Foundation

/// Serves canned Hugging Face responses so download tests never touch the network.
final class StubHub: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status = 200
        var body = Data()
        /// Delay before answering, to give a test time to cancel.
        var delay: TimeInterval = 0
    }

    nonisolated(unsafe) static var replies: [String: Reply] = [:]
    nonisolated(unsafe) static var requestedPaths: [String] = []
    private static let lock = NSLock()

    static func reset(_ replies: [String: Reply]) {
        lock.withLock {
            self.replies = replies
            requestedPaths = []
        }
    }

    static var paths: [String] { lock.withLock { requestedPaths } }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubHub.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private var cancelled = false

    override func startLoading() {
        let path = request.url?.path ?? ""
        let reply = Self.lock.withLock {
            Self.requestedPaths.append(path)
            return Self.replies[path] ?? Reply(status: 404)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay) { [self] in
            guard !cancelled, let url = request.url else { return }
            let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        cancelled = true
    }
}
