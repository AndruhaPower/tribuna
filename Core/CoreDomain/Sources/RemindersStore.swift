import Combine

public enum ReminderResult: Sendable, Equatable {
    case scheduled
    /// Уведомления запрещены пользователем.
    case denied
    /// Матч не запланирован или стартует раньше чем через 15 минут.
    case tooLate
}

/// Локальные напоминания за 15 минут до начала матча.
@MainActor
public protocol RemindersStore: AnyObject {
    var scheduled: Set<MatchID> { get }
    var scheduledPublisher: AnyPublisher<Set<MatchID>, Never> { get }
    func schedule(_ match: Match) async throws -> ReminderResult
    func cancel(_ id: MatchID)
    /// Пересверка с актуальными данными: время переносится, для начавшихся/отменённых/перенесённых напоминание снимается.
    func reconcile(with matches: [Match])
}
