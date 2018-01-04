//
//  HPACKTests.swift
//  H2SwiftTests
//
//  Created by Jim Dovey on 1/3/18.
//

import XCTest
@testable import H2Swift

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
    
    static let allTests = [
        (testIntegerEncoding, "testIntegerEncoding"),
        (testIntegerDecoding, "testIntegerDecoding"),
        (testHuffmanEncoding, "testHuffmanEncoding"),
    ]

}
