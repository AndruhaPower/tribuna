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
    @MainActor static func state(bookmarks: Int, subscriptions: Int, downloads: EpisodeDownloads) -> ProfileState {
        let (bytes, count) = downloads.usage()
        let usage = count == 0 ? "Нет загрузок" : "\(size(bytes)) · \(episodes(count))"
        var fraction: Double?
        if count > 0 {
            // Свободное место не узнать — полоска пустая.
            fraction = downloads.availableCapacity().map { Double(bytes) / Double(max(1, bytes + $0)) } ?? 0
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

    init(dependencies: FeatureProfile.Dependencies) {
        self.dependencies = dependencies
        state = ProfileFormatter.state(bookmarks: dependencies.bookmarks.bookmarks.count,
                                       subscriptions: dependencies.subscriptions.subscriptions.count, downloads: dependencies.downloads)
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
        refresh()
    }

    /// Свободное место меняется и без наших загрузок.
    func didEnterForeground() {
        refresh()
    }

    private func refresh() {
        let state = ProfileFormatter.state(bookmarks: dependencies.bookmarks.bookmarks.count,
                                           subscriptions: dependencies.subscriptions.subscriptions.count, downloads: dependencies.downloads)
        if state != self.state { self.state = state }
    }
}
