import Auth
import Combine
import CoreDomain
import Foundation

/// Нужное аккаунту от Supabase Auth — за протоколом ради тестов.
@MainActor protocol AuthBackend {
    /// Сигнал «сессия изменилась»; первым — при чтении сохранённой сессии. Само событие не несёт состояния:
    /// оно приходит с задержкой, верное — то, что лежит в хранилище сейчас (`currentUser`).
    func sessionChanges() -> AsyncStream<Void>
    /// Пользователь сохранённой сессии (nil — её нет).
    var currentUser: UserProfile? { get }
    func signUp(email: String, password: String, data: [String: AnyJSON]) async throws
    func verifyOTP(email: String, token: String, type: EmailOTPType) async throws
    func resendSignUp(email: String) async throws
    func signIn(email: String, password: String) async throws
    func resetPasswordForEmail(_ email: String) async throws
    func updatePassword(_ password: String) async throws
    func signOut() async throws
    /// Действующий токен (обновляет просроченный).
    func accessToken() async throws -> String
}

/// Аккаунт на Supabase Auth (D31): почта + пароль, коды из письма, сессия в Keychain (по умолчанию библиотеки).
/// Состояние — всегда из сохранённой сессии; пока идёт операция, события сессии не публикуются (её промежуточные
/// шаги, например сессия восстановления до смены пароля, — не вход), итог публикуется по её окончании.
@MainActor
public final class SupabaseAccount: Account {
    private let subject = CurrentValueSubject<AccountState, Never>(.unknown)
    private let auth: AuthBackend
    private let deleteURL: URL
    private let apiKey: String
    private let fetch: @MainActor (URLRequest) async throws -> (Data, URLResponse)
    private var operations = 0

    init(auth: AuthBackend, functionsURL: URL, apiKey: String,
         fetch: @escaping @MainActor (URLRequest) async throws -> (Data, URLResponse)) {
        self.auth = auth
        deleteURL = functionsURL.appendingPathComponent("delete-account")
        self.apiKey = apiKey
        self.fetch = fetch
        // Сюда же приходит окончательный сбой обновления сессии (аккаунт удалён на другом телефоне) — signedOut.
        Task { [weak self] in
            for await _ in auth.sessionChanges() {
                guard let self, operations == 0 else { continue }
                publishStoredSession()
            }
        }
    }

    public var state: AccountState { subject.value }
    public var statePublisher: AnyPublisher<AccountState, Never> { subject.removeDuplicates().eraseToAnyPublisher() }
    public var userID: String? {
        if case let .signedIn(user) = state { user.id } else { nil }
    }

    // С включённым «Confirm email» signUp на уже подтверждённую почту отвечает успехом без письма —
    // считаем «код отправлен», а confirmSignUp затем падает с invalidCode (D31).
    public func signUp(name: String, email: String, password: String) async throws {
        try await operation { try await auth.signUp(email: email, password: password, data: ["full_name": .string(name)]) }
    }

    public func confirmSignUp(email: String, code: String) async throws {
        try await operation { try await verify(email: email, code: code, type: .signup) }
    }

    public func resendSignUpCode(email: String) async throws {
        try await operation { try await auth.resendSignUp(email: email) }
    }

    public func signIn(email: String, password: String) async throws {
        try await operation {
            do {
                try await auth.signIn(email: email, password: password)
            } catch where Self.accountError(error) == .emailNotConfirmed {
                // Дальше — шаг кода; не ушло письмо — там есть «Отправить ещё раз».
                try? await auth.resendSignUp(email: email)
                throw AccountError.emailNotConfirmed
            }
        }
    }

    public func requestPasswordReset(email: String) async throws {
        try await operation { try await auth.resetPasswordForEmail(email) }
    }

    public func resetPassword(email: String, code: String, newPassword: String) async throws {
        try await operation {
            try await verify(email: email, code: code, type: .recovery)
            do {
                try await auth.updatePassword(newPassword)
            } catch {
                // Код потрачен, пароль прежний: сессию восстановления не оставляем входом.
                try? await auth.signOut()
                throw error
            }
        }
    }

    public func signOut() async {
        // Библиотека удаляет сессию до запроса к серверу, сбой запроса (нет сети) неважен.
        try? await operation { try await auth.signOut() }
    }

    public func deleteAccount() async throws {
        try await operation {
            var request = URLRequest(url: deleteURL)
            request.httpMethod = "POST"
            request.setValue("Bearer \(try await auth.accessToken())", forHTTPHeaderField: "Authorization")
            request.setValue(apiKey, forHTTPHeaderField: "apikey")
            let (_, response) = try await fetch(request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AccountError.unknown }
            try? await auth.signOut()
        }
    }

    private func verify(email: String, code: String, type: EmailOTPType) async throws {
        do {
            try await auth.verifyOTP(email: email, token: code, type: type)
        } catch let error as AuthError where error.errorCode == .validationFailed {
            throw AccountError.invalidCode // код не той длины / не цифры
        }
    }

    private func publishStoredSession() {
        subject.send(auth.currentUser.map(AccountState.signedIn) ?? .signedOut)
    }

    /// События сессии во время операции не публикуются; по окончании (успех или ошибка) — сохранённая сессия.
    private func operation(_ body: () async throws -> Void) async throws {
        operations += 1
        defer {
            operations -= 1
            if operations == 0 { publishStoredSession() }
        }
        do { try await body() } catch { throw Self.accountError(error) }
    }

    static func accountError(_ error: any Error) -> AccountError {
        if let error = error as? AccountError { return error }
        if error is URLError { return .network }
        guard let error = error as? AuthError else { return .unknown }
        switch error.errorCode {
        case .invalidCredentials: return .invalidCredentials
        case .emailNotConfirmed: return .emailNotConfirmed
        case .userAlreadyExists, .emailExists: return .emailTaken
        case .otpExpired: return .invalidCode // Supabase так отвечает и на неверный код
        case .weakPassword: return .weakPassword
        case .overEmailSendRateLimit, .overRequestRateLimit: return .rateLimited
        default: break
        }
        if case let .api(_, _, _, response) = error, response.statusCode == 429 { return .rateLimited }
        return .unknown
    }
}

/// `AuthBackend` поверх `AuthClient`.
struct LiveAuthBackend: AuthBackend {
    let client: AuthClient

    var currentUser: UserProfile? { client.currentSession.map { UserProfile($0.user) } }

    func sessionChanges() -> AsyncStream<Void> {
        let changes = client.authStateChanges
        return AsyncStream { continuation in
            let task = Task {
                for await _ in changes { continuation.yield() }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func signUp(email: String, password: String, data: [String: AnyJSON]) async throws {
        try await client.signUp(email: email, password: password, data: data)
    }

    func verifyOTP(email: String, token: String, type: EmailOTPType) async throws {
        try await client.verifyOTP(email: email, token: token, type: type)
    }

    func resendSignUp(email: String) async throws { try await client.resend(email: email, type: .signup) }

    func signIn(email: String, password: String) async throws {
        try await client.signIn(email: email, password: password)
    }

    func resetPasswordForEmail(_ email: String) async throws { try await client.resetPasswordForEmail(email) }

    func updatePassword(_ password: String) async throws {
        _ = try await client.update(user: UserAttributes(password: password))
    }

    func signOut() async throws { try await client.signOut() }

    func accessToken() async throws -> String { try await client.session.accessToken }
}

extension UserProfile {
    init(_ user: User) {
        let name = user.userMetadata["full_name"]?.stringValue
        self.init(id: user.id.uuidString.lowercased(), name: name?.isEmpty == false ? name : nil, email: user.email ?? "")
    }
}
