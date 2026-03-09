import HotwireNative
import UIKit
internal import WebKit

/// Intercepts the Google OAuth entry point and hands off to ASWebAuthenticationSession.
///
/// Matches navigations to `/users/auth/google_oauth2` on the app's own domain
/// (the OmniAuth request-phase URL). This catches the form POST from the
/// "Continue with Google" button before the WebView can follow the redirect
/// to accounts.google.com (which Google would block).
struct GoogleOAuthWebViewPolicyDecisionHandler: WebViewPolicyDecisionHandler {
    let name = "google-oauth-policy"

    func matches(navigationAction: WKNavigationAction, configuration: Navigator.Configuration) -> Bool {
        guard let url = navigationAction.request.url,
              let host = url.host?.lowercased(),
              let configHost = configuration.startLocation.host?.lowercased() else {
            return false
        }

        // Match the OmniAuth entry point on our own domain
        if host == configHost && url.path.hasPrefix("/users/auth/google_oauth2") {
            // Don't intercept the callback path — only the entry
            return !url.path.contains("/callback")
        }

        return false
    }

    func handle(navigationAction: WKNavigationAction,
                configuration: Navigator.Configuration,
                navigator: Navigator) -> WebViewPolicyManager.Decision {
        // Start from the server-side native bootstrap endpoint.
        // This endpoint can establish any required cookie/session state
        // before beginning the OAuth redirect chain.
        var components = URLComponents(url: configuration.startLocation, resolvingAgainstBaseURL: false)!
        components.path = "/auth/native/google"
        components.queryItems = nil

        guard let authURL = components.url else { return .allow }

        Task { @MainActor in
            OAuthSessionCoordinator.shared.startOAuth(from: authURL, navigator: navigator)
        }

        return .cancel
    }
}