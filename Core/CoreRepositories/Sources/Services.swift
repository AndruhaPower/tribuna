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
        // Каталоги — без входа: publishable-ключ идёт заголовком apikey.
        let postgrest = PostgrestClient(
            url: supabaseURL.appendingPathComponent("rest/v1"),
            headers: ["apikey": supabaseKey],
            logger: nil,
            decoder: FootballRepository.decoder
        )
        let football = FootballRepository(client: postgrest)
        let matches = CombinedMatchesRepository(football: football, hockey: NHLClient(session: .shared))
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return (
            matches,
            football, // таблицы только у футбола; для НХЛ запрос вернёт пусто
            SyncedBookmarksStore(defaults: defaults, account: account, remote: userClient.map(PostgrestUserDataRemote<BookmarkRow>.init)),
            LocalRemindersStore(center: UNUserNotificationCenter.current()),
            SupabaseStationsRepository(client: postgrest),
            SupabasePodcastsRepository(client: postgrest, cacheFile: caches.appendingPathComponent("podcasts.json")),
            FeedRepository(directory: caches.appendingPathComponent("feeds"), fetch: FeedRepository.fetch(session: .shared)),
            SyncedSubscriptionsStore(defaults: defaults, account: account, remote: userClient.map(PostgrestUserDataRemote<SubscriptionRow>.init)),
            SyncedListeningProgressStore(defaults: defaults, account: account, remote: userClient.map(PostgrestUserDataRemote<ProgressRow>.init))
        )
    }

    /// Аккаунт и PostgREST для таблиц пользователя (запросы с его токеном, D31). Звать один раз:
    /// второй `AuthClient` делил бы с первым сессию в Keychain и обновлял её наперегонки.
    @MainActor public static func makeAccount(supabaseURL: URL, supabaseKey: String) -> (account: Account, userClient: PostgrestClient) {
        let auth = AuthClient(configuration: .init(
            url: supabaseURL.appendingPathComponent("auth/v1"),
            headers: ["apikey": supabaseKey],
            localStorage: KeychainLocalStorage(),
            logger: nil,
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
