import GoogleSignIn
import HotwireNative
import UIKit

/// Handles native Google Sign-In using the Google Sign-In SDK.
///
/// This mirrors the Apple Sign-In flow exactly:
/// - Shows the native Google Sign-In sheet (not a redirect-based browser flow)
/// - Returns the ID token directly to the app
/// - No redirect chains, no session/cookie fragility
///
/// Flow:
/// 1. User taps "Continue with Google" in the WebView
/// 2. iOS intercepts and presents native Google Sign-In sheet
/// 3. User authenticates with their Google account
/// 4. iOS receives the ID token
/// 5. iOS POSTs the ID token to the server
/// 6. Server validates, finds/creates user, returns signed session token
/// 7. iOS loads the token exchange URL in the WebView → user is signed in
final class GoogleSignInCoordinator {
    static let shared = GoogleSignInCoordinator()

    private weak var navigator: Navigator?

    func startSignIn(navigator: Navigator) {
        self.navigator = navigator

        guard let presentingViewController = topViewController() else {
            print("Google Sign-In error: no presenting view controller")
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { [weak self] result, error in
            if let error {
                print("Google Sign-In error: \(error.localizedDescription)")
                return
            }

            guard let idToken = result?.user.idToken?.tokenString else {
                print("Google Sign-In error: no ID token received")
                return
            }

            self?.postIDTokenToServer(idToken: idToken)
        }
    }

    // MARK: - Helpers

    private func topViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }

    // MARK: - Server Communication

    private func postIDTokenToServer(idToken: String) {
        var url = rootURL
        url.appendPathComponent("auth/native/google_sign_in")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["id_token": idToken]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error {
                print("Google Sign-In network error: \(error.localizedDescription)")
                return
            }

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let rawBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<no body>"

            guard let self,
                  let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("Google Sign-In server error: HTTP \(statusCode) — could not parse JSON. Body: \(rawBody)")
                return
            }

            guard let token = json["token"] as? String else {
                print("Google Sign-In server error: HTTP \(statusCode) — no token in response. Body: \(rawBody)")
                return
            }

            // Build the token exchange URL (reuses the same endpoint as Apple)
            var exchange = URLComponents(url: rootURL, resolvingAgainstBaseURL: false)!
            exchange.path = "/auth/native/sign_in"
            exchange.queryItems = [URLQueryItem(name: "token", value: token)]

            guard let exchangeURL = exchange.url else { return }

            Task { @MainActor in
                self.navigator?.route(exchangeURL)
            }
        }.resume()
    }
}
