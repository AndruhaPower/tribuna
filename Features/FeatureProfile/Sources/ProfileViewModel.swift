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
    /// nil — без входа (и пока сессия читается): только карточка мотивации.
    var account: AccountCard?
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
    private var isBusy = false
    private var subscriptions: Set<AnyCancellable> = []
    /// Свободное место спрашиваем у системы не на каждый тик прогресса: при запуске, возврате из фона,
    /// смене занятого места и после «Очистить».
    private var available: Int64?
    private var availableForBytes: Int64

    init(dependencies: FeatureProfile.Dependencies, output: FeatureProfile.Output) {
        self.dependencies = dependencies
        self.output = output
        available = dependencies.downloads.availableCapacity()
        availableForBytes = dependencies.downloads.usage().bytes
        state = ProfileFormatter.state(bookmarks: dependencies.bookmarks.bookmarks.count,
                                       subscriptions: dependencies.subscriptions.subscriptions.count,
                                       downloads: dependencies.downloads, available: available)
        if case let .signedIn(user) = dependencies.account.state { state.account = AccountCard(user) }
        Publishers.Merge4(
            dependencies.account.statePublisher.map { _ in () },
            dependencies.bookmarks.bookmarksPublisher.map { _ in () },
            dependencies.subscriptions.subscriptionsPublisher.map { _ in () },
            dependencies.downloads.itemsPublisher.map { _ in () }
        )
        .sink { [weak self] in MainActor.assumeIsolated { self?.refresh() } }
        .store(in: &subscriptions)
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
        let timeout = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            flush.cancel()
        }
        await flush.value
        timeout.cancel()
        await dependencies.account.signOut()
        setBusy(false)
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
        if case let .signedIn(user) = dependencies.account.state { state.account = AccountCard(user) }
        state.isBusy = isBusy
        if state != self.state { self.state = state }
    }
}
