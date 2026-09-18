import XCTest
@testable import OtterStatsCore

final class SemanticVersionTests: XCTestCase {
    func testParsing() {
        XCTAssertEqual(SemanticVersion("v0.1.1"), SemanticVersion(major: 0, minor: 1, patch: 1))
        XCTAssertEqual(SemanticVersion("1.2.3-beta.2+build9"), SemanticVersion(major: 1, minor: 2, patch: 3, prerelease: ["beta", "2"]))
        XCTAssertNil(SemanticVersion("1.2"))
        XCTAssertNil(SemanticVersion("abc"))
        XCTAssertNil(SemanticVersion("1.2.x"))
        XCTAssertNil(SemanticVersion("1.2.3-"))
        XCTAssertNil(SemanticVersion("1.2.3-alpha..1"))
        XCTAssertNil(SemanticVersion("01.2.3"))
        XCTAssertNil(SemanticVersion("1.2.3-beta.01"))
        XCTAssertNil(SemanticVersion("1.2.3-bęta"))
        XCTAssertNotNil(SemanticVersion("1.2.3-rc-1.0"))
    }

    func testOrdering() {
        let v = { (s: String) in SemanticVersion(s)! }
        XCTAssertLessThan(v("0.1.0"), v("0.1.1"))
        XCTAssertLessThan(v("0.9.9"), v("1.0.0"))
        XCTAssertLessThan(v("1.0.0-beta.1"), v("1.0.0"))
        XCTAssertLessThan(v("1.0.0-beta.1"), v("1.0.0-beta.2"))
        XCTAssertLessThan(v("1.0.0-alpha"), v("1.0.0-alpha.1"))
        XCTAssertFalse(v("v1.2.3") < v("1.2.3"))
        XCTAssertEqual(v("1.2.3-rc.1").description, "1.2.3-rc.1")
    }
}
