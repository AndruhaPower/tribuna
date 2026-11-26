#if FEATURE_PROFILE2
import CoreDomain
import Foundation
import Testing
@testable import CoreRepositories

@MainActor
struct ProfileSettingsTests {
    let suite = "ProfileSettingsTests"

    @Test func valuesGoToCloudAndComeFromCloud() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cloud = FakeCloud()
        cloud.values[ProfileSettingsStore.hiddenKey] = ["PL"]
        let settings = ProfileSettingsStore(defaults: defaults, cloud: cloud)
        #expect(settings.hiddenCompetitions == ["PL"])
        #expect(!settings.remindBookmarks && !settings.notifyNewEpisodes)

        var changes = 0
        let cancellable = settings.changes.sink { changes += 1 }
        settings.remindBookmarks = true
        settings.hiddenCompetitions = ["SA", "CL"]
        #expect(cloud.values[ProfileSettingsStore.remindKey] as? Bool == true)
        #expect(cloud.values[ProfileSettingsStore.hiddenKey] as? [String] == ["CL", "SA"])

        cloud.values[ProfileSettingsStore.episodesKey] = true
        settings.applyCloud()
        #expect(settings.notifyNewEpisodes)
        #expect(changes == 3)
        cancellable.cancel()
    }

    func episode(_ podcast: String, _ guid: String, at time: TimeInterval) -> Episode {
        Episode(id: EpisodeID(podcastID: podcast, guid: guid), podcastID: podcast, title: guid, publishedAt: Date(timeIntervalSince1970: time),
                duration: nil, audioURL: URL(string: "https://example.com/\(guid).mp3")!, artworkURL: nil, link: nil)
    }

    @Test func newEpisodesOnlyAfterFirstSighting() {
        let first = NewEpisodes.detect(newest: [episode("a", "1", at: 100)], lastSeen: [:])
        #expect(first.new.isEmpty)
        #expect(first.lastSeen == ["a": Date(timeIntervalSince1970: 100)])

        let second = NewEpisodes.detect(newest: [episode("a", "2", at: 200), episode("b", "1", at: 50)], lastSeen: first.lastSeen)
        #expect(second.new.map(\.id.rawValue) == [EpisodeID(podcastID: "a", guid: "2").rawValue])
        #expect(second.lastSeen == ["a": Date(timeIntervalSince1970: 200), "b": Date(timeIntervalSince1970: 50)])

        #expect(NewEpisodes.detect(newest: [episode("a", "2", at: 200)], lastSeen: second.lastSeen).new.isEmpty)
    }

    @Test func hiddenCompetitionsAreFilteredOut() async throws {
        struct Base: MatchesRepository {
            let all: [Match]
            func matches(in interval: DateInterval) async throws -> [Match] { all }
            func match(id: MatchID) async throws -> Match? { all.first { $0.id == id } }
        }
        func match(_ id: String, _ code: String) -> Match {
            Match(id: MatchID(rawValue: "football:\(id)"), sport: .football, competition: Competition(code: code, name: code),
                  kickoff: Date(), status: .scheduled, home: nil, away: nil, homeScore: nil, awayScore: nil, round: nil,
                  homeTeamID: nil, awayTeamID: nil)
        }
        let repository = HiddenCompetitionsMatches(base: Base(all: [match("1", "PL"), match("2", "SA")]), hidden: { ["PL"] })
        let interval = DateInterval(start: Date(), duration: 60)
        #expect(try await repository.matches(in: interval).map(\.competition.code) == ["SA"])
        #expect(try await repository.match(id: MatchID(rawValue: "football:1")) != nil)
    }
}
#endif
