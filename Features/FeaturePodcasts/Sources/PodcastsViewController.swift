import Combine
import CoreDomain
import CoreUI
import SnapKit
import UIKit

/// Вкладка «Подкасты»: шапка с переключателем, плитки подписок и «Новые выпуски», каталог или «Загрузки», состояние.
final class PodcastsViewController: UIViewController {
    /// Идентификаторы стабильные (id подкаста, id выпуска), содержимое — в `payload`: смена статуса плеера
    /// или прогресса перенастраивает ячейки на месте.
    private enum Section: Hashable {
        case header, tiles, episodes, catalog, downloads, status
    }

    private enum Item: Hashable {
        case header, status
        case tile(String)
        case episode(EpisodeID)
        case podcast(String)
    }

    private struct Payload {
        var segment = PodcastsState.Segment.catalog
        var badge: Int?
        var tiles: [String: SubscriptionTile] = [:]
        var episodes: [EpisodeID: EpisodeRow] = [:]
        var podcasts: [String: PodcastRow] = [:]
        var lastItem: Item?
        var status: StatusMessage?

        /// Содержимое элемента для сравнения со старым; nil — элемента не было.
        func value(for item: Item) -> AnyHashable? {
            switch item {
            case .header: AnyHashable([AnyHashable(segment), AnyHashable(badge)])
            case .status: status.map(AnyHashable.init)
            case let .tile(id): tiles[id].map(AnyHashable.init)
            case let .episode(id): episodes[id].map { AnyHashable([AnyHashable($0), AnyHashable(lastItem == item)]) }
            case let .podcast(id): podcasts[id].map { AnyHashable([AnyHashable($0), AnyHashable(lastItem == item)]) }
            }
        }
    }

    private let viewModel: PodcastsViewModel
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private lazy var dataSource = makeDataSource()
    private let refreshControl = UIRefreshControl()
    private var cancellables = Set<AnyCancellable>()
    private var payload = Payload()

    init(viewModel: PodcastsViewModel) {
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
        viewModel.viewDidAppear()
    }

    // MARK: - Состояние

    private func render(_ state: PodcastsState) {
        var new = Payload()
        new.segment = state.segment
        new.badge = state.badge
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.header])
        snapshot.appendItems([.header], toSection: .header)

        switch state.content {
        case let .status(status):
            new.status = status
        case let .catalog(rows):
            let items = rows.filter { new.podcasts.updateValue($0, forKey: $0.id) == nil }.map { Item.podcast($0.id) }
            new.lastItem = items.last
            snapshot.appendSections([.catalog])
            snapshot.appendItems(items, toSection: .catalog)
        case let .subscriptions(tiles, episodes):
            // Повтор id в снимке роняет diffable — дубликаты пропускаем.
            let tileItems = tiles.filter { new.tiles.updateValue($0, forKey: $0.id) == nil }.map { Item.tile($0.id) }
            if !tileItems.isEmpty {
                snapshot.appendSections([.tiles])
                snapshot.appendItems(tileItems, toSection: .tiles)
            }
            append(episodes, to: .episodes, &snapshot, &new)
        case let .downloads(episodes):
            append(episodes, to: .downloads, &snapshot, &new)
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
        if !state.isRefreshing, refreshControl.isRefreshing { refreshControl.endRefreshing() }
    }

    private func append(
        _ episodes: PodcastsState.EpisodesContent,
        to section: Section,
        _ snapshot: inout NSDiffableDataSourceSnapshot<Section, Item>,
        _ new: inout Payload
    ) {
        switch episodes {
        case let .rows(rows):
            // Повтор id в снимке роняет diffable — дубликаты пропускаем.
            let items = rows.filter { new.episodes.updateValue($0, forKey: $0.id) == nil }.map { Item.episode($0.id) }
            new.lastItem = items.last
            snapshot.appendSections([section])
            snapshot.appendItems(items, toSection: section)
        case let .status(status):
            new.status = status
        }
    }

    // MARK: - Коллекция

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, Item> {
        let headerCell = UICollectionView.CellRegistration<PodcastsHeaderCell, Item> { [weak self] cell, _, _ in
            guard let self else { return }
            cell.configure(selected: payload.segment, badge: payload.badge)
            cell.onSelect = { [weak self] in self?.viewModel.didSelectSegment($0) }
        }
        let tileCell = UICollectionView.CellRegistration<SubscriptionTileCell, Item> { [weak self] cell, _, item in
            if case let .tile(id) = item, let tile = self?.payload.tiles[id] { cell.configure(tile) }
        }
        let episodeCell = UICollectionView.CellRegistration<ListRowCell, Item> { [weak self] cell, _, item in
            guard let self, case let .episode(id) = item, let row = payload.episodes[id] else { return }
            cell.configure(ListRowCell.Content(row), isLast: payload.lastItem == item)
            cell.onButton = { [weak self] in self?.viewModel.didTapEpisodeButton(id) }
            cell.onDownload = { [weak self] in self?.viewModel.didTapDownloadAction(id) }
        }
        let podcastCell = UICollectionView.CellRegistration<ListRowCell, Item> { [weak self] cell, _, item in
            guard let self, case let .podcast(id) = item, let row = payload.podcasts[id] else { return }
            cell.configure(ListRowCell.Content(row), isLast: payload.lastItem == item)
            cell.onButton = { [weak self] in self?.viewModel.didTapSubscribe(id) }
        }
        let statusCell = UICollectionView.CellRegistration<StatusCell, Item> { [weak self] cell, _, _ in
            let status = self?.payload.status
            cell.configure(message: status?.message, showsRetry: status?.showsRetry ?? false)
            cell.onRetry = { self?.viewModel.didTapRetry() }
        }

        let dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .header: collectionView.dequeueConfiguredReusableCell(using: headerCell, for: indexPath, item: item)
            case .tile: collectionView.dequeueConfiguredReusableCell(using: tileCell, for: indexPath, item: item)
            case .episode: collectionView.dequeueConfiguredReusableCell(using: episodeCell, for: indexPath, item: item)
            case .podcast: collectionView.dequeueConfiguredReusableCell(using: podcastCell, for: indexPath, item: item)
            case .status: collectionView.dequeueConfiguredReusableCell(using: statusCell, for: indexPath, item: item)
            }
        }
        let header = UICollectionView.SupplementaryRegistration<SectionHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { view, _, _ in
            view.configure(title: "НОВЫЕ ВЫПУСКИ", trailing: nil)
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
        }
        return dataSource
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { [weak self] index, environment in
            guard let self, let section = dataSource.sectionIdentifier(for: index) else { return nil }
            return layoutSection(section, environment: environment)
        }
    }

    /// «Загрузки» — список ради свайпа «Удалить»; разделители рисует сама строка.
    private func downloadsSection(_ environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.showsSeparators = false
        configuration.backgroundColor = .clear
        configuration.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            guard case let .episode(id) = self?.dataSource.itemIdentifier(for: indexPath) else { return nil }
            return UISwipeActionsConfiguration(actions: [UIContextualAction(style: .destructive, title: "Удалить") { _, _, done in
                self?.viewModel.didSwipeDelete(id)
                done(true)
            }])
        }
        let result = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
        // Обложка первой строки — в 20.5 pt под переключателем, как в «Подборке».
        result.contentInsets = NSDirectionalEdgeInsets(top: 4.5, leading: 20, bottom: 0, trailing: 20)
        return result
    }

    /// Размеры — замер макета «Подкасты» (390 pt): поля 20 pt.
    private func layoutSection(_ section: Section, environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let inset: CGFloat = 20
        let width = environment.container.effectiveContentSize.width
        switch section {
        case .header:
            return Self.list(.absolute(PodcastsHeaderCell.height))
        case .downloads:
            return downloadsSection(environment)
        case .tiles:
            // Три плитки на ширину экрана с промежутком 12 pt; больше трёх — прокрутка вбок.
            let size = NSCollectionLayoutSize(widthDimension: .absolute((width - 2 * inset - 24) / 3), heightDimension: .absolute(SubscriptionTileCell.height))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
            let result = NSCollectionLayoutSection(group: group)
            result.orthogonalScrollingBehavior = .continuous
            result.interGroupSpacing = 12
            // Плитки в 20.5 pt под переключателем.
            result.contentInsets = NSDirectionalEdgeInsets(top: 20.5, leading: inset, bottom: 0, trailing: inset)
            return result
        case .episodes:
            let result = Self.list(.estimated(ListRowCell.estimatedHeight))
            result.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: inset, bottom: 0, trailing: inset)
            // Заголовок 40 pt: верх обложки первой строки в 56 pt от верха заголовка (16 pt — поле строки).
            result.boundarySupplementaryItems = [NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(40)),
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            )]
            return result
        case .catalog:
            let result = Self.list(.estimated(ListRowCell.estimatedHeight))
            // Обложка первой строки — в 20.5 pt под переключателем, как плитки.
            result.contentInsets = NSDirectionalEdgeInsets(top: 4.5, leading: inset, bottom: 0, trailing: inset)
            return result
        case .status:
            let result = Self.list(.absolute(StatusCell.height))
            result.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: inset, bottom: 0, trailing: inset)
            return result
        }
    }

    static func list(_ height: NSCollectionLayoutDimension) -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: height)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
        return NSCollectionLayoutSection(group: group)
    }
}

extension PodcastsViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        switch dataSource.itemIdentifier(for: indexPath) {
        case let .tile(id), let .podcast(id):
            viewModel.didTapPodcast(id)
        case let .episode(id):
            viewModel.didTapEpisode(id)
        default:
            break
        }
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        switch dataSource.itemIdentifier(for: indexPath) {
        case .tile, .episode, .podcast: true
        default: false
        }
    }

    func collectionView(
        _ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard indexPaths.count == 1, case let .episode(id) = dataSource.itemIdentifier(for: indexPaths[0]),
              let action = payload.episodes[id]?.downloadAction else { return nil }
        return action.contextMenu { [weak self] in self?.viewModel.didTapDownloadAction(id) }
    }
}

extension EpisodeRow.DownloadAction {
    /// Меню долгого нажатия на строку выпуска — один пункт по состоянию загрузки.
    @MainActor func contextMenu(_ handler: @escaping @MainActor () -> Void) -> UIContextMenuConfiguration {
        let (title, attributes): (String, UIMenuElement.Attributes) = switch self {
        case .download: ("Скачать", [])
        case .cancel: ("Отменить загрузку", [])
        case .remove: ("Удалить загрузку", .destructive)
        }
        return UIContextMenuConfiguration(actionProvider: { _ in
            UIMenu(children: [UIAction(title: title, attributes: attributes) { _ in handler() }])
        })
    }
}

extension ListRowCell.Content {
    init(_ row: EpisodeRow) {
        self.init(
            artworkURL: row.artworkURL,
            caption: row.caption,
            isCaptionActive: row.isNew,
            title: row.title,
            subtitle: row.subtitle,
            button: row.button.map { $0 == .pause ? ("Пауза", "pause", .accent) : ("Слушать", "play", .accent) },
            showsDownloadButton: row.showsDownloadButton,
            downloadButtonAccessibilityLabel: row.downloadButtonAccessibilityLabel,
            progress: row.downloadProgress,
            accessibilityLabel: row.accessibilityLabel,
            buttonAccessibilityLabel: row.buttonAccessibilityLabel
        )
    }

    init(_ row: PodcastRow) {
        self.init(
            artworkURL: row.artworkURL,
            caption: nil,
            isCaptionActive: false,
            title: row.title,
            subtitle: row.author,
            button: row.isSubscribed ? ("Вы подписаны", nil, .outline) : ("Подписаться", nil, .accent),
            accessibilityLabel: "\(row.title), \(row.author)"
        )
    }
}
