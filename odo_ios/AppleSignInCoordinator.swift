import AuthenticationServices
import HotwireNative
import UIKit

/// Handles native Apple Sign-In using ASAuthorizationController.
///
/// This is Apple's recommended approach for native apps:
/// - Shows the native Sign in with Apple sheet (no browser popup)
/// - Face ID / Touch ID happens once, natively
/// - Returns the credential directly to the app
///
/// Flow:
/// 1. User taps "Continue with Apple" in the WebView
/// 2. iOS intercepts and presents native ASAuthorizationController
/// 3. User authenticates with Face ID (once)
/// 4. iOS receives ASAuthorizationAppleIDCredential
/// 5. iOS POSTs the identity token to the server
/// 6. Server validates, finds/creates user, returns signed session token
/// 7. iOS loads the token exchange URL in the WebView → user is signed in
final class AppleSignInCoordinator: NSObject,
                                     ASAuthorizationControllerDelegate,
                                     ASAuthorizationControllerPresentationContextProviding {
    static let shared = AppleSignInCoordinator()

    private weak var navigator: Navigator?
    private var authController: ASAuthorizationController?

    func startSignIn(navigator: Navigator) {
        self.navigator = navigator

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        authController = controller
        controller.performRequests()
    }

    // MARK: - ASAuthorizationControllerDelegate

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        authController = nil
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            return
        }

        // Apple only provides name on the FIRST sign-in.
        // We must send it now so the server can store it.
        let firstName = credential.fullName?.givenName
        let lastName = credential.fullName?.familyName

        postCredentialToServer(
            identityToken: identityToken,
            firstName: firstName,
            lastName: lastName
        )
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        authController = nil
        // User cancelled or another error — do nothing
        let authError = error as? ASAuthorizationError
        if authError?.code == .canceled { return }

        print("Apple Sign-In error: \(error.localizedDescription)")
    }

    // MARK: - ASAuthorizationControllerPresentationContextProviding

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    // MARK: - Server Communication

    private func postCredentialToServer(identityToken: String,
                                        firstName: String?,
                                        lastName: String?) {
        var url = rootURL
        url.appendPathComponent("auth/native/apple_sign_in")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Only send the identity token and display name.
        // Email is extracted server-side from the verified JWT — never from client params.
        var body: [String: String] = ["identity_token": identityToken]
        if let firstName { body["first_name"] = firstName }
        if let lastName { body["last_name"] = lastName }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error {
                print("Apple Sign-In network error: \(error.localizedDescription)")
                return
            }

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let rawBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<no body>"

            guard let self,
                  let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("Apple Sign-In server error: HTTP \(statusCode) — could not parse JSON. Body: \(rawBody)")
                return
            }

            guard let token = json["token"] as? String else {
                print("Apple Sign-In server error: HTTP \(statusCode) — no token in response. Body: \(rawBody)")
                return
            }

            // Build the token exchange URL (reuses the same endpoint as Google)
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
