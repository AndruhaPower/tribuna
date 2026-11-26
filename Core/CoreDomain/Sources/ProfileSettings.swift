#if FEATURE_PROFILE2
import Combine

/// Настройки профиля 1.2 (D41): уведомления и «Турниры в ленте». Работают без входа и переезжают
/// на другие iPhone с тем же Apple ID (iCloud KVS).
@MainActor public protocol ProfileSettings: AnyObject {
    /// «Начало событий»: закладка сама ставит напоминание за 15 минут.
    var remindBookmarks: Bool { get set }
    /// «Новые выпуски»: уведомление, когда у подписки вышел выпуск.
    var notifyNewEpisodes: Bool { get set }
    /// Коды турниров, скрытых на «Сегодня».
    var hiddenCompetitions: Set<String> { get set }
    /// Любое изменение, в том числе пришедшее с другого iPhone.
    var changes: AnyPublisher<Void, Never> { get }
}

/// Турниры для «Турниров в ленте».
public protocol CompetitionsRepository: Sendable {
    func competitions() async throws -> [Competition]
}

/// Смена имени в профиле (1.2). Отдельно от `Account`, чтобы аккаунты-фейки других фич не менялись.
@MainActor public protocol AccountRenaming: AnyObject {
    /// Успех — новое имя в `Account.state`.
    func updateName(_ name: String) async throws
}
#endif
