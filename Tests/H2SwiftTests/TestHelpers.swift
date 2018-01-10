//
//  TestHelpers.swift
//  H2SwiftTests
//
//  Created by Jim Dovey on 1/10/18.
//

import XCTest

func XCTAssertEqualTuple<T1: Equatable, T2: Equatable>(_ expression1: @autoclosure () throws -> (T1, T2), _ expression2: @autoclosure () throws -> (T1, T2), _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    let ex1: (T1, T2)
    let ex2: (T1, T2)
    do {
        ex1 = try expression1()
        ex2 = try expression2()
    }
    catch {
        XCTFail("Unexpected exception: \(error) \(message())", file: file, line: line)
        return
    }
    
    XCTAssertEqual(ex1.0, ex2.0, message(), file: file, line: line)
    XCTAssertEqual(ex1.1, ex2.1, message(), file: file, line: line)
}
