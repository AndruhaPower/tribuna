import Combine
import Foundation

/// Фото профиля (D43): JPEG вошедшего пользователя; nil — фото нет или вход не выполнен.
@MainActor public protocol AvatarStore: AnyObject {
    var image: Data? { get }
    var imagePublisher: AnyPublisher<Data?, Never> { get }
    /// Квадратный JPEG до 1 МБ. Ошибка — `AccountError`.
    func upload(_ jpeg: Data) async throws
    func remove() async throws
}
