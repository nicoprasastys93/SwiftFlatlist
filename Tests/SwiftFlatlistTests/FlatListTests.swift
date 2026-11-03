import XCTest
import UIKit
@testable import SwiftFlatlist

final class FlatListTests: XCTestCase {
    private final class TitleCell: UICollectionViewCell {
        let label = UILabel()
        override init(frame: CGRect) {
            super.init(frame: frame)
            label.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(label)
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: contentView.topAnchor),
                label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
            ])
        }
        required init?(coder: NSCoder) { fatalError() }
    }

    private func makeList() -> FlatList {
        let list = FlatList()
        list.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        list.register(cell: TitleCell.self) { (cell, item: String, _) in
            cell.label.text = item
        }
        return list
    }

    func testSetDataKeepsTheFirstOfDuplicateKeys() {
        let list = makeList()
        list.setData(["a", "b", "a"], animated: false)
        XCTAssertEqual(list.data.compactMap { $0 as? String }, ["a", "b"])
    }

    func testKeyExtractorDecidesIdentity() {
        let list = makeList()
        list.setData([(1, "x"), (1, "y"), (2, "z")], keyExtractor: { $0.0 }, animated: false)
        XCTAssertEqual(list.data.count, 2)
    }

    func testNumColumnsNeverDropsBelowOne() {
        let list = makeList()
        list.numColumns = 0
        XCTAssertEqual(list.numColumns, 1)
    }

    func testListEmptyShowsOnlyWhileThereIsNoData() {
        let list = makeList()
        let empty = UIView()
        list.listEmpty = empty
        XCTAssertTrue(list.backgroundView === empty)
        list.setData(["a"], animated: false)
        XCTAssertNil(list.backgroundView)
    }

    func testRefreshControlFollowsOnRefresh() {
        let list = makeList()
        XCTAssertNil(list.refreshControl)
        list.onRefresh = {}
        XCTAssertNotNil(list.refreshControl)
        list.onRefresh = nil
        XCTAssertNil(list.refreshControl)
    }
}
