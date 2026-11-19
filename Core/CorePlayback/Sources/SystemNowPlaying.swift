import MediaPlayer

/// Экран блокировки и Пункт управления: сведения о станции и кнопки play/pause.
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
        // Эфир: перемотки и переключения треков нет.
        for command in [
            center.skipForwardCommand, center.skipBackwardCommand, center.seekForwardCommand, center.seekBackwardCommand,
            center.nextTrackCommand, center.previousTrackCommand, center.changePlaybackPositionCommand,
        ] {
            command.isEnabled = false
        }
    }

    func update(_ info: NowPlayingInfo?) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info?.dictionary
    }
}
