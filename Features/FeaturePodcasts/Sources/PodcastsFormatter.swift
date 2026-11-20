import CoreDomain
import Foundation

/// Правила «новых» выпусков и тексты вкладки «Подкасты» (D29). Плитки, бейдж и список считаются одной функцией `isNew`,
/// поэтому их счётчики сходятся.
enum PodcastsFormatter {
    /// Окно «новых» до подписки: выпуски старше не считаются новыми даже не начатыми.
    static let newWindow: TimeInterval = 7 * 24 * 3600

    private static let months = ["янв", "февр", "мар", "апр", "мая", "июн", "июл", "авг", "сент", "окт", "нояб", "дек"]

    /// Новый — не начат (позиции нет, не прослушан) и опубликован не раньше чем за 7 дней до подписки.
    static func isNew(_ episode: Episode, subscribedAt: Date, progress: [EpisodeID: ListeningProgress]) -> Bool {
        progress[episode.id] == nil && episode.publishedAt >= subscribedAt.addingTimeInterval(-newWindow)
    }

    /// Начат и не дослушан.
    static func isInProgress(_ episode: Episode, progress: [EpisodeID: ListeningProgress]) -> Bool {
        progress[episode.id].map { !$0.isFinished } ?? false
    }

    /// «1 новый», «2 новых», «21 новый», «11 новых»; 0 — «Всё прослушано».
    static func newLabel(_ count: Int) -> String {
        guard count > 0 else { return "Всё прослушано" }
        return count % 10 == 1 && count % 100 != 11 ? "\(count) новый" : "\(count) новых"
    }

    /// Подписанные подкасты в порядке каталога (подписки на подкасты, которых нет в каталоге, не показываем).
    static func subscribed(_ podcasts: [Podcast], subscriptions: [String: Date]) -> [(podcast: Podcast, since: Date)] {
        podcasts.compactMap { podcast in subscriptions[podcast.id].map { (podcast, $0) } }
    }

    static func tiles(
        _ subscribed: [(podcast: Podcast, since: Date)],
        episodes: [String: [Episode]],
        failed: Set<String>,
        progress: [EpisodeID: ListeningProgress]
    ) -> [SubscriptionTile] {
        subscribed.map { podcast, since in
            // Лента ещё грузится — пусто, не загрузилась — «Нет связи», но не «Всё прослушано».
            let subtitle = episodes[podcast.id].map { list in
                newLabel(list.filter { isNew($0, subscribedAt: since, progress: progress) }.count)
            } ?? (failed.contains(podcast.id) ? "Нет связи" : "")
            return SubscriptionTile(id: podcast.id, title: podcast.title, artworkURL: podcast.artworkURL, subtitle: subtitle)
        }
    }

    /// «Новые выпуски»: новые и начатые выпуски подписок вперемешку, по дате публикации, новые первыми.
    static func feed(
        _ subscribed: [(podcast: Podcast, since: Date)],
        episodes: [String: [Episode]],
        progress: [EpisodeID: ListeningProgress]
    ) -> [(episode: Episode, podcast: Podcast, isNew: Bool)] {
        subscribed
            .flatMap { podcast, since in
                (episodes[podcast.id] ?? []).compactMap { episode in
                    let isNew = isNew(episode, subscribedAt: since, progress: progress)
                    return isNew || isInProgress(episode, progress: progress) ? (episode, podcast, isNew) : nil
                }
            }
            .sorted { $0.episode.publishedAt > $1.episode.publishedAt }
    }

    /// Кнопка — у первой строки и у выпуска, который сейчас в плеере; «Скачать» — рядом с ней, если записи нет или она `.failed`.
    /// `inDownloads` — строка сегмента «Загрузки»: обложка из файла, размер скачанного во второй строке.
    static func row(
        _ episode: Episode,
        podcast: Podcast,
        isNew: Bool,
        isFirst: Bool,
        progress: [EpisodeID: ListeningProgress],
        playback: PlaybackState,
        download: DownloadedEpisode?,
        wifiOnly: Bool,
        inDownloads: Bool = false,
        now: Date,
        calendar: Calendar
    ) -> EpisodeRow {
        let isCurrent = playback.item?.episode?.id == episode.id
        let isActive = isCurrent && (playback.status == .playing || playback.status == .loading)
        let state = download?.state
        var name = podcast.title
        var tail: String?
        var downloadProgress: Double?
        let action: EpisodeRow.DownloadAction
        switch state {
        case nil, .failed:
            action = .download
            if state == .failed { tail = "не удалось скачать" }
        case .waiting:
            action = .cancel
            tail = wifiOnly ? "ждёт Wi-Fi" : "ждёт сеть"
            downloadProgress = 0
        case let .downloading(value):
            action = .cancel
            tail = wifiOnly ? "загрузка по Wi-Fi" : "загрузка"
            downloadProgress = value
        case let .downloaded(bytes):
            action = .remove
            name += " · скачан"
            if inDownloads { tail = size(bytes) }
        }
        let subtitle = [subtitle(episode, progress: progress[episode.id], now: now, calendar: calendar), tail].compactMap { $0 }.joined(separator: " · ")
        let caption = isNew ? "● Новый · \(name)" : name
        let button: EpisodeRow.Button? = isFirst || isCurrent ? (isActive ? .pause : .listen) : nil
        return EpisodeRow(
            id: episode.id,
            artworkURL: (inDownloads ? download?.artworkFile : nil) ?? episode.artworkURL ?? podcast.artworkURL,
            caption: caption,
            isNew: isNew,
            title: episode.title,
            subtitle: subtitle,
            button: button,
            showsDownloadButton: button != nil && action == .download,
            downloadProgress: downloadProgress,
            downloadAction: action,
            buttonAccessibilityLabel: button.map { ($0 == .pause ? "Пауза" : "Слушать") + ", \(episode.title)" },
            accessibilityLabel: [episode.title, isNew ? "Новый, \(name)" : name, subtitle].joined(separator: ", ")
        )
    }

    /// «48 МБ», «1,25 ГБ» — по-русски независимо от языка устройства.
    static func size(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file).locale(Locale(identifier: "ru_RU")))
    }

    /// «Сегодня · 34 мин», «16 нояб · осталось 12 мин» (начат), «2 нояб · прослушано».
    static func subtitle(_ episode: Episode, progress: ListeningProgress?, now: Date, calendar: Calendar) -> String {
        let tail: String? = if progress?.isFinished == true {
            "прослушано"
        } else if let progress, let duration = episode.duration {
            "осталось \(minutes(duration - progress.position))"
        } else {
            episode.duration.map(minutes)
        }
        return [day(episode.publishedAt, now: now, calendar: calendar), tail].compactMap { $0 }.joined(separator: " · ")
    }

    /// «Сегодня», «Вчера», «16 нояб», в другом году — «16 нояб 2025».
    static func day(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Сегодня" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "Вчера" }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let text = "\(parts.day ?? 0) \(months[(parts.month ?? 1) - 1])"
        return parts.year == calendar.component(.year, from: now) ? text : "\(text) \(parts.year ?? 0)"
    }

    /// «34 мин» (34:10 — как в макете), «1 ч 12 мин», «2 ч»; до ближайшей минуты, не меньше 1 мин.
    static func minutes(_ seconds: TimeInterval) -> String {
        let total = max(1, Int((seconds / 60).rounded()))
        let (hours, rest) = total.quotientAndRemainder(dividingBy: 60)
        guard hours > 0 else { return "\(rest) мин" }
        return rest == 0 ? "\(hours) ч" : "\(hours) ч \(rest) мин"
    }
}
