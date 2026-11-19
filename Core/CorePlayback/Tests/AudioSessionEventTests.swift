import AVFoundation
import Testing
@testable import CorePlayback

struct AudioSessionEventTests {
    private func interruption(_ type: AVAudioSession.InterruptionType, options: AVAudioSession.InterruptionOptions = []) -> Notification {
        Notification(name: AVAudioSession.interruptionNotification, object: nil, userInfo: [
            AVAudioSessionInterruptionTypeKey: type.rawValue,
            AVAudioSessionInterruptionOptionKey: options.rawValue,
        ])
    }

    private func routeChange(_ reason: AVAudioSession.RouteChangeReason) -> Notification {
        Notification(name: AVAudioSession.routeChangeNotification, object: nil, userInfo: [AVAudioSessionRouteChangeReasonKey: reason.rawValue])
    }

    @Test func parsesInterruptions() {
        #expect(AudioSessionEvent(interruption(.began)) == .interruptionBegan)
        #expect(AudioSessionEvent(interruption(.ended, options: .shouldResume)) == .interruptionEnded(shouldResume: true))
        #expect(AudioSessionEvent(interruption(.ended)) == .interruptionEnded(shouldResume: false))
    }

    @Test func parsesRouteChange() {
        #expect(AudioSessionEvent(routeChange(.oldDeviceUnavailable)) == .outputLost)
        #expect(AudioSessionEvent(routeChange(.newDeviceAvailable)) == nil)
    }
}
