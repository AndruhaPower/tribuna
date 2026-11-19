import Foundation

/// Конфигурация бэкенда. Publishable-ключ публичен по замыслу Supabase, доступ ограничен RLS (D20) — не секрет в смысле D9.
enum AppConfig {
    static let supabaseURL = URL(string: "https://wgwsdhyrazjzqwvnhgzk.supabase.co")!
    static let supabaseKey = "sb_publishable_l-xow6_fopQcOc02UAzpfw_RbeFcQLE"
}
