import AVFoundation
import Combine

extension AudioSessionEvent {
    /// nil — уведомление плееру не интересно.
    init?(_ notification: Notification) {
        let info = notification.userInfo ?? [:]
        switch notification.name {
        case AVAudioSession.interruptionNotification:
            guard let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return nil }
            switch type {
            case .began:
                self = .interruptionBegan
            case .ended:
                let options = AVAudioSession.InterruptionOptions(rawValue: info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
                self = .interruptionEnded(shouldResume: options.contains(.shouldResume))
            @unknown default:
                return nil
            }
        case AVAudioSession.routeChangeNotification:
            guard let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return nil }
            self = .outputLost
        default:
            return nil
        }
    }
}

/// AVAudioSession с категорией `.playback`: звук идёт в фоне и при беззвучном режиме.
@MainActor
final class SystemAudioSession: AudioSessionControlling {
    var onEvent: ((AudioSessionEvent) -> Void)?
    private var cancellable: AnyCancellable?

    init(center: NotificationCenter = .default) {
        let session = AVAudioSession.sharedInstance()
        // Уведомления сессии приходят не на главном потоке.
        cancellable = center.publisher(for: AVAudioSession.interruptionNotification, object: session)
            .merge(with: center.publisher(for: AVAudioSession.routeChangeNotification, object: session))
            .compactMap(AudioSessionEvent.init)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                MainActor.assumeIsolated { self?.onEvent?(event) }
            }
    }

    func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }

    func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
