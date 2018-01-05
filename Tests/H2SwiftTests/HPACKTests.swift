//
//  HPACKTests.swift
//  H2SwiftTests
//
//  Created by Jim Dovey on 1/3/18.
//

import XCTest
@testable import H2Swift

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

class HPACKTests: XCTestCase {
    
    private func encodeInteger(_ value: UInt, prefix: Int) -> Data {
        var data = Data(count: 11)
        data.withUnsafeMutableBytes { (ptr: UnsafeMutablePointer<UInt8>) -> Void in
            let count = H2Swift.encodeInteger(value, to: ptr, prefix: prefix)
            data.count = count
        }
        return data
    }
    
    private func decodeInteger(from bytes: [UInt8], prefix: Int) throws -> UInt {
        return try bytes.withUnsafeBufferPointer { (buf: UnsafeBufferPointer<UInt8>) -> UInt in
            let r: UInt
            (r, _) = try H2Swift.decodeInteger(from: buf, prefix: prefix)
            return r
        }
    }

    func testIntegerEncoding() {
        // values from the standard: http://httpwg.org/specs/rfc7541.html#integer.representation.examples
        var data = encodeInteger(10, prefix: 5)
        XCTAssertEqual(data.count, 1)
        XCTAssertEqual(data[0], 0b00001010)
        
        data = encodeInteger(1337, prefix: 5)
        XCTAssertEqual(data.count, 3)
        XCTAssertEqual(Array<UInt8>(data), [31, 154, 10])
        
        data = encodeInteger(42, prefix: 8)
        XCTAssertEqual(data.count, 1)
        XCTAssertEqual(data[0], 42)
    }
    
    private func huffmanDecode(data: Data, using decoder: HuffmanDecoder) throws -> String {
        return try data.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> String in
            try decoder.decodeString(from: ptr, count: data.count)
        }
    }
    
    func testIntegerDecoding() {
        XCTAssertEqual(try decodeInteger(from: [0b00001010], prefix: 5), 10)
        XCTAssertEqual(try decodeInteger(from: [0b11101010], prefix: 5), 10)
        
        XCTAssertEqual(try decodeInteger(from: [0b00011111, 154, 10], prefix: 5), 1337)
        XCTAssertEqual(try decodeInteger(from: [0b11111111, 154, 10], prefix: 5), 1337)
        
        XCTAssertEqual(try decodeInteger(from: [42], prefix: 8), 42)
    }
    
    func verifyHuffmanCoding(_ string: String, _ bytes: [UInt8]) {
        let encoder = HuffmanEncoder()
        let decoder = HuffmanDecoder()
        let data = Data(bytes: bytes)
        
        XCTAssertEqual(encoder.encode(string), data.count, "Failed on '\(string)'")
        XCTAssertEqual(encoder.data, data, "Failed on '\(string)'")
        XCTAssertEqual(try huffmanDecode(data: data, using: decoder), string, "Failed on '\(string)'")
    }
    
    func testHuffmanEncoding() {
        // all these values come from http://httpwg.org/specs/rfc7541.html#request.examples.with.huffman.coding
        verifyHuffmanCoding("www.example.com", [0xf1, 0xe3, 0xc2, 0xe5, 0xf2, 0x3a, 0x6b, 0xa0, 0xab, 0x90, 0xf4, 0xff])
        verifyHuffmanCoding("no-cache", [0xa8, 0xeb, 0x10, 0x64, 0x9c, 0xbf])
        verifyHuffmanCoding("custom-key", [0x25, 0xa8, 0x49, 0xe9, 0x5b, 0xa9, 0x7d, 0x7f])
        verifyHuffmanCoding("custom-value", [0x25, 0xa8, 0x49, 0xe9, 0x5b, 0xb8, 0xe8, 0xb4, 0xbf])
        
        // these come from http://httpwg.org/specs/rfc7541.html#response.examples.with.huffman.coding
        verifyHuffmanCoding("302", [0x64, 0x02])
        verifyHuffmanCoding("private", [0xae, 0xc3, 0x77, 0x1a, 0x4b])
        verifyHuffmanCoding("Mon, 21 Oct 2013 20:13:21 GMT", [0xd0, 0x7a, 0xbe, 0x94, 0x10, 0x54, 0xd4, 0x44, 0xa8, 0x20, 0x05, 0x95, 0x04, 0x0b, 0x81, 0x66, 0xe0, 0x82, 0xa6, 0x2d, 0x1b, 0xff])
        verifyHuffmanCoding("https://www.example.com", [0x9d, 0x29, 0xad, 0x17, 0x18, 0x63, 0xc7, 0x8f, 0x0b, 0x97, 0xc8, 0xe9, 0xae, 0x82, 0xae, 0x43, 0xd3])
        verifyHuffmanCoding("307", [0x64, 0x0e, 0xff])
        verifyHuffmanCoding("Mon, 21 Oct 2013 20:13:22 GMT", [0xd0, 0x7a, 0xbe, 0x94, 0x10, 0x54, 0xd4, 0x44, 0xa8, 0x20, 0x05, 0x95, 0x04, 0x0b, 0x81, 0x66, 0xe0, 0x84, 0xa6, 0x2d, 0x1b, 0xff])
        verifyHuffmanCoding("gzip", [0x9b, 0xd9, 0xab])
        verifyHuffmanCoding("foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1", [0x94, 0xe7, 0x82, 0x1d, 0xd7, 0xf2, 0xe6, 0xc7, 0xb3, 0x35, 0xdf, 0xdf, 0xcd, 0x5b, 0x39, 0x60, 0xd5, 0xaf, 0x27, 0x08, 0x7f, 0x36, 0x72, 0xc1, 0xab, 0x27, 0x0f, 0xb5, 0x29, 0x1f, 0x95, 0x87, 0x31, 0x60, 0x65, 0xc0, 0x03, 0xed, 0x4e, 0xe5, 0xb1, 0x06, 0x3d, 0x50, 0x07])
    }
    
    func testStaticHeaderTable() {
        let table = IndexedHeaderTable()
        
        // headers with matching values
        XCTAssertEqualTuple((2, true), table.firstHeaderMatch(forName: ":method", value: "GET")!)
        XCTAssertEqualTuple((3, true), table.firstHeaderMatch(forName: ":method", value: "POST")!)
        XCTAssertEqualTuple((4, true), table.firstHeaderMatch(forName: ":path", value: "/")!)
        XCTAssertEqualTuple((5, true), table.firstHeaderMatch(forName: ":path", value: "/index.html")!)
        XCTAssertEqualTuple((8, true), table.firstHeaderMatch(forName: ":status", value: "200")!)
        XCTAssertEqualTuple((13, true), table.firstHeaderMatch(forName: ":status", value: "404")!)
        XCTAssertEqualTuple((14, true), table.firstHeaderMatch(forName: ":status", value: "500")!)
        XCTAssertEqualTuple((16, true), table.firstHeaderMatch(forName: "accept-encoding", value: "gzip, deflate")!)
        
        // headers with no values in the table
        XCTAssertEqualTuple((15, false), table.firstHeaderMatch(forName: "accept-charset", value: "any")!)
        XCTAssertEqualTuple((24, false), table.firstHeaderMatch(forName: "cache-control", value: "private")!)
        
        // header-only matches for table entries with a different value
        XCTAssertEqualTuple((8, false), table.firstHeaderMatch(forName: ":status", value: "501")!)
        XCTAssertEqualTuple((4, false), table.firstHeaderMatch(forName: ":path", value: "/test/path.html")!)
        XCTAssertEqualTuple((2, false), table.firstHeaderMatch(forName: ":method", value: "CONNECT")!)
        
        // things that aren't in the table at all
        XCTAssertNil(table.firstHeaderMatch(forName: "non-existent-key", value: "non-existent-value"))
    }
    
    func testDynamicTableInsertion() {
        // NB: I'm using the overall table class to verify the expected indices of dynamic table items.
        let table = IndexedHeaderTable(maxDynamicTableSize: 1024)
        XCTAssertEqual(table.dynamicTableLength, 0)
        
        XCTAssertNoThrow(try table.append(headerNamed: ":authority", value: "www.example.com"))
        XCTAssertEqual(table.dynamicTableLength, 57)
        XCTAssertEqualTuple((62, true), table.firstHeaderMatch(forName: ":authority", value: "www.example.com")!)
        XCTAssertEqualTuple((1, false), table.firstHeaderMatch(forName: ":authority", value: "www.something-else.com")!)
        
        XCTAssertNoThrow(try table.append(headerNamed: "cache-control", value: "no-cache"))
        XCTAssertEqual(table.dynamicTableLength, 110)
        XCTAssertEqualTuple((62, true), table.firstHeaderMatch(forName: "cache-control", value: "no-cache")!)
        XCTAssertEqualTuple((63, true), table.firstHeaderMatch(forName: ":authority", value: "www.example.com")!)
        
        // custom key not yet in the table, should return nil
        XCTAssertNil(table.firstHeaderMatch(forName: "custom-key", value: "custom-value"))
        
        XCTAssertNoThrow(try table.append(headerNamed: "custom-key", value: "custom-value"))
        XCTAssertEqual(table.dynamicTableLength, 164)
        XCTAssertEqualTuple((62, true), table.firstHeaderMatch(forName: "custom-key", value: "custom-value")!)
        XCTAssertEqualTuple((62, false), table.firstHeaderMatch(forName: "custom-key", value: "other-value")!)
        XCTAssertEqualTuple((63, true), table.firstHeaderMatch(forName: "cache-control", value: "no-cache")!)
        XCTAssertEqualTuple((64, true), table.firstHeaderMatch(forName: ":authority", value: "www.example.com")!)
        
        // should evict the first-inserted value (:authority = www.example.com)
        table.maxDynamicTableLength = 128
        XCTAssertEqual(table.dynamicTableLength, 164 - 57)
        XCTAssertEqualTuple((62, true), table.firstHeaderMatch(forName: "custom-key", value: "custom-value")!)
        XCTAssertEqualTuple((62, false), table.firstHeaderMatch(forName: "custom-key", value: "other-value")!)
        XCTAssertEqualTuple((63, true), table.firstHeaderMatch(forName: "cache-control", value: "no-cache")!)
        XCTAssertEqualTuple((1, false), table.firstHeaderMatch(forName: ":authority", value: "www.example.com")!)   // will find the header name in static table
        
        table.maxDynamicTableLength = 64
        XCTAssertEqual(table.dynamicTableLength, 164 - 110)
        XCTAssertEqualTuple((62, true), table.firstHeaderMatch(forName: "custom-key", value: "custom-value")!)
        XCTAssertEqualTuple((62, false), table.firstHeaderMatch(forName: "custom-key", value: "other-value")!)
        XCTAssertEqualTuple((24, false), table.firstHeaderMatch(forName: "cache-control", value: "no-cache")!)  // will find the header name in static table
        XCTAssertEqualTuple((1, false), table.firstHeaderMatch(forName: ":authority", value: "www.example.com")!)   // will find the header name in static table
        
        table.maxDynamicTableLength = 164 - 110    // should cause no evictions
        XCTAssertEqual(table.dynamicTableLength, 164 - 110)
        XCTAssertEqualTuple((62, true), table.firstHeaderMatch(forName: "custom-key", value: "custom-value")!)
        
        // evict final entry
        table.maxDynamicTableLength = table.dynamicTableLength - 1
        XCTAssertEqual(table.dynamicTableLength, 0)
        XCTAssertNil(table.firstHeaderMatch(forName: "custom-key", value: "custom-value"))
    }
    
    func testHeaderCompression() {
        let request1 = Data(bytes: [0x82, 0x86, 0x84, 0x41, 0x8c, 0xf1, 0xe3, 0xc2, 0xe5, 0xf2, 0x3a, 0x6b, 0xa0, 0xab, 0x90, 0xf4, 0xff])
        let request2 = Data(bytes: [0x82, 0x86, 0x84, 0xbe, 0x58, 0x86, 0xa8, 0xeb, 0x10, 0x64, 0x9c, 0xbf])
        let request3 = Data(bytes: [0x82, 0x87, 0x85, 0xbf, 0x40, 0x88, 0x25, 0xa8, 0x49, 0xe9, 0x5b, 0xa9, 0x7d, 0x7f, 0x89, 0x25, 0xa8, 0x49, 0xe9, 0x5b, 0xb8, 0xe8, 0xb4, 0xbf])
        
        let headers1 = [
            (":method", "GET"),
            (":scheme", "http"),
            (":path", "/"),
            (":authority", "www.example.com")
        ]
        let headers2 = [
            (":method", "GET"),
            (":scheme", "http"),
            (":path", "/"),
            (":authority", "www.example.com"),
            ("cache-control", "no-cache")
        ]
        let headers3 = [
            (":method", "GET"),
            (":scheme", "https"),
            (":path", "/index.html"),
            (":authority", "www.example.com"),
            ("custom-key", "custom-value")
        ]
        
        let indices1 = IndexSet(integer: 3)
        let indices2 = IndexSet(integer: 4)
        let indices3 = IndexSet(integer: 4)
        
        let encoder = HpackEncoder()
        XCTAssertEqual(encoder.append(headers: headers1), indices1) // item at index 3 should be flagged for addition to the dynamic table
        XCTAssertNoThrow(try encoder.updateDynamicTable(for: [headers1.last!]))
        XCTAssertEqual(encoder.encodedData, request1)
        
        encoder.reset()
        XCTAssertEqual(encoder.append(headers: headers2), indices2)
        XCTAssertNoThrow(try encoder.updateDynamicTable(for: [headers2.last!]))
        XCTAssertEqual(encoder.encodedData, request2)
        
        encoder.reset()
        XCTAssertEqual(encoder.append(headers: headers3), indices3)
        XCTAssertNoThrow(try encoder.updateDynamicTable(for: [headers3.last!]))
        XCTAssertEqual(encoder.encodedData, request3)
        
        let decoder = HpackDecoder()
        XCTAssertEqual(decoder.dynamicTableLength, 0)
        
        guard let decoded1 = try? decoder.decodeHeaders(from: request1) else {
            XCTFail("Error decoding first set of headers.")
            return
        }
        XCTAssertEqual(decoded1.count, headers1.count)
        for i in decoded1.indices {
            XCTAssertEqualTuple(decoded1[i], headers1[i])
        }
        XCTAssertEqual(decoder.dynamicTableLength, 57)
        
        guard let decoded2 = try? decoder.decodeHeaders(from: request2) else {
            XCTFail("Error decoding second set of headers.")
            return
        }
        XCTAssertEqual(decoded2.count, headers2.count)
        for i in decoded2.indices {
            XCTAssertEqualTuple(decoded2[i], headers2[i])
        }
        XCTAssertEqual(decoder.dynamicTableLength, 110)
        
        guard let decoded3 = try? decoder.decodeHeaders(from: request3) else {
            XCTFail("Error decoding third set of headers.")
            return
        }
        XCTAssertEqual(decoded3.count, headers3.count)
        for i in decoded3.indices {
            XCTAssertEqualTuple(decoded3[i], headers3[i])
        }
        XCTAssertEqual(decoder.dynamicTableLength, 164)
        
        // finally, a non-huffman-encoded variant:
        let request4 = Data(bytes: [0x82, 0x86, 0x84, 0x41, 0x0f, 0x77, 0x77, 0x77, 0x2e, 0x65, 0x78, 0x61, 0x6d, 0x70, 0x6c, 0x65, 0x2e, 0x63, 0x6f, 0x6d])
        guard let decoded4 = try? decoder.decodeHeaders(from: request4) else {
            XCTFail("Error decoding fourth set of headers.")
            return
        }
        XCTAssertEqual(decoded4.count, headers1.count)  // same actual headers as request 1, just a different encoding
        for i in decoded4.indices {
            XCTAssertEqualTuple(decoded4[i], headers1[i])
        }
        XCTAssertEqual(decoder.dynamicTableLength, 164+57)      // it should re-add the ":authority: www.example.com" pair as a fourth element
    }
    
    static let allTests = [
        (testIntegerEncoding, "testIntegerEncoding"),
        (testIntegerDecoding, "testIntegerDecoding"),
        (testHuffmanEncoding, "testHuffmanEncoding"),
        (testStaticHeaderTable, "testStaticHeaderTable"),
        (testDynamicTableInsertion, "testDynamicTableInsertion"),
        (testHeaderCompression, "testHeaderCompression")
    ]

}