import XCTest
@testable import H2Swift

class H2SwiftTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(H2Swift().text, "Hello, World!")
    }


    static var allTests = [
        ("testExample", testExample),
    ]
}
