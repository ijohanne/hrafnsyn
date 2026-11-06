import XCTest
import MapKit
@testable import Hrafnsyn

final class MapInteractionTests: XCTestCase {
    func testSheetOverlapDoesNotCountMapFooterTwice() throws {
        // Observed accessibility landscape: Map excludes the 74.9pt status/home
        // footer, while the 220pt detent sits above the 21pt home safe area.
        let covered = RouteCamera.coveredHeight(sheetHeight: 220, containerBottomInset: 21, mapBottomInset: 74.9)
        XCTAssertEqual(covered, 166.1, accuracy: 0.001)
        let viewport = CGSize(width: 750, height: 249.1)
        let route = [CLLocationCoordinate2D(latitude: 36.2, longitude: -6.1),
                     CLLocationCoordinate2D(latitude: 36.4, longitude: -5.9)]
        let rect = try XCTUnwrap(RouteCamera.rect(coordinates: route, viewport: viewport, coveredBottom: covered))
        for coordinate in route {
            let y = (MKMapPoint(coordinate).y - rect.minY) / rect.height * viewport.height
            XCTAssertGreaterThan(y, 0)
            XCTAssertLessThan(y, viewport.height - covered)
        }
        XCTAssertEqual(RouteCamera.coveredHeight(sheetHeight: 30, containerBottomInset: 21, mapBottomInset: 74.9), 0)
    }

    func testRouteFitsAbovePhonePanelInPortraitAndLandscape() throws {
        let route = [CLLocationCoordinate2D(latitude: 37, longitude: -4),
                     CLLocationCoordinate2D(latitude: 38.5, longitude: -2)]
        for viewport in [CGSize(width: 390, height: 740), CGSize(width: 844, height: 320)] {
            for coveredBottom: CGFloat in [234, 300, 334] {
                if coveredBottom >= viewport.height {
                    XCTAssertNil(RouteCamera.rect(coordinates: route, viewport: viewport, coveredBottom: coveredBottom))
                    continue
                }
                let rect = try XCTUnwrap(RouteCamera.rect(coordinates: route, viewport: viewport, coveredBottom: coveredBottom))
                let visibleHeight = viewport.height - coveredBottom
                let verticalPadding = min(36, visibleHeight / 4)
                for coordinate in route {
                    let point = MKMapPoint(coordinate)
                    let x = (point.x - rect.minX) / rect.width * viewport.width
                    let y = (point.y - rect.minY) / rect.height * viewport.height
                    XCTAssertGreaterThanOrEqual(x, 35.99)
                    XCTAssertLessThanOrEqual(x, viewport.width - 35.99)
                    XCTAssertGreaterThanOrEqual(y, verticalPadding - 0.01)
                    XCTAssertLessThanOrEqual(y, visibleHeight - verticalPadding + 0.01)
                }
            }
        }
    }

    func testIPadFitCentersRouteInUncoveredMap() throws {
        let point = CLLocationCoordinate2D(latitude: 55, longitude: 12)
        let viewport = CGSize(width: 700, height: 900)
        let rect = try XCTUnwrap(RouteCamera.rect(coordinates: [point], viewport: viewport, coveredBottom: 0))
        XCTAssertEqual(rect.midX, MKMapPoint(point).x, accuracy: 0.001)
        XCTAssertEqual(rect.midY, MKMapPoint(point).y, accuracy: 0.001)
        XCTAssertGreaterThan(rect.width, 0)
        XCTAssertEqual(rect.width / rect.height, viewport.width / viewport.height, accuracy: 0.001)
    }

    func testDatelineRouteDoesNotZoomOutToTheWholeWorld() throws {
        let route = [CLLocationCoordinate2D(latitude: 10, longitude: 179.9),
                     CLLocationCoordinate2D(latitude: 10.1, longitude: -179.9)]
        let rect = try XCTUnwrap(RouteCamera.rect(coordinates: route, viewport: CGSize(width: 390, height: 740), coveredBottom: 234))
        XCTAssertLessThan(rect.width, MKMapRect.world.width / 100)
    }

    func testEmptyOrInvalidRouteDoesNotProduceCamera() {
        let viewport = CGSize(width: 390, height: 740)
        XCTAssertNil(RouteCamera.rect(coordinates: [], viewport: viewport, coveredBottom: 234))
        XCTAssertNil(RouteCamera.rect(coordinates: [.init(latitude: .nan, longitude: 0)], viewport: viewport, coveredBottom: 234))
        XCTAssertNil(RouteCamera.rect(coordinates: [.init(latitude: 0, longitude: 0)], viewport: .zero, coveredBottom: 234))
    }

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
