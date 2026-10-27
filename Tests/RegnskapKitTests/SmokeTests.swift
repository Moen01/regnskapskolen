import XCTest
@testable import RegnskapKit

final class SmokeTests: XCTestCase {
    func testKitLoads() {
        XCTAssertEqual(RegnskapKit.version, "0.1.0")
    }
}
