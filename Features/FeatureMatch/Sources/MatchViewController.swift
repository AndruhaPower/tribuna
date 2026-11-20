import Combine
import CoreUI
import SnapKit
import UIKit

/// Карточка матча: своя шапка с круглыми «назад» и «поделиться» (как в макете, системная панель скрыта)
/// и коллекция — блок матча, таблица турнира или состояние загрузки.
final class MatchViewController: UIViewController {
    /// Идентификаторы стабильные (id команды), содержимое — в `payload`: при обновлении счёта
    /// ячейки перенастраиваются на месте, без мигания и потери фокуса VoiceOver.
    private enum Section: Hashable {
        case card, standings, status
    }

    private enum Item: Hashable {
        case card, tableHeader, status
        case row(String)
    }

    private struct RowPayload: Hashable {
        let row: MatchState.Row
        let isLast: Bool
    }

    /// `message == nil` — загрузка.
    private struct StatusPayload: Hashable {
        let message: String?
        let showsRetry: Bool
    }

    private struct Payload {
        var card: MatchState.Card?
        var rows: [String: RowPayload] = [:]
        var status: StatusPayload?

        /// Содержимое элемента для сравнения со старым; nil — элемента не было.
        func value(for item: Item) -> AnyHashable? {
            switch item {
            case .tableHeader: nil
            case .card: card.map(AnyHashable.init)
            case .status: status.map(AnyHashable.init)
            case let .row(id): rows[id].map(AnyHashable.init)
            }
        }
    }

    /// Высота шапки от верха безопасной зоны: кнопки 44 pt с полями 5 pt — замер по макету.
    private static let headerHeight: CGFloat = 54

    private let viewModel: MatchViewModel
    private let output: FeatureMatch.Output
    private let titleLabel = UILabel()
    private let emblemView = EmblemView()
    private var emblemURL: URL?
    private let shareButton = MatchViewController.roundButton(icon: "share", label: "Поделиться")
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private lazy var dataSource = makeDataSource()
    private var cancellables = Set<AnyCancellable>()
    private var payload = Payload()
    /// Делегат жеста «назад» навигации — возвращаем его, уходя с экрана.
    private weak var previousPopDelegate: UIGestureRecognizerDelegate?

    init(viewModel: MatchViewModel, output: FeatureMatch.Output) {
        self.viewModel = viewModel
        self.output = output
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        collectionView.backgroundColor = Palette.background
        collectionView.contentInset.bottom = 20
        // Шапка своя, поэтому отступ сверху — от неё, а не от безопасной зоны.
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.contentInset.top = 11

        let backButton = Self.roundButton(icon: "chevron-left", label: "Назад")
        backButton.addAction(UIAction { [weak self] _ in self?.navigationController?.popViewController(animated: true) }, for: .touchUpInside)
        shareButton.addAction(UIAction { [weak self] _ in self?.share() }, for: .touchUpInside)
        let titleFont = Typography.text(14)
        titleLabel.font = titleFont
        titleLabel.textColor = Palette.textSecondary
        titleLabel.textAlignment = .center
        titleLabel.accessibilityTraits = .header

        let header = UIView()
        header.backgroundColor = Palette.background
        [collectionView, header].forEach(view.addSubview)
        let titleStack = UIStackView(arrangedSubviews: [emblemView, titleLabel])
        titleStack.alignment = .center
        titleStack.spacing = 6
        [backButton, titleStack, shareButton].forEach(header.addSubview)
        header.snp.makeConstraints {
            $0.top.equalTo(view.safeAreaLayoutGuide)
            $0.leading.trailing.equalToSuperview()
            $0.height.equalTo(Self.headerHeight)
        }
        backButton.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(12)
            $0.centerY.equalToSuperview()
        }
        shareButton.snp.makeConstraints {
            $0.trailing.equalToSuperview().inset(12)
            $0.centerY.equalToSuperview()
        }
        titleStack.snp.makeConstraints {
            $0.centerX.equalToSuperview().priority(.high)
            $0.centerY.equalToSuperview()
            $0.leading.greaterThanOrEqualTo(backButton.snp.trailing).offset(8)
            $0.trailing.lessThanOrEqualTo(shareButton.snp.leading).offset(-8)
        }
        collectionView.snp.makeConstraints {
            $0.top.equalTo(header.snp.bottom)
            $0.leading.trailing.equalToSuperview()
            $0.bottom.equalTo(view.safeAreaLayoutGuide)
        }

        viewModel.$state.sink { [weak self] in self?.render($0) }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in self?.viewModel.didEnterForeground() }
            .store(in: &cancellables)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Со скрытой панелью свайп «назад» не срабатывает, пока жест не разрешит свой делегат.
        if let gesture = navigationController?.interactivePopGestureRecognizer, gesture.delegate !== self {
            previousPopDelegate = gesture.delegate
            gesture.delegate = self
        }
        viewModel.viewDidAppear()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.interactivePopGestureRecognizer?.delegate = previousPopDelegate
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewModel.viewDidDisappear()
    }

    // MARK: - Действия

    private func share() {
        guard let text = payload.card?.shareText else { return }
        let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = shareButton
        present(controller, animated: true)
    }

    private func remind() {
        viewModel.didTapRemindButton { [weak self] in
            guard let self else { return }
            let alert = UIAlertController(
                title: "Уведомления выключены",
                message: "Чтобы получить напоминание о матче, разрешите уведомления Tribuna в Настройках.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            alert.addAction(UIAlertAction(title: "Настройки", style: .default) { [output] _ in output.openSettings() })
            present(alert, animated: true)
        }
    }

    // MARK: - Состояние

    private func render(_ state: MatchState) {
        var new = Payload()
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        switch state.content {
        case .loading:
            new.status = StatusPayload(message: nil, showsRetry: false)
        case .notFound:
            new.status = StatusPayload(message: "Матч не найден", showsRetry: false)
        case let .error(message):
            new.status = StatusPayload(message: message, showsRetry: true)
        case let .loaded(card):
            new.card = card
            snapshot.appendSections([.card])
            snapshot.appendItems([.card], toSection: .card)
            // Повтор id в снимке роняет diffable — дубликаты пропускаем.
            let rows = card.standings.filter { row in
                guard new.rows[row.id] == nil else { return false }
                new.rows[row.id] = RowPayload(row: row, isLast: false)
                return true
            }
            if let last = rows.last {
                new.rows[last.id] = RowPayload(row: last, isLast: true)
                snapshot.appendSections([.standings])
                snapshot.appendItems([.tableHeader] + rows.map { .row($0.id) }, toSection: .standings)
            }
        }
        if new.status != nil {
            snapshot.appendSections([.status])
            snapshot.appendItems([.status], toSection: .status)
        }
        titleLabel.text = new.card?.header
        // Скрытый значок перезапрашиваем на каждом обновлении: после сбоя без сети он должен появиться, когда сеть вернётся.
        if emblemURL != new.card?.emblemURL || emblemView.isHidden {
            emblemURL = new.card?.emblemURL
            emblemView.setImage(url: emblemURL)
        }
        shareButton.isEnabled = new.card != nil

        let old = payload
        payload = new
        let changed = snapshot.itemIdentifiers.filter { item in
            guard let before = old.value(for: item) else { return false }
            return before != new.value(for: item)
        }
        snapshot.reconfigureItems(changed)
        dataSource.apply(snapshot, animatingDifferences: false)
        for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: UICollectionView.elementKindSectionHeader) {
            (collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionHeader, at: indexPath) as? SectionHeaderView)?
                .configure(title: new.card?.standingsTitle ?? "", trailing: nil)
        }
    }

    // MARK: - Коллекция

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, Item> {
        let cardCell = UICollectionView.CellRegistration<MatchCardCell, Item> { [weak self] cell, _, _ in
            guard let card = self?.payload.card else { return }
            cell.configure(card)
            cell.onToggleBookmark = { self?.viewModel.didToggleBookmark() }
            cell.onRemind = { self?.remind() }
        }
        let headerCell = UICollectionView.CellRegistration<StandingsRowCell, Item> { cell, _, _ in
            cell.configureHeader()
        }
        let rowCell = UICollectionView.CellRegistration<StandingsRowCell, Item> { [weak self] cell, _, item in
            guard case let .row(id) = item, let value = self?.payload.rows[id] else { return }
            cell.configure(value.row, isLast: value.isLast)
        }
        let statusCell = UICollectionView.CellRegistration<StatusCell, Item> { [weak self] cell, _, _ in
            let status = self?.payload.status
            cell.configure(message: status?.message, showsRetry: status?.showsRetry ?? false)
            cell.onRetry = { self?.viewModel.didTapRetry() }
        }
        let dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .card: collectionView.dequeueConfiguredReusableCell(using: cardCell, for: indexPath, item: item)
            case .tableHeader: collectionView.dequeueConfiguredReusableCell(using: headerCell, for: indexPath, item: item)
            case .row: collectionView.dequeueConfiguredReusableCell(using: rowCell, for: indexPath, item: item)
            case .status: collectionView.dequeueConfiguredReusableCell(using: statusCell, for: indexPath, item: item)
            }
        }
        let header = UICollectionView.SupplementaryRegistration<SectionHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] view, _, _ in
            view.configure(title: self?.payload.card?.standingsTitle ?? "", trailing: nil)
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
        }
        return dataSource
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { [weak self] index, _ in
            guard let section = self?.dataSource.sectionIdentifier(for: index) else { return nil }
            return Self.layoutSection(section)
        }
    }

    /// Поля 20 pt — замер макета (390 pt).
    private static func layoutSection(_ section: Section) -> NSCollectionLayoutSection {
        let result: NSCollectionLayoutSection
        switch section {
        case .card:
            // Высота по содержимому: без подписи о задержке карточка ниже.
            result = list(height: .estimated(MatchCardCell.estimatedHeight))
        case .standings:
            // Высоты заголовка и строк разные — ячейки задают их сами.
            result = list(height: .estimated(StandingsRowCell.rowHeight))
            result.boundarySupplementaryItems = [NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(SectionHeaderView.height)),
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            )]
        case .status:
            result = list(height: .absolute(StatusCell.height))
        }
        result.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
        return result
    }

    private static func list(height: NSCollectionLayoutDimension) -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: height)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
        return NSCollectionLayoutSection(group: group)
    }

    /// Круглая кнопка шапки 44 pt на подложке карточек.
    private static func roundButton(icon: String, label: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: icon, in: .module, compatibleWith: nil), for: .normal)
        button.tintColor = Palette.textPrimary
        button.backgroundColor = Palette.surface
        button.layer.cornerRadius = 22
        button.accessibilityLabel = label
        button.snp.makeConstraints { $0.size.equalTo(44) }
        return button
    }
}

extension MatchViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        (navigationController?.viewControllers.count ?? 0) > 1
    }
}
