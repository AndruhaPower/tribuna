import Combine
import CoreDomain
import Foundation
import Testing
import UIKit
@testable import FeatureProfile

@MainActor
final class FakeAvatarStore: AvatarStore {
    let subject = CurrentValueSubject<Data?, Never>(nil)
    var error: AccountError?
    var image: Data? { subject.value }
    var imagePublisher: AnyPublisher<Data?, Never> { subject.eraseToAnyPublisher() }
    func upload(_ jpeg: Data) async throws {
        if let error { throw error }
        subject.value = jpeg
    }
    func remove() async throws {
        if let error { throw error }
        subject.value = nil
    }
}

/// Фото профиля (D43).
@MainActor
struct ProfilePhotoTests {
    let base = ProfileTests()

    @Test func pickedPhotoShowsInCardAndCanBeRemoved() async {
        let viewModel = base.makeViewModel()
        #expect(viewModel.state.avatar == nil)
        #expect(await viewModel.didPickPhoto(Data([1, 2, 3])) == nil)
        #expect(viewModel.state.avatar == Data([1, 2, 3]))
        #expect(await viewModel.didRemovePhoto() == nil)
        #expect(viewModel.state.avatar == nil)
    }

    @Test func uploadErrorIsShownAndPhotoStays() async {
        let viewModel = base.makeViewModel()
        _ = await viewModel.didPickPhoto(Data([1]))
        base.avatars.error = .network
        #expect(await viewModel.didPickPhoto(Data([2])) != nil)
        #expect(viewModel.state.avatar == Data([1]))
        #expect(!viewModel.state.isBusy)
    }

    @Test func avatarIsSquareJPEGFromTheMiddle() throws {
        let wide = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        }
        let data = try #require(AvatarImage.jpeg(from: wide))
        let image = try #require(UIImage(data: data))
        #expect(image.size == CGSize(width: 512, height: 512))
        #expect(data.starts(with: [0xFF, 0xD8]))
    }
}
