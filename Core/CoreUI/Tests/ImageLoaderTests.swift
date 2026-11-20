import Testing
import UIKit
@testable import CoreUI

/// Считает вызовы fetch; пауза даёт параллельным запросам успеть склеиться.
private actor Counter {
    private(set) var count = 0
    func hit() { count += 1 }
}

private func pngData() -> Data {
    UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { $0.fill(CGRect(x: 0, y: 0, width: 4, height: 4)) }
}

@MainActor
struct ImageLoaderTests {
    private let url = URL(string: "https://example.com/a.png")!

    @Test func memoryHitDoesNotRefetch() async {
        let counter = Counter()
        let loader = ImageLoader { _ in await counter.hit(); return pngData() }
        #expect(await loader.image(for: url) != nil)
        #expect(await loader.image(for: url) != nil)
        #expect(await counter.count == 1)
    }

    @Test func concurrentRequestsShareOneFetch() async {
        let counter = Counter()
        let loader = ImageLoader { _ in
            await counter.hit()
            try? await Task.sleep(for: .milliseconds(100))
            return pngData()
        }
        async let a = loader.image(for: url)
        async let b = loader.image(for: url)
        let (x, y) = await (a, b)
        #expect(x != nil && y != nil)
        #expect(await counter.count == 1)
    }

    private struct Rejected: Error {}

    @Test func networkErrorIsRetriedLater() async {
        let counter = Counter()
        let loader = ImageLoader { _ in await counter.hit(); throw URLError(.notConnectedToInternet) }
        #expect(await loader.image(for: url) == nil)
        #expect(await loader.image(for: url) == nil)
        #expect(await counter.count == 2)
    }

    @Test func definitiveFailureReturnsNilAndIsNotRetried() async {
        let counter = Counter()
        let loader = ImageLoader { _ in await counter.hit(); throw Rejected() }
        #expect(await loader.image(for: url) == nil)
        #expect(await loader.image(for: url) == nil)
        #expect(await counter.count == 1)
    }

    @Test func undecodableDataIsFailure() async {
        let counter = Counter()
        let loader = ImageLoader { _ in await counter.hit(); return Data("не картинка".utf8) }
        #expect(await loader.image(for: url) == nil)
        #expect(await loader.image(for: url) == nil)
        #expect(await counter.count == 1)
    }
}

@MainActor
struct TeamBadgeReuseTests {
    private let a = URL(string: "https://example.com/a.png")!
    private let b = URL(string: "https://example.com/b.png")!

    private func labelHidden(_ badge: TeamBadgeView) -> Bool {
        (badge.subviews.first { $0 is UILabel })?.isHidden ?? false
    }

    private func logo(_ badge: TeamBadgeView) -> RemoteImageView? { badge.subviews.compactMap { $0 as? RemoteImageView }.first }

    @Test func logoThenNilShowsAbbreviation() async throws {
        let loader = ImageLoader { _ in pngData() }
        let badge = TeamBadgeView(loader: loader)
        badge.configure(abbreviation: "ARS", logoURL: a)
        try await Task.sleep(for: .milliseconds(100))
        #expect(labelHidden(badge) && logo(badge)?.image != nil)
        badge.configure(abbreviation: "LIV", logoURL: nil)
        #expect(!labelHidden(badge) && logo(badge)?.image == nil)
    }

    @Test func lateResultForOldURLIsIgnored() async throws {
        let loader = ImageLoader { url in
            if url.lastPathComponent == "a.png" { try? await Task.sleep(for: .milliseconds(150)) }
            return pngData()
        }
        let view = RemoteImageView()
        view.setImage(url: a, loader: loader)
        view.setImage(url: nil, loader: loader)
        view.setImage(url: b, loader: loader)
        try await Task.sleep(for: .milliseconds(300))
        #expect(view.url == b && view.image != nil)
        view.setImage(url: nil, loader: loader)
        try await Task.sleep(for: .milliseconds(10))
        #expect(view.image == nil)
    }
}
