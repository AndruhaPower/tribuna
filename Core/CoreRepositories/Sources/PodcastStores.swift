import Combine
import CoreDomain
import Foundation

/// Подписки локально: словарь id подкаста → дата подписки в UserDefaults.
@MainActor
final class UserDefaultsSubscriptionsStore: SubscriptionsStore {
    static let key = "podcasts.subscriptions.v1"

    private let defaults: UserDefaults
    private let now: () -> Date
    private let subject: CurrentValueSubject<[String: Date], Never>

    init(defaults: UserDefaults, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        subject = CurrentValueSubject(defaults.dictionary(forKey: Self.key) as? [String: Date] ?? [:])
    }

    var subscriptions: [String: Date] { subject.value }

    var subscriptionsPublisher: AnyPublisher<[String: Date], Never> { subject.eraseToAnyPublisher() }

    func toggle(_ podcastID: String) {
        var subscriptions = subject.value
        if subscriptions.removeValue(forKey: podcastID) == nil { subscriptions[podcastID] = now() }
        defaults.set(subscriptions, forKey: Self.key)
        subject.send(subscriptions)
    }
}

/// Позиция и «прослушано» локально: JSON `[EpisodeID.rawValue: ListeningProgress]` в UserDefaults.
// shortcut: пишем весь словарь при каждом сохранении (раз в 10 с); переходить на файл/выборочную запись, если выпусков станут тысячи.
@MainActor
final class UserDefaultsListeningProgressStore: ListeningProgressStore {
    static let key = "podcasts.progress.v1"

    private let defaults: UserDefaults
    private let subject: CurrentValueSubject<[EpisodeID: ListeningProgress], Never>

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([String: ListeningProgress].self, from: $0) } ?? [:]
        subject = CurrentValueSubject(Dictionary(uniqueKeysWithValues: stored.map { (EpisodeID(rawValue: $0.key), $0.value) }))
    }

    var progress: [EpisodeID: ListeningProgress] { subject.value }

    var progressPublisher: AnyPublisher<[EpisodeID: ListeningProgress], Never> { subject.eraseToAnyPublisher() }

    func setPosition(_ position: TimeInterval, for id: EpisodeID) {
        update(id) { $0.position = position }
    }

    func markFinished(_ id: EpisodeID) {
        update(id) { $0 = ListeningProgress(position: 0, isFinished: true) }
    }

    private func update(_ id: EpisodeID, _ change: (inout ListeningProgress) -> Void) {
        var progress = subject.value
        change(&progress[id, default: ListeningProgress(position: 0, isFinished: false)])
        let stored = Dictionary(uniqueKeysWithValues: progress.map { ($0.key.rawValue, $0.value) })
        defaults.set(try? JSONEncoder().encode(stored), forKey: Self.key)
        subject.send(progress)
    }
}
