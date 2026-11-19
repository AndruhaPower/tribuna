import Combine
import CoreDomain
import CoreUI
import SnapKit
import UIKit

/// Экран «Эфир»: одна коллекция — шапка с поиском, чипы жанров, «Сейчас играет», станции, состояние.
final class RadioViewController: UIViewController {
    /// Идентификаторы стабильные (жанр, id станции), содержимое — в `payload`:
    /// при смене статуса плеера ячейка перенастраивается на месте, поле поиска не теряет фокус.
    private enum Section: Hashable {
        case header, chips, nowPlaying, stations, status
    }

    private enum Item: Hashable {
        case header, nowPlaying, status
        case chip(StationGenre)
        case station(String)
    }

    private struct RowPayload: Hashable {
        let row: RadioState.Row
        let isLast: Bool
    }

    /// `message == nil` — загрузка.
    private struct StatusPayload: Hashable {
        let message: String?
        let showsRetry: Bool
    }

    private struct Payload {
        var chips: [StationGenre: RadioState.Chip] = [:]
        var nowPlaying: RadioState.NowPlaying?
        var rows: [String: RowPayload] = [:]
        var stationsTitle = ""
        var query = ""
        var status: StatusPayload?

        /// Содержимое элемента для сравнения со старым; nil — элемента не было.
        func value(for item: Item) -> AnyHashable? {
            switch item {
            case .header: nil
            case .nowPlaying: nowPlaying.map(AnyHashable.init)
            case .status: status.map(AnyHashable.init)
            case let .chip(id): chips[id].map(AnyHashable.init)
            case let .station(id): rows[id].map(AnyHashable.init)
            }
        }
    }

    private let viewModel: RadioViewModel
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private lazy var dataSource = makeDataSource()
    private var cancellables = Set<AnyCancellable>()
    private var payload = Payload()

    init(viewModel: RadioViewModel) {
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
        collectionView.keyboardDismissMode = .onDrag
        collectionView.contentInset.bottom = 20
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

    private func render(_ state: RadioState) {
        var new = Payload()
        new.query = state.query
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.header, .chips])
        snapshot.appendItems([.header], toSection: .header)
        for chip in state.chips {
            new.chips[chip.id] = chip
            snapshot.appendItems([.chip(chip.id)], toSection: .chips)
        }
        if let card = state.nowPlaying {
            new.nowPlaying = card
            snapshot.appendSections([.nowPlaying])
            snapshot.appendItems([.nowPlaying], toSection: .nowPlaying)
        }

        switch state.content {
        case .loading:
            new.status = StatusPayload(message: nil, showsRetry: false)
        case let .empty(message):
            new.status = StatusPayload(message: message, showsRetry: false)
        case let .error(message):
            new.status = StatusPayload(message: message, showsRetry: true)
        case let .loaded(title, rows):
            // Повтор id в снимке роняет diffable; каталог по построению без повторов, но дубликаты пропускаем.
            let unique = rows.filter { row in
                guard new.rows[row.id] == nil else { return false }
                new.rows[row.id] = RowPayload(row: row, isLast: false)
                return true
            }
            if let last = unique.last { new.rows[last.id] = RowPayload(row: last, isLast: true) }
            new.stationsTitle = title
            snapshot.appendSections([.stations])
            snapshot.appendItems(unique.map { .station($0.id) }, toSection: .stations)
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
        // Заголовок секции не перенастраивается снимком — обновляем видимый.
        for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: UICollectionView.elementKindSectionHeader) {
            (collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionHeader, at: indexPath) as? SectionHeaderView)?
                .configure(title: payload.stationsTitle, trailing: nil)
        }
    }

    // MARK: - Коллекция

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, Item> {
        let headerCell = UICollectionView.CellRegistration<RadioHeaderCell, Item> { [weak self] cell, _, _ in
            cell.configure(query: self?.payload.query ?? "")
            cell.onQueryChange = { self?.viewModel.didChangeQuery($0) }
        }
        let chipCell = UICollectionView.CellRegistration<GenreChipCell, Item> { [weak self] cell, _, item in
            if case let .chip(id) = item, let chip = self?.payload.chips[id] { cell.configure(chip) }
        }
        let nowPlayingCell = UICollectionView.CellRegistration<NowPlayingCell, Item> { [weak self] cell, _, _ in
            if let card = self?.payload.nowPlaying { cell.configure(card) }
            cell.onPlayPause = { self?.viewModel.didTapNowPlayingButton() }
        }
        let stationCell = UICollectionView.CellRegistration<StationRowCell, Item> { [weak self] cell, _, item in
            guard case let .station(id) = item, let value = self?.payload.rows[id] else { return }
            cell.configure(value.row, isLast: value.isLast)
            cell.onPlay = { self?.viewModel.didTapStation(id) }
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
            case .chip:
                collectionView.dequeueConfiguredReusableCell(using: chipCell, for: indexPath, item: item)
            case .nowPlaying:
                collectionView.dequeueConfiguredReusableCell(using: nowPlayingCell, for: indexPath, item: item)
            case .station:
                collectionView.dequeueConfiguredReusableCell(using: stationCell, for: indexPath, item: item)
            case .status:
                collectionView.dequeueConfiguredReusableCell(using: statusCell, for: indexPath, item: item)
            }
        }
        let header = UICollectionView.SupplementaryRegistration<SectionHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] view, _, _ in
            view.configure(title: self?.payload.stationsTitle ?? "", trailing: nil)
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

    /// Размеры — замер макета «Эфир» (390 pt): поля 20 pt.
    private static func layoutSection(_ section: Section) -> NSCollectionLayoutSection {
        let inset: CGFloat = 20
        switch section {
        case .header:
            return list(height: RadioHeaderCell.height)
        case .chips:
            let size = NSCollectionLayoutSize(widthDimension: .estimated(80), heightDimension: .absolute(GenreChipCell.height))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
            let result = NSCollectionLayoutSection(group: group)
            result.orthogonalScrollingBehavior = .continuous
            result.interGroupSpacing = 8
            // Снизу 2 pt: заголовок секции станций стоит на 2 pt ниже блока над ним (как на «Сегодня»).
            result.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: inset, bottom: 2, trailing: inset)
            return result
        case .nowPlaying:
            let result = list(height: NowPlayingCell.height)
            // Карточка в 20 pt под чипами (2 pt уже даёт секция чипов).
            result.contentInsets = NSDirectionalEdgeInsets(top: 18, leading: inset, bottom: 2, trailing: inset)
            return result
        case .stations:
            let result = list(height: StationRowCell.height)
            result.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: inset, bottom: 0, trailing: inset)
            result.boundarySupplementaryItems = [NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(SectionHeaderView.height)),
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            )]
            return result
        case .status:
            let result = list(height: StatusCell.height)
            result.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: inset, bottom: 0, trailing: inset)
            return result
        }
    }

    private static func list(height: CGFloat) -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
        return NSCollectionLayoutSection(group: group)
    }
}

extension RadioViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        switch dataSource.itemIdentifier(for: indexPath) {
        case let .chip(genre):
            viewModel.didSelectGenre(genre)
        case .nowPlaying:
            viewModel.didTapNowPlaying()
        case let .station(id):
            viewModel.didTapStation(id)
        default:
            break
        }
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        switch dataSource.itemIdentifier(for: indexPath) {
        case .chip, .nowPlaying, .station: true
        default: false
        }
    }
}
