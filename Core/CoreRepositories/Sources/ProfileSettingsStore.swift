#if FEATURE_PROFILE2
import Combine
import CoreDomain
import Foundation

/// Настройки профиля 1.2 (D41): `UserDefaults` — источник для этого iPhone, iCloud KVS — для остальных.
/// Пришедшее из облака (при запуске и по `didChangeExternallyNotification`) переписывает локальное.
@MainActor
public final class ProfileSettingsStore: ProfileSettings {
    static let remindKey = "settings.remindBookmarks"
    static let episodesKey = "settings.notifyNewEpisodes"
    static let hiddenKey = "settings.hiddenCompetitions"

    private let defaults: UserDefaults
    private let cloud: CloudSettings?
    private let subject = PassthroughSubject<Void, Never>()
    private var observer: (any NSObjectProtocol)?

    public static func make() -> ProfileSettingsStore {
        let cloud = NSUbiquitousKeyValueStore.default
        let store = ProfileSettingsStore(defaults: .standard, cloud: cloud)
        store.observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main
        ) { [weak store] _ in MainActor.assumeIsolated { store?.applyCloud() } }
        return store
    }

    init(defaults: UserDefaults, cloud: CloudSettings?) {
        self.defaults = defaults
        self.cloud = cloud
        applyCloud()
    }

    public var remindBookmarks: Bool {
        get { defaults.bool(forKey: Self.remindKey) }
        set { write(newValue, Self.remindKey) }
    }

    public var notifyNewEpisodes: Bool {
        get { defaults.bool(forKey: Self.episodesKey) }
        set { write(newValue, Self.episodesKey) }
    }

    public var hiddenCompetitions: Set<String> {
        get { Set(defaults.stringArray(forKey: Self.hiddenKey) ?? []) }
        set { write(newValue.sorted(), Self.hiddenKey) }
    }

    public var changes: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }

    func applyCloud() {
        guard let cloud else { return }
        for key in [Self.remindKey, Self.episodesKey, Self.hiddenKey] {
            if let value = cloud.object(forKey: key) { defaults.set(value, forKey: key) }
        }
        subject.send()
    }

    private func write(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        cloud?.set(value, forKey: key)
        subject.send()
    }
}

/// «Турниры в ленте» (D41): матчи скрытых турниров не попадают на «Сегодня». Карточку матча по id отдаёт как есть.
public struct HiddenCompetitionsMatches: MatchesRepository {
    let base: any MatchesRepository
    let hidden: @Sendable () async -> Set<String>

    public init(base: any MatchesRepository, hidden: @escaping @Sendable () async -> Set<String>) {
        self.base = base
        self.hidden = hidden
    }

    public func matches(in interval: DateInterval) async throws -> [Match] {
        let hidden = await hidden()
        return try await base.matches(in: interval).filter { !hidden.contains($0.competition.code) }
    }

    public func match(id: MatchID) async throws -> Match? { try await base.match(id: id) }
}

/// «Новые выпуски» (D41): что из свежих лент считать новым. Первая встреча с подкастом — только запоминаем.
enum NewEpisodes {
    static let lastSeenKey = "podcasts.lastSeen.v1"

    /// `newest` — самый свежий выпуск каждой подписки. Возвращает новые выпуски и обновлённые даты.
    static func detect(newest: [Episode], lastSeen: [String: Date]) -> (new: [Episode], lastSeen: [String: Date]) {
        var seen = lastSeen
        var new: [Episode] = []
        for episode in newest {
            if let previous = seen[episode.podcastID], episode.publishedAt > previous { new.append(episode) }
            if seen[episode.podcastID].map({ episode.publishedAt > $0 }) ?? true { seen[episode.podcastID] = episode.publishedAt }
        }
        return (new, seen)
    }
}

extension FootballRepository: CompetitionsRepository {
    /// Включённые турниры, по-русски, если есть перевод.
    func competitions() async throws -> [Competition] {
        struct Row: Decodable {
            let code: String
            let name: String
            let nameRu: String?
            enum CodingKeys: String, CodingKey { case code, name, nameRu = "name_ru" }
        }
        let rows: [Row] = try await client.from("competitions").select("code,name,name_ru").eq("enabled", value: true).execute().value
        return rows.map { Competition(code: $0.code, name: $0.nameRu ?? $0.name) }
    }
}

extension Services {
    /// Турниры для «Турниров в ленте».
    public static func competitions(supabaseURL: URL, supabaseKey: String) -> any CompetitionsRepository {
        FootballRepository(client: catalogClient(supabaseURL: supabaseURL, supabaseKey: supabaseKey))
    }
}
#endif
