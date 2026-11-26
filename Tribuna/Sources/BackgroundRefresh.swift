import BackgroundTasks
import CoreDomain
import CoreRepositories
import Foundation
import UserNotifications

/// Фоновое обновление лент подписок (D35, `UIBackgroundModes: fetch`). Когда запустить — решает iOS;
/// мы просим не раньше чем через час после ухода в фон.
enum BackgroundRefresh {
    /// Совпадает с `BGTaskSchedulerPermittedIdentifiers` в `Project.swift`.
    static let identifier = (Bundle.main.bundleIdentifier ?? "com.tribuna.app") + ".refresh"

    /// Только до конца `didFinishLaunching`, иначе iOS падает.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            // Очередь .main: задача приходит на главный поток и дальше живёт только там.
            nonisolated(unsafe) let task = task
            MainActor.assumeIsolated { run(task) }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor private static func run(_ task: BGTask) {
        schedule()
        let work = Task { @MainActor in
            let new = await Services.refreshSubscribedFeeds(supabaseURL: AppConfig.supabaseURL, supabaseKey: AppConfig.supabaseKey)
            #if FEATURE_PROFILE2
            if AppDependencies.profileSettings.notifyNewEpisodes { await notify(new) }
            #else
            _ = new
            #endif
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
    }

    #if FEATURE_PROFILE2
    /// «Новые выпуски» (1.2, D41): локальное уведомление на каждый новый выпуск подписки. Без разрешения iOS их просто не покажет.
    @MainActor private static func notify(_ new: [(podcast: Podcast, episode: Episode)]) async {
        for (podcast, episode) in new {
            let content = UNMutableNotificationContent()
            content.title = podcast.title
            content.body = "Новый выпуск: \(episode.title)"
            content.sound = .default
            let request = UNNotificationRequest(identifier: "episode:\(episode.id.rawValue)", content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }
    #endif
}
