import CoreDomain
import Foundation
import Testing
@testable import CoreRepositories

private struct FakeError: Error, Equatable { let name: String }

private struct FakeRepository: MatchesRepository {
    let result: Result<[Match], FakeError>
    func matches(in interval: DateInterval) async throws -> [Match] { try result.get() }
    func match(id: MatchID) async throws -> Match? { nil }
}

private func match(_ sport: Sport, _ id: String) -> Match {
    Match(
        id: MatchID(sport: sport, sourceID: id), sport: sport, competition: Competition(code: "X", name: "X"),
        kickoff: Date(timeIntervalSince1970: 0), status: .scheduled, home: nil, away: nil,
        homeScore: nil, awayScore: nil, round: nil, homeTeamID: nil, awayTeamID: nil
    )
}

struct CombinedMatchesRepositoryTests {
    let day = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 86400)

    @Test func mergesBoth() async throws {
        let repo = CombinedMatchesRepository(
            football: FakeRepository(result: .success([match(.football, "1")])),
            hockey: FakeRepository(result: .success([match(.hockey, "2")]))
        )
        #expect(try await repo.matches(in: day).map(\.id.rawValue) == ["football:1", "hockey:2"])
    }

    @Test func hockeyFailsFootballStays() async throws {
        let repo = CombinedMatchesRepository(
            football: FakeRepository(result: .success([match(.football, "1")])),
            hockey: FakeRepository(result: .failure(FakeError(name: "nhl")))
        )
        #expect(try await repo.matches(in: day).map(\.id.rawValue) == ["football:1"])
    }

    @Test func footballFailsHockeyStays() async throws {
        let repo = CombinedMatchesRepository(
            football: FakeRepository(result: .failure(FakeError(name: "football"))),
            hockey: FakeRepository(result: .success([match(.hockey, "2")]))
        )
        #expect(try await repo.matches(in: day).map(\.id.rawValue) == ["hockey:2"])
    }

    @Test func bothFailThrowsFirst() async {
        let repo = CombinedMatchesRepository(
            football: FakeRepository(result: .failure(FakeError(name: "football"))),
            hockey: FakeRepository(result: .failure(FakeError(name: "nhl")))
        )
        await #expect(throws: FakeError(name: "football")) { try await repo.matches(in: day) }
    }

    @Test func emptyWithFailedSourceThrows() async {
        let repo = CombinedMatchesRepository(
            football: FakeRepository(result: .failure(FakeError(name: "football"))),
            hockey: FakeRepository(result: .success([]))
        )
        await #expect(throws: FakeError(name: "football")) { try await repo.matches(in: day) }
    }
}
