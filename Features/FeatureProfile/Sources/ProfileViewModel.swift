import Combine
import CoreDomain
import Foundation

/// Карточка аккаунта: «Алексей», почта, буква в кружке. Без имени — «Болельщик», «Б».
struct AccountCard: Equatable {
    let name: String
    let email: String
    let initial: String

    init(name: String, email: String, initial: String) {
        self.name = name
        self.email = email
        self.initial = initial
    }

    init(_ user: UserProfile) {
        let trimmed = user.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        name = trimmed.isEmpty ? "Болельщик" : trimmed
        email = user.email
        initial = name.prefix(1).uppercased()
    }
}

enum ProfileTexts {
    static let signOutConfirm = "Выйти из профиля? Загрузки будут удалены с телефона"
    static let deleteConfirm = "Удалить аккаунт? Закладки, подписки и история прослушивания удалятся навсегда"
}

/// Готовое к показу состояние Профиля.
struct ProfileState: Equatable {
    /// nil — без входа: только карточка мотивации.
    var account: AccountCard?
    /// Сессия ещё читается (`unknown`): ни мотивации, ни карточки аккаунта — без мигания при запуске.
    var isResolving = false
    /// Идёт выход или удаление — кнопки аккаунта неактивны.
    var isBusy = false
    /// Плитки-счётчики: «4», «3».
    let bookmarks: String
    let subscriptions: String
    let wifiOnly: Bool
    /// «412 МБ · 6 выпусков» или «Нет загрузок».
    let usage: String
    /// Доля занятого от занятого + свободного места; nil — нет загрузок, полоски нет.
    let usageFraction: Double?
    /// «Очистить загрузки» активна, пока в загрузках есть хоть одна запись (и идущая).
    let canClear: Bool
    /// Фото профиля (JPEG); nil — буква в кружке.
    var avatar: Data?
}

enum ProfileFormatter {
    /// `available` — свободное место (кеш модели); nil — не узнать.
    @MainActor static func state(bookmarks: Int, subscriptions: Int, downloads: EpisodeDownloads, available: Int64?) -> ProfileState {
        let (bytes, count) = downloads.usage()
        let usage = count == 0 ? "Нет загрузок" : "\(size(bytes)) · \(episodes(count))"
        var fraction: Double?
        if count > 0 {
            // Свободное место не узнать — полоска пустая.
            fraction = available.map { Double(bytes) / Double(max(1, bytes + $0)) } ?? 0
        }
        return ProfileState(
            account: nil, bookmarks: String(bookmarks), subscriptions: String(subscriptions), wifiOnly: downloads.wifiOnly,
            usage: usage, usageFraction: fraction, canClear: !downloads.items.isEmpty
        )
    }

    /// «412 МБ»: `ByteCountFormatter` говорит на языке устройства, поэтому `formatted` с русской локалью (как в «Подкастах», D30).
    static func size(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file).locale(Locale(identifier: "ru_RU")))
    }

    /// «1 выпуск», «2 выпуска», «5 выпусков» (21 — как 1, 11–14 — как 5).
    static func episodes(_ count: Int) -> String {
        let (mod10, mod100) = (count % 10, count % 100)
        let form = if mod10 == 1, mod100 != 11 { "выпуск" }
            else if (2...4).contains(mod10), !(12...14).contains(mod100) { "выпуска" }
            else { "выпусков" }
        return "\(count) \(form)"
    }
}

@MainActor
final class ProfileViewModel {
    @Published private(set) var state: ProfileState

    private let dependencies: FeatureProfile.Dependencies
    private let output: FeatureProfile.Output
    /// Сколько ждать отправки перед выходом.
    private let flushTimeout: TimeInterval
    private var isBusy = false
    private var subscriptions: Set<AnyCancellable> = []
    /// Свободное место спрашиваем у системы не на каждый тик прогресса: при запуске, возврате из фона,
    /// смене занятого места и после «Очистить».
    private var available: Int64?
    private var availableForBytes: Int64

    init(dependencies: FeatureProfile.Dependencies, output: FeatureProfile.Output, flushTimeout: TimeInterval = 3) {
        self.dependencies = dependencies
        self.output = output
        self.flushTimeout = flushTimeout
        available = dependencies.downloads.availableCapacity()
        availableForBytes = dependencies.downloads.usage().bytes
        state = ProfileFormatter.state(bookmarks: dependencies.bookmarks.bookmarks.count,
                                       subscriptions: dependencies.subscriptions.subscriptions.count,
                                       downloads: dependencies.downloads, available: available)
        Self.apply(dependencies.account.state, to: &state)
        state.avatar = dependencies.avatars.image
        Publishers.MergeMany(
            dependencies.account.statePublisher.map { _ in () }.eraseToAnyPublisher(),
            dependencies.bookmarks.bookmarksPublisher.map { _ in () }.eraseToAnyPublisher(),
            dependencies.subscriptions.subscriptionsPublisher.map { _ in () }.eraseToAnyPublisher(),
            dependencies.downloads.itemsPublisher.map { _ in () }.eraseToAnyPublisher(),
            dependencies.avatars.imagePublisher.map { _ in () }.eraseToAnyPublisher()
        )
        .sink { [weak self] in MainActor.assumeIsolated { self?.refresh() } }
        .store(in: &subscriptions)
    }

    /// Новое фото (уже квадратный JPEG). Ошибка — текст для показа.
    func didPickPhoto(_ jpeg: Data) async -> String? {
        await photoAction { try await $0.upload(jpeg) }
    }

    func didRemovePhoto() async -> String? {
        await photoAction { try await $0.remove() }
    }

    private func photoAction(_ action: @MainActor (AvatarStore) async throws -> Void) async -> String? {
        setBusy(true)
        defer { setBusy(false) }
        do {
            try await action(dependencies.avatars)
            return nil
        } catch {
            return SignInTexts.message(error as? AccountError ?? .unknown)
        }
    }

    func didToggleWifiOnly(_ isOn: Bool) {
        dependencies.downloads.wifiOnly = isOn
        refresh()
    }

    /// «Удалить все загрузки?» → «Удалить».
    func didConfirmClear() {
        dependencies.downloads.removeAll()
        refresh(reloadCapacity: true)
    }

    /// «Выйти» подтверждено: сначала отправить неотправленное (не дольше 3 с — выход важнее, D31), затем выйти.
    func didConfirmSignOut() async {
        setBusy(true)
        let flush = Task { await output.flushUserData() }
        let timeout = flushTimeout
        // Гонка: кто первый — отправка или таймер. Отправка, не слышащая отмены, выход не держит.
        let gate = Gate()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            gate.continuation = continuation
            Task { await flush.value; gate.open() }
            Task { try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)); gate.open() }
        }
        flush.cancel()
        await dependencies.account.signOut()
        setBusy(false)
    }

    /// Продолжение, которое возобновляется один раз — первым из гонки.
    @MainActor private final class Gate {
        var continuation: CheckedContinuation<Void, Never>?
        func open() {
            continuation?.resume()
            continuation = nil
        }
    }

    /// «Удалить аккаунт» подтверждено. Ошибка — текст для показа, остаёмся во входе.
    func didConfirmDelete() async -> String? {
        setBusy(true)
        defer { setBusy(false) }
        do {
            try await dependencies.account.deleteAccount()
            return nil
        } catch {
            return SignInTexts.message(error as? AccountError ?? .unknown)
        }
    }

    /// Свободное место меняется и без наших загрузок.
    func didEnterForeground() {
        refresh(reloadCapacity: true)
    }

    private static func apply(_ account: AccountState, to state: inout ProfileState) {
        state.isResolving = account == .unknown
        if case let .signedIn(user) = account { state.account = AccountCard(user) }
    }

    private func setBusy(_ busy: Bool) {
        isBusy = busy
        refresh()
    }

    private func refresh(reloadCapacity: Bool = false) {
        let bytes = dependencies.downloads.usage().bytes
        if reloadCapacity || bytes != availableForBytes {
            available = dependencies.downloads.availableCapacity()
            availableForBytes = bytes
        }
        var state = ProfileFormatter.state(bookmarks: dependencies.bookmarks.bookmarks.count,
                                           subscriptions: dependencies.subscriptions.subscriptions.count,
                                           downloads: dependencies.downloads, available: available)
        Self.apply(dependencies.account.state, to: &state)
        state.avatar = dependencies.avatars.image
        state.isBusy = isBusy
        if state != self.state { self.state = state }
    }
}
