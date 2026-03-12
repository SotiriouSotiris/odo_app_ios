import GoogleSignIn
import HotwireNative
import UIKit
internal import WebKit

let rootURL = URL(string: "https://my-odo.app")!

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    override init() {
        super.init()

        Hotwire.registerWebViewPolicyDecisionHandlers([
            GoogleOAuthWebViewPolicyDecisionHandler(),
            AppleSignInWebViewPolicyDecisionHandler(),
            ReloadWebViewPolicyDecisionHandler(),
            NewWindowWebViewPolicyDecisionHandler(),
            ExternalNavigationWebViewPolicyDecisionHandler(),
            LinkActivatedWebViewPolicyDecisionHandler()
        ])
    }

    private lazy var navigator: Navigator = {
        let nav = Navigator(configuration: .init(
            name: "main",
            startLocation: rootURL
        ))

        return nav
    }()

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        window?.rootViewController = navigator.rootViewController

        // Hide the native navigation bar — the web app handles its own UI
        let navController = navigator.rootViewController as UINavigationController
        navController.setNavigationBarHidden(true, animated: false)
        // Ensure web content sits below the notch / Dynamic Island
        navController.additionalSafeAreaInsets = .zero

        navigator.start()

        // Re-enable swipe-from-left-edge back gesture AFTER navigator.start().
        // Must be on the next run-loop tick — Hotwire's Navigator configures its
        // own navigation controller during start() and can reset the gesture state.
        DispatchQueue.main.async {
            navController.interactivePopGestureRecognizer?.isEnabled = true
            navController.interactivePopGestureRecognizer?.delegate = self
        }
    }

    // Handle custom URL scheme callbacks (odo:// and Google Sign-In)
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }

        // Let Google Sign-In SDK handle its callback URLs first
        if GIDSignIn.sharedInstance.handle(url) { return }

        navigator.route(url)
    }

    // Handle universal link callbacks
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else { return }
        navigator.route(url)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension SceneDelegate: UIGestureRecognizerDelegate {
    /// Allow the swipe-back gesture only when there is more than one
    /// view controller on the stack — prevents a UIKit crash on the root screen.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navController = navigator.rootViewController as? UINavigationController else {
            return false
        }
        return navController.viewControllers.count > 1
    }

    /// Give the pop gesture priority over WKWebView's scroll gesture.
    /// Without this, WKWebView's UIPanGestureRecognizer consumes edge touches
    /// for scrolling before the UIScreenEdgePanGestureRecognizer can claim them.
    /// Because the pop gesture is edge-only, it fails instantly for non-edge
    /// touches, so normal scrolling is unaffected.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
