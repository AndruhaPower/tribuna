import Combine
import CoreUI
import SnapKit
import UIKit

/// Экран «Сегодня»: одна коллекция — шапка, полоса дней, «Мои события», турниры, состояние.
final class TodayViewController: UIViewController {
    private enum Section: Hashable {
        case header, days, events, status
        /// Подписи заголовка входят в идентификатор: изменились — секция перерисуется вместе с заголовком.
        case competition(id: String, title: String, trailing: String)
    }

    private enum Item: Hashable {
        case header
        case day(TodayState.DayItem)
        case event(TodayState.EventCard)
        case row(TodayState.MatchRow, isFirst: Bool)
        case loading
        case message(String, showsRetry: Bool)
    }

    private let viewModel: TodayViewModel
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private lazy var dataSource = makeDataSource()
    private let refreshControl = UIRefreshControl()
    private var subscription: AnyCancellable?

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
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Заголовок рисуется в контенте; на экранах, открытых отсюда, панель с «Назад» возвращается.
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
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

        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.header, .days])
        snapshot.appendItems([.header], toSection: .header)
        snapshot.appendItems(state.days.map(Item.day), toSection: .days)

        switch state.content {
        case .loading:
            snapshot.appendSections([.status])
            snapshot.appendItems([.loading], toSection: .status)
        case .empty:
            snapshot.appendSections([.status])
            snapshot.appendItems([.message("Матчей нет", showsRetry: false)], toSection: .status)
        case let .error(message):
            snapshot.appendSections([.status])
            snapshot.appendItems([.message(message, showsRetry: true)], toSection: .status)
        case let .loaded(events, sections):
            if !events.isEmpty {
                snapshot.appendSections([.events])
                snapshot.appendItems(events.map(Item.event), toSection: .events)
            }
            for section in sections {
                let id = Section.competition(id: section.id, title: section.title, trailing: section.trailing)
                snapshot.appendSections([id])
                snapshot.appendItems(section.rows.enumerated().map { Item.row($1, isFirst: $0 == 0) }, toSection: id)
            }
        }
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: - Коллекция

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, Item> {
        let headerCell = UICollectionView.CellRegistration<TodayHeaderCell, Item> { _, _, _ in }
        let dayCell = UICollectionView.CellRegistration<DayChipCell, TodayState.DayItem> { cell, _, day in
            cell.configure(day)
        }
        let eventCell = UICollectionView.CellRegistration<EventCardCell, TodayState.EventCard> { cell, _, event in
            cell.configure(event)
        }
        let rowCell = UICollectionView.CellRegistration<MatchRowCell, (TodayState.MatchRow, Bool)> { [weak self] cell, _, value in
            cell.configure(value.0, isFirst: value.1)
            let id = value.0.id
            cell.onToggleBookmark = { self?.viewModel.didToggleBookmark(id) }
        }
        let statusCell = UICollectionView.CellRegistration<TodayStatusCell, Item> { [weak self] cell, _, item in
            if case let .message(text, showsRetry) = item {
                cell.configure(message: text, showsRetry: showsRetry)
            } else {
                cell.configure(message: nil, showsRetry: false)
            }
            cell.onRetry = { self?.viewModel.didTapRetry() }
        }

        let dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .header:
                collectionView.dequeueConfiguredReusableCell(using: headerCell, for: indexPath, item: item)
            case let .day(day):
                collectionView.dequeueConfiguredReusableCell(using: dayCell, for: indexPath, item: day)
            case let .event(event):
                collectionView.dequeueConfiguredReusableCell(using: eventCell, for: indexPath, item: event)
            case let .row(row, isFirst):
                collectionView.dequeueConfiguredReusableCell(using: rowCell, for: indexPath, item: (row, isFirst))
            case .loading, .message:
                collectionView.dequeueConfiguredReusableCell(using: statusCell, for: indexPath, item: item)
            }
        }
        let header = UICollectionView.SupplementaryRegistration<SectionHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] view, _, indexPath in
            switch self?.dataSource.sectionIdentifier(for: indexPath.section) {
            case .events:
                view.configure(title: "МОИ СОБЫТИЯ", trailing: nil)
            case let .competition(_, title, trailing):
                view.configure(title: title, trailing: trailing)
            default:
                break
            }
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
        }
        return dataSource
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
            let result = list(height: TodayStatusCell.height, spacing: 0)
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
        case let .day(day):
            viewModel.didSelectDay(day.id)
        case let .event(event):
            viewModel.didTapMatch(event.id)
        case let .row(row, _):
            viewModel.didTapMatch(row.id)
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
