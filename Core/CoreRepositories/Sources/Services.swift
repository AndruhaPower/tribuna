import Auth
import CoreDomain
import Foundation
import PostgREST
import UserNotifications

/// Сборка источников данных для приложения.
public enum Services {
    /// Закладки, подписки и позиция — пользователя `account`, синхронизируются через `userClient` (D31);
    /// `userClient` nil — только локально (отладочные моки).
    @MainActor public static func make(supabaseURL: URL, supabaseKey: String, account: Account, userClient: PostgrestClient?,
                                       defaults: UserDefaults = .standard)
        -> (matches: MatchesRepository, standings: StandingsRepository, bookmarks: BookmarksStore, reminders: RemindersStore, stations: StationsRepository,
            podcasts: PodcastsRepository, episodes: EpisodesRepository, subscriptions: SubscriptionsStore, progress: ListeningProgressStore) {
        let postgrest = catalogClient(supabaseURL: supabaseURL, supabaseKey: supabaseKey)
        // НХЛ убран до лицензии: условия NHL запрещают коммерческое использование (D34).
        let football = FootballRepository(client: postgrest)
        // Локальные хранилища до профиля (D31): без входа данных нет, не переносим.
        for key in ["bookmarks.v1", "podcasts.subscriptions.v1", "podcasts.progress.v1"] { defaults.removeObject(forKey: key) }
        return (
            football,
            football,
            SyncedBookmarksStore(defaults: defaults, account: account, remote: userClient.map(PostgrestUserDataRemote<BookmarkRow>.init)),
            LocalRemindersStore(center: UNUserNotificationCenter.current()),
            SupabaseStationsRepository(client: postgrest),
            podcastsRepository(postgrest),
            feedRepository(),
            SyncedSubscriptionsStore(defaults: defaults, account: account, remote: userClient.map(PostgrestUserDataRemote<SubscriptionRow>.init)),
            SyncedListeningProgressStore(defaults: defaults, account: account, remote: userClient.map(PostgrestUserDataRemote<ProgressRow>.init))
        )
    }

    /// Фоновое обновление (D35): ленты подписок последнего вошедшего — в кеш `FeedRepository`,
    /// чтобы новые выпуски были на экране сразу при открытии. Отмена задачи — выходим между лентами.
    @MainActor public static func refreshSubscribedFeeds(supabaseURL: URL, supabaseKey: String, defaults: UserDefaults = .standard) async {
        let subscribed = SyncedCollection<Date>.storedValue(name: SyncedSubscriptionsStore.collectionName, defaults: defaults)
        guard !subscribed.isEmpty,
              let podcasts = try? await podcastsRepository(catalogClient(supabaseURL: supabaseURL, supabaseKey: supabaseKey)).podcasts()
        else { return }
        let feeds = feedRepository()
        for podcast in podcasts where subscribed[podcast.id] != nil {
            guard !Task.isCancelled else { return }
            _ = try? await feeds.episodes(for: podcast, forceRefresh: true)
        }
    }

    /// Каталоги — без входа: publishable-ключ идёт заголовком apikey.
    static func catalogClient(supabaseURL: URL, supabaseKey: String) -> PostgrestClient {
        PostgrestClient(
            url: supabaseURL.appendingPathComponent("rest/v1"),
            headers: ["apikey": supabaseKey],
            logger: nil,
            decoder: FootballRepository.decoder
        )
    }

    private static var caches: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0] }

    private static func podcastsRepository(_ client: PostgrestClient) -> SupabasePodcastsRepository {
        SupabasePodcastsRepository(client: client, cacheFile: caches.appendingPathComponent("podcasts.json"))
    }

    private static func feedRepository() -> FeedRepository {
        FeedRepository(directory: caches.appendingPathComponent("feeds"), fetch: FeedRepository.fetch(session: .shared))
    }

    /// Отправить очереди закладок, подписок и позиции — перед выходом (D31). Сбой оставляет очередь, выход её сотрёт.
    @MainActor public static func flushUserData(bookmarks: BookmarksStore, subscriptions: SubscriptionsStore, progress: ListeningProgressStore) async {
        await (bookmarks as? SyncedBookmarksStore)?.flush()
        await (subscriptions as? SyncedSubscriptionsStore)?.flush()
        await (progress as? SyncedListeningProgressStore)?.flush()
    }

    /// Аккаунт и PostgREST для таблиц пользователя (запросы с его токеном, D31). Звать один раз:
    /// второй `AuthClient` делил бы с первым сессию в Keychain и обновлял её наперегонки.
    @MainActor public static func makeAccount(supabaseURL: URL, supabaseKey: String) -> (account: Account, userClient: PostgrestClient) {
        let auth = AuthClient(configuration: .init(
            url: supabaseURL.appendingPathComponent("auth/v1"),
            headers: ["apikey": supabaseKey],
            localStorage: KeychainLocalStorage(),
            logger: nil,
            // Своё замыкание вместо значения по умолчанию: замыкание из default-аргумента библиотеки
            // падало при входе EXC_BAD_ACCESS в swift_task_dealloc (D31, грабли).
            fetch: { try await URLSession.shared.data(for: $0) },
            // Сохранённая сессия сразу, даже просроченная: без сети остаёмся во входе, обновит библиотека.
            emitLocalSessionAsInitialSession: true
        ))
        let userClient = PostgrestClient(
            url: supabaseURL.appendingPathComponent("rest/v1"),
            headers: ["apikey": supabaseKey],
            logger: nil,
            fetch: { request in
                var request = request
                if let token = try? await auth.session.accessToken {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                return try await URLSession.shared.data(for: request)
            }
        )
        let account = SupabaseAccount(
            auth: LiveAuthBackend(client: auth),
            functionsURL: supabaseURL.appendingPathComponent("functions/v1"),
            apiKey: supabaseKey,
            fetch: { try await URLSession.shared.data(for: $0) }
        )
        return (account, userClient)
    }
}
