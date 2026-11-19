import Combine
import CoreDomain
import CoreUI
import SnapKit
import UIKit

/// Экран «Сегодня»: одна коллекция — шапка, полоса дней, «Мои события», турниры, состояние.
final class TodayViewController: UIViewController {
    /// Идентификаторы стабильные (код турнира, дата, id матча), содержимое — в `payload`:
    /// так при смене счёта или закладки ячейка перенастраивается на месте, не теряя фокус VoiceOver и прокрутку дней.
    private enum Section: Hashable {
        case header, days, events, status
        case competition(String)
    }

    private enum Item: Hashable {
        case header, status
        case day(Date)
        case event(MatchID)
        case row(MatchID)
    }

    private struct RowPayload: Hashable {
        let row: TodayState.MatchRow
        let isFirst: Bool
    }

    /// `message == nil` — загрузка.
    private struct StatusPayload: Hashable {
        let message: String?
        let showsRetry: Bool
    }

    private struct Payload {
        var days: [Date: TodayState.DayItem] = [:]
        var events: [MatchID: TodayState.EventCard] = [:]
        var rows: [MatchID: RowPayload] = [:]
        var sections: [String: TodayState.Section] = [:]
        var status: StatusPayload?

        /// Содержимое элемента для сравнения со старым; nil — элемента не было.
        func value(for item: Item) -> AnyHashable? {
            switch item {
            case .header: nil
            case .status: status.map(AnyHashable.init)
            case let .day(id): days[id].map(AnyHashable.init)
            case let .event(id): events[id].map(AnyHashable.init)
            case let .row(id): rows[id].map(AnyHashable.init)
            }
        }
    }

    private let viewModel: TodayViewModel
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private lazy var dataSource = makeDataSource()
    private let refreshControl = UIRefreshControl()
    private var subscription: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var payload = Payload()

    init(viewModel: TodayViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        collectionView.backgroundColor = Palette.background
        collectionView.delegate = self
        collectionView.contentInset.bottom = 20
        refreshControl.tintColor = Palette.textSecondary
        refreshControl.addAction(UIAction { [weak self] _ in self?.viewModel.didPullToRefresh() }, for: .valueChanged)
        collectionView.refreshControl = refreshControl
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { $0.edges.equalToSuperview() }
        subscription = viewModel.$state.sink { [weak self] in self?.render($0) }
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in self?.viewModel.didEnterForeground() }
            .store(in: &cancellables)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Заголовок рисуется в контенте; карточка матча тоже без системной панели, поэтому обратно её не показываем.
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel.viewDidAppear()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewModel.viewDidDisappear()
    }

    // MARK: - Состояние

    private func render(_ state: TodayState) {
        if !state.isRefreshing, refreshControl.isRefreshing { refreshControl.endRefreshing() }

        var new = Payload()
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.header, .days])
        snapshot.appendItems([.header], toSection: .header)
        for day in state.days where new.days[day.id] == nil {
            new.days[day.id] = day
            snapshot.appendItems([.day(day.id)], toSection: .days)
        }

        switch state.content {
        case .loading:
            new.status = StatusPayload(message: nil, showsRetry: false)
        case .empty:
            new.status = StatusPayload(message: "Матчей нет", showsRetry: false)
        case let .error(message):
            new.status = StatusPayload(message: message, showsRetry: true)
        case let .loaded(events, sections):
            // Повтор id в снимке роняет diffable; по построению его нет, но дубликаты пропускаем.
            for event in events where new.events[event.id] == nil {
                if new.events.isEmpty { snapshot.appendSections([.events]) }
                new.events[event.id] = event
                snapshot.appendItems([.event(event.id)], toSection: .events)
            }
            for section in sections where new.sections[section.id] == nil {
                let rows = section.rows.filter { new.rows[$0.id] == nil }
                guard !rows.isEmpty else { continue }
                new.sections[section.id] = section
                for (index, row) in rows.enumerated() {
                    new.rows[row.id] = RowPayload(row: row, isFirst: index == 0)
                }
                snapshot.appendSections([.competition(section.id)])
                snapshot.appendItems(rows.map { .row($0.id) }, toSection: .competition(section.id))
            }
        }
        if new.status != nil {
            snapshot.appendSections([.status])
            snapshot.appendItems([.status], toSection: .status)
        }

        let old = payload
        payload = new
        let changed = snapshot.itemIdentifiers.filter { item in
            guard let before = old.value(for: item) else { return false }
            return before != new.value(for: item)
        }
        snapshot.reconfigureItems(changed)
        dataSource.apply(snapshot, animatingDifferences: false)
        // Заголовки секций не перенастраиваются снимком — обновляем видимые.
        for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: UICollectionView.elementKindSectionHeader) {
            if let header = collectionView.supplementaryView(
                forElementKind: UICollectionView.elementKindSectionHeader, at: indexPath
            ) as? SectionHeaderView {
                configure(header, section: indexPath.section)
            }
        }
    }

    // MARK: - Коллекция

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, Item> {
        let headerCell = UICollectionView.CellRegistration<TodayHeaderCell, Item> { _, _, _ in }
        let dayCell = UICollectionView.CellRegistration<DayChipCell, Item> { [weak self] cell, _, item in
            if case let .day(id) = item, let day = self?.payload.days[id] { cell.configure(day) }
        }
        let eventCell = UICollectionView.CellRegistration<EventCardCell, Item> { [weak self] cell, _, item in
            if case let .event(id) = item, let event = self?.payload.events[id] { cell.configure(event) }
        }
        let rowCell = UICollectionView.CellRegistration<MatchRowCell, Item> { [weak self] cell, _, item in
            guard case let .row(id) = item, let value = self?.payload.rows[id] else { return }
            cell.configure(value.row, isFirst: value.isFirst)
            cell.onToggleBookmark = { self?.viewModel.didToggleBookmark(id) }
        }
        let statusCell = UICollectionView.CellRegistration<StatusCell, Item> { [weak self] cell, _, _ in
            let status = self?.payload.status
            cell.configure(message: status?.message, showsRetry: status?.showsRetry ?? false)
            cell.onRetry = { self?.viewModel.didTapRetry() }
        }

        let dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .header:
                collectionView.dequeueConfiguredReusableCell(using: headerCell, for: indexPath, item: item)
            case .day:
                collectionView.dequeueConfiguredReusableCell(using: dayCell, for: indexPath, item: item)
            case .event:
                collectionView.dequeueConfiguredReusableCell(using: eventCell, for: indexPath, item: item)
            case .row:
                collectionView.dequeueConfiguredReusableCell(using: rowCell, for: indexPath, item: item)
            case .status:
                collectionView.dequeueConfiguredReusableCell(using: statusCell, for: indexPath, item: item)
            }
        }
        let header = UICollectionView.SupplementaryRegistration<SectionHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] view, _, indexPath in
            self?.configure(view, section: indexPath.section)
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
        }
        return dataSource
    }

    private func configure(_ header: SectionHeaderView, section index: Int) {
        switch dataSource.sectionIdentifier(for: index) {
        case .events:
            header.configure(title: "МОИ СОБЫТИЯ", trailing: nil)
        case let .competition(code):
            let section = payload.sections[code]
            header.configure(title: section?.title ?? "", trailing: section?.trailing)
        default:
            break
        }
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        let layout = UICollectionViewCompositionalLayout { [weak self] index, environment in
            guard let section = self?.dataSource.sectionIdentifier(for: index) else { return nil }
            return Self.layoutSection(section, environment: environment)
        }
        layout.register(CompetitionCardBackground.self, forDecorationViewOfKind: CompetitionCardBackground.kind)
        return layout
    }

    /// Размеры — замер макета «Сегодня» (390 pt): поля 20 pt, карточки на всю ширину между полями.
    private static func layoutSection(_ section: Section, environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let inset: CGFloat = 20
        switch section {
        case .header:
            return list(height: TodayHeaderCell.height, spacing: 0)
        case .days:
            let size = NSCollectionLayoutSize(
                widthDimension: .absolute(DayChipCell.size.width),
                heightDimension: .absolute(DayChipCell.size.height)
            )
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
            let result = NSCollectionLayoutSection(group: group)
            result.orthogonalScrollingBehavior = .continuous
            result.interGroupSpacing = 8
            // Снизу 2 pt: от чипов до заголовка секции в макете на 2 pt больше, чем от карточки.
            result.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: inset, bottom: 2, trailing: inset)
            return result
        case .events:
            let result = list(height: EventCardCell.height, spacing: 12)
            result.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: inset, bottom: 0, trailing: inset)
            result.boundarySupplementaryItems = [header()]
            return result
        case .competition:
            let result = list(height: MatchRowCell.height, spacing: 1)
            result.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: inset, bottom: 0, trailing: inset)
            result.boundarySupplementaryItems = [header()]
            let background = NSCollectionLayoutDecorationItem.background(elementKind: CompetitionCardBackground.kind)
            // Подложка под строками, без заголовка: его высоту вычитаем сверху.
            background.contentInsets = NSDirectionalEdgeInsets(top: SectionHeaderView.height, leading: inset, bottom: 0, trailing: inset)
            result.decorationItems = [background]
            return result
        case .status:
            let result = list(height: StatusCell.height, spacing: 0)
            result.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: inset, bottom: 0, trailing: inset)
            return result
        }
    }

    private static func list(height: CGFloat, spacing: CGFloat) -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = spacing
        return section
    }

    private static func header() -> NSCollectionLayoutBoundarySupplementaryItem {
        NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(SectionHeaderView.height)),
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
    }
}

extension TodayViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        switch dataSource.itemIdentifier(for: indexPath) {
        case let .day(id):
            viewModel.didSelectDay(id)
        case let .event(id), let .row(id):
            viewModel.didTapMatch(id)
        default:
            break
        }
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        switch dataSource.itemIdentifier(for: indexPath) {
        case .day, .event, .row: true
        default: false
        }
    }
}
