import CoreDomain
import Foundation
import Testing
@testable import FeaturePodcasts

/// Ворота (D31): «Подписаться», «Скачать» и сегменты без входа.
@MainActor
extension PodcastsViewModelTests {
    var signedOut: AccountState { .signedOut }

    @Test func subscribeGatedActionRunsAfterSignIn() async {
        let setup = make(subscriptions: [:], account: signedOut)
        await appear(setup.viewModel)

        setup.viewModel.didTapSubscribe("puck")
        #expect(setup.signIn.reasons == [.subscription])
        #expect(setup.subscriptions.subscriptions.isEmpty)

        setup.signIn.signIn()
        #expect(setup.subscriptions.subscriptions["puck"] != nil)
    }

    @Test func subscribeGatedActionDroppedOnCancel() async {
        let setup = make(subscriptions: [:], account: signedOut)
        await appear(setup.viewModel)

        setup.viewModel.didTapSubscribe("puck")
        setup.signIn.cancel()
        setup.signIn.signIn()
        #expect(setup.subscriptions.subscriptions.isEmpty)
    }

    /// Подписка пришла с сервера, пока входили, — «Подписаться» её не снимает.
    @Test func subscribeGateKeepsSubscriptionThatArrivedWithSignIn() async {
        let setup = make(subscriptions: [:], account: signedOut)
        await appear(setup.viewModel)

        setup.viewModel.didTapSubscribe("puck")
        setup.subscriptions.subject.send(["puck": testNow])
        setup.signIn.signIn()
        #expect(setup.subscriptions.subscriptions["puck"] != nil)
    }

    @Test func downloadGatedActionRunsAfterSignIn() async {
        let setup = make()
        await appear(setup.viewModel)
        setup.signIn.account.subject.send(.signedOut)

        setup.viewModel.didTapDownloadAction(preview.id)
        setup.viewModel.didTapDownloadAction(cup.id, shown: .download)
        #expect(setup.signIn.reasons == [.download, .download])
        #expect(setup.downloads.downloaded.isEmpty)

        setup.signIn.signIn()
        #expect(setup.downloads.downloaded == [cup.id])
    }

    @Test func downloadGatedActionDroppedOnCancel() async {
        let setup = make()
        await appear(setup.viewModel)
        setup.signIn.account.subject.send(.signedOut)

        setup.viewModel.didTapDownloadAction(preview.id)
        setup.signIn.cancel()
        setup.signIn.signIn()
        #expect(setup.downloads.downloaded.isEmpty)
    }

    @Test func segmentsShowSignInWhenSignedOut() async {
        let setup = make(subscriptions: [:], account: signedOut)
        await appear(setup.viewModel)

        setup.viewModel.didSelectSegment(.subscriptions)
        #expect(setup.viewModel.state.content == .signIn(title: "Войдите, чтобы подписываться"))
        setup.viewModel.didTapSignIn()
        #expect(setup.signIn.reasons == [.subscription])

        setup.viewModel.didSelectSegment(.downloads)
        #expect(setup.viewModel.state.content == .signIn(title: "Войдите, чтобы скачивать"))
        setup.viewModel.didTapSignIn()
        #expect(setup.signIn.reasons == [.subscription, .download])

        // Вход перерисовывает экран (подписка на `statePublisher`).
        setup.signIn.signIn()
        #expect(setup.viewModel.state.content == .downloads(.status(StatusMessage(message: "Скачанных выпусков нет", showsRetry: false))))
        setup.viewModel.didSelectSegment(.catalog)
        #expect(catalogRows(setup.viewModel).count == catalog.count)
    }

    @Test func defaultSegmentCatalogWhenSignedOut() async {
        #expect(make(account: signedOut).viewModel.state.segment == .catalog)

        // Запуск: сессия ещё читается — «Подборка»; вошёл и сегмент не трогали — «Подписки».
        let launch = make(account: .unknown)
        #expect(launch.viewModel.state.segment == .catalog)
        launch.signIn.account.subject.send(.signedIn(testUser))
        #expect(launch.viewModel.state.segment == .subscriptions)

        let chosen = make(account: .unknown)
        chosen.viewModel.didSelectSegment(.downloads)
        chosen.signIn.account.subject.send(.signedIn(testUser))
        #expect(chosen.viewModel.state.segment == .downloads)
    }
}

extension PodcastViewModelTests {
    @Test func podcastSubscribeGatedActionRunsAfterSignIn() async {
        let signIn = FakeSignIn(FakeAccount(.signedOut))
        let (viewModel, store, _) = make(subscribed: false, feed: feed, signIn: signIn)

        viewModel.didTapSubscribe()
        #expect(signIn.reasons == [.subscription])
        #expect(store.subscriptions.isEmpty)

        signIn.signIn()
        #expect(viewModel.state.header.isSubscribed)
    }

    @Test func podcastSubscribeGatedActionDroppedOnCancel() async {
        let signIn = FakeSignIn(FakeAccount(.signedOut))
        let (viewModel, store, _) = make(subscribed: false, feed: feed, signIn: signIn)

        viewModel.didTapSubscribe()
        signIn.cancel()
        signIn.signIn()
        #expect(store.subscriptions.isEmpty)
    }

    @Test func podcastDownloadGatedActionRunsAfterSignIn() async {
        let signIn = FakeSignIn(FakeAccount(.signedOut))
        let downloads = FakeDownloads()
        let (viewModel, _, _) = make(subscribed: false, feed: feed, downloads: downloads, signIn: signIn)
        viewModel.viewDidAppear()
        await viewModel.loadTask?.value

        viewModel.didTapDownloadAction(feed[0].id)
        #expect(signIn.reasons == [.download])
        #expect(downloads.downloaded.isEmpty)

        signIn.signIn()
        #expect(downloads.downloaded == [feed[0].id])
    }

    @Test func podcastDownloadGatedActionDroppedOnCancel() async {
        let signIn = FakeSignIn(FakeAccount(.signedOut))
        let downloads = FakeDownloads()
        let (viewModel, _, _) = make(subscribed: false, feed: feed, downloads: downloads, signIn: signIn)
        viewModel.viewDidAppear()
        await viewModel.loadTask?.value

        viewModel.didTapDownloadAction(feed[0].id, shown: .download)
        signIn.cancel()
        signIn.signIn()
        #expect(downloads.downloaded.isEmpty)
    }
}
