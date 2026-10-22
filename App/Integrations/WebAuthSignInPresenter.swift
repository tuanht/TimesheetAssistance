import AppKit
import AuthenticationServices
import Foundation
import Integrations
import TimesheetCore

/// Shows an OAuth authorize page in an ephemeral `ASWebAuthenticationSession`, anchored to the key window.
struct WebAuthSignInPresenter: SignInPresenter {
    func present(_ url: URL, callbackScheme: String?) async throws -> URL {
        // Only Jira signs in through the browser, and always with a custom scheme.
        guard let callbackScheme else { throw ContextError.signInAgain(.jira) }
        let sheet = await WebAuthSheet()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                Task { @MainActor in sheet.start(url, scheme: callbackScheme, continuation: continuation) }
            }
        } onCancel: {
            Task { @MainActor in sheet.cancel() }
        }
    }
}

/// One browser sign-in. Resumes its continuation exactly once.
@MainActor
private final class WebAuthSheet: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, Error>?
    /// Cancellation can arrive before `start`.
    private var cancelled = false

    func start(_ url: URL, scheme: String, continuation: CheckedContinuation<URL, Error>) {
        self.continuation = continuation
        guard !cancelled else { return finish(.failure(CancellationError())) }
        let session = ASWebAuthenticationSession(url: url, callback: .customScheme(scheme)) { callback, error in
            let result = Self.result(callback: callback, error: error)
            Task { @MainActor in self.finish(result) }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true
        self.session = session
        if !session.start() { finish(.failure(ContextError.signInAgain(.jira))) }
    }

    func cancel() {
        cancelled = true
        session?.cancel()
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<URL, Error>) {
        session = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    /// Closing the sheet is a cancellation; any other failure means signing in again. Never system text.
    private nonisolated static func result(callback: URL?, error: Error?) -> Result<URL, Error> {
        if let callback { return .success(callback) }
        if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
            return .failure(CancellationError())
        }
        return .failure(ContextError.signInAgain(.jira))
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { NSApp.keyWindow ?? ASPresentationAnchor() }
    }
}
