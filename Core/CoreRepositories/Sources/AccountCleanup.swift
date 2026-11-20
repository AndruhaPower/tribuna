import Combine
import CoreDomain
import Foundation

/// Чистка данных телефона при смене владельца (D31): снять все напоминания и удалить загрузки.
/// Правило то же, что у синхронизируемых хранилищ: `signedIn(X)` → `signedOut`, `signedIn(X)` → `signedIn(Y)`
/// и запуск с сохранённым владельцем, разрешившийся в `signedOut`. Запуск без входа ничего не трогает.
@MainActor
public final class AccountCleanup {
    private static let ownerKey = "account.owner"

    private let reminders: RemindersStore
    private let downloads: EpisodeDownloads
    private let defaults: UserDefaults
    private var subscriptions: Set<AnyCancellable> = []
    /// Напоминания центр отдаёт асинхронно: пришедшие после чистки снимаем, пока нет входа.
    private var lateReminders: AnyCancellable?

    public init(account: Account, reminders: RemindersStore, downloads: EpisodeDownloads, defaults: UserDefaults = .standard) {
        self.reminders = reminders
        self.downloads = downloads
        self.defaults = defaults
        account.statePublisher.sink { [weak self] in self?.apply($0) }.store(in: &subscriptions)
    }

    private func apply(_ state: AccountState) {
        let owner = defaults.string(forKey: Self.ownerKey)
        switch state {
        case .unknown:
            break
        case .signedOut:
            guard owner != nil else { return }
            defaults.removeObject(forKey: Self.ownerKey)
            cleanup()
            lateReminders = reminders.scheduledPublisher
                .first { !$0.isEmpty }
                .sink { [weak self] in self?.cancel($0) }
        case let .signedIn(user):
            lateReminders = nil
            guard owner != user.id else { return }
            defaults.set(user.id, forKey: Self.ownerKey)
            if owner != nil { cleanup() }
        }
    }

    private func cleanup() {
        cancel(reminders.scheduled)
        downloads.removeAll()
    }

    private func cancel(_ ids: Set<MatchID>) {
        ids.forEach(reminders.cancel)
    }
}
