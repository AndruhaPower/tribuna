import Combine
import CoreDomain
import Foundation

/// Фото профиля в Supabase Storage (D43): приватное хранилище `avatars`, файл `<user id>.jpg`, RLS — только своё.
/// Копия на диске (`Caches/avatars`) — фото сразу при запуске и без сети; с сервера — при входе и после запуска.
@MainActor
final class SupabaseAvatarStore: AvatarStore {
    private let subject = CurrentValueSubject<Data?, Never>(nil)
    private let objectsURL: URL
    private let apiKey: String
    private let token: @MainActor () async throws -> String
    private let fetch: @MainActor (URLRequest) async throws -> (Data, URLResponse)
    private let cacheDirectory: URL
    private var userID: String?
    /// Растёт с каждой загрузкой и удалением: ответ сервера, начатый раньше, их не перезаписывает.
    private var changes = 0
    private var subscription: AnyCancellable?

    /// `storageURL` — `<проект>/storage/v1`.
    init(account: Account, storageURL: URL, apiKey: String, cacheDirectory: URL,
         token: @escaping @MainActor () async throws -> String,
         fetch: @escaping @MainActor (URLRequest) async throws -> (Data, URLResponse)) {
        objectsURL = storageURL.appendingPathComponent("object")
        self.apiKey = apiKey
        self.cacheDirectory = cacheDirectory
        self.token = token
        self.fetch = fetch
        subscription = account.statePublisher.sink { [weak self] in self?.apply($0) }
    }

    var image: Data? { subject.value }
    var imagePublisher: AnyPublisher<Data?, Never> { subject.removeDuplicates().eraseToAnyPublisher() }

    func upload(_ jpeg: Data) async throws {
        guard let userID else { throw AccountError.unknown }
        var request = try await request("avatars/\(userID).jpg", method: "POST")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.httpBody = jpeg
        guard try await status(of: request) == 200 else { throw AccountError.unknown }
        changes += 1
        save(jpeg, for: userID)
    }

    func remove() async throws {
        guard let userID else { return }
        let code = try await status(of: try await request("avatars/\(userID).jpg", method: "DELETE"))
        // Фото уже нет — то же, что удалили.
        guard code == 200 || Self.isMissing(code) else { throw AccountError.unknown }
        changes += 1
        save(nil, for: userID)
    }

    private func apply(_ state: AccountState) {
        switch state {
        case .unknown:
            break
        case .signedOut:
            // Чужое фото не остаётся на телефоне после выхода.
            userID = nil
            subject.value = nil
            try? FileManager.default.removeItem(at: cacheDirectory)
        case let .signedIn(user) where user.id != userID:
            userID = user.id
            subject.value = try? Data(contentsOf: cacheFile(user.id))
            Task { await refresh(user.id) }
        case .signedIn:
            break
        }
    }

    /// Сбой сети — остаётся копия; «нет фото» на сервере — копию стираем.
    private func refresh(_ id: String) async {
        let started = changes
        guard let request = try? await request("authenticated/avatars/\(id).jpg", method: "GET"),
              let (data, response) = try? await fetch(request), let code = (response as? HTTPURLResponse)?.statusCode,
              id == userID, changes == started
        else { return }
        if code == 200 { save(data, for: id) } else if Self.isMissing(code) { save(nil, for: id) }
    }

    private func save(_ jpeg: Data?, for id: String) {
        let file = cacheFile(id)
        if let jpeg {
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try? jpeg.write(to: file, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: file)
        }
        if id == userID { subject.value = jpeg }
    }

    private func request(_ path: String, method: String) async throws -> URLRequest {
        var request = URLRequest(url: objectsURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        return request
    }

    private func status(of request: URLRequest) async throws -> Int {
        do {
            return (try await fetch(request).1 as? HTTPURLResponse)?.statusCode ?? 0
        } catch is URLError {
            throw AccountError.network
        }
    }

    /// Storage отвечает на отсутствующий файл 400 с `"statusCode":"404"` в теле или 404.
    private static func isMissing(_ code: Int) -> Bool { code == 400 || code == 404 }

    private func cacheFile(_ id: String) -> URL {
        cacheDirectory.appendingPathComponent((id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id) + ".jpg")
    }
}
