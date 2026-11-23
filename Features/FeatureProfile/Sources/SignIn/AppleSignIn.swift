import AuthenticationServices
import CoreDomain
import CryptoKit
import SnapKit
import UIKit

/// Ответ Apple для входа в Supabase: токен, исходный nonce (в запрос Apple уходит его SHA-256), имя — только при первом входе.
struct AppleCredential: Equatable {
    let idToken: String
    let nonce: String
    let name: String?
}

/// Системный лист «Войти с Apple». Без capability `com.apple.developer.applesignin` у подписи Apple отвечает ошибкой —
/// это `AccountError.appleUnavailable`; закрытый лист — nil.
@MainActor
final class AppleSignIn: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let anchor: UIWindow
    private var continuation: CheckedContinuation<ASAuthorization, any Error>?
    private var controller: ASAuthorizationController?

    private init(anchor: UIWindow) { self.anchor = anchor }

    static func authorize(from window: UIWindow) async throws -> AppleCredential? {
        let nonce = randomNonce()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
        let flow = AppleSignIn(anchor: window)
        let authorization: ASAuthorization
        do {
            authorization = try await withCheckedThrowingContinuation { continuation in
                flow.continuation = continuation
                let controller = ASAuthorizationController(authorizationRequests: [request])
                controller.delegate = flow // слабая ссылка: держим flow и контроллер до ответа
                controller.presentationContextProvider = flow
                flow.controller = controller
                controller.performRequests()
            }
            flow.controller = nil
        } catch let error as ASAuthorizationError where error.code == .canceled {
            flow.controller = nil
            return nil
        } catch {
            flow.controller = nil
            throw AccountError.appleUnavailable
        }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let token = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) })
        else { throw AccountError.appleUnavailable }
        let name = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) }
        return AppleCredential(idToken: token, nonce: nonce, name: name?.isEmpty == false ? name : nil)
    }

    private static func randomNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        precondition(SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        MainActor.assumeIsolated { finish(.success(authorization)) }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        MainActor.assumeIsolated { finish(.failure(error)) }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated { anchor }
    }

    private func finish(_ result: Result<ASAuthorization, any Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}

/// Системная кнопка Apple в размер пилюль листа (50 pt, полное скругление); тёмная тема — белая кнопка.
@MainActor func appleButton(action: @escaping (UIWindow) -> Void) -> UIControl {
    let button = ASAuthorizationAppleIDButton(authorizationButtonType: .continue, authorizationButtonStyle: .white)
    button.cornerRadius = WidePillButton.height / 2
    button.snp.makeConstraints { $0.height.equalTo(WidePillButton.height) }
    button.addAction(UIAction { [weak button] _ in
        if let window = button?.window { action(window) }
    }, for: .touchUpInside)
    return button
}
