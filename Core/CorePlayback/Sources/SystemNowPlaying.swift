import MediaPlayer

/// Экран блокировки и Пункт управления: сведения о станции или выпуске, play/pause; у выпуска ещё −15/+30 и перемотка.
@MainActor
final class SystemNowPlaying: NowPlayingControlling {
    var onCommand: ((RemoteCommand) -> Void)?

    init() {
        let center = MPRemoteCommandCenter.shared()
        let commands: [(MPRemoteCommand, RemoteCommand)] = [
            (center.playCommand, .play), (center.pauseCommand, .pause), (center.togglePlayPauseCommand, .togglePlayPause),
        ]
        for (command, value) in commands {
            command.isEnabled = true
            command.addTarget { [weak self] _ in
                // Обработчики команд система вызывает на главном потоке.
                MainActor.assumeIsolated { self?.onCommand?(value) }
                return .success
            }
        }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.preferredIntervals = [30]
        center.skipBackwardCommand.addTarget { [weak self] event in
            let seconds = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            MainActor.assumeIsolated { self?.onCommand?(.skip(-seconds)) }
            return .success
        }
        center.skipForwardCommand.addTarget { [weak self] event in
            let seconds = (event as? MPSkipIntervalCommandEvent)?.interval ?? 30
            MainActor.assumeIsolated { self?.onCommand?(.skip(seconds)) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            MainActor.assumeIsolated { self?.onCommand?(.seek(to: position)) }
            return .success
        }
        // Переключения треков нет никогда, перемотка — только у выпуска (см. update).
        for command in [
            center.skipForwardCommand, center.skipBackwardCommand, center.seekForwardCommand, center.seekBackwardCommand,
            center.nextTrackCommand, center.previousTrackCommand, center.changePlaybackPositionCommand,
        ] {
            command.isEnabled = false
        }
    }

    func update(_ info: NowPlayingInfo?) {
        let center = MPRemoteCommandCenter.shared()
        let seekable = info?.isLive == false
        for command in [center.skipForwardCommand, center.skipBackwardCommand, center.changePlaybackPositionCommand] where command.isEnabled != seekable {
            command.isEnabled = seekable
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info?.dictionary
    }
}
