#if FEATURE_PROFILE2
import CoreDomain
import CoreUI
import SnapKit
import UIKit

/// Строка с переключателем и подписью под названием — «Уведомления» по макету «Профиль» (1.2, D41).
final class SwitchRow: UIView {
    let toggle = UISwitch()

    init(title: String, subtitle: String) {
        super.init(frame: .zero)
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = Typography.text(16, .medium)
        titleLabel.textColor = Palette.textPrimary
        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = Typography.text(14)
        subtitleLabel.textColor = Palette.textSecondary
        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        labels.axis = .vertical
        labels.spacing = 2
        labels.isAccessibilityElement = false
        toggle.onTintColor = Palette.switchOn
        toggle.thumbTintColor = Palette.background
        toggle.accessibilityLabel = title
        toggle.accessibilityHint = subtitle
        [labels, toggle].forEach(addSubview)
        labels.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(16)
            $0.trailing.lessThanOrEqualTo(toggle.snp.leading).offset(-12)
            $0.centerY.equalToSuperview()
        }
        toggle.snp.makeConstraints {
            $0.trailing.equalToSuperview().inset(16)
            $0.centerY.equalToSuperview()
        }
        snp.makeConstraints { $0.height.equalTo(64) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }
}

/// Карточка из строк с разделителями — как «Загрузки».
@MainActor func cardStack(_ rows: [UIView]) -> UIView {
    let card = UIView()
    card.backgroundColor = Palette.surface
    card.layer.cornerRadius = 18
    var views: [UIView] = []
    for (index, row) in rows.enumerated() {
        if index > 0 {
            let separator = UIView()
            separator.backgroundColor = Palette.separator
            separator.snp.makeConstraints { $0.height.equalTo(1) }
            views.append(separator)
        }
        views.append(row)
    }
    let stack = UIStackView(arrangedSubviews: views)
    stack.axis = .vertical
    card.addSubview(stack)
    stack.snp.makeConstraints { $0.edges.equalToSuperview() }
    return card
}

/// Подвал по макету: «Турниры в ленте · О приложении и источниках данных».
@MainActor func profileFooter(openCompetitions: @escaping () -> Void, openAbout: @escaping () -> Void) -> UIView {
    func link(_ title: String, _ action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(Palette.textSecondary, for: .normal)
        button.titleLabel?.font = Typography.text(14, .medium)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }
    let dot = UILabel()
    dot.text = "·"
    dot.textColor = Palette.textSecondary
    dot.isAccessibilityElement = false
    let stack = UIStackView(arrangedSubviews: [
        link("Турниры в ленте", openCompetitions), dot, link("О приложении и источниках данных", openAbout),
    ])
    stack.spacing = 6
    stack.alignment = .center
    return stack
}

/// Экраны поверх Профиля — со стандартной навигацией (у Профиля она скрыта).
class ProfileSubscreen: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.navigationBar.tintColor = Palette.textPrimary
        navigationController?.navigationBar.titleTextAttributes = [.foregroundColor: Palette.textPrimary]
    }
}

/// «Турниры в ленте»: выключенный турнир не показывается на «Сегодня». Работает без входа (D41).
final class CompetitionsViewController: ProfileSubscreen, UITableViewDataSource {
    private let settings: ProfileSettings
    private let repository: CompetitionsRepository
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let status = UILabel()
    private var competitions: [Competition] = []

    init(settings: ProfileSettings, repository: CompetitionsRepository) {
        self.settings = settings
        self.repository = repository
        super.init(nibName: nil, bundle: nil)
        title = "Турниры в ленте"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    override func viewDidLoad() {
        super.viewDidLoad()
        table.backgroundColor = .clear
        table.dataSource = self
        table.allowsSelection = false
        status.font = Typography.text(15)
        status.textColor = Palette.textSecondary
        status.textAlignment = .center
        status.numberOfLines = 0
        status.text = "Загружаем турниры…"
        [table, status].forEach(view.addSubview)
        table.snp.makeConstraints { $0.edges.equalToSuperview() }
        status.snp.makeConstraints {
            $0.center.equalTo(view.safeAreaLayoutGuide)
            $0.leading.trailing.equalToSuperview().inset(32)
        }
        Task { await load() }
    }

    private func load() async {
        do {
            competitions = try await repository.competitions()
            status.isHidden = !competitions.isEmpty
            status.text = "Турниров нет"
        } catch {
            status.text = "Не удалось загрузить турниры. Проверьте подключение и откройте экран ещё раз."
        }
        table.reloadData()
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        competitions.isEmpty ? nil : "Выключенные турниры не показываются на «Сегодня». Настройка сохранится на всех ваших iPhone."
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { competitions.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let competition = competitions[indexPath.row]
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.text = competition.name
        content.textProperties.font = Typography.text(16, .medium)
        content.textProperties.color = Palette.textPrimary
        cell.contentConfiguration = content
        cell.backgroundColor = Palette.surface
        let toggle = UISwitch()
        toggle.onTintColor = Palette.switchOn
        toggle.isOn = !settings.hiddenCompetitions.contains(competition.code)
        toggle.accessibilityLabel = competition.name
        toggle.addAction(UIAction { [weak self] action in
            guard let self, let toggle = action.sender as? UISwitch else { return }
            var hidden = settings.hiddenCompetitions
            if toggle.isOn { hidden.remove(competition.code) } else { hidden.insert(competition.code) }
            settings.hiddenCompetitions = hidden
        }, for: .valueChanged)
        cell.accessoryView = toggle
        return cell
    }
}

/// «О приложении и источниках данных»: версия, откуда данные, лицензии библиотек и шрифтов (D41, D34).
final class AboutViewController: ProfileSubscreen {
    static let text = """
    ДАННЫЕ

    Матчи, счёт и таблицы — football-data.org. Football data provided by the Football-Data.org API.

    Подкасты — открытые RSS-ленты издателей (podster.fm, mave.digital): выпуски и обложки загружаются по ссылкам из лент, мы их не храним.

    Радио — общедоступные потоки радиостанций по ссылкам вещателей.

    Гербы клубов и логотипы турниров не используются.

    БИБЛИОТЕКИ И ШРИФТЫ

    SnapKit — MIT License, © SnapKit Team.
    supabase-swift — MIT License, © Supabase.
    swift-crypto, swift-asn1, swift-http-types — Apache License 2.0, © Apple Inc.
    swift-clocks, swift-concurrency-extras, xctest-dynamic-overlay — MIT License, © Point-Free.
    Шрифт Unbounded — SIL Open Font License 1.1.
    Иконки Lucide — ISC License, © Lucide Contributors.
    """

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "О приложении"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        let textView = UITextView()
        textView.isEditable = false
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 24, right: 16)
        textView.attributedText = NSAttributedString(string: "Tribuna \(version) (\(build))\n\n" + Self.text, attributes: [
            .font: Typography.text(15), .foregroundColor: Palette.textPrimary,
        ])
        textView.adjustsFontForContentSizeCategory = true
        view.addSubview(textView)
        textView.snp.makeConstraints { $0.edges.equalTo(view.safeAreaLayoutGuide) }
    }
}
#endif
