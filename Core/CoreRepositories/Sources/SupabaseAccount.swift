import Auth
import Combine
import CoreDomain
import Foundation

/// Нужное аккаунту от Supabase Auth — за протоколом ради тестов.
@MainActor protocol AuthBackend {
    /// Профиль при каждой смене сессии (nil — сессии нет); первым — сохранённая сессия.
    func sessionChanges() -> AsyncStream<UserProfile?>
    func signUp(email: String, password: String, data: [String: AnyJSON]) async throws
    func verifyOTP(email: String, token: String, type: EmailOTPType) async throws -> UserProfile
    func resendSignUp(email: String) async throws
    func signIn(email: String, password: String) async throws -> UserProfile
    func resetPasswordForEmail(_ email: String) async throws
    func updatePassword(_ password: String) async throws -> UserProfile
    func signOut() async throws
    /// Действующий токен (обновляет просроченный).
    func accessToken() async throws -> String
}

/// Аккаунт на Supabase Auth (D31): почта + пароль, коды из письма, сессия в Keychain (по умолчанию библиотеки).
@MainActor
public final class SupabaseAccount: Account {
    private let subject = CurrentValueSubject<AccountState, Never>(.unknown)
    private let auth: AuthBackend
    private let deleteURL: URL
    private let apiKey: String
    private let fetch: @MainActor (URLRequest) async throws -> (Data, URLResponse)

    init(auth: AuthBackend, functionsURL: URL, apiKey: String,
         fetch: @escaping @MainActor (URLRequest) async throws -> (Data, URLResponse)) {
        self.auth = auth
        deleteURL = functionsURL.appendingPathComponent("delete-account")
        self.apiKey = apiKey
        self.fetch = fetch
        // Сюда же приходит окончательный сбой обновления сессии (аккаунт удалён на другом телефоне) — signedOut.
        Task { [weak self] in
            for await profile in auth.sessionChanges() {
                self?.subject.send(profile.map(AccountState.signedIn) ?? .signedOut)
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
        try await mapped { try await auth.signUp(email: email, password: password, data: ["full_name": .string(name)]) }
    }

    public func confirmSignUp(email: String, code: String) async throws {
        let user = try await mapped { try await auth.verifyOTP(email: email, token: code, type: .signup) }
        subject.send(.signedIn(user))
    }

    public func resendSignUpCode(email: String) async throws {
        try await mapped { try await auth.resendSignUp(email: email) }
    }

    public func signIn(email: String, password: String) async throws {
        do {
            let user = try await mapped { try await auth.signIn(email: email, password: password) }
            subject.send(.signedIn(user))
        } catch AccountError.emailNotConfirmed {
            // Дальше — шаг кода; не ушло письмо — там есть «Отправить ещё раз».
            try? await auth.resendSignUp(email: email)
            throw AccountError.emailNotConfirmed
        }
    }

    public func requestPasswordReset(email: String) async throws {
        try await mapped { try await auth.resetPasswordForEmail(email) }
    }

    public func resetPassword(email: String, code: String, newPassword: String) async throws {
        _ = try await mapped { try await auth.verifyOTP(email: email, token: code, type: .recovery) }
        do {
            let user = try await mapped { try await auth.updatePassword(newPassword) }
            subject.send(.signedIn(user))
        } catch {
            // Код потрачен, пароль прежний: сессию восстановления не оставляем входом.
            await signOut()
            throw error
        }
    }

    public func signOut() async {
        // Библиотека удаляет сессию до запроса к серверу, сбой запроса (нет сети) неважен.
        try? await auth.signOut()
        subject.send(.signedOut)
    }

    public func deleteAccount() async throws {
        try await mapped {
            var request = URLRequest(url: deleteURL)
            request.httpMethod = "POST"
            request.setValue("Bearer \(try await auth.accessToken())", forHTTPHeaderField: "Authorization")
            request.setValue(apiKey, forHTTPHeaderField: "apikey")
            let (_, response) = try await fetch(request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AccountError.unknown }
        }
        await signOut()
    }

    private func mapped<T>(_ body: () async throws -> T) async throws -> T {
        do { return try await body() } catch { throw Self.accountError(error) }
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

    func sessionChanges() -> AsyncStream<UserProfile?> {
        let changes = client.authStateChanges
        return AsyncStream { continuation in
            let task = Task {
                for await (_, session) in changes { continuation.yield(session.map { UserProfile($0.user) }) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func signUp(email: String, password: String, data: [String: AnyJSON]) async throws {
        try await client.signUp(email: email, password: password, data: data)
    }

    func verifyOTP(email: String, token: String, type: EmailOTPType) async throws -> UserProfile {
        guard case let .session(session) = try await client.verifyOTP(email: email, token: token, type: type) else {
            throw AccountError.unknown
        }
        return UserProfile(session.user)
    }

    func resendSignUp(email: String) async throws { try await client.resend(email: email, type: .signup) }

    func signIn(email: String, password: String) async throws -> UserProfile {
        UserProfile(try await client.signIn(email: email, password: password).user)
    }

    func resetPasswordForEmail(_ email: String) async throws { try await client.resetPasswordForEmail(email) }

    func updatePassword(_ password: String) async throws -> UserProfile {
        UserProfile(try await client.update(user: UserAttributes(password: password)))
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
