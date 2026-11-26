import Foundation

/// Конфигурация бэкенда. Publishable-ключ публичен по замыслу Supabase, доступ ограничен RLS (D20) — не секрет в смысле D9.
enum AppConfig {
    static let supabaseURL = URL(string: "https://wgwsdhyrazjzqwvnhgzk.supabase.co")!
    static let supabaseKey = "sb_publishable_l-xow6_fopQcOc02UAzpfw_RbeFcQLE"
    /// Endpoint приложения из кабинета Mindbox (D36) — идентификатор, не секрет: всё равно лежит в бинарнике.
    /// Пусто — Mindbox не запускается. До выкладки заполнить: без него режимы processing и remote-notification не используются.
    static let mindboxEndpoint = ""
    static let mindboxDomain = "api.mindbox.ru"
}
