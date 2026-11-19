import Combine
import CoreUI
import SnapKit
import UIKit

/// Мини-плеер над таб-баром (макеты «Сегодня», «Подкасты»): карточка 60 pt, значок, станция, статус, play/pause.
/// Показ и скрытие (и отступы вкладок) делает контейнер по `onVisibilityChange`; нажатие на карточку — `onOpen`.
/// Отступы — замер макета от края карточки.
public final class MiniPlayerView: UIView {
    public static let height: CGFloat = 60

    /// Есть ли что показать (`item != nil`).
    public private(set) var isVisible = false
    /// Зовётся сразу при установке и при каждой смене видимости.
    public var onVisibilityChange: ((Bool) -> Void)? {
        didSet { onVisibilityChange?(isVisible) }
    }

    private let viewModel: PlayerViewModel
    private let openArea = UIControl()
    private let nameLabel = UILabel()
    private let statusLabel = UILabel()
    /// Точка 4.5 pt перед «В эфире».
    private let liveDot = UIView()
    private var statusLeading: Constraint?
    private let button = PlayButton(tint: Palette.textPrimary, iconSize: 19)
    private var subscription: AnyCancellable?

    init(viewModel: PlayerViewModel, onOpen: @escaping () -> Void) {
        self.viewModel = viewModel
        super.init(frame: .zero)
        backgroundColor = Palette.surfaceRaised
        layer.cornerRadius = 16
        layer.borderWidth = 1
        layer.borderColor = Palette.track.cgColor

        let iconBox = UIView()
        iconBox.backgroundColor = Palette.surfaceHigh
        iconBox.layer.cornerRadius = 10
        iconBox.isUserInteractionEnabled = false
        let icon = UIImageView(image: Icon.image("audio-lines"))
        icon.tintColor = Palette.textPrimary
        icon.contentMode = .scaleAspectFit
        let nameFont = Typography.text(15, .semibold)
        nameLabel.font = nameFont
        nameLabel.textColor = Palette.textPrimary
        let statusFont = Typography.text(13, .medium)
        statusLabel.font = statusFont
        liveDot.backgroundColor = Palette.accent
        liveDot.layer.cornerRadius = 2.25
        liveDot.isUserInteractionEnabled = false
        openArea.addAction(UIAction { _ in onOpen() }, for: .touchUpInside)
        button.addAction(UIAction { [weak self] _ in self?.viewModel.didTapPlayPause() }, for: .touchUpInside)

        [openArea, iconBox, nameLabel, liveDot, statusLabel, button].forEach(addSubview)
        iconBox.addSubview(icon)
        snp.makeConstraints { $0.height.equalTo(Self.height) }
        openArea.snp.makeConstraints { $0.edges.equalToSuperview() }
        iconBox.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(11)
            $0.centerY.equalToSuperview()
            $0.size.equalTo(40)
        }
        // Значок макета — audio-lines в масштабе 0.875 (шаг линий 3.5 pt).
        icon.snp.makeConstraints {
            $0.center.equalToSuperview()
            $0.size.equalTo(17.5)
        }
        button.snp.makeConstraints {
            $0.size.equalTo(44)
            $0.centerY.equalToSuperview()
            $0.trailing.equalToSuperview().inset(9)
        }
        nameLabel.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(63.5)
            $0.trailing.lessThanOrEqualTo(button.snp.leading).offset(-8)
            $0.firstBaseline.equalTo(snp.top).offset(27)
        }
        liveDot.snp.makeConstraints {
            $0.size.equalTo(4.5)
            $0.leading.equalToSuperview().offset(64)
            $0.centerY.equalTo(statusLabel.snp.firstBaseline).offset(-3.75)
        }
        statusLabel.snp.makeConstraints {
            statusLeading = $0.leading.equalToSuperview().offset(64).constraint
            $0.trailing.lessThanOrEqualTo(button.snp.leading).offset(-8)
            $0.firstBaseline.equalTo(snp.top).offset(44)
        }
        // VoiceOver: карточка — «открыть плеер», play/pause — отдельный элемент.
        openArea.isAccessibilityElement = true
        openArea.accessibilityTraits = .button
        openArea.accessibilityHint = "Открыть плеер"
        accessibilityElements = [openArea, button]

        subscription = viewModel.$state.sink { [weak self] in self?.render($0) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    private func render(_ state: PlayerState?) {
        if let state {
            nameLabel.text = state.name
            statusLabel.text = state.status
            statusLabel.textColor = switch state.statusTone {
            case .live: Palette.accent
            case .secondary: Palette.textSecondary
            case .error: Palette.destructive
            }
            liveDot.isHidden = state.statusTone != .live
            statusLeading?.update(offset: liveDot.isHidden ? 64 : 74.5)
            button.configure(state.button, label: state.actionLabel)
            openArea.accessibilityLabel = state.summaryLabel
        }
        // Пока скрывается, остаётся последнее содержимое — анимации не на что мигать.
        let visible = state != nil
        guard visible != isVisible else { return }
        isVisible = visible
        onVisibilityChange?(visible)
    }
}
