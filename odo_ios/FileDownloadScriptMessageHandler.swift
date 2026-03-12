import UIKit
internal import WebKit

/// Handles `window.webkit.messageHandlers.fileDownload.postMessage(…)` calls
/// from the web app's Stimulus controller.
///
/// When the web app detects it is running inside a Turbo Native / Hotwire Native
/// WKWebView, it sends a `{ url, filename }` message instead of following the
/// normal download link. This handler downloads the file (with session cookies
/// for authentication) and presents the native share sheet.
final class FileDownloadScriptMessageHandler: NSObject, WKScriptMessageHandler {

    static let handlerName = "fileDownload"

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.handlerName,
              let body = message.body as? [String: String],
              let urlString = body["url"],
              let filename = body["filename"]
        else { return }

        // Resolve relative URLs against the webView's current URL
        guard let webView = message.webView,
              let baseURL = webView.url,
              let downloadURL = URL(string: urlString, relativeTo: baseURL)?.absoluteURL
        else { return }

        downloadAndShare(url: downloadURL, filename: filename, webView: webView)
    }

    // MARK: - Private

    private func downloadAndShare(url: URL, filename: String, webView: WKWebView) {
        // Extract cookies from the WKWebView so authenticated blob URLs work.
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            var request = URLRequest(url: url)
            let cookieHeaders = HTTPCookie.requestHeaderFields(with: cookies)
            for (key, value) in cookieHeaders {
                request.setValue(value, forHTTPHeaderField: key)
            }

            let task = URLSession.shared.downloadTask(with: request) { [weak self] tempURL, _, error in
                guard let self, let tempURL, error == nil else { return }

                let fileManager = FileManager.default
                let destURL = fileManager.temporaryDirectory.appendingPathComponent(filename)

                try? fileManager.removeItem(at: destURL)   // clean up any previous copy
                try? fileManager.moveItem(at: tempURL, to: destURL)

                DispatchQueue.main.async {
                    self.presentShareSheet(for: destURL)
                }
            }
            task.resume()
        }
    }

    private func presentShareSheet(for fileURL: URL) {
        guard let viewController = topViewController() else { return }

        let activityVC = UIActivityViewController(
            activityItems: [fileURL],
            applicationActivities: nil
        )

        // iPad popover support
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = viewController.view
            popover.sourceRect = CGRect(
                x: viewController.view.bounds.midX,
                y: viewController.view.bounds.midY,
                width: 0, height: 0
            )
            popover.permittedArrowDirections = []
        }

        viewController.present(activityVC, animated: true)
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
