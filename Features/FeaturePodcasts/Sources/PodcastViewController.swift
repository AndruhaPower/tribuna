import Combine
import CoreDomain
import CoreUI
import SnapKit
import UIKit

/// Экран подкаста: системная панель с «назад» (прозрачная), шапка, «Выпуски», состояние.
final class PodcastViewController: UIViewController {
    private enum Section: Hashable {
        case header, episodes, status
    }

    private enum Item: Hashable {
        case header, status
        case episode(EpisodeID)
    }

    private struct Payload {
        var header: PodcastState.Header?
        var episodes: [EpisodeID: EpisodeRow] = [:]
        var lastItem: Item?
        var status: StatusMessage?

        func value(for item: Item) -> AnyHashable? {
            switch item {
            case .header: header.map(AnyHashable.init)
            case .status: status.map(AnyHashable.init)
            case let .episode(id): episodes[id].map { AnyHashable([AnyHashable($0), AnyHashable(lastItem == item)]) }
            }
        }
    }

    private let viewModel: PodcastViewModel
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private lazy var dataSource = makeDataSource()
    private let refreshControl = UIRefreshControl()
    private var cancellables = Set<AnyCancellable>()
    private var payload = Payload()

    init(viewModel: PodcastViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.backButtonDisplayMode = .minimal
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
        navigationController?.navigationBar.tintColor = Palette.textPrimary
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel.viewDidAppear()
    }

    private func render(_ state: PodcastState) {
        var new = Payload()
        new.header = state.header
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.header])
        snapshot.appendItems([.header], toSection: .header)
        switch state.episodes {
        case let .rows(rows):
            // Повтор id в снимке роняет diffable — дубликаты пропускаем.
            let items = rows.filter { new.episodes.updateValue($0, forKey: $0.id) == nil }.map { Item.episode($0.id) }
            new.lastItem = items.last
            snapshot.appendSections([.episodes])
            snapshot.appendItems(items, toSection: .episodes)
        case let .status(status):
            new.status = status
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

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, Item> {
        let headerCell = UICollectionView.CellRegistration<PodcastHeaderCell, Item> { [weak self] cell, _, _ in
            if let header = self?.payload.header { cell.configure(header) }
            cell.onSubscribe = { self?.viewModel.didTapSubscribe() }
        }
        let episodeCell = UICollectionView.CellRegistration<ListRowCell, Item> { [weak self] cell, _, item in
            guard let self, case let .episode(id) = item, let row = payload.episodes[id] else { return }
            cell.configure(ListRowCell.Content(row), isLast: payload.lastItem == item)
            cell.onButton = { [weak self] in self?.viewModel.didTapEpisodeButton(id) }
            cell.onDownload = { [weak self] in self?.viewModel.didTapDownloadAction(id) }
        }
        let statusCell = UICollectionView.CellRegistration<StatusCell, Item> { [weak self] cell, _, _ in
            let status = self?.payload.status
            cell.configure(message: status?.message, showsRetry: status?.showsRetry ?? false)
            cell.onRetry = { self?.viewModel.didTapRetry() }
        }
        let dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .header: collectionView.dequeueConfiguredReusableCell(using: headerCell, for: indexPath, item: item)
            case .episode: collectionView.dequeueConfiguredReusableCell(using: episodeCell, for: indexPath, item: item)
            case .status: collectionView.dequeueConfiguredReusableCell(using: statusCell, for: indexPath, item: item)
            }
        }
        let header = UICollectionView.SupplementaryRegistration<SectionHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { view, _, _ in
            view.configure(title: "ВЫПУСКИ", trailing: nil)
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
        }
        return dataSource
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { [weak self] index, _ in
            guard let section = self?.dataSource.sectionIdentifier(for: index) else { return nil }
            let inset: CGFloat = 20
            switch section {
            case .header:
                let result = PodcastsViewController.list(.estimated(PodcastHeaderCell.estimatedHeight))
                result.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: inset, bottom: 0, trailing: inset)
                return result
            case .episodes:
                let result = PodcastsViewController.list(.estimated(ListRowCell.estimatedHeight))
                result.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: inset, bottom: 0, trailing: inset)
                result.boundarySupplementaryItems = [NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(40)),
                    elementKind: UICollectionView.elementKindSectionHeader,
                    alignment: .top
                )]
                return result
            case .status:
                let result = PodcastsViewController.list(.absolute(StatusCell.height))
                result.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: inset, bottom: 0, trailing: inset)
                return result
            }
        }
    }
}

extension PodcastViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        if case let .episode(id) = dataSource.itemIdentifier(for: indexPath) { viewModel.didTapEpisode(id) }
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        if case .episode = dataSource.itemIdentifier(for: indexPath) { true } else { false }
    }

    func collectionView(
        _ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard indexPaths.count == 1, case let .episode(id) = dataSource.itemIdentifier(for: indexPaths[0]),
              let action = payload.episodes[id]?.downloadAction else { return nil }
        return action.contextMenu { [weak self] in self?.viewModel.didTapDownloadAction(id) }
    }
}
