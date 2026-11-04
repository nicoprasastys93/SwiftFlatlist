//
//  FlatList.swift
//  SwiftFlatlist
//
//  A UICollectionView that works like React Native's FlatList.
//
//  Usage:
//      let list = FlatList()
//      list.register(cell: VoucherCell.self) { (cell, voucher: Voucher, indexPath) in
//          cell.setup(voucher)
//      }
//      list.numColumns = 2
//      list.itemSpacing = 12
//      list.listHeader = headerView
//      list.listEmpty = emptyView
//      list.onEndReached = { loadNextPage() }
//      list.onRefresh = { reload() }
//      list.onItemPress = { index, item in ... }
//      list.maxHeight = 360   // self sizing: as tall as its content, scrolls only past 360pt
//      list.separatorColor = .lightGray   // a line between the items, none after the last one
//      list.separatorView = { MySeparator() }   // or any view, one instance per item
//      list.separatorOnLastItem = true          // also after the last item (default: hidden)
//      list.setData(vouchers, keyExtractor: { $0.id })
//
//  RN prop        -> FlatList
//  data           -> setData(_:keyExtractor:animated:)
//  renderItem     -> register(cell:fromNib:renderItem:)
//  keyExtractor   -> setData(_:keyExtractor:)
//  horizontal     -> horizontal
//  numColumns     -> numColumns (vertical only)
//  (no RN equivalent) -> itemWidthFraction: horizontal item width, 0.5 = half the list
//  ItemSeparator  -> itemSpacing / columnSpacing (space), separatorColor (line)
//  ListHeader/ListFooter/ListEmpty -> listHeader / listFooter / listEmpty
//  onEndReached(+Threshold) -> onEndReached / onEndReachedThreshold
//  onRefresh/refreshing -> onRefresh / refreshing
//  extraData      -> reloadItems()
//  scrollToIndex/scrollToEnd/scrollToOffset -> same names
//  (no RN equivalent) -> maxHeight: self sizing like SelfSizingCollectionView, scroll turns on at the cap
//

import UIKit

public final class FlatList: UICollectionView {

    // MARK: - Defaults
    /// Color of the spinner shown by `setPaginationLoading` when no color is passed.
    /// A closure, so a dynamic app color is read when the spinner is built. Set it once at launch:
    ///     FlatList.paginationLoadingColor = { .color_company }
    public static var paginationLoadingColor: () -> UIColor = { .systemGray }

    // MARK: - Props
    /// Scroll direction. A horizontal list needs a height from its parent (like RN).
    public var horizontal: Bool = false { didSet { updateLayout(); updateSelfSizing() } }
    /// Item width as a fraction of the list width (0...1], horizontal lists only. 0.5 = two items per screen.
    /// `nil` (default): the width comes from the cell's Auto Layout (`estimatedItemSize` is the first guess).
    public var itemWidthFraction: CGFloat? { didSet { updateLayout() } }
    /// Number of columns (vertical lists only).
    public var numColumns: Int = 1 { didSet { numColumns = max(1, numColumns); updateLayout() } }
    /// Space between rows (vertical) or between items (horizontal). RN: ItemSeparatorComponent.
    public var itemSpacing: CGFloat = 0 { didSet { updateLayout() } }
    /// Space between columns when `numColumns > 1`.
    public var columnSpacing: CGFloat = 0 { didSet { updateLayout() } }
    /// Estimated item length on the scroll axis. Items always size themselves with Auto Layout.
    public var estimatedItemSize: CGFloat = 100 { didSet { updateLayout() } }
    /// RN: contentContainerStyle padding.
    public var contentInsets: NSDirectionalEdgeInsets = .zero { didSet { updateLayout() } }
    /// RN: ItemSeparatorComponent. A plain line, drawn at the bottom edge of every item except the last one.
    /// `nil` (default) draws nothing (unless `separatorView` is set).
    public var separatorColor: UIColor? { didSet { separatorChanged() } }
    /// Thickness of the plain separator line.
    public var separatorHeight: CGFloat = 1 { didSet { separatorChanged() } }
    /// RN: ItemSeparatorComponent with any view. A factory, because every item needs its own instance.
    /// Takes over from `separatorColor` / `separatorHeight`. The view sits at the bottom edge of the item,
    /// its height comes from its own constraints / intrinsic size (give it one).
    ///     list.separatorView = { let line = MyDashedLine(); return line }
    public var separatorView: (() -> UIView)? { didSet { separatorChanged() } }
    /// `false` (default): the last item has no separator. `true`: it gets one too.
    /// Applies to both the plain line and `separatorView`.
    public var separatorOnLastItem: Bool = false { didSet { reloadItems() } }

    /// Self sizing. When set, the list is as tall as its content (like `SelfSizingCollectionView`) and only
    /// scrolls once the content is taller than this value. `nil` (default) keeps the normal behaviour:
    /// the list fills the height its parent gives it and always scrolls.
    /// Do not pin a height to the list while this is set, its intrinsic height is the size.
    /// Horizontal lists: the height is the tallest item (items size their own height), capped at this value;
    /// the list keeps scrolling sideways.
    public var maxHeight: CGFloat? {
        didSet {
            if horizontal { updateLayout() }  // item height switches between "fill the list" and "fit the cell"
            if maxHeight != nil {
                // inside a stack view spare height goes to the lowest hugging priority: stay at the content height
                setContentHuggingPriority(.required, for: .vertical)
                setContentCompressionResistancePriority(.required, for: .vertical)
            }
            updateSelfSizing()
        }
    }

    /// RN: ListHeaderComponent. Sized by Auto Layout.
    public var listHeader: UIView? { didSet { updateLayout() } }
    /// RN: ListFooterComponent. Sized by Auto Layout.
    public var listFooter: UIView? { didSet { updateLayout() } }
    /// RN: ListEmptyComponent. Shown while `data` is empty.
    public var listEmpty: UIView? {
        didSet {
            if backgroundView === oldValue { backgroundView = nil }
            updateEmptyView()
        }
    }

    /// RN: onEndReached. Fired once per content length.
    public var onEndReached: (() -> Void)?
    /// RN: onEndReachedThreshold, in visible lengths from the end (0.5 = half a screen).
    public var onEndReachedThreshold: CGFloat = 0.5
    /// RN: onRefresh. Setting it adds pull to refresh (vertical lists).
    public var onRefresh: (() -> Void)? {
        didSet {
            if onRefresh != nil, refreshControl == nil {
                let control = UIRefreshControl()
                control.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
                refreshControl = control
            } else if onRefresh == nil {
                refreshControl = nil
            }
        }
    }
    /// RN: refreshing.
    public var refreshing: Bool {
        get { refreshControl?.isRefreshing ?? false }
        set {
            guard let control = refreshControl, control.isRefreshing != newValue else { return }
            if newValue { control.beginRefreshing() } else { control.endRefreshing() }
        }
    }
    /// Item tapped. RN: Pressable inside renderItem.
    public var onItemPress: ((_ index: Int, _ item: Any) -> Void)?
    /// RN: onScroll.
    public var onScroll: ((UIScrollView) -> Void)?

    // MARK: - Data
    private struct Row: Hashable {
        let key: AnyHashable
        let value: Any
        static func == (lhs: Row, rhs: Row) -> Bool { lhs.key == rhs.key }
        func hash(into hasher: inout Hasher) { hasher.combine(key) }
    }

    private var rows: [Row] = []
    private var renderer: ((UICollectionView, IndexPath, Any) -> UICollectionViewCell)?
    private var diffable: UICollectionViewDiffableDataSource<Int, Row>!
    private var lastEndReachedContentLength: CGFloat = -1
    private var isApplyingSnapshot = false
    private var needsReapply = false
    private var paginationLoadingRequested = false

    /// Current data as passed to `setData`.
    public var data: [Any] { rows.map { $0.value } }

    // MARK: - Init
    public init() {
        super.init(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        commonInit()
    }

    public override init(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout) {
        super.init(frame: frame, collectionViewLayout: layout)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .clear
        alwaysBounceVertical = true
        delegate = self

        register(
            FlatListSupplementaryView.self,
            forSupplementaryViewOfKind: FlatListSupplementaryView.headerKind,
            withReuseIdentifier: FlatListSupplementaryView.reuseIdentifier
        )
        register(
            FlatListSupplementaryView.self,
            forSupplementaryViewOfKind: FlatListSupplementaryView.footerKind,
            withReuseIdentifier: FlatListSupplementaryView.reuseIdentifier
        )

        diffable = UICollectionViewDiffableDataSource<Int, Row>(collectionView: self) { [weak self] collectionView, indexPath, _ in
            // Render from our own array so content changes with an unchanged key are picked up.
            guard let self, let renderer = self.renderer, indexPath.item < self.rows.count else {
                return UICollectionViewCell()
            }
            return renderer(collectionView, indexPath, self.rows[indexPath.item].value)
        }
        diffable.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            let view = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: FlatListSupplementaryView.reuseIdentifier,
                for: indexPath
            ) as? FlatListSupplementaryView
            view?.setContent(kind == FlatListSupplementaryView.headerKind ? self?.listHeader : self?.listFooter)
            return view
        }

        updateLayout()
    }

    // MARK: - renderItem
    /// RN: renderItem. Registers the cell class (or nib named like the class) and how to fill it.
    public func register<Item, Cell: UICollectionViewCell>(
        cell: Cell.Type,
        fromNib: Bool = false,
        renderItem: @escaping (_ cell: Cell, _ item: Item, _ indexPath: IndexPath) -> Void
    ) {
        let identifier = String(describing: Cell.self)
        if fromNib {
            register(UINib(nibName: identifier, bundle: Bundle(for: Cell.self)), forCellWithReuseIdentifier: identifier)
        } else {
            register(Cell.self, forCellWithReuseIdentifier: identifier)
        }
        renderer = { [weak self] collectionView, indexPath, value in
            guard
                let item = value as? Item,
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: identifier, for: indexPath) as? Cell
            else { return UICollectionViewCell() }
            renderItem(cell, item, indexPath)
            self?.applySeparator(to: cell, at: indexPath)
            return cell
        }
    }

    // MARK: - Separator
    private static let separatorTag = 0xF1A7
    /// Cells are reused: a separator built for an older configuration is rebuilt when this changed.
    private var separatorGeneration = 0

    private final class SeparatorContainerView: UIView {
        var generation = 0
    }

    private func separatorChanged() {
        separatorGeneration += 1
        reloadItems()
    }

    /// A container owned by the list (not by the cell) at the bottom of the cell's content, hidden on the last item.
    /// Existing items are reconfigured on every `setData`, so the old last item gets its separator back when more items arrive.
    private func applySeparator(to cell: UICollectionViewCell, at indexPath: IndexPath) {
        var container = cell.contentView.viewWithTag(Self.separatorTag) as? SeparatorContainerView
        guard separatorColor != nil || separatorView != nil else {
            container?.isHidden = true
            return
        }
        if let existing = container, existing.generation != separatorGeneration {
            existing.removeFromSuperview()
            container = nil
        }
        if container == nil {
            let view = SeparatorContainerView()
            view.generation = separatorGeneration
            view.tag = Self.separatorTag
            view.isUserInteractionEnabled = false
            view.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(view)
            view.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor).isActive = true
            view.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor).isActive = true
            view.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor).isActive = true
            if let custom = separatorView?() {
                custom.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(custom)
                custom.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
                custom.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
                custom.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
                custom.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
            } else {
                view.heightAnchor.constraint(equalToConstant: separatorHeight).isActive = true
            }
            container = view
        }
        if separatorView == nil { container?.backgroundColor = separatorColor }
        container?.isHidden = !separatorOnLastItem && indexPath.item >= rows.count - 1
        if let container { cell.contentView.bringSubviewToFront(container) }
    }

    // MARK: - data
    /// RN: data + keyExtractor. Items with a duplicate key are ignored (keeps the first).
    public func setData<Item>(
        _ data: [Item],
        keyExtractor: (Item) -> AnyHashable,
        animated: Bool = true
    ) {
        var seen = Set<AnyHashable>()
        rows = data.compactMap { item in
            let key = keyExtractor(item)
            return seen.insert(key).inserted ? Row(key: key, value: item) : nil
        }
        applyRows(animated: animated)
    }

    /// RN: data, when the item itself is its key.
    public func setData<Item: Hashable>(_ data: [Item], animated: Bool = true) {
        setData(data, keyExtractor: { $0 }, animated: animated)
    }

    /// RN: extraData. Re-renders every visible/existing item without changing data.
    public func reloadItems() {
        var snapshot = diffable.snapshot()
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        diffable.apply(snapshot, animatingDifferences: false)
    }

    private func applyRows(animated: Bool) {
        // Applying a snapshot can scroll / re-layout and fire callbacks (onEndReached) that call setData again.
        // A nested apply deadlocks the diffable data source, so queue it and re-run once the current one is done.
        guard !isApplyingSnapshot else {
            needsReapply = true
            return
        }
        isApplyingSnapshot = true

        let old = Set(diffable.snapshot().itemIdentifiers)
        var snapshot = NSDiffableDataSourceSnapshot<Int, Row>()
        snapshot.appendSections([0])
        snapshot.appendItems(rows)
        // Same key, maybe new content: reconfigure instead of delete + insert.
        snapshot.reconfigureItems(rows.filter { old.contains($0) })
        diffable.apply(snapshot, animatingDifferences: animated && window != nil) { [weak self] in
            guard let self else { return }
            self.isApplyingSnapshot = false
            self.updateEmptyView()
            if self.needsReapply {
                self.needsReapply = false
                self.applyRows(animated: false)
            }
        }
        updateEmptyView()
    }

    /// Only touches `backgroundView` for `listEmpty`, so an owner-provided background (e.g. a skeleton) is kept.
    private func updateEmptyView() {
        if rows.isEmpty {
            if let listEmpty { backgroundView = listEmpty }
        } else if backgroundView != nil, backgroundView === listEmpty {
            backgroundView = nil
        }
        if maxHeight != nil { invalidateIntrinsicContentSize() }
    }

    // MARK: - Self sizing
    private var lastIntrinsicHeight: CGFloat = -1

    public override var contentSize: CGSize {
        didSet {
            guard maxHeight != nil, oldValue.height != contentSize.height else { return }
            updateSelfSizing()
        }
    }

    public override var intrinsicContentSize: CGSize {
        guard let maxHeight else { return super.intrinsicContentSize }
        let height = min(selfSizingContentHeight(), maxHeight)
        lastIntrinsicHeight = height
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    private func selfSizingContentHeight() -> CGFloat {
        if rows.isEmpty {
            // only the empty view is shown, its height drives the size
            guard let listEmpty, bounds.width > 0 else { return 0 }
            let size = listEmpty.systemLayoutSizeFitting(
                CGSize(width: bounds.width, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            )
            return ceil(size.height)
        }
        // A collection view with zero height never lays out, so its content size stays 0 and it can never grow.
        // Keep at least 1pt while there are rows; the real height replaces it after the next layout pass.
        return max(collectionViewLayout.collectionViewContentSize.height, 1)
    }

    private func updateSelfSizing() {
        guard let maxHeight else {
            isScrollEnabled = true
            invalidateIntrinsicContentSize()
            return
        }
        // vertical: scroll only turns on at the highest point. Horizontal always scrolls sideways.
        let shouldScroll = horizontal || collectionViewLayout.collectionViewContentSize.height > maxHeight + 0.5
        if isScrollEnabled != shouldScroll { isScrollEnabled = shouldScroll }
        invalidateIntrinsicContentSize()
        // a list that is not scrolling (yet) still has to be able to ask for the next page
        DispatchQueue.main.async { [weak self] in self?.checkEndReached() }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard let maxHeight else { return }
        // width / cell heights settle after layout: report again when the wanted height moved
        if min(selfSizingContentHeight(), maxHeight) != lastIntrinsicHeight { updateSelfSizing() }
    }

    // MARK: - Layout
    private func updateLayout() {
        collectionViewLayout = makeLayout()
        alwaysBounceVertical = !horizontal
        alwaysBounceHorizontal = horizontal
    }

    /// First guess for the cross axis length (height of a horizontal item) before the cell measured itself.
    private static let estimatedCrossSize: CGFloat = 100

    private func makeLayout() -> UICollectionViewLayout {
        let estimate = estimatedItemSize
        let item: NSCollectionLayoutItem
        let group: NSCollectionLayoutGroup

        if horizontal {
            // Self sizing: the height follows the tallest cell. Otherwise it fills the height the parent gives.
            let height: NSCollectionLayoutDimension = maxHeight != nil ? .estimated(Self.estimatedCrossSize) : .fractionalHeight(1)
            if let fraction = itemWidthFraction {
                let width = NSCollectionLayoutDimension.fractionalWidth(min(max(fraction, 0.01), 1))
                item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: height))
                group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: width, heightDimension: height), subitems: [item])
            } else {
                item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .estimated(estimate), heightDimension: height))
                group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .estimated(estimate), heightDimension: height), subitems: [item])
            }
        } else {
            item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1.0 / CGFloat(numColumns)), heightDimension: .estimated(estimate)))
            let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(estimate))
            if numColumns > 1 {
                if #available(iOS 16.0, *) {
                    group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, repeatingSubitem: item, count: numColumns)
                } else {
                    group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitem: item, count: numColumns)
                }
                group.interItemSpacing = .fixed(columnSpacing)
            } else {
                group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])
            }
        }

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = contentInsets
        section.interGroupSpacing = itemSpacing

        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.scrollDirection = horizontal ? .horizontal : .vertical

        let boundarySize = horizontal
            ? NSCollectionLayoutSize(widthDimension: .estimated(44), heightDimension: maxHeight != nil ? .estimated(44) : .fractionalHeight(1))
            : NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44))
        var boundaries: [NSCollectionLayoutBoundarySupplementaryItem] = []
        if listHeader != nil {
            boundaries.append(NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: boundarySize,
                elementKind: FlatListSupplementaryView.headerKind,
                alignment: horizontal ? .leading : .top
            ))
        }
        if listFooter != nil {
            boundaries.append(NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: boundarySize,
                elementKind: FlatListSupplementaryView.footerKind,
                alignment: horizontal ? .trailing : .bottom
            ))
        }
        configuration.boundarySupplementaryItems = boundaries

        return UICollectionViewCompositionalLayout(section: section, configuration: configuration)
    }

    // MARK: - Pagination loader
    /// Shows / hides a spinner as `listFooter` while the next page loads.
    /// Only touches the footer when it changes, because setting it rebuilds the layout.
    public func setPaginationLoading(_ isLoading: Bool, color: UIColor = FlatList.paginationLoadingColor()) {
        paginationLoadingRequested = isLoading
        // Changing the footer rebuilds the layout; never do it underneath a scroll / snapshot callback.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let loading = self.paginationLoadingRequested
            guard loading != (self.listFooter != nil) else { return }
            guard loading else {
                self.listFooter = nil
                return
            }

            let container = UIView()
            container.translatesAutoresizingMaskIntoConstraints = false
            container.heightAnchor.constraint(equalToConstant: 44).isActive = true

            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.color = color
            indicator.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(indicator)
            NSLayoutConstraint.activate([
                indicator.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                indicator.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])
            indicator.startAnimating()
            self.listFooter = container
        }
    }

    // MARK: - Scroll
    /// RN: scrollToIndex.
    public func scrollToIndex(_ index: Int, animated: Bool = true) {
        guard rows.indices.contains(index) else { return }
        scrollToItem(
            at: IndexPath(item: index, section: 0),
            at: horizontal ? .centeredHorizontally : .top,
            animated: animated
        )
    }

    /// RN: scrollToEnd.
    public func scrollToEnd(animated: Bool = true) {
        layoutIfNeeded()
        let offset = horizontal
            ? CGPoint(x: max(-adjustedContentInset.left, contentSize.width - bounds.width + adjustedContentInset.right), y: contentOffset.y)
            : CGPoint(x: contentOffset.x, y: max(-adjustedContentInset.top, contentSize.height - bounds.height + adjustedContentInset.bottom))
        setContentOffset(offset, animated: animated)
    }

    /// RN: scrollToOffset.
    public func scrollToOffset(_ offset: CGFloat, animated: Bool = true) {
        setContentOffset(horizontal ? CGPoint(x: offset, y: contentOffset.y) : CGPoint(x: contentOffset.x, y: offset), animated: animated)
    }

    @objc private func handleRefresh() {
        onRefresh?()
    }

    private func checkEndReached() {
        guard onEndReached != nil, !rows.isEmpty else { return }
        let contentLength = horizontal ? contentSize.width : contentSize.height
        let visibleLength = horizontal ? bounds.width : bounds.height
        let offset = horizontal ? contentOffset.x : contentOffset.y
        guard contentLength > 0, visibleLength > 0 else { return }

        let distanceFromEnd = contentLength - visibleLength - offset
        if distanceFromEnd <= onEndReachedThreshold * visibleLength {
            // once per content length, like RN
            guard lastEndReachedContentLength != contentLength else { return }
            lastEndReachedContentLength = contentLength
            onEndReached?()
        } else if distanceFromEnd > onEndReachedThreshold * visibleLength {
            // scrolled away from the end, allow it to fire again for the same length
            lastEndReachedContentLength = -1
        }
    }
}

// MARK: - UICollectionViewDelegate
extension FlatList: UICollectionViewDelegate {
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard rows.indices.contains(indexPath.item) else { return }
        onItemPress?(indexPath.item, rows[indexPath.item].value)
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        onScroll?(scrollView)
        checkEndReached()
    }
}

// MARK: - Header / footer container
private final class FlatListSupplementaryView: UICollectionReusableView {
    static let reuseIdentifier = "FlatListSupplementaryView"
    static let headerKind = "FlatListHeader"
    static let footerKind = "FlatListFooter"

    private weak var content: UIView?

    func setContent(_ view: UIView?) {
        guard content !== view else { return }
        content?.removeFromSuperview()
        content = view
        guard let view else { return }
        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}
