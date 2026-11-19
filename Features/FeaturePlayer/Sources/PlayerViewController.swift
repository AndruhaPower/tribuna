import Combine
import CoreUI
import SnapKit
import UIKit

/// Полноэкранный плеер радио по макету «Плеер» (подкастный, без перемотки, скорости, «Скачан», «Поделиться» и «…»).
/// Лист (large) с системным «язычком». Отступы — замер макета от верха и от карточки; карточка квадратная во всю ширину
/// без полей 24 pt, на низких экранах (iPhone SE) сначала сжимается промежуток до play, затем карточка.
final class PlayerViewController: UIViewController {
    /// 19 столбиков 8 pt, первые 9 — светлые (рисунок макета).
    private static let waveStyle = WaveView.Style(
        heights: [20, 60, 100, 40, 80, 30, 110, 50, 70, 30, 90, 50, 20, 80, 40, 100, 30, 60, 20],
        barWidth: 8, accentCount: 9, accent: Palette.textPrimary, rest: Palette.waveDim
    )

    private let viewModel: PlayerViewModel
    private let headerLabel = UILabel()
    private let captionLabel = UILabel()
    private let wave = WaveView(style: PlayerViewController.waveStyle)
    private let cardNameLabel = UILabel()
    private let nameLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let playButton = PlayButton(tint: Palette.onAccent, iconSize: 28)
    private let sleepButton = UIButton(type: .system)
    private let sleepLabel = UILabel()
    private var subscription: AnyCancellable?
    private var timer: Timer?

    init(viewModel: PlayerViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        sheetPresentationController?.detents = [.large()]
        sheetPresentationController?.prefersGrabberVisible = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        let safe = view.safeAreaLayoutGuide

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(named: "chevron-down", in: .module, compatibleWith: nil), for: .normal)
        closeButton.tintColor = Palette.textPrimary
        closeButton.backgroundColor = Palette.surface
        closeButton.layer.cornerRadius = 22
        closeButton.accessibilityLabel = "Закрыть плеер"
        closeButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        headerLabel.font = Typography.text(14, .semibold)
        headerLabel.textColor = Palette.textSecondary
        headerLabel.textAlignment = .center
        headerLabel.accessibilityTraits = .header

        let card = UIView()
        card.backgroundColor = Palette.surface
        card.layer.cornerRadius = 28
        let captionFont = Typography.text(13, .bold)
        captionLabel.font = captionFont
        captionLabel.textColor = Palette.textSecondary
        let cardNameFont = Typography.display(22)
        cardNameLabel.font = cardNameFont
        cardNameLabel.textColor = Palette.textPrimary
        cardNameLabel.numberOfLines = 2
        // Карточка — оформление: название и подпись VoiceOver прочтёт ниже.
        captionLabel.isAccessibilityElement = false
        cardNameLabel.isAccessibilityElement = false

        let nameFont = Typography.text(22, .bold)
        nameLabel.font = nameFont
        nameLabel.textColor = Palette.textPrimary
        let subtitleFont = Typography.text(15, .medium)
        subtitleLabel.font = subtitleFont
        subtitleLabel.numberOfLines = 2

        playButton.backgroundColor = Palette.accent
        playButton.layer.cornerRadius = 38
        playButton.addAction(UIAction { [weak self] _ in self?.viewModel.didTapPlayPause() }, for: .touchUpInside)
        sleepButton.setImage(UIImage(named: "moon", in: .module, compatibleWith: nil), for: .normal)
        sleepButton.layer.cornerRadius = 13
        sleepButton.layer.borderWidth = 1
        sleepButton.layer.borderColor = Palette.track.cgColor
        sleepButton.accessibilityLabel = "Таймер сна"
        sleepButton.addAction(UIAction { [weak self] _ in self?.showSleepTimerOptions() }, for: .touchUpInside)
        sleepLabel.font = Typography.text(14, .medium)
        sleepLabel.textColor = Palette.textSecondary
        sleepLabel.textAlignment = .center

        [closeButton, headerLabel, card, nameLabel, subtitleLabel, playButton, sleepButton, sleepLabel].forEach(view.addSubview)
        [captionLabel, wave, cardNameLabel].forEach(card.addSubview)
        closeButton.snp.makeConstraints {
            $0.top.equalTo(safe).offset(22)
            $0.leading.equalToSuperview().offset(24)
            $0.size.equalTo(44)
        }
        headerLabel.snp.makeConstraints {
            $0.centerY.equalTo(closeButton)
            $0.centerX.equalToSuperview()
            $0.leading.greaterThanOrEqualTo(closeButton.snp.trailing).offset(8)
        }
        card.snp.makeConstraints {
            $0.top.equalTo(safe).offset(94)
            $0.leading.trailing.equalToSuperview().inset(24)
            $0.height.lessThanOrEqualTo(card.snp.width)
            $0.height.equalTo(card.snp.width).priority(.high)
        }
        captionLabel.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(24)
            $0.firstBaseline.equalTo(card.snp.top).offset(36.5)
        }
        // Середина волны на 152.75 pt от верха карточки 342 pt — держим ту же долю на других ширинах.
        wave.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(24)
            $0.centerY.equalToSuperview().multipliedBy(152.75 / 171)
            $0.height.equalTo(Self.waveStyle.height)
        }
        cardNameLabel.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(24)
            $0.lastBaseline.equalTo(card.snp.bottom).offset(-29.5)
        }
        nameLabel.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(24)
            $0.firstBaseline.equalTo(card.snp.bottom).offset(47.5)
        }
        subtitleLabel.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(24)
            $0.firstBaseline.equalTo(card.snp.bottom).offset(70)
        }
        playButton.snp.makeConstraints {
            $0.size.equalTo(76)
            $0.centerX.equalToSuperview()
            $0.centerY.equalTo(card.snp.bottom).offset(184).priority(700)
            $0.top.greaterThanOrEqualTo(subtitleLabel.snp.lastBaseline).offset(24)
        }
        sleepButton.snp.makeConstraints {
            $0.width.equalTo(56)
            $0.height.equalTo(44)
            $0.trailing.equalToSuperview().inset(24)
            $0.centerY.equalTo(playButton)
        }
        // Место под «Сон через N мин» есть всегда — play не прыгает, когда таймер включают.
        sleepLabel.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(24)
            $0.top.equalTo(playButton.snp.bottom).offset(20)
            $0.height.equalTo(18)
            $0.bottom.lessThanOrEqualTo(safe).offset(-16)
        }

        subscription = viewModel.$state.sink { [weak self] in self?.render($0) }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.refresh()
        // «Сон через N мин» обновляется чаще раза в минуту.
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.viewModel.refresh() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timer?.invalidate()
        timer = nil
    }

    override func accessibilityPerformEscape() -> Bool {
        dismiss(animated: true)
        return true
    }

    private func render(_ state: PlayerState?) {
        // Плеер закрыли (`stop()`) — закрываем и экран.
        guard let state else {
            if !isBeingDismissed { presentingViewController?.dismiss(animated: true) }
            return
        }
        headerLabel.text = state.header
        captionLabel.attributedText = NSAttributedString(string: state.caption, attributes: [.kern: 0.6])
        cardNameLabel.text = state.name
        nameLabel.text = state.name
        subtitleLabel.text = state.subtitle
        subtitleLabel.textColor = state.isError ? Palette.destructive : Palette.textSecondary
        playButton.configure(state.button, label: state.actionLabel)
        wave.isAnimating = state.isAnimating
        sleepLabel.text = state.sleepTimer
        sleepButton.tintColor = state.sleepTimer == nil ? Palette.textPrimary : Palette.accent
        sleepButton.accessibilityValue = state.sleepTimer ?? "выключен"
    }

    private func showSleepTimerOptions() {
        let sheet = UIAlertController(title: "Таймер сна", message: nil, preferredStyle: .actionSheet)
        for minutes in [15, 30, 60] {
            sheet.addAction(UIAlertAction(title: "\(minutes) минут", style: .default) { [weak self] _ in
                self?.viewModel.didSelectSleepTimer(minutes: minutes)
            })
        }
        if viewModel.state?.sleepTimer != nil {
            sheet.addAction(UIAlertAction(title: "Выключить таймер", style: .destructive) { [weak self] _ in
                self?.viewModel.didSelectSleepTimer(minutes: nil)
            })
        }
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        sheet.popoverPresentationController?.sourceView = sleepButton
        present(sheet, animated: true)
    }
}
