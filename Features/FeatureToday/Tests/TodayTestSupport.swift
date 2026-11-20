import Combine
import CoreDomain
import Foundation
@testable import FeatureToday

let moscow = TimeZone(identifier: "Europe/Moscow")!

func calendar(_ timeZone: TimeZone = moscow) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
}

/// "2026-11-18 20:00" в заданном поясе.
func date(_ string: String, _ timeZone: TimeZone = moscow) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.date(from: string)!
}

let now = date("2026-11-18 20:00")

func match(
    _ id: String,
    _ code: String = "PL",
    _ name: String = "АПЛ",
    at kickoff: String = "2026-11-18 22:00",
    status: MatchStatus = .scheduled,
    home: String? = "Ливерпуль",
    away: String? = "Арсенал",
    score: (Int, Int)? = nil,
    round: String? = "12 тур"
) -> Match {
    Match(
        id: MatchID(rawValue: id),
        sport: code == "NHL" ? .hockey : .football,
        competition: Competition(code: code, name: name, emblemURL: code == "NHL" ? nil : URL(string: "https://crests.test/\(code).png")),
        kickoff: date(kickoff),
        status: status,
        home: home.map { Team(name: $0, abbreviation: String($0.prefix(3)).uppercased(), logoURL: code == "NHL" ? nil : URL(string: "https://crests.test/\($0).png")) },
        away: away.map { Team(name: $0, abbreviation: String($0.prefix(3)).uppercased(), logoURL: code == "NHL" ? nil : URL(string: "https://crests.test/\($0).png")) },
        homeScore: score?.0,
        awayScore: score?.1,
        round: round,
        homeTeamID: nil,
        awayTeamID: nil
    )
}

struct FakeError: Error {}

/// Фейковый репозиторий: отдаёт заданный результат (или ответ по началу дня из `byDay`), запоминает интервалы,
/// по желанию ждёт `release(_:)` своего дня и, как настоящая сеть, не реагирует на отмену.
final class FakeMatchesRepository: MatchesRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _result: Result<[Match], FakeError>
    private var _intervals: [DateInterval] = []
    private let byDay: [Date: [Match]]?
    private let held: Bool
    private var gates: [Date: AsyncStream<Void>.Continuation] = [:]
    private var streams: [Date: AsyncStream<Void>] = [:]

    init(_ matches: [Match] = [], byDay: [Date: [Match]]? = nil, held: Bool = false) {
        _result = .success(matches)
        self.byDay = byDay
        self.held = held
    }

    var result: Result<[Match], FakeError> {
        get { lock.withLock { _result } }
        set { lock.withLock { _result = newValue } }
    }

    var intervals: [DateInterval] { lock.withLock { _intervals } }
    var calls: Int { intervals.count }

    /// Отпускает запрос дня `start` (по умолчанию — сегодняшнего); можно звать до самого запроса.
    func release(_ start: Date = date("2026-11-18 00:00")) { gate(start).continuation.yield() }

    func matches(in interval: DateInterval) async throws -> [Match] {
        lock.withLock { _intervals.append(interval) }
        if held {
            let stream = gate(interval.start).stream
            await Task.detached { for await _ in stream { break } }.value
        }
        if let byDay { return byDay[interval.start] ?? [] }
        return try result.get()
    }

    func match(id: MatchID) async throws -> Match? { try result.get().first { $0.id == id } }

    private func gate(_ start: Date) -> (stream: AsyncStream<Void>, continuation: AsyncStream<Void>.Continuation) {
        lock.withLock {
            if let stream = streams[start], let continuation = gates[start] { return (stream, continuation) }
            let (stream, continuation) = AsyncStream<Void>.makeStream()
            streams[start] = stream
            gates[start] = continuation
            return (stream, continuation)
        }
    }
}

@MainActor
final class FakeBookmarksStore: BookmarksStore {
    private let subject: CurrentValueSubject<Set<MatchID>, Never>

    init(_ ids: Set<String> = []) {
        subject = CurrentValueSubject(Set(ids.map(MatchID.init(rawValue:))))
    }

    var bookmarks: Set<MatchID> { subject.value }
    var bookmarksPublisher: AnyPublisher<Set<MatchID>, Never> { subject.eraseToAnyPublisher() }

    func toggle(_ id: MatchID) {
        if subject.value.contains(id) { subject.value.remove(id) } else { subject.value.insert(id) }
    }
}
