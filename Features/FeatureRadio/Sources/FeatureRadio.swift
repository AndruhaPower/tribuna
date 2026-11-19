import CoreDomain
import CoreUI
import UIKit

public enum FeatureRadio {
    public struct Dependencies {
        let stations: StationsRepository
        let player: AudioPlayer

        public init(stations: StationsRepository, player: AudioPlayer) {
            self.stations = stations
            self.player = player
        }
    }

    public struct Output {
        let openPlayer: () -> Void

        public init(openPlayer: @escaping () -> Void) {
            self.openPlayer = openPlayer
        }
    }

    @MainActor public static func make(dependencies: Dependencies, output: Output) -> UIViewController {
        RadioViewController(viewModel: RadioViewModel(
            stations: dependencies.stations,
            player: dependencies.player,
            onOpenPlayer: output.openPlayer
        ))
    }
}
