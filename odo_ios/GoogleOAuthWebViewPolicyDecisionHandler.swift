import HotwireNative
import UIKit
internal import WebKit

/// Intercepts the Google Sign-In button tap and hands off to native Google Sign-In SDK.
///
/// Matches navigations to `/users/auth/google_oauth2` on the app's own domain.
/// Instead of following the OmniAuth web-based redirect chain, this launches
/// the native Google Sign-In sheet, which then POSTs the ID token directly
/// to the server — identical to how Apple Sign-In works.
struct GoogleOAuthWebViewPolicyDecisionHandler: WebViewPolicyDecisionHandler {
    let name = "google-oauth-policy"

    func matches(navigationAction: WKNavigationAction, configuration: Navigator.Configuration) -> Bool {
        guard let url = navigationAction.request.url,
              let host = url.host?.lowercased(),
              let configHost = configuration.startLocation.host?.lowercased() else {
            return false
        }

        // Match the OmniAuth Google entry point on our own domain
        if host == configHost && url.path.hasPrefix("/users/auth/google_oauth2") {
            // Don't intercept the callback path — only the entry
            return !url.path.contains("/callback")
        }

        return false
    }

    func handle(navigationAction: WKNavigationAction,
                configuration: Navigator.Configuration,
                navigator: Navigator) -> WebViewPolicyManager.Decision {
        Task { @MainActor in
            GoogleSignInCoordinator.shared.startSignIn(navigator: navigator)
        }

        return .cancel
    }
}