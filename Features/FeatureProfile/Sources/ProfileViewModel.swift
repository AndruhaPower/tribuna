import Combine
import CoreDomain
import Foundation

/// Готовое к показу состояние Профиля.
struct ProfileState: Equatable {
    /// Плитки-счётчики: «4», «3».
    let bookmarks: String
    let subscriptions: String
    let wifiOnly: Bool
    /// «412 МБ · 6 выпусков» или «Нет загрузок».
    let usage: String
    /// Доля занятого от занятого + свободного места; nil — нет загрузок, полоски нет.
    let usageFraction: Double?
    /// «Очистить загрузки» активна, пока в загрузках есть хоть одна запись (и идущая).
    let canClear: Bool
}

enum ProfileFormatter {
    /// `available` — свободное место (кеш модели); nil — не узнать.
    @MainActor static func state(bookmarks: Int, subscriptions: Int, downloads: EpisodeDownloads, available: Int64?) -> ProfileState {
        let (bytes, count) = downloads.usage()
        let usage = count == 0 ? "Нет загрузок" : "\(size(bytes)) · \(episodes(count))"
        var fraction: Double?
        if count > 0 {
            // Свободное место не узнать — полоска пустая.
            fraction = available.map { Double(bytes) / Double(max(1, bytes + $0)) } ?? 0
        }
        return ProfileState(
            bookmarks: String(bookmarks), subscriptions: String(subscriptions), wifiOnly: downloads.wifiOnly,
            usage: usage, usageFraction: fraction, canClear: !downloads.items.isEmpty
        )
    }

    /// «412 МБ»: `ByteCountFormatter` говорит на языке устройства, поэтому `formatted` с русской локалью (как в «Подкастах», D30).
    static func size(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file).locale(Locale(identifier: "ru_RU")))
    }

    /// «1 выпуск», «2 выпуска», «5 выпусков» (21 — как 1, 11–14 — как 5).
    static func episodes(_ count: Int) -> String {
        let (mod10, mod100) = (count % 10, count % 100)
        let form = if mod10 == 1, mod100 != 11 { "выпуск" }
            else if (2...4).contains(mod10), !(12...14).contains(mod100) { "выпуска" }
            else { "выпусков" }
        return "\(count) \(form)"
    }
}

@MainActor
final class ProfileViewModel {
    @Published private(set) var state: ProfileState

    private let dependencies: FeatureProfile.Dependencies
    private var subscriptions: Set<AnyCancellable> = []
    /// Свободное место спрашиваем у системы не на каждый тик прогресса: при запуске, возврате из фона,
    /// смене занятого места и после «Очистить».
    private var available: Int64?
    private var availableForBytes: Int64

    init(dependencies: FeatureProfile.Dependencies) {
        self.dependencies = dependencies
        available = dependencies.downloads.availableCapacity()
        availableForBytes = dependencies.downloads.usage().bytes
        state = ProfileFormatter.state(bookmarks: dependencies.bookmarks.bookmarks.count,
                                       subscriptions: dependencies.subscriptions.subscriptions.count,
                                       downloads: dependencies.downloads, available: available)
        Publishers.Merge3(
            dependencies.bookmarks.bookmarksPublisher.map { _ in () },
            dependencies.subscriptions.subscriptionsPublisher.map { _ in () },
            dependencies.downloads.itemsPublisher.map { _ in () }
        )
        .sink { [weak self] in MainActor.assumeIsolated { self?.refresh() } }
        .store(in: &subscriptions)
    }

    func didToggleWifiOnly(_ isOn: Bool) {
        dependencies.downloads.wifiOnly = isOn
        refresh()
    }

    /// «Удалить все загрузки?» → «Удалить».
    func didConfirmClear() {
        dependencies.downloads.removeAll()
        refresh(reloadCapacity: true)
    }

    /// Свободное место меняется и без наших загрузок.
    func didEnterForeground() {
        refresh(reloadCapacity: true)
    }

    private func refresh(reloadCapacity: Bool = false) {
        let bytes = dependencies.downloads.usage().bytes
        if reloadCapacity || bytes != availableForBytes {
            available = dependencies.downloads.availableCapacity()
            availableForBytes = bytes
        }
        let state = ProfileFormatter.state(bookmarks: dependencies.bookmarks.bookmarks.count,
                                           subscriptions: dependencies.subscriptions.subscriptions.count,
                                           downloads: dependencies.downloads, available: available)
        if state != self.state { self.state = state }
    }
}
