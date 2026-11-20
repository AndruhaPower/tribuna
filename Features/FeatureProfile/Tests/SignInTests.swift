import Combine
import CoreDomain
import Foundation
import Testing
@testable import FeatureProfile

/// Аккаунт-сценарий: записывает вызовы, бросает заданные ошибки, успех входа публикует `signedIn`.
@MainActor
final class FakeAccount: Account {
    let subject: CurrentValueSubject<AccountState, Never>
    var calls: [String] = []
    var errors: [String: AccountError] = [:]
    /// Общий журнал с другими фейками — для проверки порядка.
    var log: (String) -> Void = { _ in }

    init(_ state: AccountState = .signedOut) { subject = CurrentValueSubject(state) }

    var state: AccountState { subject.value }
    var statePublisher: AnyPublisher<AccountState, Never> { subject.eraseToAnyPublisher() }
    var userID: String? { if case let .signedIn(user) = state { user.id } else { nil } }

    /// Задержать ответы до `release()` — запрос «в полёте».
    var holding = false
    private var held: [CheckedContinuation<Void, Never>] = []
    var isHeld: Bool { !held.isEmpty }
    func release() {
        holding = false
        held.forEach { $0.resume() }
        held = []
    }

    private func call(_ name: String, _ detail: String = "", signsIn: Bool = false) async throws {
        calls.append(detail.isEmpty ? name : "\(name) \(detail)")
        log(name)
        if holding { await withCheckedContinuation { held.append($0) } }
        if let error = errors[name] { throw error }
        if signsIn { subject.send(.signedIn(UserProfile(id: "u", name: nil, email: "a@b.ru"))) }
    }

    func signUp(name: String, email: String, password: String) async throws { try await call("signUp", "\(name) \(email)") }
    func confirmSignUp(email: String, code: String) async throws { try await call("confirmSignUp", "\(email) \(code)", signsIn: true) }
    func resendSignUpCode(email: String) async throws { try await call("resendSignUpCode", email) }
    func signIn(email: String, password: String) async throws { try await call("signIn", email, signsIn: true) }
    func requestPasswordReset(email: String) async throws { try await call("requestPasswordReset", email) }
    func resetPassword(email: String, code: String, newPassword: String) async throws {
        try await call("resetPassword", "\(email) \(code)", signsIn: true)
    }
    func signOut() async {
        try? await call("signOut")
        subject.send(.signedOut)
    }
    func deleteAccount() async throws {
        try await call("deleteAccount")
        subject.send(.signedOut)
    }
}

final class Box<T> {
    var value: T
    init(_ value: T) { self.value = value }
}

@MainActor
final class Clock {
    var now = Date(timeIntervalSince1970: 1_000_000)
}

@MainActor
struct SignInTests {
    let account = FakeAccount()
    let clock = Clock()
    let finished = Box<[Bool]>([])

    func makeModel(reason: SignInReason = .bookmark, start: SignInStart = .motivation) -> SignInModel {
        let model = SignInModel(account: account, reason: reason, start: start, now: { [clock] in clock.now })
        model.onFinish = { [finished] in finished.value.append($0) }
        return model
    }

    @Test func signUpFlow() async {
        let model = makeModel()
        #expect(model.state.path == [.motivation])
        model.createProfile()
        #expect(model.state.path == [.motivation, .signUp])
        #expect(!model.state.canSubmit)
        model.name = "Алексей"
        model.email = "a@b.ru"
        model.password = "1234567"
        #expect(!model.state.canSubmit) // пароль короче 8
        model.password = "12345678"
        #expect(model.state.canSubmit)
        await model.submit()
        #expect(account.calls == ["signUp Алексей a@b.ru"])
        #expect(model.state.path.last == .code)
        #expect(model.codeHint == "Мы отправили код на a@b.ru")
        model.code = "12345"
        #expect(!model.state.canSubmit)
        model.code = "123456"
        #expect(model.state.canSubmit)
        await model.submit()
        #expect(account.calls.last == "confirmSignUp a@b.ru 123456")
        #expect(finished.value == [true])
    }

    @Test func emptyNameAllowedButEmailRequired() {
        let model = makeModel(start: .signUp)
        #expect(model.state.path == [.signUp])
        model.password = "12345678"
        #expect(!model.state.canSubmit)
        model.email = "a@b.ru"
        #expect(model.state.canSubmit)
    }

    @Test func signInSucceeds() async {
        let model = makeModel(start: .signIn)
        #expect(!model.state.canSubmit)
        model.email = "a@b.ru"
        #expect(!model.state.canSubmit)
        model.password = "secret12"
        #expect(model.state.canSubmit)
        await model.submit()
        #expect(account.calls == ["signIn a@b.ru"])
        #expect(finished.value == [true])
    }

    @Test func signInUnconfirmedGoesToCode() async {
        account.errors["signIn"] = .emailNotConfirmed
        let model = makeModel(start: .signIn)
        model.email = "a@b.ru"
        model.password = "secret12"
        await model.submit()
        #expect(model.state.path == [.signIn, .code])
        #expect(model.state.error == nil)
        #expect(!model.state.canResend) // код только что отправлен заново
        model.code = "123456"
        await model.submit()
        #expect(account.calls.last == "confirmSignUp a@b.ru 123456")
        #expect(finished.value == [true])
    }

    @Test func forgotPasswordFlow() async {
        let model = makeModel(start: .signIn)
        model.email = "a@b.ru"
        model.password = "old"
        model.forgotPassword()
        #expect(model.state.path == [.signIn, .forgot])
        #expect(model.state.canSubmit) // почта уже введена
        await model.submit()
        #expect(account.calls == ["requestPasswordReset a@b.ru"])
        #expect(model.state.path.last == .resetCode)
        #expect(model.password.isEmpty) // поле нового пароля пустое
        model.code = "123456"
        model.password = "1234567"
        #expect(!model.state.canSubmit)
        model.password = "12345678"
        await model.submit()
        #expect(account.calls.last == "resetPassword a@b.ru 123456")
        #expect(finished.value == [true])
    }

    @Test func resendAtMostEverySixtySeconds() async {
        let model = makeModel(start: .signUp)
        model.email = "a@b.ru"
        model.password = "12345678"
        await model.submit()
        #expect(!model.state.canResend)
        clock.now += 59
        model.tick()
        #expect(!model.state.canResend)
        clock.now += 1
        model.tick()
        #expect(model.state.canResend)
        await model.resend()
        #expect(account.calls.last == "resendSignUpCode a@b.ru")
        #expect(!model.state.canResend)
        // Повтор раньше срока ничего не шлёт.
        await model.resend()
        #expect(account.calls.filter { $0.hasPrefix("resendSignUpCode") }.count == 1)
    }

    @Test func resendOnResetCodeRequestsResetAgain() async {
        let model = makeModel(start: .signIn)
        model.email = "a@b.ru"
        model.forgotPassword()
        await model.submit()
        clock.now += 60
        model.tick()
        await model.resend()
        #expect(account.calls == ["requestPasswordReset a@b.ru", "requestPasswordReset a@b.ru"])
    }

    @Test func errorShownAndClearedOnEdit() async {
        account.errors["signIn"] = .invalidCredentials
        let model = makeModel(start: .signIn)
        model.email = "a@b.ru"
        model.password = "secret12"
        await model.submit()
        #expect(model.state.error == "Неверная почта или пароль")
        #expect(!model.state.isLoading)
        #expect(model.state.path == [.signIn])
        #expect(finished.value.isEmpty)
        model.password = "secret123"
        #expect(model.state.error == nil)
    }

    @Test func errorTexts() {
        let expected: [(AccountError, String)] = [
            (.invalidCredentials, "Неверная почта или пароль"),
            (.emailTaken, "Эта почта уже зарегистрирована — войдите"),
            (.invalidCode, "Неверный или устаревший код"),
            (.weakPassword, "Пароль — от 8 символов"),
            (.rateLimited, "Слишком часто. Попробуйте через минуту"),
            (.network, "Нет соединения"),
            (.unknown, "Что-то пошло не так. Попробуйте ещё раз"),
        ]
        for (error, text) in expected { #expect(SignInTexts.message(error) == text) }
    }

    @Test func reasonLines() {
        #expect(SignInTexts.reason(.bookmark) == "Закладки на матчи и напоминания о начале")
        #expect(SignInTexts.reason(.reminder) == "Закладки на матчи и напоминания о начале")
        #expect(SignInTexts.reason(.subscription) == "Подписки и счётчик новых выпусков")
        #expect(SignInTexts.reason(.download) == "Выпуски без интернета")
        #expect(SignInTexts.reason(.profile) == nil)
    }

    @Test func notNowAndDismissFinishOnce() {
        let model = makeModel()
        model.notNow()
        model.dismissed()
        #expect(finished.value == [false])
    }

    @Test func dismissWithoutSignInIsFalse() {
        let model = makeModel()
        model.dismissed()
        #expect(finished.value == [false])
    }

    /// Запрос в полёте: запустить `submit`, дождаться, пока аккаунт его держит.
    func startHeld(_ model: SignInModel) async -> Task<Void, Never> {
        account.holding = true
        let task = Task { await model.submit() }
        while !account.isHeld { await Task.yield() }
        return task
    }

    @Test func dismissDuringLoadingKeepsSuccessfulSignIn() async {
        let model = makeModel(start: .signIn)
        model.email = "a@b.ru"
        model.password = "secret12"
        let task = await startHeld(model)
        #expect(model.state.isLoading)
        model.dismissed()
        #expect(finished.value.isEmpty) // ждём итога запроса
        account.release()
        await task.value
        #expect(finished.value == [true])
        model.dismissed()
        #expect(finished.value == [true])
    }

    @Test func dismissDuringLoadingThenFailureIsFalseOnce() async {
        account.errors["signIn"] = .network
        let model = makeModel(start: .signIn)
        model.email = "a@b.ru"
        model.password = "secret12"
        let task = await startHeld(model)
        model.dismissed()
        account.release()
        await task.value
        #expect(finished.value == [false])
    }

    @Test func codeStepNotPushedAfterLeavingStep() async {
        let model = makeModel()
        model.createProfile()
        model.email = "a@b.ru"
        model.password = "12345678"
        let task = await startHeld(model)
        model.didPop(toDepth: 1)
        account.release()
        await task.value
        #expect(model.state.path == [.motivation])
    }

    @Test func emailTakenOffersSignIn() async {
        account.errors["signUp"] = .emailTaken
        let model = makeModel()
        model.createProfile()
        model.email = "a@b.ru"
        model.password = "12345678"
        await model.submit()
        #expect(model.state.error == "Эта почта уже зарегистрирована — войдите")
        #expect(model.state.offersSignIn)
        model.signInInstead()
        #expect(model.state.path == [.motivation, .signUp, .signIn])
        #expect(model.email == "a@b.ru")
        #expect(!model.state.offersSignIn)
        #expect(model.state.canSubmit)
    }

    @Test func backTruncatesPath() {
        let model = makeModel()
        model.haveProfile()
        model.forgotPassword()
        #expect(model.state.path == [.motivation, .signIn, .forgot])
        model.didPop(toDepth: 1)
        #expect(model.state.path == [.motivation])
    }
}
