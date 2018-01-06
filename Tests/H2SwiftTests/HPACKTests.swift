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
    
    // HPACK RFC7541 § C.3
    // http://httpwg.org/specs/rfc7541.html#request.examples.without.huffman.coding
    func testRequestHeadersWithoutHuffmanCoding() {
        let request1 = Data(bytes: [0x82, 0x86, 0x84, 0x41, 0x0f, 0x77, 0x77, 0x77, 0x2e, 0x65, 0x78, 0x61, 0x6d, 0x70, 0x6c, 0x65, 0x2e, 0x63, 0x6f, 0x6d])
        let request2 = Data(bytes: [0x82, 0x86, 0x84, 0xbe, 0x58, 0x08, 0x6e, 0x6f, 0x2d, 0x63, 0x61, 0x63, 0x68, 0x65])
        let request3 = Data(bytes: [0x82, 0x87, 0x85, 0xbf, 0x40, 0x0a, 0x63, 0x75, 0x73, 0x74, 0x6f, 0x6d, 0x2d, 0x6b, 0x65, 0x79, 0x0c, 0x63, 0x75, 0x73, 0x74, 0x6f, 0x6d, 0x2d, 0x76, 0x61, 0x6c, 0x75, 0x65])
        
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
        XCTAssertEqualTuple(headers1[3], decoder.headerTable.header(at: 62)!)
        
        guard let decoded2 = try? decoder.decodeHeaders(from: request2) else {
            XCTFail("Error decoding second set of headers.")
            return
        }
        XCTAssertEqual(decoded2.count, headers2.count)
        for i in decoded2.indices {
            XCTAssertEqualTuple(decoded2[i], headers2[i])
        }
        XCTAssertEqual(decoder.dynamicTableLength, 110)
        XCTAssertEqualTuple(headers2[4], decoder.headerTable.header(at: 62)!)
        XCTAssertEqualTuple(headers1[3], decoder.headerTable.header(at: 63)!)
        
        guard let decoded3 = try? decoder.decodeHeaders(from: request3) else {
            XCTFail("Error decoding third set of headers.")
            return
        }
        XCTAssertEqual(decoded3.count, headers3.count)
        for i in decoded3.indices {
            XCTAssertEqualTuple(decoded3[i], headers3[i])
        }
        XCTAssertEqual(decoder.dynamicTableLength, 164)
        XCTAssertEqualTuple(headers3[4], decoder.headerTable.header(at: 62)!)
        XCTAssertEqualTuple(headers2[4], decoder.headerTable.header(at: 63)!)
        XCTAssertEqualTuple(headers1[3], decoder.headerTable.header(at: 64)!)
    }
    
    // HPACK RFC7541 § C.4
    // http://httpwg.org/specs/rfc7541.html#request.examples.with.huffman.coding
    func testRequestHeadersWithHuffmanCoding() {
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
        
        let encoder = HpackEncoder()
        XCTAssertNoThrow(try encoder.append(headers: headers1))
        XCTAssertEqual(encoder.encodedData, request1)
        XCTAssertEqual(encoder.headerIndexTable.dynamicTableLength, 57)
        XCTAssertEqualTuple(headers1[3], encoder.headerIndexTable.header(at: 62)!)
        
        encoder.reset()
        XCTAssertNoThrow(try encoder.append(headers: headers2))
        XCTAssertEqual(encoder.encodedData, request2)
        XCTAssertEqual(encoder.headerIndexTable.dynamicTableLength, 110)
        XCTAssertEqualTuple(headers2[4], encoder.headerIndexTable.header(at: 62)!)
        XCTAssertEqualTuple(headers1[3], encoder.headerIndexTable.header(at: 63)!)
        
        encoder.reset()
        XCTAssertNoThrow(try encoder.append(headers: headers3))
        XCTAssertEqual(encoder.encodedData, request3)
        XCTAssertEqual(encoder.headerIndexTable.dynamicTableLength, 164)
        XCTAssertEqualTuple(headers3[4], encoder.headerIndexTable.header(at: 62)!)
        XCTAssertEqualTuple(headers2[4], encoder.headerIndexTable.header(at: 63)!)
        XCTAssertEqualTuple(headers1[3], encoder.headerIndexTable.header(at: 64)!)
        
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
        XCTAssertEqualTuple(headers1[3], decoder.headerTable.header(at: 62)!)
        
        guard let decoded2 = try? decoder.decodeHeaders(from: request2) else {
            XCTFail("Error decoding second set of headers.")
            return
        }
        XCTAssertEqual(decoded2.count, headers2.count)
        for i in decoded2.indices {
            XCTAssertEqualTuple(decoded2[i], headers2[i])
        }
        XCTAssertEqual(decoder.dynamicTableLength, 110)
        XCTAssertEqualTuple(headers2[4], decoder.headerTable.header(at: 62)!)
        XCTAssertEqualTuple(headers1[3], decoder.headerTable.header(at: 63)!)
        
        guard let decoded3 = try? decoder.decodeHeaders(from: request3) else {
            XCTFail("Error decoding third set of headers.")
            return
        }
        XCTAssertEqual(decoded3.count, headers3.count)
        for i in decoded3.indices {
            XCTAssertEqualTuple(decoded3[i], headers3[i])
        }
        XCTAssertEqual(decoder.dynamicTableLength, 164)
        XCTAssertEqualTuple(headers3[4], decoder.headerTable.header(at: 62)!)
        XCTAssertEqualTuple(headers2[4], decoder.headerTable.header(at: 63)!)
        XCTAssertEqualTuple(headers1[3], decoder.headerTable.header(at: 64)!)
    }
    
    // HPACK RFC7541 § C.5
    // http://httpwg.org/specs/rfc7541.html#response.examples.without.huffman.coding
    func testResponseHeadersWithoutHuffmanCoding() {
        let response1 = Data(bytes: [
            // :status: 302
            0x48, 0x03, 0x33, 0x30, 0x32,
            // cache-control: private
            0x58, 0x07, 0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65,
            // date: Mon, 21 Oct 2013 20:13:21 GMT
            0x61, 0x1d, 0x4d, 0x6f, 0x6e, 0x2c, 0x20, 0x32, 0x31, 0x20, 0x4f, 0x63, 0x74, 0x20, 0x32, 0x30, 0x31, 0x33, 0x20, 0x32, 0x30, 0x3a, 0x31, 0x33, 0x3a, 0x32, 0x31, 0x20, 0x47, 0x4d, 0x54,
            // location: https://www.example.com
            0x6e, 0x17, 0x68, 0x74, 0x74, 0x70, 0x73, 0x3a, 0x2f, 0x2f, 0x77, 0x77, 0x77, 0x2e, 0x65, 0x78, 0x61, 0x6d, 0x70, 0x6c, 0x65, 0x2e, 0x63, 0x6f, 0x6d
        ])
        let response2 = Data(bytes: [
            // :status: 307
            0x48, 0x03, 0x33, 0x30, 0x37,
            // cache-control: private
            0xc1,
            // date: Mon, 21 Oct 2013 20:13:21 GMT
            0xc0,
            // location: https://www.example.com
            0xbf
        ])
        let response3 = Data(bytes: [
            // :status: 200
            0x88,
            // cache-control: private
            0xc1,
            // date: Mon, 21 Oct 2013 20:13:22 GMT
            0x61, 0x1d, 0x4d, 0x6f, 0x6e, 0x2c, 0x20, 0x32, 0x31, 0x20, 0x4f, 0x63, 0x74, 0x20, 0x32, 0x30, 0x31, 0x33, 0x20, 0x32, 0x30, 0x3a, 0x31, 0x33, 0x3a, 0x32, 0x32, 0x20, 0x47, 0x4d, 0x54,
            // location: https://www.example.com
            0xc0,
            // content-encoding: gzip
            0x5a, 0x04, 0x67, 0x7a, 0x69, 0x70,
            // set-cookie: foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1
            0x77, 0x38, 0x66, 0x6f, 0x6f, 0x3d, 0x41, 0x53, 0x44, 0x4a, 0x4b, 0x48, 0x51, 0x4b, 0x42, 0x5a, 0x58, 0x4f, 0x51, 0x57, 0x45, 0x4f, 0x50, 0x49, 0x55, 0x41, 0x58, 0x51, 0x57, 0x45, 0x4f, 0x49, 0x55, 0x3b, 0x20, 0x6d, 0x61, 0x78, 0x2d, 0x61, 0x67, 0x65, 0x3d, 0x33, 0x36, 0x30, 0x30, 0x3b, 0x20, 0x76, 0x65, 0x72, 0x73, 0x69, 0x6f, 0x6e, 0x3d, 0x31
        ])
        
        let headers1 = [
            (":status", "302"),
            ("cache-control", "private"),
            ("date", "Mon, 21 Oct 2013 20:13:21 GMT"),
            ("location", "https://www.example.com")
        ]
        let headers2 = [
            (":status", "307"),
            ("cache-control", "private"),
            ("date", "Mon, 21 Oct 2013 20:13:21 GMT"),
            ("location", "https://www.example.com")
        ]
        let headers3 = [
            (":status", "200"),
            ("cache-control", "private"),
            ("date", "Mon, 21 Oct 2013 20:13:22 GMT"),
            ("location", "https://www.example.com"),
            ("content-encoding", "gzip"),
            ("set-cookie", "foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1")
        ]
        
        let decoder = HpackDecoder(maxDynamicTableSize: 256)
        XCTAssertEqual(decoder.dynamicTableLength, 0)
        
        guard let decoded1 = try? decoder.decodeHeaders(from: response1) else {
            XCTFail("Error decoding first set of headers.")
            return
        }
        XCTAssertEqual(decoded1.count, headers1.count)
        for i in decoded1.indices {
            XCTAssertEqualTuple(decoded1[i], headers1[i])
        }
        
        XCTAssertEqual(decoder.dynamicTableLength, 222)
        XCTAssertEqualTuple(headers1[3], decoder.headerTable.header(at: 62)!)
        XCTAssertEqualTuple(headers1[2], decoder.headerTable.header(at: 63)!)
        XCTAssertEqualTuple(headers1[1], decoder.headerTable.header(at: 64)!)
        XCTAssertEqualTuple(headers1[0], decoder.headerTable.header(at: 65)!)
        
        guard let decoded2 = try? decoder.decodeHeaders(from: response2) else {
            XCTFail("Error decoding second set of headers.")
            return
        }
        XCTAssertEqual(decoded2.count, headers2.count)
        for i in decoded2.indices {
            XCTAssertEqualTuple(decoded2[i], headers2[i])
        }
        
        XCTAssertEqual(decoder.dynamicTableLength, 222)
        XCTAssertEqualTuple(headers2[0], decoder.headerTable.header(at: 62)!)
        XCTAssertEqualTuple(headers1[3], decoder.headerTable.header(at: 63)!)
        XCTAssertEqualTuple(headers1[2], decoder.headerTable.header(at: 64)!)
        XCTAssertEqualTuple(headers1[1], decoder.headerTable.header(at: 65)!)
        
        guard let decoded3 = try? decoder.decodeHeaders(from: response3) else {
            XCTFail("Error decoding third set of headers.")
            return
        }
        XCTAssertEqual(decoded3.count, headers3.count)
        for i in decoded3.indices {
            XCTAssertEqualTuple(decoded3[i], headers3[i])
        }
        
        XCTAssertEqual(decoder.dynamicTableLength, 215)
        XCTAssertEqualTuple(headers3[5], decoder.headerTable.header(at: 62)!)
        XCTAssertEqualTuple(headers3[4], decoder.headerTable.header(at: 63)!)
        XCTAssertEqualTuple(headers3[2], decoder.headerTable.header(at: 64)!)
    }
    
    // HPACK RFC7541 § C.6
    // http://httpwg.org/specs/rfc7541.html#response.examples.with.huffman.coding
    func testResponseHeadersWithHuffmanCoding() {
        let response1 = Data(bytes: [
            0x48, 0x82, 0x64, 0x02, 0x58, 0x85, 0xae, 0xc3, 0x77, 0x1a, 0x4b, 0x61, 0x96, 0xd0, 0x7a, 0xbe, 0x94, 0x10, 0x54, 0xd4, 0x44, 0xa8, 0x20, 0x05, 0x95, 0x04, 0x0b, 0x81, 0x66, 0xe0, 0x82, 0xa6, 0x2d, 0x1b, 0xff, 0x6e, 0x91, 0x9d, 0x29, 0xad, 0x17, 0x18, 0x63, 0xc7, 0x8f, 0x0b, 0x97, 0xc8, 0xe9, 0xae, 0x82, 0xae, 0x43, 0xd3
        ])
        let response2 = Data(bytes: [
            0x48, 0x83, 0x64, 0x0e, 0xff, 0xc1, 0xc0, 0xbf
        ])
        let response3 = Data(bytes: [
            0x88, 0xc1, 0x61, 0x96, 0xd0, 0x7a, 0xbe, 0x94, 0x10, 0x54, 0xd4, 0x44, 0xa8, 0x20, 0x05, 0x95, 0x04, 0x0b, 0x81, 0x66, 0xe0, 0x84, 0xa6, 0x2d, 0x1b, 0xff, 0xc0, 0x5a, 0x83, 0x9b, 0xd9, 0xab, 0x77, 0xad, 0x94, 0xe7, 0x82, 0x1d, 0xd7, 0xf2, 0xe6, 0xc7, 0xb3, 0x35, 0xdf, 0xdf, 0xcd, 0x5b, 0x39, 0x60, 0xd5, 0xaf, 0x27, 0x08, 0x7f, 0x36, 0x72, 0xc1, 0xab, 0x27, 0x0f, 0xb5, 0x29, 0x1f, 0x95, 0x87, 0x31, 0x60, 0x65, 0xc0, 0x03, 0xed, 0x4e, 0xe5, 0xb1, 0x06, 0x3d, 0x50, 0x07
        ])
        
        let headers1 = [
            (":status", "302"),
            ("cache-control", "private"),
            ("date", "Mon, 21 Oct 2013 20:13:21 GMT"),
            ("location", "https://www.example.com")
        ]
        let headers2 = [
            (":status", "307"),
            ("cache-control", "private"),
            ("date", "Mon, 21 Oct 2013 20:13:21 GMT"),
            ("location", "https://www.example.com")
        ]
        let headers3 = [
            (":status", "200"),
            ("cache-control", "private"),
            ("date", "Mon, 21 Oct 2013 20:13:22 GMT"),
            ("location", "https://www.example.com"),
            ("content-encoding", "gzip"),
            ("set-cookie", "foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1")
        ]
        
        let encoder = HpackEncoder()
        XCTAssertNoThrow(try encoder.append(headers: headers1))
        XCTAssertEqual(encoder.encodedData, response1)
        XCTAssertEqualTuple(headers1[3], encoder.headerIndexTable.header(at: 62)!)
        XCTAssertEqualTuple(headers1[2], encoder.headerIndexTable.header(at: 63)!)
        XCTAssertEqualTuple(headers1[1], encoder.headerIndexTable.header(at: 64)!)
        XCTAssertEqualTuple(headers1[0], encoder.headerIndexTable.header(at: 65)!)
        
        encoder.reset()
        XCTAssertNoThrow(try encoder.append(headers: headers2))
        XCTAssertEqual(encoder.encodedData, response2)
        XCTAssertEqualTuple(headers2[0], encoder.headerIndexTable.header(at: 62)!)
        XCTAssertEqualTuple(headers1[3], encoder.headerIndexTable.header(at: 63)!)
        XCTAssertEqualTuple(headers1[2], encoder.headerIndexTable.header(at: 64)!)
        XCTAssertEqualTuple(headers1[1], encoder.headerIndexTable.header(at: 65)!)
        
        encoder.reset()
        XCTAssertNoThrow(try encoder.append(headers: headers3))
        XCTAssertEqual(encoder.encodedData, response3)
        XCTAssertEqualTuple(headers3[5], encoder.headerIndexTable.header(at: 62)!)
        XCTAssertEqualTuple(headers3[4], encoder.headerIndexTable.header(at: 63)!)
        XCTAssertEqualTuple(headers3[2], encoder.headerIndexTable.header(at: 64)!)
        
        let decoder = HpackDecoder(maxDynamicTableSize: 256)
        XCTAssertEqual(decoder.dynamicTableLength, 0)
        
        guard let decoded1 = try? decoder.decodeHeaders(from: response1) else {
            XCTFail("Error decoding first set of headers.")
            return
        }
        XCTAssertEqual(decoded1.count, headers1.count)
        for i in decoded1.indices {
            XCTAssertEqualTuple(decoded1[i], headers1[i])
        }
        
        XCTAssertEqual(decoder.dynamicTableLength, 222)
        XCTAssertEqualTuple(headers1[3], decoder.headerTable.header(at: 62)!)
        XCTAssertEqualTuple(headers1[2], decoder.headerTable.header(at: 63)!)
        XCTAssertEqualTuple(headers1[1], decoder.headerTable.header(at: 64)!)
        XCTAssertEqualTuple(headers1[0], decoder.headerTable.header(at: 65)!)
        
        guard let decoded2 = try? decoder.decodeHeaders(from: response2) else {
            XCTFail("Error decoding second set of headers.")
            return
        }
        XCTAssertEqual(decoded2.count, headers2.count)
        for i in decoded2.indices {
            XCTAssertEqualTuple(decoded2[i], headers2[i])
        }
        
        XCTAssertEqual(decoder.dynamicTableLength, 222)
        XCTAssertEqualTuple(headers2[0], decoder.headerTable.header(at: 62)!)
        XCTAssertEqualTuple(headers1[3], decoder.headerTable.header(at: 63)!)
        XCTAssertEqualTuple(headers1[2], decoder.headerTable.header(at: 64)!)
        XCTAssertEqualTuple(headers1[1], decoder.headerTable.header(at: 65)!)
        
        guard let decoded3 = try? decoder.decodeHeaders(from: response3) else {
            XCTFail("Error decoding third set of headers.")
            return
        }
        XCTAssertEqual(decoded3.count, headers3.count)
        for i in decoded3.indices {
            XCTAssertEqualTuple(decoded3[i], headers3[i])
        }
        
        XCTAssertEqual(decoder.dynamicTableLength, 215)
        XCTAssertEqualTuple(headers3[5], decoder.headerTable.header(at: 62)!)
        XCTAssertEqualTuple(headers3[4], decoder.headerTable.header(at: 63)!)
        XCTAssertEqualTuple(headers3[2], decoder.headerTable.header(at: 64)!)
    }
    
    private func byteString(from data: Data, hex: Bool = false) -> String {
        let result = "" as NSMutableString
        for byte in data {
            result.appendFormat(hex ? "%02hhx " : "%02hhu ", byte)
        }
        return result as String
    }
    
    private func byteString(from utf8: String.UTF8View, hex: Bool = false) -> String {
        let result = "" as NSMutableString
        for byte in utf8 {
            result.appendFormat(hex ? "%02hhx " : "%02hhu ", byte)
        }
        return result as String
    }
    
    func testExerciseHuffmanEncoder() {
        let encoder = HuffmanEncoder()
        let decoder = HuffmanDecoder()
        
        let text = "鯖審"
        let encoded = Data(bytes: [0xff, 0xff, 0xaf, 0xff, 0xff, 0x67, 0xff, 0xfe, 0x2f, 0xff, 0xf3, 0xff, 0xff, 0xec, 0xff, 0xff, 0x77])
//        print("Input length: \(text.count) chars, \(text.utf8.count) utf-8 bytes")
//        print("Input utf-8 bytes: \(byteString(from: text.utf8))")
        let amount = encoder.encode(text)
//        print("Encoded length: \(amount)")
        XCTAssertEqual(amount, encoded.count)
        let data = encoder.data
//        print("Encoded data: \(byteString(from: data))")
        XCTAssertEqual(data, encoded)
        
        let decoded = try! decoder.decodeString(from: encoded)
//        print("Decoded utf-8 data: \(byteString(from: decoded.utf8))")
        XCTAssertEqual(decoded, text)
        
        encoder.reset()
        decoder.reset()
        
        let text1 = "Hello, world. I am a header value; I have Teh Texts. I am going on for quite a long time because I want to ensure that the encoded data buffer needs to be expanded to test out that code. I'll try some meta-characters too: \r\t\n ought to do it, no?"
        guard let encoded1 = Data(base64Encoded: "xlooP9KeD2USLqZFB0qDUnKOQtincdFpftTIpOPuVTeWdTeXylC6mRQdKkxzVTKHqUlPYp2tMkqg1KD1TKJNSVSMpB2oKpkU8DqSok6hakW2FUTONKiZyqFqIeQsikg0jUjtllLYpUUsiFEnUjKoXzWOqQsiiTqJKhKh7UqJnGlQh5CrqZP9UUKJs9KIPSVSkqRrEnHYMiS2IUSc9xT////3//+r////xQ9s06VEnUkOoZP0pUf/Pw==") else {
            XCTFail("Unable to import base-64 result data")
            return
        }
        
        let amount1 = encoder.encode(text1)
        XCTAssertEqual(amount1, encoded1.count)
        let data1 = encoder.data
//        print("\n\n\(data1.base64EncodedString())\n\n")
        XCTAssertEqual(data1, encoded1)
        
        let decoded1 = data1.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> String in
            guard let result = try? decoder.decodeString(from: UnsafeRawPointer(ptr), count: data1.count) else {
                XCTFail()
                return ""
            }
            return result
        }
        XCTAssertEqual(decoded1, text1)

        // The encoder has a 256-byte encoding buffer to start with, and we want to overflow that to make it expand automatically
        // We also want to include some > 24-bit codes to test all the conditions.
        // So: here's a goodly-sized chunk of UTF-8 text. It won't compress worth a damn.

        encoder.reset()
        decoder.reset()

        let text2 = "午セイ谷高ぐふあト食71入ツエヘナ津県を類及オモ曜一購ごきわ致掲ぎぐず敗文輪へけり鯖審ヘ塊米卸呪おぴ。"
        guard let encoded2 = Data(base64Encoded: "//8///3v//W//83//P//8n//m//5///c//+r//wf//v//+v///D//8n//m//9L//+z//zf/+l//8P//m//9L//n//83//R//63//1//+3///e6H//z//+p//+j//zf/9H//p//+b//n///V//5v/+j//8n//m//6P//t//+j//9v//6P//5//+z//93//zf/8///r///X//3f//z//+f//7///2///N//z//+9//5v/+j//p//9H//5f//Z//+n//q//5v//q//8X//8P//N//6X//93//m//9L//73//m//5///v///V//9n//9v//o///r//+D//zf/+l///X//5v//S///s//83//pf/+x//6P//w///j//9H//4v//s///V///D//3v//N//6X//V//5v//S///t//83//P//9v//6///2f//i//8///7P//d//83//R//+T//z//93//7f//8///D//4v//P//97//q//8///9v//vf/+b//0v//t//+b//0v//2//+b//m//5/") else {
            XCTFail("Unable to import base-64 result data")
            return
        }

        let amount2 = encoder.encode(text2)
        XCTAssertEqual(amount2, encoded2.count)
        let data2 = encoder.data
        XCTAssertEqual(data2, encoded2)

//        print("\n\n\n\(data2.base64EncodedString())\n\n\n")

        let decoded2 = data2.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> String in
            guard let result = try? decoder.decodeString(from: UnsafeRawPointer(ptr), count: data2.count) else {
                XCTFail()
                return ""
            }
            return result
        }
        XCTAssertEqual(decoded2, text2)
    }
    
    func testNonIndexedRequest() {
        let request1 = Data(bytes: [0x82, 0x86, 0x84, 0x01, 0x8c, 0xf1, 0xe3, 0xc2, 0xe5, 0xf2, 0x3a, 0x6b, 0xa0, 0xab, 0x90, 0xf4, 0xff])
        let request2 = Data(bytes: [0x82, 0x86, 0x84, 0x01, 0x8c, 0xf1, 0xe3, 0xc2, 0xe5, 0xf2, 0x3a, 0x6b, 0xa0, 0xab, 0x90, 0xf4, 0xff, 0x0f, 0x09, 0x86, 0xa8, 0xeb, 0x10, 0x64, 0x9c, 0xbf, 0x00, 0x88, 0x25, 0xa8, 0x49, 0xe9, 0x5b, 0xa9, 0x7d, 0x7f, 0x89, 0x25, 0xa8, 0x49, 0xe9, 0x5b, 0xb8, 0xe8, 0xb4, 0xbf])
        let request3 = Data(bytes: [0x82, 0x87, 0x85, 0x11, 0x8c, 0xf1, 0xe3, 0xc2, 0xe5, 0xf2, 0x3a, 0x6b, 0xa0, 0xab, 0x90, 0xf4, 0xff, 0x10, 0x88, 0x25, 0xa8, 0x49, 0xe9, 0x5b, 0xa9, 0x7d, 0x7f, 0x89, 0x25, 0xa8, 0x49, 0xe9, 0x5b, 0xb8, 0xe8, 0xb4, 0xbf])
        
        let headers1 = [
            (":method", "GET"),
            (":scheme", "http"),
            (":path", "/")
        ]
        let h1NoIndex = (name: ":authority", value: "www.example.com")
        let h2NoIndex = (name: "cache-control", value: "no-cache")
        
        let headers3 = [
            (":method", "GET"),
            (":scheme", "https"),
            (":path", "/index.html")
        ]
        let h3NeverIndex = (name: "custom-key", value: "custom-value")
        
        let encoder = HpackEncoder()
        XCTAssertNoThrow(try encoder.append(headers: headers1))
        encoder.appendNonIndexed(header: h1NoIndex.name, value: h1NoIndex.value)
        XCTAssertEqual(encoder.encodedData, request1)
        XCTAssertEqual(encoder.headerIndexTable.dynamicTableLength, 0)
        
        encoder.reset()
        XCTAssertNoThrow(try encoder.append(headers: headers1))
        encoder.appendNonIndexed(header: h1NoIndex.name, value: h1NoIndex.value)
        encoder.appendNonIndexed(header: h2NoIndex.name, value: h2NoIndex.value)
        encoder.appendNonIndexed(header: h3NeverIndex.name, value: h3NeverIndex.value)
        XCTAssertEqual(encoder.encodedData, request2)
        print("enc2: \(byteString(from: encoder.encodedData, hex: true))")
        print("exp2: \(byteString(from: request2, hex: true))")
        XCTAssertEqual(encoder.headerIndexTable.dynamicTableLength, 0)
        
        encoder.reset()
        XCTAssertNoThrow(try encoder.append(headers: headers3))
        encoder.appendNeverIndexed(header: h1NoIndex.name, value: h1NoIndex.value)
        encoder.appendNeverIndexed(header: h3NeverIndex.name, value: h3NeverIndex.value)
        XCTAssertEqual(encoder.encodedData, request3)
        XCTAssertEqual(encoder.headerIndexTable.dynamicTableLength, 0)
        
        let decoder = HpackDecoder()
        XCTAssertEqual(decoder.dynamicTableLength, 0)
        
        let fullHeaders1 = [
            (":method", "GET"),
            (":scheme", "http"),
            (":path", "/"),
            (":authority", "www.example.com")
        ]
        let fullHeaders2 = [
            (":method", "GET"),
            (":scheme", "http"),
            (":path", "/"),
            (":authority", "www.example.com"),
            ("cache-control", "no-cache"),
            ("custom-key", "custom-value")
        ]
        let fullHeaders3 = [
            (":method", "GET"),
            (":scheme", "https"),
            (":path", "/index.html"),
            (":authority", "www.example.com"),
            ("custom-key", "custom-value")
        ]
        
        guard let decoded1 = try? decoder.decodeHeaders(from: request1) else {
            XCTFail("Error decoding first set of headers.")
            return
        }
        XCTAssertEqual(decoded1.count, fullHeaders1.count)
        for i in decoded1.indices {
            XCTAssertEqualTuple(decoded1[i], fullHeaders1[i])
        }
        XCTAssertEqual(decoder.dynamicTableLength, 0)
        
        guard let decoded2 = try? decoder.decodeHeaders(from: request2) else {
            XCTFail("Error decoding first set of headers.")
            return
        }
        XCTAssertEqual(decoded2.count, fullHeaders2.count)
        for i in decoded2.indices {
            XCTAssertEqualTuple(decoded2[i], fullHeaders2[i])
        }
        XCTAssertEqual(decoder.dynamicTableLength, 0)
        
        guard let decoded3 = try? decoder.decodeHeaders(from: request3) else {
            XCTFail("Error decoding first set of headers.")
            return
        }
        XCTAssertEqual(decoded3.count, fullHeaders3.count)
        for i in decoded3.indices {
            XCTAssertEqualTuple(decoded3[i], fullHeaders3[i])
        }
        XCTAssertEqual(decoder.dynamicTableLength, 0)
    }
    
    static let allTests = [
        (testIntegerEncoding, "testIntegerEncoding"),
        (testIntegerDecoding, "testIntegerDecoding"),
        (testHuffmanEncoding, "testHuffmanEncoding"),
        (testStaticHeaderTable, "testStaticHeaderTable"),
        (testDynamicTableInsertion, "testDynamicTableInsertion"),
        (testRequestHeadersWithoutHuffmanCoding, "testRequestHeadersWithoutHuffmanCoding"),
        (testRequestHeadersWithHuffmanCoding, "testRequestHeadersWithHuffmanCoding"),
        (testResponseHeadersWithoutHuffmanCoding, "testResponseHeadersWithoutHuffmanCoding"),
        (testResponseHeadersWithHuffmanCoding, "testResponseHeadersWithHuffmanCoding"),
        (testExerciseHuffmanEncoder, "testExerciseHuffmanEncoder"),
    ]

}
