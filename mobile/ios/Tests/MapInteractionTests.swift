import XCTest
@testable import Hrafnsyn

final class MapInteractionTests: XCTestCase {
    func testDenseSelectionRemainsAtItsOwnPositionWithClearNeighbors() {
        let points: [CGPoint] = [.init(x: 0, y: 0), .init(x: 20, y: 0),
                                 .init(x: 70, y: 0), .init(x: 150, y: 0), .init(x: 200, y: 0)]
        let groups = MapClustering.groups(points, clearance: 80, anchoredIndex: 0)
        XCTAssertEqual(groups.flatMap { $0 }.sorted(), Array(points.indices))
        let selectedGroup = groups.first { $0.contains(0) }!
        XCTAssertEqual(selectedGroup.sorted(), [0, 1, 2])
        for group in groups where !group.contains(0) {
            let center = CGPoint(x: group.map { points[$0].x }.reduce(0, +) / CGFloat(group.count),
                                 y: group.map { points[$0].y }.reduce(0, +) / CGFloat(group.count))
            XCTAssertGreaterThanOrEqual(hypot(center.x - points[0].x, center.y - points[0].y), 80)
        }
    }

    func testNeighboringClustersRemainDistinctAndPreserveEveryContact() {
        // Contacts straddle old grid boundaries; merging also moves a centroid
        // close enough to another group to require a second collision pass.
        let points: [CGPoint] = [CGPoint(x: 48, y: 0), CGPoint(x: 52, y: 0),
                                 CGPoint(x: 99, y: 0), CGPoint(x: 101, y: 0),
                                 CGPoint(x: 180, y: 0), CGPoint(x: 182, y: 0)]
        for clearance: CGFloat in [58, 80] {
            let groups = MapClustering.groups(points, clearance: clearance)
            XCTAssertEqual(groups.flatMap { $0 }.sorted(), Array(points.indices))
            XCTAssertLessThan(groups.count, points.count)
            let centers = groups.map { indices in
                CGPoint(x: indices.map { points[$0].x }.reduce(0, +) / CGFloat(indices.count),
                        y: indices.map { points[$0].y }.reduce(0, +) / CGFloat(indices.count))
            }
            for first in centers.indices {
                for second in (first + 1)..<centers.count {
                    XCTAssertGreaterThanOrEqual(hypot(centers[first].x - centers[second].x,
                                                     centers[first].y - centers[second].y), clearance)
                }
            }
        }
    }

    @MainActor func testDismissalAllowsSelectingTheSameContactAgain() async {
        let model = AppModel()
        await model.select("same-contact")
        XCTAssertEqual(model.selectedID, "same-contact")
        model.loadingDetails = true
        // Both Done and interactive dismissal invoke this synchronous callback.
        model.dismissSelection()
        XCTAssertNil(model.selectedID)
        XCTAssertFalse(model.loadingDetails)
        XCTAssertNil(model.details)
        await model.select("same-contact")
        XCTAssertEqual(model.selectedID, "same-contact")
    }
}
