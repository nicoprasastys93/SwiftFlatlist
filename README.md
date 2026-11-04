# SwiftFlatlist

A `UICollectionView` that works like React Native's `FlatList`: diffable data source, compositional layout, self sizing cells, pull to refresh, pagination, header / footer / empty views and separators.

Requires iOS 15+ / Swift 5.9+. UIKit only, no third-party dependencies.

## Install

Swift Package Manager: add this repo, product `SwiftFlatlist`.

```swift
import SwiftFlatlist
```

## Usage

```swift
let list = FlatList()               // or a collectionView in a xib with Custom Class `FlatList`
list.numColumns = 2
list.itemSpacing = 16
list.columnSpacing = 16
list.contentInsets = .init(top: 16, leading: 16, bottom: 16, trailing: 16)

list.register(cell: VoucherCell.self, fromNib: true) { (cell, voucher: Voucher, indexPath) in
    cell.setup(voucher)
}
list.onRefresh = { reload() }
list.onEndReached = { loadNextPage() }
list.onItemPress = { index, item in ... }

list.listEmpty = EmptyView()
list.setData(vouchers, keyExtractor: { $0.id })
```

In a xib, set the collection view's *Custom Class* to `FlatList` and *Module* to `SwiftFlatlist`.

| RN | FlatList |
| --- | --- |
| `data` | `setData(_:keyExtractor:animated:)` |
| `renderItem` | `register(cell:fromNib:renderItem:)` |
| `keyExtractor` | `setData(_:keyExtractor:)` (a duplicate key keeps the first item) |
| `horizontal` | `horizontal` |
| `numColumns` | `numColumns` (vertical only) |
| - | `itemWidthFraction` (horizontal item width), `maxHeight` (self sizing) |
| `ItemSeparatorComponent` | `itemSpacing` / `columnSpacing` (space), `separatorColor` / `separatorView` (line) |
| `ListHeader/Footer/EmptyComponent` | `listHeader` / `listFooter` / `listEmpty` |
| `onEndReached(+Threshold)` | `onEndReached` / `onEndReachedThreshold` |
| `onRefresh` / `refreshing` | `onRefresh` / `refreshing` |
| `extraData` | `reloadItems()` |
| `scrollToIndex/End/Offset` | same names |

### Self sizing

```swift
list.maxHeight = .greatestFiniteMagnitude   // as tall as its content, the parent scrolls
list.maxHeight = 360                        // as tall as its content, scrolls only past 360pt
```

Do not pin a height to the list while `maxHeight` is set.

### Vertical list

```swift
let list = FlatList()
list.numColumns = 2                 // grid; 1 = plain list
list.itemSpacing = 16               // between rows
list.columnSpacing = 16             // between columns
list.onRefresh = { reload() }       // pull to refresh (vertical only)
list.onEndReached = { loadNextPage() }
list.setData(items, keyExtractor: { $0.id })
```

Give the list a height from its parent (constraints), or let it be as tall as its content with `maxHeight` (see Self sizing above).

### Horizontal list

```swift
let list = FlatList()
list.horizontal = true
list.itemSpacing = 12               // between items
list.itemWidthFraction = 0.5        // each item is half the list width; nil = width from the cell's Auto Layout
list.contentInsets = .init(top: 0, leading: 16, bottom: 0, trailing: 16)
list.register(cell: ProductCell.self) { (cell, product: Product, _) in cell.setup(product) }
list.setData(products, keyExtractor: { $0.id })
```

Two ways to size the height:

```swift
// 1. Fill the height the parent gives (constraints): the default
list.heightAnchor.constraint(equalToConstant: 200).isActive = true

// 2. Fit the content: height = tallest item, scrolls sideways only. Do not pin a height.
list.maxHeight = .greatestFiniteMagnitude   // or a number to cap the height
```

Header, footer, pagination loader and `listEmpty` work in both directions. `numColumns`, `onRefresh` and separators are for vertical lists only. `itemWidthFraction` is measured against the list width without subtracting `itemSpacing`; use `contentInsets` to fine tune.

### Separators

```swift
list.separatorColor = .lightGray            // a line under every item, none after the last one
list.separatorView = { MyDashedLine() }     // or any view, one instance per item
list.separatorOnLastItem = true             // also after the last item
```

### Pagination spinner

```swift
list.setPaginationLoading(state.isFetchingNextPage)
```

The spinner color defaults to `FlatList.paginationLoadingColor`. Set it once at launch:

```swift
FlatList.paginationLoadingColor = { .color_company }
```

## Notes

- Items are `Any`. Cells are reconfigured (not replaced) when `setData` receives an item with a known key, so content changes are picked up.
- `setData` can be called from inside `onEndReached`; a nested apply is queued, never run underneath another one.
- `register` can be called again to switch cell type (e.g. grid <-> list); call `setData([])` first so a reused cell of the old type is not reconfigured.
