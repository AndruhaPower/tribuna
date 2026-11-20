import Combine
import CoreUI
import SnapKit
import UIKit

/// Плеер (лист) по макету «Плеер». У выпуска — ползунок, время, скорость, −15/+30, «Скачать» и «Поделиться» («…» — позже);
/// у радио их нет. Лист (large) с системным «язычком». Отступы — замер макета от верха и от карточки; карточка квадратная
/// во всю ширину без полей 24 pt, на низких экранах (iPhone SE) сначала сжимаются промежутки до play, затем карточка.
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
    // Выпуск.
    private let slider = ProgressSlider()
    private let elapsedLabel = UILabel()
    private let remainingLabel = UILabel()
    private let speedButton = UIButton(type: .system)
    private lazy var skipBackButton = skipButton(seconds: -15, icon: "skip-back", label: "Назад на 15 секунд")
    private lazy var skipForwardButton = skipButton(seconds: 30, icon: "skip-forward", label: "Вперёд на 30 секунд")
    private let shareButton = UIButton(type: .system)
    private let downloadButton = UIButton(type: .system)
    private var shownDownload: PlayerState.Download?

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

        // Вариант экрана выбирается при открытии: пока лист открыт, сменить эфир на выпуск нельзя.
        if viewModel.state?.progress != nil { setUpEpisodeControls(card: card) }

        subscription = viewModel.$state.sink { [weak self] in self?.render($0) }
    }

    /// Ниже карточки у выпуска: ползунок, время, скорость, −15 / play / +30 / сон, «Поделиться» (замер макета от низа карточки).
    private func setUpEpisodeControls(card: UIView) {
        let safe = view.safeAreaLayoutGuide
        slider.addAction(UIAction { [weak self] _ in
            // Слайдер iOS 26 шлёт последний `valueChanged` уже после отпускания — он не должен снова «взять» бегунок.
            guard let self, slider.isTracking else { return }
            viewModel.scrub(to: slider.value)
        }, for: .valueChanged)
        slider.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            viewModel.endScrubbing(at: slider.value)
        }, for: [.touchUpInside, .touchUpOutside])
        slider.addAction(UIAction { [weak self] _ in self?.viewModel.cancelScrubbing() }, for: .touchCancel)
        slider.onAccessibilityAdjust = { [weak self] in self?.viewModel.didAdjustAccessibility(forward: $0) }
        slider.accessibilityLabel = "Позиция"
        for label in [elapsedLabel, remainingLabel] {
            label.font = Typography.digits(13, .medium)
            label.textColor = Palette.textSecondary
            // Время прочтёт ползунок.
            label.isAccessibilityElement = false
        }
        speedButton.titleLabel?.font = Typography.text(13, .bold)
        speedButton.setTitleColor(Palette.textPrimary, for: .normal)
        speedButton.layer.cornerRadius = 13
        speedButton.layer.borderWidth = 1
        speedButton.layer.borderColor = Palette.track.cgColor
        speedButton.addAction(UIAction { [weak self] _ in self?.viewModel.didTapSpeed() }, for: .touchUpInside)

        var share = UIButton.Configuration.plain()
        share.attributedTitle = AttributedString("Поделиться", attributes: AttributeContainer([.font: Typography.text(16, .semibold)]))
        share.image = UIImage(named: "share", in: .module, compatibleWith: nil)
        share.imagePadding = 11.5
        share.baseForegroundColor = Palette.textPrimary
        share.background.backgroundColor = Palette.surface
        share.background.cornerRadius = 14
        share.background.strokeColor = Palette.track
        share.background.strokeWidth = 1
        shareButton.configuration = share
        shareButton.addAction(UIAction { [weak self] _ in self?.share() }, for: .touchUpInside)
        downloadButton.addAction(UIAction { [weak self] _ in self?.didTapDownload() }, for: .touchUpInside)

        [slider, elapsedLabel, remainingLabel, speedButton, skipBackButton, skipForwardButton, downloadButton, shareButton].forEach(view.addSubview)
        slider.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(24)
            $0.height.equalTo(44)
            $0.centerY.equalTo(card.snp.bottom).offset(101)
        }
        elapsedLabel.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(24)
            $0.firstBaseline.equalTo(card.snp.bottom).offset(123.5)
        }
        remainingLabel.snp.makeConstraints {
            $0.trailing.equalToSuperview().inset(24)
            $0.firstBaseline.equalTo(elapsedLabel)
        }
        playButton.snp.makeConstraints { $0.top.greaterThanOrEqualTo(elapsedLabel.snp.lastBaseline).offset(16) }
        speedButton.snp.makeConstraints {
            $0.width.equalTo(56)
            $0.height.equalTo(44)
            $0.leading.equalToSuperview().offset(24)
            $0.centerY.equalTo(playButton)
        }
        for (button, offset) in [(skipBackButton, -76.5), (skipForwardButton, 76.5)] {
            button.snp.makeConstraints {
                $0.size.equalTo(44)
                $0.centerY.equalTo(playButton)
                $0.centerX.equalTo(playButton).offset(offset)
            }
        }
        // «Скачать» и «Поделиться» делят ширину, промежуток 10 pt (макет).
        downloadButton.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(24)
            $0.top.bottom.equalTo(shareButton)
        }
        shareButton.snp.makeConstraints {
            $0.leading.equalTo(downloadButton.snp.trailing).offset(10)
            $0.width.equalTo(downloadButton)
            $0.trailing.equalToSuperview().inset(24)
            $0.height.equalTo(48)
            $0.top.equalTo(card.snp.bottom).offset(273.5).priority(700)
            $0.top.greaterThanOrEqualTo(sleepLabel.snp.bottom).offset(8)
            $0.bottom.lessThanOrEqualTo(safe).offset(-16)
        }
    }

    /// Круглая стрелка в стиле Lucide с числом секунд внутри (макет).
    private func skipButton(seconds: TimeInterval, icon: String, label: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: icon, in: .module, compatibleWith: nil), for: .normal)
        button.tintColor = Palette.textPrimary
        button.accessibilityLabel = label
        button.addAction(UIAction { [weak self] _ in self?.viewModel.didTapSkip(by: seconds) }, for: .touchUpInside)
        let number = UILabel()
        number.text = "\(Int(abs(seconds)))"
        number.font = Typography.text(10, .bold)
        number.textColor = Palette.textPrimary
        number.isUserInteractionEnabled = false
        button.addSubview(number)
        // Центр круга значка на 2 pt ниже центра кнопки (стрелка сверху).
        number.snp.makeConstraints {
            $0.centerX.equalToSuperview()
            $0.centerY.equalToSuperview().offset(2)
        }
        return button
    }

    private func didTapDownload() {
        guard viewModel.state?.progress?.download == .downloaded else { return viewModel.didTapDownload() }
        let sheet = UIAlertController(title: "Удалить загрузку?", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Удалить", style: .destructive) { [weak self] _ in self?.viewModel.didConfirmRemoveDownload() })
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        sheet.popoverPresentationController?.sourceView = downloadButton
        present(sheet, animated: true)
    }

    /// Контурная кнопка как «Поделиться»: «Скачать» со стрелкой, «45 %», «Скачан» с галочкой.
    private func renderDownload(_ download: PlayerState.Download) {
        // Прогресс приходит дважды в секунду — кнопку пересобираем, только когда текст сменился.
        guard download != shownDownload else { return }
        shownDownload = download
        var config = shareButton.configuration ?? .plain()
        // Цифры одной ширины — «45 %» не дрожит.
        config.attributedTitle = AttributedString(download.title, attributes: AttributeContainer([.font: Typography.digits(16, .semibold)]))
        switch download {
        case .download: config.image = UIImage(named: "download", in: .module, compatibleWith: nil)
        case .progress: config.image = nil
        case .downloaded: config.image = UIImage(named: "check", in: .module, compatibleWith: nil)
        }
        config.imagePadding = 9.5
        UIView.performWithoutAnimation {
            downloadButton.configuration = config
            downloadButton.layoutIfNeeded()
        }
        // Идущую загрузку из плеера не трогаем — отменить можно в списке выпусков.
        let isLoading = if case .progress = download { true } else { false }
        downloadButton.isUserInteractionEnabled = !isLoading
        downloadButton.accessibilityLabel = download.accessibilityLabel
        downloadButton.accessibilityHint = download == .downloaded ? "Удалить загрузку" : nil
        downloadButton.accessibilityTraits = isLoading ? [.staticText, .updatesFrequently] : .button
    }

    private func share() {
        let activity = UIActivityViewController(activityItems: viewModel.shareItems(), applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = shareButton
        present(activity, animated: true)
    }

    /// Сжатая карточка (iPhone SE) и название в две строки: волна сжимается по высоте между подписью и названием.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let room = min(wave.center.y - captionLabel.frame.maxY, cardNameLabel.frame.minY - wave.center.y) - 12
        let scale = max(0, min(1, 2 * room / Self.waveStyle.height))
        wave.transform = CGAffineTransform(scaleX: 1, y: scale)
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
        subtitleLabel.numberOfLines = state.progress == nil ? 2 : 1
        renderProgress(state.progress)
    }

    private func renderProgress(_ progress: PlayerState.Progress?) {
        let views: [UIView] = [slider, elapsedLabel, remainingLabel, speedButton, skipBackButton, skipForwardButton, downloadButton, shareButton]
        views.forEach { $0.isHidden = progress == nil }
        guard let progress else { return }
        // Пока палец на ползунке, модель отдаёт значение под пальцем — бегунок не дёргается.
        if !slider.isTracking { slider.value = progress.fraction ?? 0 }
        slider.isEnabled = progress.fraction != nil
        slider.spokenValue = progress.accessibilityValue
        elapsedLabel.text = progress.elapsed
        remainingLabel.text = progress.remaining
        UIView.performWithoutAnimation {
            speedButton.setTitle(progress.speed, for: .normal)
            speedButton.layoutIfNeeded()
        }
        speedButton.accessibilityLabel = progress.speedLabel
        renderDownload(progress.download)
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

/// Ползунок позиции выпуска: дорожка 6 pt, бегунок 16 pt (макет); VoiceOver — ±15 с и «18 минут 42 секунды из 34 минут».
private final class ProgressSlider: UISlider {
    var onAccessibilityAdjust: ((Bool) -> Void)?
    var spokenValue: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        minimumTrackTintColor = Palette.accent
        maximumTrackTintColor = Palette.track
        let thumb = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { _ in
            Palette.accent.setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 16, height: 16)).fill()
        }
        setThumbImage(thumb, for: .normal)
        setThumbImage(thumb, for: .highlighted)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    override func trackRect(forBounds bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX, y: bounds.midY - 3, width: bounds.width, height: 6)
    }

    override var accessibilityValue: String? {
        get { spokenValue }
        set { spokenValue = newValue }
    }

    override func accessibilityIncrement() { onAccessibilityAdjust?(true) }
    override func accessibilityDecrement() { onAccessibilityAdjust?(false) }
}
