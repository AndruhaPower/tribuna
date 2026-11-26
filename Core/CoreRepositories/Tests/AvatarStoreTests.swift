import CoreDomain
import Foundation
import Testing
@testable import CoreRepositories

/// Фото профиля (D43): запросы к Storage, копия на диске, выход стирает фото.
@MainActor
struct AvatarStoreTests {
    let cache = FileManager.default.temporaryDirectory.appendingPathComponent("AvatarStoreTests-\(UUID().uuidString)")
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0x01])

    /// Сервер в памяти: файл по пути, журнал запросов; `offline` — нет сети.
    final class Server {
        var files: [String: Data] = [:]
        var log: [String] = []
        var offline = false

        func handle(_ request: URLRequest) throws -> (Data, URLResponse) {
            if offline { throw URLError(.notConnectedToInternet) }
            let path = request.url!.path.replacingOccurrences(of: "/storage/v1/object/", with: "")
                .replacingOccurrences(of: "authenticated/", with: "")
            log.append("\(request.httpMethod!) \(path) \(request.value(forHTTPHeaderField: "Authorization") ?? "-")")
            var code = 200
            var body = Data()
            switch request.httpMethod {
            case "POST": files[path] = request.httpBody
            case "DELETE": code = files.removeValue(forKey: path) == nil ? 400 : 200
            default: if let data = files[path] { body = data } else { code = 400 }
            }
            return (body, HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
        }
    }

    func make(_ account: FakeAccount, _ server: Server) -> SupabaseAvatarStore {
        SupabaseAvatarStore(account: account, storageURL: URL(string: "https://x.supabase.co/storage/v1")!, apiKey: "key",
                            cacheDirectory: cache, token: { "t" }, fetch: { try server.handle($0) })
    }

    @Test func uploadShowsPhotoAndKeepsItForNextLaunch() async throws {
        let server = Server()
        let account = FakeAccount(user("u1"))
        let store = make(account, server)
        try await store.upload(jpeg)
        #expect(store.image == jpeg)
        #expect(server.log.contains("POST avatars/u1.jpg Bearer t"))
        server.offline = true
        // Следующий запуск без сети — фото из копии на диске.
        #expect(make(FakeAccount(user("u1")), server).image == jpeg)
    }

    @Test func photoFromServerAfterSignIn() async throws {
        let server = Server()
        server.files["avatars/u1.jpg"] = jpeg
        let account = FakeAccount(.signedOut)
        let store = make(account, server)
        account.subject.send(user("u1"))
        while store.image == nil { await Task.yield() }
        #expect(store.image == jpeg)
    }

    @Test func removeAndSignOutClearPhoto() async throws {
        let server = Server()
        let account = FakeAccount(user("u1"))
        let store = make(account, server)
        try await store.upload(jpeg)
        try await store.remove()
        #expect(store.image == nil && server.files.isEmpty)
        try await store.remove() // фото уже нет — не ошибка

        try await store.upload(jpeg)
        await account.signOut()
        #expect(store.image == nil)
        #expect(!FileManager.default.fileExists(atPath: cache.path))
    }

    @Test func offlineUploadIsNetworkError() async {
        let server = Server()
        server.offline = true
        let store = make(FakeAccount(user("u1")), server)
        await #expect(throws: AccountError.network) { try await store.upload(jpeg) }
        #expect(store.image == nil)
    }
}
