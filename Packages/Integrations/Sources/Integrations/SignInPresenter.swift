import Foundation

/// Shows an OAuth authorize page; the app backs it with `ASWebAuthenticationSession`.
public protocol SignInPresenter: Sendable {
    /// Opens `url` in the system browser session; returns the callback URL.
    /// Throws `CancellationError` when the user closes the sheet.
    func present(_ url: URL, callbackScheme: String?) async throws -> URL
}
