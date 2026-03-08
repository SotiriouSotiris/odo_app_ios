import AuthenticationServices
import HotwireNative
import UIKit

/// Manages the OAuth flow using ASWebAuthenticationSession.
///
/// ASWebAuthenticationSession is Apple's recommended API for OAuth:
/// - Uses a system browser sheet (not an embedded WebView)
/// - Google trusts it (no disallowed_useragent error)
/// - Maintains its own consistent cookie store throughout the flow
/// - Returns control to the app via a custom URL scheme callback
final class OAuthSessionCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OAuthSessionCoordinator()

    private weak var navigator: Navigator?
    private var authSession: ASWebAuthenticationSession?

    /// Starts the OAuth flow in an ASWebAuthenticationSession popup.
    ///
    /// Flow:
    /// 1. Opens the OmniAuth entry URL in a system browser sheet
    /// 2. OmniAuth redirects to Google → user authenticates
    /// 3. Google redirects back to OmniAuth callback → server processes
    /// 4. Server detects native app, generates signed token
    /// 5. Server redirects to odo://auth-success?token=XXX
    /// 6. ASWebAuthenticationSession captures the custom scheme redirect
    /// 7. We extract the token and load the exchange URL in the WebView
    func startOAuth(from entryURL: URL, navigator: Navigator) {
        self.navigator = navigator

        let session = ASWebAuthenticationSession(
            url: entryURL,
            callbackURLScheme: "odo"
        ) { [weak self] callbackURL, error in
            guard let self else { return }
            self.authSession = nil

            if let error = error as? ASWebAuthenticationSessionError,
               error.code == .canceledLogin {
                // User dismissed the sheet — do nothing
                return
            }

            guard let callbackURL else { return }
            self.handleCallback(callbackURL)
        }

        session.presentationContextProvider = self
        // Share cookies with Safari so the user may already be signed into Google
        session.prefersEphemeralWebBrowserSession = false

        authSession = session
        session.start()
    }

    private func handleCallback(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value
        else { return }

        // Build the token exchange URL on our server
        var exchange = URLComponents(url: rootURL, resolvingAgainstBaseURL: false)!
        exchange.path = "/auth/native/sign_in"
        exchange.queryItems = [URLQueryItem(name: "token", value: token)]

        guard let exchangeURL = exchange.url else { return }

        Task { @MainActor in
            // Navigate the WebView to the token exchange endpoint.
            // The server validates the token, creates a session in the
            // WebView's cookie store, and redirects to the dashboard.
            self.navigator?.route(exchangeURL)
        }
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
