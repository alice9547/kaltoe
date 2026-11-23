import XCTest
import AppKit
@testable import Kaltoe

final class WidgetPlacementTests: XCTestCase {
    private let main = NSRect(x: 0, y: 0, width: 1440, height: 875)
    private let right = NSRect(x: 1440, y: 100, width: 1920, height: 1080)
    private let size = CGSize(width: 320, height: 150)

    func testFullyInsideIsReachableAndUnchanged() {
        let f = NSRect(origin: NSPoint(x: 100, y: 100), size: size)
        XCTAssertTrue(WidgetPlacement.isReachable(f, areas: [main]))
        XCTAssertEqual(WidgetPlacement.corrected(f, areas: [main]), f)
    }

    func testPartiallyOffscreenWith48OverlapIsLeftAlone() {
        let f = NSRect(x: -272, y: 100, width: 320, height: 150)   // 가로 48 걸침
        XCTAssertTrue(WidgetPlacement.isReachable(f, areas: [main]))
        XCTAssertEqual(WidgetPlacement.corrected(f, areas: [main]), f)
    }

    func testOverlapUnder48IsPushedInside() {
        let f = NSRect(x: -274, y: 100, width: 320, height: 150)   // 가로 46 걸침
        XCTAssertFalse(WidgetPlacement.isReachable(f, areas: [main]))
        XCTAssertEqual(WidgetPlacement.corrected(f, areas: [main]).origin, NSPoint(x: 0, y: 100))
    }

    func testVerticalOverlapUnder48() {
        let f = NSRect(x: 100, y: 875 - 30, width: 320, height: 150)  // 세로 30 걸침
        XCTAssertFalse(WidgetPlacement.isReachable(f, areas: [main]))
        XCTAssertEqual(WidgetPlacement.corrected(f, areas: [main]).maxY, 875)
    }

    func testFarAwayGoesToNearestScreen() {
        let f = NSRect(x: 5000, y: 400, width: 320, height: 150)
        let c = WidgetPlacement.corrected(f, areas: [main, right])
        XCTAssertEqual(c.maxX, right.maxX)
        XCTAssertEqual(c.minY, 400)
        XCTAssertTrue(right.contains(c))
    }

    func testReachableOnSecondScreenUnchanged() {
        let f = NSRect(x: 2000, y: 300, width: 320, height: 150)
        XCTAssertEqual(WidgetPlacement.corrected(f, areas: [main, right]), f)
    }

    func testNoScreensReturnsFrame() {
        let f = NSRect(x: 9, y: 9, width: 320, height: 150)
        XCTAssertEqual(WidgetPlacement.corrected(f, areas: []), f)
    }

    func testTopRightOrigin() {
        let o = WidgetPlacement.topRightOrigin(size: size, area: main)
        XCTAssertEqual(o, NSPoint(x: 1440 - 320 - 16, y: 875 - 150 - 16))
    }

    func testDistanceZeroWhenOverlapping() {
        XCTAssertEqual(WidgetPlacement.distance(NSRect(x: 0, y: 0, width: 10, height: 10),
                                                NSRect(x: 5, y: 5, width: 10, height: 10)), 0)
    }
}
