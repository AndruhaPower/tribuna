#if FEATURE_PROFILE2
import Combine
import CoreDomain
import Foundation
import Testing
@testable import FeatureProfile

@MainActor
final class FakeProfileSettings: ProfileSettings {
    let subject = PassthroughSubject<Void, Never>()
    var remindBookmarks = false { didSet { subject.send() } }
    var notifyNewEpisodes = false { didSet { subject.send() } }
    var hiddenCompetitions: Set<String> = [] { didSet { subject.send() } }
    var changes: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }
}

struct FakeCompetitions: CompetitionsRepository {
    func competitions() async throws -> [Competition] { [Competition(code: "PL", name: "АПЛ")] }
}

extension FakeAccount: AccountRenaming {
    func updateName(_ name: String) async throws {
        calls.append("updateName \(name)")
        if let error = errors["updateName"] { throw error }
        if case let .signedIn(user) = state { subject.send(.signedIn(UserProfile(id: user.id, name: name, email: user.email))) }
    }
}

/// Профиль 1.2 (D41): уведомления, смена имени.
@MainActor
struct Profile2Tests {
    let base = ProfileTests()

    @Test func enablingAsksPermissionAndKeepsOffWhenDenied() async {
        let viewModel = base.makeViewModel()
        base.notificationsGranted.value = false
        #expect(await viewModel.didToggleRemindBookmarks(true) == false)
        #expect(!base.settings.remindBookmarks && !viewModel.state.remindBookmarks)

        base.notificationsGranted.value = true
        #expect(await viewModel.didToggleNewEpisodes(true))
        #expect(base.settings.notifyNewEpisodes && viewModel.state.notifyNewEpisodes)
    }

    @Test func disablingDoesNotAskPermission() async {
        base.settings.remindBookmarks = true
        let viewModel = base.makeViewModel()
        base.notificationsGranted.value = false
        #expect(await viewModel.didToggleRemindBookmarks(false))
        #expect(!base.settings.remindBookmarks)
    }

    @Test func settingsFromAnotherPhoneShowUp() {
        let viewModel = base.makeViewModel()
        base.settings.notifyNewEpisodes = true
        #expect(viewModel.state.notifyNewEpisodes)
    }

    @Test func renameTrimsAndShowsNewName() async {
        let viewModel = base.makeViewModel()
        #expect(await viewModel.didRename("  Пётр ") == nil)
        #expect(base.account.calls.contains("updateName Пётр"))
        #expect(viewModel.state.account?.name == "Пётр")
        #expect(await viewModel.didRename("   ") == nil)
        #expect(base.account.calls.filter { $0.hasPrefix("updateName") }.count == 1)
    }

    @Test func renameErrorIsShown() async {
        base.account.errors["updateName"] = .network
        let viewModel = base.makeViewModel()
        #expect(await viewModel.didRename("Пётр") != nil)
    }
}
#endif
