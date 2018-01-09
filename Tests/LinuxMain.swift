import XCTest
@testable import H2SwiftTests

XCTMain([
    testCase(HPACKTests.allTests),
    testCase(FrameTests.allTests)
])
