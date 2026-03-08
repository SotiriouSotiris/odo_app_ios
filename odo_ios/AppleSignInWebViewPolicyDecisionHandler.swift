import HotwireNative
import UIKit
internal import WebKit

/// Intercepts the Apple Sign-In button tap and hands off to native ASAuthorizationController.
///
/// Matches navigations to `/users/auth/apple` on the app's own domain.
/// Instead of letting the WebView follow OmniAuth's web-based Apple flow
/// (which causes double Face ID and session issues), this launches the
/// native Sign in with Apple sheet for a seamless single-step experience.
struct AppleSignInWebViewPolicyDecisionHandler: WebViewPolicyDecisionHandler {
    let name = "apple-sign-in-policy"

    func matches(navigationAction: WKNavigationAction, configuration: Navigator.Configuration) -> Bool {
        guard let url = navigationAction.request.url,
              let host = url.host?.lowercased(),
              let configHost = configuration.startLocation.host?.lowercased() else {
            return false
        }

        // Match the OmniAuth Apple entry point on our own domain
        if host == configHost && url.path.hasPrefix("/users/auth/apple") {
            // Don't intercept the callback path — only the entry
            return !url.path.contains("/callback")
        }

        return false
    }

    func handle(navigationAction: WKNavigationAction,
                configuration: Navigator.Configuration,
                navigator: Navigator) -> WebViewPolicyManager.Decision {
        Task { @MainActor in
            AppleSignInCoordinator.shared.startSignIn(navigator: navigator)
        }

        return .cancel
    }
}
