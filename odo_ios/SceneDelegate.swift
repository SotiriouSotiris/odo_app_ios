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
    }

    // Handle custom URL scheme callbacks (odo://)
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        navigator.route(url)
    }

    // Handle universal link callbacks
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else { return }
        navigator.route(url)
    }
}
