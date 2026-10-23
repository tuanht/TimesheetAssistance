import Foundation

/// Refuses every redirect, so a credential never follows a request to another host.
final class RedirectRefuser: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = RedirectRefuser()

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
