import Auth
import CoreDomain
import Foundation
import Testing
@testable import CoreRepositories

/// Фейк Supabase Auth: записывает вызовы, бросает заданные ошибки, сессию шлёт тест.
@MainActor
final class FakeAuth: AuthBackend {
    var calls: [String] = []
    var errors: [String: any Error] = [:]
    var signUpData: [String: AnyJSON]?
    let profile = UserProfile(id: "u1", name: "Алексей", email: "a@b.ru")
    let (sessions, session) = AsyncStream<UserProfile?>.makeStream()

    private func call(_ name: String) throws {
        calls.append(name)
        if let error = errors[name.components(separatedBy: "(")[0]] { throw error }
    }

    func sessionChanges() -> AsyncStream<UserProfile?> { sessions }
    func signUp(email: String, password: String, data: [String: AnyJSON]) async throws {
        signUpData = data
        try call("signUp(\(email))")
    }
    func verifyOTP(email: String, token: String, type: EmailOTPType) async throws -> UserProfile {
        try call("verifyOTP(\(email),\(token),\(type.rawValue))")
        return profile
    }
    func resendSignUp(email: String) async throws { try call("resend(\(email))") }
    func signIn(email: String, password: String) async throws -> UserProfile {
        try call("signIn(\(email))")
        return profile
    }
    func resetPasswordForEmail(_ email: String) async throws { try call("recover(\(email))") }
    func updatePassword(_ password: String) async throws -> UserProfile {
        try call("updatePassword(\(password))")
        return profile
    }
    func signOut() async throws { try call("signOut") }
    func accessToken() async throws -> String {
        try call("accessToken")
        return "jwt-1"
    }
}

private func apiError(_ code: ErrorCode, status: Int = 400) -> AuthError {
    .api(message: "", errorCode: code, underlyingData: Data(),
         underlyingResponse: HTTPURLResponse(url: URL(string: "https://x.test")!, statusCode: status, httpVersion: nil, headerFields: nil)!)
}

@MainActor
struct AccountTests {
    let auth = FakeAuth()
    let functionsURL = URL(string: "https://x.test/functions/v1")!

    func makeAccount(fetch: @escaping @MainActor (URLRequest) async throws -> (Data, URLResponse) = { _ in throw URLError(.badURL) })
        -> SupabaseAccount {
        SupabaseAccount(auth: auth, functionsURL: functionsURL, apiKey: "key", fetch: fetch)
    }

    func wait(_ account: SupabaseAccount, for expected: AccountState) async {
        for await state in account.statePublisher.values where state == expected { return }
    }

    func error(_ body: () async throws -> Void) async -> AccountError? {
        do { try await body(); return nil } catch { return error as? AccountError }
    }

    @Test func stateRestoredFromStoredSession() async {
        let account = makeAccount()
        #expect(account.state == .unknown)
        #expect(account.userID == nil)
        auth.session.yield(auth.profile)
        await wait(account, for: .signedIn(auth.profile))
        #expect(account.userID == "u1")

        let other = FakeAuth()
        let signedOut = SupabaseAccount(auth: other, functionsURL: functionsURL, apiKey: "key", fetch: { _ in throw URLError(.badURL) })
        other.session.yield(nil)
        await wait(signedOut, for: .signedOut)
    }

    @Test func signUpThenConfirmSignsIn() async throws {
        let account = makeAccount()
        try await account.signUp(name: "Алексей", email: "a@b.ru", password: "12345678")
        #expect(auth.signUpData == ["full_name": .string("Алексей")])
        #expect(account.state == .unknown)

        auth.errors["verifyOTP"] = apiError(.otpExpired, status: 403)
        #expect(await error { try await account.confirmSignUp(email: "a@b.ru", code: "000000") } == .invalidCode)
        auth.errors = [:]
        try await account.confirmSignUp(email: "a@b.ru", code: "123456")
        #expect(auth.calls.last == "verifyOTP(a@b.ru,123456,signup)")
        #expect(account.state == .signedIn(auth.profile))

        auth.errors["signUp"] = apiError(.userAlreadyExists, status: 422)
        #expect(await error { try await account.signUp(name: "", email: "a@b.ru", password: "12345678") } == .emailTaken)
        auth.errors["signUp"] = AuthError.weakPassword(message: "", reasons: [])
        #expect(await error { try await account.signUp(name: "", email: "a@b.ru", password: "1") } == .weakPassword)
        try await account.resendSignUpCode(email: "a@b.ru")
        #expect(auth.calls.last == "resend(a@b.ru)")
    }

    @Test func signInMapsErrors() async throws {
        let account = makeAccount()
        auth.errors["signIn"] = apiError(.invalidCredentials)
        #expect(await error { try await account.signIn(email: "a@b.ru", password: "x") } == .invalidCredentials)

        auth.errors["signIn"] = apiError(.emailNotConfirmed)
        #expect(await error { try await account.signIn(email: "a@b.ru", password: "x") } == .emailNotConfirmed)
        #expect(auth.calls.last == "resend(a@b.ru)")

        auth.errors["signIn"] = URLError(.notConnectedToInternet)
        #expect(await error { try await account.signIn(email: "a@b.ru", password: "x") } == .network)

        auth.errors["signIn"] = apiError(ErrorCode("something_new"), status: 429)
        #expect(await error { try await account.signIn(email: "a@b.ru", password: "x") } == .rateLimited)
        auth.errors["signIn"] = apiError(.overEmailSendRateLimit)
        #expect(await error { try await account.signIn(email: "a@b.ru", password: "x") } == .rateLimited)

        auth.errors["signIn"] = apiError(ErrorCode("something_new"), status: 500)
        #expect(await error { try await account.signIn(email: "a@b.ru", password: "x") } == .unknown)
        #expect(account.state == .unknown)

        auth.errors = [:]
        try await account.signIn(email: "a@b.ru", password: "x")
        #expect(account.state == .signedIn(auth.profile))
    }

    @Test func resetPasswordFlow() async throws {
        let account = makeAccount()
        try await account.requestPasswordReset(email: "a@b.ru")
        #expect(auth.calls == ["recover(a@b.ru)"])

        try await account.resetPassword(email: "a@b.ru", code: "654321", newPassword: "newpass12")
        #expect(auth.calls.suffix(2) == ["verifyOTP(a@b.ru,654321,recovery)", "updatePassword(newpass12)"])
        #expect(account.state == .signedIn(auth.profile))

        // Код уже потрачен, сессия восстановления не должна остаться входом со старым паролем.
        auth.errors["updatePassword"] = AuthError.weakPassword(message: "", reasons: [])
        #expect(await error { try await account.resetPassword(email: "a@b.ru", code: "1", newPassword: "x") } == .weakPassword)
        #expect(auth.calls.last == "signOut")
        #expect(account.state == .signedOut)
    }

    @Test func signOutIgnoresRemoteFailure() async throws {
        let account = makeAccount()
        try await account.signIn(email: "a@b.ru", password: "x")
        auth.errors["signOut"] = URLError(.notConnectedToInternet)
        await account.signOut()
        #expect(auth.calls.last == "signOut")
        #expect(account.state == .signedOut)
    }

    @Test func deleteAccountCallsFunctionThenSignsOut() async throws {
        var requests: [URLRequest] = []
        var status = 500
        let account = makeAccount { request in
            requests.append(request)
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        try await account.signIn(email: "a@b.ru", password: "x")

        #expect(await error { try await account.deleteAccount() } == .unknown)
        #expect(account.state == .signedIn(auth.profile))
        #expect(!auth.calls.contains("signOut"))

        status = 200
        try await account.deleteAccount()
        let request = try #require(requests.last)
        #expect(request.url?.absoluteString == "https://x.test/functions/v1/delete-account")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer jwt-1")
        #expect(request.value(forHTTPHeaderField: "apikey") == "key")
        #expect(auth.calls.suffix(2) == ["accessToken", "signOut"])
        #expect(account.state == .signedOut)
    }

    @Test func refreshFailureSignsOut() async {
        let account = makeAccount()
        auth.session.yield(auth.profile)
        await wait(account, for: .signedIn(auth.profile))
        auth.session.yield(nil) // библиотека шлёт signedOut, когда обновить сессию окончательно не удалось
        await wait(account, for: .signedOut)
    }
}
