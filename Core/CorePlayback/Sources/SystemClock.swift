import Combine
import Foundation

@MainActor
final class SystemClock: PlaybackClock {
    var now: Date { Date() }

    func schedule(after seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> AnyCancellable {
        // Пока играет фоновое аудио, приложение не засыпает и задача срабатывает в фоне.
        let task = Task { @MainActor in
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            // Снятие могло прийти между концом сна и переходом на главный актор.
            guard !Task.isCancelled else { return }
            action()
        }
        // @Sendable: снятие может прийти из deinit не на главном потоке.
        return AnyCancellable { @Sendable in task.cancel() }
    }
}
