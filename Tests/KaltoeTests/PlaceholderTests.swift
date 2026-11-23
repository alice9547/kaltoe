import XCTest
@testable import Kaltoe

final class PlaceholderTests: XCTestCase {
    func testWaitingSnapshot() {
        XCTAssertEqual(WorkdaySnapshot.waiting().phase, .waiting)
    }
}
