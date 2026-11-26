import BackgroundTasks
import CoreRepositories
import Foundation

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
            await Services.refreshSubscribedFeeds(supabaseURL: AppConfig.supabaseURL, supabaseKey: AppConfig.supabaseKey)
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
    }
}
