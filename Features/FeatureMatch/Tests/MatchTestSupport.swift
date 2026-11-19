import Combine
import CoreDomain
import Foundation
@testable import FeatureMatch

let moscow = TimeZone(identifier: "Europe/Moscow")!

func calendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = moscow
    return calendar
}

/// "2026-11-18 20:00" по Москве.
func date(_ string: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = moscow
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.date(from: string)!
}

let now = date("2026-11-18 20:00")
let footballID = MatchID(rawValue: "football:1")
let hockeyID = MatchID(rawValue: "hockey:2")

func match(
    _ id: MatchID = footballID,
    at kickoff: String = "2026-11-18 22:00",
    status: MatchStatus = .scheduled,
    score: (Int, Int)? = nil
) -> Match {
    let isHockey = id == hockeyID
    return Match(
        id: id,
        sport: isHockey ? .hockey : .football,
        competition: isHockey ? Competition(code: "NHL", name: "НХЛ") : Competition(code: "PL", name: "АПЛ"),
        kickoff: date(kickoff),
        status: status,
        home: Team(name: "Ливерпуль", abbreviation: "LIV"),
        away: Team(name: "Арсенал", abbreviation: "ARS"),
        homeScore: score?.0,
        awayScore: score?.1,
        round: isHockey ? nil : "12 тур",
        homeTeamID: "64",
        awayTeamID: "57"
    )
}

func row(_ position: Int, _ name: String, _ teamID: String) -> StandingRow {
    StandingRow(position: position, team: Team(name: name, abbreviation: nil), teamID: teamID, played: 12, points: 30 - position)
}

let table = [row(1, "Арсенал", "57"), row(2, "Манчестер Сити", "65"), row(3, "Ливерпуль", "64")]

struct FakeError: Error {}

/// Фейковый репозиторий матча: по желанию ждёт `release()` и, как настоящая сеть, не реагирует на отмену.
final class FakeMatchesRepository: MatchesRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _result: Result<Match?, FakeError>
    private var _calls = 0
    private let held: Bool
    private let (stream, continuation) = AsyncStream<Void>.makeStream()

    init(_ match: Match?, held: Bool = false) {
        _result = .success(match)
        self.held = held
    }

    var result: Result<Match?, FakeError> {
        get { lock.withLock { _result } }
        set { lock.withLock { _result = newValue } }
    }

    var calls: Int { lock.withLock { _calls } }

    /// Отпускает один запрос; можно звать до самого запроса.
    func release() { continuation.yield() }

    func matches(in interval: DateInterval) async throws -> [Match] { [] }

    func match(id: MatchID) async throws -> Match? {
        lock.withLock { _calls += 1 }
        if held {
            let stream = stream
            await Task.detached { for await _ in stream { break } }.value
        }
        return try result.get()
    }
}

final class FakeStandingsRepository: StandingsRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _result: Result<[StandingRow], FakeError>
    private var _codes: [String] = []

    init(_ rows: [StandingRow] = table) {
        _result = .success(rows)
    }

    var result: Result<[StandingRow], FakeError> {
        get { lock.withLock { _result } }
        set { lock.withLock { _result = newValue } }
    }

    var codes: [String] { lock.withLock { _codes } }

    func standings(competitionCode: String) async throws -> [StandingRow] {
        lock.withLock { _codes.append(competitionCode) }
        return try result.get()
    }
}

@MainActor
final class FakeBookmarksStore: BookmarksStore {
    let subject = CurrentValueSubject<Set<MatchID>, Never>([])

    var bookmarks: Set<MatchID> { subject.value }
    var bookmarksPublisher: AnyPublisher<Set<MatchID>, Never> { subject.eraseToAnyPublisher() }

    func toggle(_ id: MatchID) {
        if subject.value.contains(id) { subject.value.remove(id) } else { subject.value.insert(id) }
    }
}

@MainActor
final class FakeRemindersStore: RemindersStore {
    let subject = CurrentValueSubject<Set<MatchID>, Never>([])
    var scheduleResult: ReminderResult = .scheduled
    private(set) var scheduledMatches: [MatchID] = []

    var scheduled: Set<MatchID> { subject.value }
    var scheduledPublisher: AnyPublisher<Set<MatchID>, Never> { subject.eraseToAnyPublisher() }

    /// true — `schedule` ждёт `release()`.
    var held = false
    private let (stream, continuation) = AsyncStream<Void>.makeStream()

    func release() { continuation.yield() }

    func schedule(_ match: Match) async throws -> ReminderResult {
        scheduledMatches.append(match.id)
        if held { for await _ in stream { break } }
        if scheduleResult == .scheduled { subject.value.insert(match.id) }
        return scheduleResult
    }

    func cancel(_ id: MatchID) { subject.value.remove(id) }

    private(set) var reconciled: [[Match]] = []

    func reconcile(with matches: [Match]) { reconciled.append(matches) }
}
