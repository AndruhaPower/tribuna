import Combine
import CoreDomain
import Foundation
import UserNotifications

/// То, что нужно от `UNUserNotificationCenter`; в тестах — фейк.
@MainActor
protocol UserNotificationCenter: AnyObject {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: UserNotificationCenter {}

/// Локальные напоминания за 15 минут до начала. Своего хранилища нет: набор берётся из ожидающих запросов центра,
/// поэтому переживает перезапуск. Идентификатор запроса — `MatchID.rawValue`, время начала — в `userInfo`.
@MainActor
final class LocalRemindersStore: RemindersStore {
    static let lead: TimeInterval = 15 * 60
    private static let kickoffKey = "kickoff"

    private let center: UserNotificationCenter
    private let now: () -> Date
    private let subject = CurrentValueSubject<Set<MatchID>, Never>([])
    /// Запланированные матчи и время начала, под которое стоит напоминание.
    private var kickoffs: [MatchID: Date] = [:] {
        didSet { if Set(kickoffs.keys) != subject.value { subject.send(Set(kickoffs.keys)) } }
    }
    /// Последняя операция с центром: следующие ждут её, чтобы загрузка и пересверка не перемешивались.
    private var work = Task<Void, Never> {}

    init(center: UserNotificationCenter, now: @escaping () -> Date = Date.init) {
        self.center = center
        self.now = now
        enqueue { await self.load() }
    }

    var scheduled: Set<MatchID> { subject.value }

    var scheduledPublisher: AnyPublisher<Set<MatchID>, Never> { subject.eraseToAnyPublisher() }

    func schedule(_ match: Match) async throws -> ReminderResult {
        guard canRemind(match) else { return .tooLate }
        await work.value
        // Системный запрос показывается один раз; дальше сразу возвращает текущее разрешение.
        guard try await center.requestAuthorization(options: [.alert, .sound]) else { return .denied }
        try await center.add(Self.request(for: match))
        kickoffs[match.id] = match.kickoff
        return .scheduled
    }

    func cancel(_ id: MatchID) {
        kickoffs[id] = nil
        enqueue { self.center.removePendingNotificationRequests(withIdentifiers: [id.rawValue]) }
    }

    func reconcile(with matches: [Match]) {
        enqueue {
            await self.load() // показанные уведомления уже не в ожидании — убираем их из набора
            for match in matches {
                guard let kickoff = self.kickoffs[match.id] else { continue }
                if !self.canRemind(match) {
                    // Начался, отменён, перенесён или сдвинут ближе чем на 15 минут.
                    if match.status != .scheduled || kickoff != match.kickoff { self.drop(match.id) }
                } else if kickoff != match.kickoff {
                    // Тот же идентификатор заменяет ожидающий запрос.
                    do {
                        try await self.center.add(Self.request(for: match))
                        self.kickoffs[match.id] = match.kickoff
                    } catch {
                        self.drop(match.id)
                    }
                }
            }
        }
    }

    /// Ждёт завершения поставленных операций (для тестов).
    func idle() async {
        await work.value
    }

    private func canRemind(_ match: Match) -> Bool {
        match.status == .scheduled && match.kickoff.addingTimeInterval(-Self.lead) > now()
    }

    private func drop(_ id: MatchID) {
        kickoffs[id] = nil
        center.removePendingNotificationRequests(withIdentifiers: [id.rawValue])
    }

    private func load() async {
        let requests = await center.pendingNotificationRequests()
        kickoffs = Dictionary(requests.compactMap { request in
            (request.content.userInfo[Self.kickoffKey] as? TimeInterval).map {
                (MatchID(rawValue: request.identifier), Date(timeIntervalSince1970: $0))
            }
        }, uniquingKeysWith: { first, _ in first })
    }

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = work
        work = Task { await previous.value; await operation() }
    }

    private static func request(for match: Match) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Скоро матч"
        content.body = "\(match.home?.name ?? "Хозяева") — \(match.away?.name ?? "Гости") через 15 минут"
        content.sound = .default
        content.userInfo = [kickoffKey: match.kickoff.timeIntervalSince1970]
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: match.kickoff.addingTimeInterval(-lead)
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: match.id.rawValue, content: content, trigger: trigger)
    }
}
