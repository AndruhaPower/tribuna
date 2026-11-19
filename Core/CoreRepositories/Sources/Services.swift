import CoreDomain
import Foundation
import PostgREST
import UserNotifications

/// Сборка источников данных для приложения.
public enum Services {
    @MainActor public static func make(supabaseURL: URL, supabaseKey: String, defaults: UserDefaults = .standard)
        -> (matches: MatchesRepository, standings: StandingsRepository, bookmarks: BookmarksStore, reminders: RemindersStore, stations: StationsRepository) {
        // Только PostgREST: Auth нам не нужен, publishable-ключ идёт заголовком apikey.
        let postgrest = PostgrestClient(
            url: supabaseURL.appendingPathComponent("rest/v1"),
            headers: ["apikey": supabaseKey],
            logger: nil,
            decoder: FootballRepository.decoder
        )
        let football = FootballRepository(client: postgrest)
        let matches = CombinedMatchesRepository(football: football, hockey: NHLClient(session: .shared))
        return (
            matches,
            football, // таблицы только у футбола; для НХЛ запрос вернёт пусто
            UserDefaultsBookmarksStore(defaults: defaults),
            LocalRemindersStore(center: UNUserNotificationCenter.current()),
            SupabaseStationsRepository(client: postgrest)
        )
    }
}
