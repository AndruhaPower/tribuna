import Combine

/// Пользователь профиля (D31). Имя — из регистрации (`user_metadata.full_name`), может не быть.
public struct UserProfile: Sendable, Equatable {
    public let id: String
    public let name: String?
    public let email: String

    public init(id: String, name: String?, email: String) {
        self.id = id
        self.name = name
        self.email = email
    }
}

public enum AccountState: Sendable, Equatable {
    /// Сохранённая сессия ещё читается при запуске; для ворот — как `signedOut`.
    case unknown
    case signedOut
    case signedIn(UserProfile)
}

public enum AccountError: Error, Equatable, Sendable {
    case invalidCredentials, emailNotConfirmed, emailTaken, invalidCode, weakPassword, rateLimited, network, unknown
}

/// Повод показать лист входа — от него зависит строка мотивации.
public enum SignInReason: Sendable, Equatable {
    case bookmark, reminder, subscription, download, profile
}

/// Аккаунт: вход по почте и паролю, подтверждение и сброс — 6-значным кодом из письма. Ошибки — `AccountError`.
@MainActor public protocol Account: AnyObject {
    var state: AccountState { get }
    var statePublisher: AnyPublisher<AccountState, Never> { get }
    /// nil без входа.
    var userID: String? { get }
    /// После успеха нужен код из письма (`confirmSignUp`).
    func signUp(name: String, email: String, password: String) async throws
    /// Успех — `signedIn`.
    func confirmSignUp(email: String, code: String) async throws
    func resendSignUpCode(email: String) async throws
    /// `emailNotConfirmed` — код подтверждения уже отправлен заново.
    func signIn(email: String, password: String) async throws
    func requestPasswordReset(email: String) async throws
    /// Успех — `signedIn` с новым паролем.
    func resetPassword(email: String, code: String, newPassword: String) async throws
    /// Всегда успешно локально.
    func signOut() async
    /// Успех — `signedOut`.
    func deleteAccount() async throws
}
