import CoreDomain
import Foundation
import PostgREST

/// Сборка источников данных для приложения.
public enum Services {
    @MainActor public static func make(supabaseURL: URL, supabaseKey: String, defaults: UserDefaults = .standard)
        -> (matches: MatchesRepository, bookmarks: BookmarksStore) {
        // Только PostgREST: Auth нам не нужен, publishable-ключ идёт заголовком apikey.
        let postgrest = PostgrestClient(
            url: supabaseURL.appendingPathComponent("rest/v1"),
            headers: ["apikey": supabaseKey],
            logger: nil,
            decoder: FootballRepository.decoder
        )
        let matches = CombinedMatchesRepository(
            football: FootballRepository(client: postgrest),
            hockey: NHLClient(session: .shared)
        )
        return (matches, UserDefaultsBookmarksStore(defaults: defaults))
    }
}
