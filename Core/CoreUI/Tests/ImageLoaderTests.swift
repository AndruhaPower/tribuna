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

    @Test func failureReturnsNilAndIsNotRetried() async {
        let counter = Counter()
        let loader = ImageLoader { _ in await counter.hit(); throw URLError(.notConnectedToInternet) }
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
