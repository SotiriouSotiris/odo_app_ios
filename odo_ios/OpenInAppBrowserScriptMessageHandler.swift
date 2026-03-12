import SafariServices
import UIKit
internal import WebKit

/// Handles `window.webkit.messageHandlers.openInAppBrowser.postMessage(…)` calls
/// from the web app's Stimulus controller.
///
/// When the web app detects it is running inside a Turbo Native / Hotwire Native
/// WKWebView and wants to open a URL (e.g. a PDF) in a native in-app browser, it
/// sends a `{ url }` message. This handler resolves the URL relative to the
/// webView's current location and presents `SFSafariViewController` as a page
/// sheet — giving the user a full browser chrome with native PDF rendering,
/// pinch-to-zoom, and built-in share/download controls.
final class OpenInAppBrowserScriptMessageHandler: NSObject, WKScriptMessageHandler {

    static let handlerName = "openInAppBrowser"

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.handlerName,
              let body = message.body as? [String: String],
              let urlString = body["url"],
              let webView = message.webView,
              let baseURL = webView.url,
              let url = URL(string: urlString, relativeTo: baseURL)?.absoluteURL
        else { return }

        DispatchQueue.main.async {
            self.presentSafari(for: url)
        }
    }

    // MARK: - Private

    private func presentSafari(for url: URL) {
        guard let viewController = topViewController() else { return }

        let safari = SFSafariViewController(url: url)
        safari.modalPresentationStyle = .pageSheet
        viewController.present(safari, animated: true)
    }

    private func topViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return nil }

        var top = rootVC
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}
