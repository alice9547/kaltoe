import XCTest
@testable import Kaltoe

final class HandoffTests: XCTestCase {
    func testVersionCompare() {
        XCTAssertEqual(Handoff.compare("1.1.0", "1.1.1"), .orderedAscending)
        XCTAssertEqual(Handoff.compare("1.10.0", "1.9.9"), .orderedDescending)
        XCTAssertEqual(Handoff.compare("1.1", "1.1.0"), .orderedSame)
        XCTAssertEqual(Handoff.compare("2.0.0", "1.99.99"), .orderedDescending)
    }

    func testVersionReadsOnlyKaltoeBundles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let contents = dir.appendingPathComponent("Kaltoe.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let plist = contents.appendingPathComponent("Info.plist")

        NSDictionary(dictionary: ["CFBundleIdentifier": "dev.kaltoe.app", "CFBundleShortVersionString": "1.1.0"]).write(to: plist, atomically: true)
        XCTAssertEqual(Handoff.version(ofBundleAt: dir.appendingPathComponent("Kaltoe.app")), "1.1.0")

        NSDictionary(dictionary: ["CFBundleIdentifier": "com.other.app", "CFBundleShortVersionString": "0.1"]).write(to: plist, atomically: true)
        XCTAssertNil(Handoff.version(ofBundleAt: dir.appendingPathComponent("Kaltoe.app")))
    }
}
