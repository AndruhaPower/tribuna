import Combine
import CoreDomain
import Foundation

/// С какого шага открыть лист входа.
public enum SignInStart: Sendable {
    case motivation, signUp, signIn
}

/// Шаги листа: мотивация → регистрация → код; вход (неподтверждённая почта → код); «Забыли пароль?» → почта → код и новый пароль.
enum SignInStep: Equatable {
    case motivation, signUp, code, signIn, forgot, resetCode
}

struct SignInState: Equatable {
    /// Стек шагов в навигации листа.
    var path: [SignInStep]
    var isLoading = false
    /// Подпись под полями.
    var error: String?
    var canSubmit = false
    var canResend = false
    /// Почта занята — под ошибкой ссылка «Войти» (`signInInstead()`).
    var offersSignIn = false
}

enum SignInTexts {
    static let benefits = ["Закладки и напоминания о матчах", "Подписки и новые выпуски", "Слушайте с того же места на любом iPhone"]

    /// Строка мотивации по поводу; у Профиля — нет.
    static func reason(_ reason: SignInReason) -> String? {
        switch reason {
        case .bookmark, .reminder: "Закладки на матчи и напоминания о начале"
        case .subscription: "Подписки и счётчик новых выпусков"
        case .download: "Выпуски без интернета"
        case .profile: nil
        }
    }

    static func message(_ error: AccountError) -> String {
        switch error {
        case .invalidCredentials: "Неверная почта или пароль"
        case .emailTaken: "Эта почта уже зарегистрирована — войдите"
        case .invalidCode: "Неверный или устаревший код"
        case .weakPassword: "Пароль — от 8 символов"
        case .rateLimited: "Слишком часто. Попробуйте через минуту"
        case .network: "Нет соединения"
        case .appleUnavailable: "Вход через Apple пока недоступен"
        // `emailNotConfirmed` ведёт на шаг кода и сюда не доходит.
        case .emailNotConfirmed, .unknown: "Что-то пошло не так. Попробуйте ещё раз"
        }
    }
}

/// Модель листа входа (D21, D31): поля, шаги и вызовы `Account`. Итог — `onFinish(true)` после входа, `false` — закрыли.
@MainActor
final class SignInModel {
    static let resendInterval: TimeInterval = 60
    static let minPasswordLength = 8

    @Published private(set) var state: SignInState
    var name = "" { didSet { edited() } }
    var email = "" { didSet { edited() } }
    /// Пароль входа и регистрации; на шаге сброса — новый пароль.
    var password = "" { didSet { edited() } }
    var code = "" { didSet { edited() } }
    var onFinish: ((Bool) -> Void)?

    let reason: SignInReason
    private let account: Account
    private let now: () -> Date
    private var codeSentAt: Date?
    private var isFinished = false
    /// Лист закрыли, пока шёл запрос: итог — по его результату (вход не теряется).
    private var dismissedWhileLoading = false

    init(account: Account, reason: SignInReason, start: SignInStart, now: @escaping () -> Date = Date.init) {
        self.account = account
        self.reason = reason
        self.now = now
        let step: SignInStep = switch start {
        case .motivation: .motivation
        case .signUp: .signUp
        case .signIn: .signIn
        }
        state = SignInState(path: [step])
        update()
    }

    var step: SignInStep { state.path.last ?? .motivation }

    /// «Мы отправили код на <почта>».
    var codeHint: String { "Мы отправили код на \(trimmedEmail)" }

    func createProfile() { push(.signUp) }
    func haveProfile() { push(.signIn) }
    func forgotPassword() { push(.forgot) }
    func notNow() { finish(false) }

    /// Лист закрыли (жест, «Закрыть»). Во время запроса итог сообщим, когда он закончится.
    func dismissed() {
        if state.isLoading { dismissedWhileLoading = true } else { finish(false) }
    }

    /// «Войти» под ошибкой «почта занята»: шаг входа с той же почтой.
    func signInInstead() { push(.signIn) }

    /// Навигация листа вернулась назад («‹» или свайп).
    func didPop(toDepth depth: Int) {
        guard depth < state.path.count, depth > 0 else { return }
        state.path.removeLast(state.path.count - depth)
        state.error = nil
        state.offersSignIn = false
        update()
    }

    /// Секундный таймер экрана кода: «Отправить ещё раз» оживает через 60 с.
    func tick() { update() }

    func submit() async {
        guard state.canSubmit, !state.isLoading else { return }
        let email = trimmedEmail
        let origin = state.path
        await perform {
            switch step {
            case .motivation:
                break
            case .signUp:
                try await account.signUp(name: name.trimmingCharacters(in: .whitespacesAndNewlines), email: email, password: password)
                codeSent(next: .code, from: origin)
            case .code:
                try await account.confirmSignUp(email: email, code: code)
                finish(true)
            case .signIn:
                do {
                    try await account.signIn(email: email, password: password)
                    finish(true)
                } catch AccountError.emailNotConfirmed {
                    // Код подтверждения уже отправлен заново.
                    codeSent(next: .code, from: origin)
                }
            case .forgot:
                try await account.requestPasswordReset(email: email)
                password = ""
                codeSent(next: .resetCode, from: origin)
            case .resetCode:
                try await account.resetPassword(email: email, code: code, newPassword: password)
                finish(true)
            }
        }
    }

    /// «Войти с Apple»: `authorize` показывает системный лист Apple, nil — человек его закрыл.
    func signInWithApple(_ authorize: () async throws -> AppleCredential?) async {
        guard !state.isLoading else { return }
        await perform {
            guard let credential = try await authorize() else { return }
            try await account.signInWithApple(idToken: credential.idToken, nonce: credential.nonce, name: credential.name)
            finish(true)
        }
    }

    func resend() async {
        guard state.canResend, !state.isLoading else { return }
        let email = trimmedEmail
        await perform {
            if step == .resetCode {
                try await account.requestPasswordReset(email: email)
            } else {
                try await account.resendSignUpCode(email: email)
            }
            codeSentAt = now()
        }
    }

    // MARK: - Внутреннее

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func perform(_ operation: () async throws -> Void) async {
        state.isLoading = true
        state.error = nil
        state.offersSignIn = false
        update()
        do {
            try await operation()
        } catch {
            let accountError = error as? AccountError ?? .unknown
            state.error = SignInTexts.message(accountError)
            state.offersSignIn = accountError == .emailTaken
        }
        state.isLoading = false
        update()
        if dismissedWhileLoading { finish(false) } // успех уже сообщил `finish(true)`
    }

    /// Код отправлен — следующий шаг, если человек всё ещё на шаге, с которого отправлял, и лист не закрыт.
    private func codeSent(next: SignInStep, from origin: [SignInStep]) {
        codeSentAt = now()
        code = ""
        guard state.path == origin, !dismissedWhileLoading else { return }
        push(next)
    }

    private func push(_ step: SignInStep) {
        state.path.append(step)
        state.error = nil
        state.offersSignIn = false
        update()
    }

    private func finish(_ signedIn: Bool) {
        guard !isFinished else { return }
        isFinished = true
        onFinish?(signedIn)
    }

    private func edited() {
        state.error = nil
        state.offersSignIn = false
        update()
    }

    /// Длина кода из письма задаётся в Supabase (Email OTP Length, 6–10; по умолчанию 8) — принимаем любую.
    static let codeLengths = 6...10

    private func update() {
        let hasEmail = trimmedEmail.contains("@")
        let strongPassword = password.count >= Self.minPasswordLength
        let hasCode = Self.codeLengths.contains(code.count) && code.allSatisfy(\.isNumber)
        var next = state
        let filled = switch step {
        case .motivation: false
        case .signUp: hasEmail && strongPassword
        case .code: hasCode
        case .signIn: hasEmail && !password.isEmpty
        case .forgot: hasEmail
        case .resetCode: hasCode && strongPassword
        }
        next.canSubmit = !state.isLoading && filled
        next.canResend = !state.isLoading && (step == .code || step == .resetCode)
            && codeSentAt.map { now().timeIntervalSince($0) >= Self.resendInterval } ?? true
        if next != state { state = next }
    }
}
