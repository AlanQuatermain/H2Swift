//
//  HpackDecoder.swift
//  H2Swift
//
//  Created by Jim Dovey on 1/4/18.
//

import Foundation

public class HpackDecoder
{
    public static let maxDynamicTableSize = DynamicHeaderTable.defaultSize
    
    // internal for testability
    let headerTable: IndexedHeaderTable
    
    var dynamicTableLength: Int {
        return headerTable.dynamicTableLength
    }
    
    public var maxDynamicTableLength: Int {
        get {
            return headerTable.maxDynamicTableLength
        }
        set {
            headerTable.maxDynamicTableLength = newValue
        }
    }
    
    public enum Error : Swift.Error
    {
        case invalidIndexedHeader(Int)
        case indexedHeaderWithNoValue(Int)
        case indexOutOfRange(Int, Int)
        case invalidUTF8StringData(Data)
        case invalidHeaderStartByte(UInt8, Int)
    }
    
    public init(maxDynamicTableSize: Int = HpackDecoder.maxDynamicTableSize) {
        headerTable = IndexedHeaderTable(maxDynamicTableSize: maxDynamicTableSize)
    }
    
    public func decodeHeaders(from data: Data) throws -> [(String, String)] {
        var result = [(String, String)]()
        var idx = data.startIndex
        
        while idx < data.endIndex {
            if let pair = try decodeHeader(from: data, startingAt: &idx) {
                result.append(pair)
            }
        }
        
        return result
    }
    
    private func decodeHeader(from data: Data, startingAt idx: inout Data.Index) throws -> (String, String)? {
        switch data[idx] {
        case let x where x & 0x80 == 0x80:
            // purely-indexed header field/value
            let (hidx, nbytes) = try decodeInteger(from: data.subdata(in: idx..<data.endIndex), prefix: 7)
            idx = idx.advanced(by: nbytes)
            return try decodeIndexedHeader(from: Int(hidx))
            
        case let x where x & 0xc0 == 0x40:
            // literal header with possibly-indexed name
            let (hidx, nbytes) = try decodeInteger(from: data.subdata(in: idx..<data.endIndex), prefix: 6)
            idx = idx.advanced(by: nbytes)
            return try decodeLiteralHeader(from: data, startingAt: &idx, headerIndex: Int(hidx))
            
        case let x where x & 0xf0 == 0x00:
            // literal header with possibly-indexed name, not added to dynamic table
            let (hidx, nbytes) = try decodeInteger(from: data.subdata(in: idx..<data.endIndex), prefix: 4)
            idx = idx.advanced(by: nbytes)
            return try decodeLiteralHeader(from: data, startingAt: &idx, headerIndex: Int(hidx), addToIndex: false)
            
        case let x where x & 0xf0 == 0x10:
            // literal header with possibly-indexed name, never added to dynamic table or modified by proxies
            let (hidx, nbytes) = try decodeInteger(from: data.subdata(in: idx..<data.endIndex), prefix: 4)
            idx = idx.advanced(by: nbytes)
            return try decodeLiteralHeader(from: data, startingAt: &idx, headerIndex: Int(hidx), addToIndex: false)
            
        case let x where x & 0xe0 == 0x20:
            // dynamic header table size update
            let (size, nbytes) = try decodeInteger(from: data.subdata(in: idx..<data.endIndex), prefix: 5)
            idx = idx.advanced(by: nbytes)
            maxDynamicTableLength = Int(size)
            return nil
            
        default:
            throw Error.invalidHeaderStartByte(data[idx], idx)
        }
    }
    
    private func decodeIndexedHeader(from hidx: Int) throws -> (String, String) {
        guard let (h, v) = headerTable.header(at: hidx) else {
            throw Error.invalidIndexedHeader(hidx)
        }
        guard !v.isEmpty else {
            throw Error.indexedHeaderWithNoValue(hidx)
        }
        
        return (h, v)
    }
    
    private func decodeLiteralHeader(from data: Data, startingAt idx: inout Data.Index, headerIndex: Int, addToIndex: Bool = true) throws -> (String, String) {
        if headerIndex != 0 {
            guard let (h, _) = headerTable.header(at: headerIndex) else {
                throw Error.invalidIndexedHeader(headerIndex)
            }
            
            let value = try readEncodedString(from: data, startingAt: &idx)
            
            // this type gets written into the dynamic table
            if (addToIndex) {
                try headerTable.append(headerNamed: h, value: value)
            }
            
            return (h, value)
        }
        else {
            let header = try readEncodedString(from: data, startingAt: &idx)
            let value = try readEncodedString(from: data, startingAt: &idx)
            
            if (addToIndex) {
                try headerTable.append(headerNamed: header, value: value)
            }
            
            return (header, value)
        }
    }
    
    private func readEncodedString(from data: Data, startingAt idx: inout Data.Index) throws -> String {
        // get the encoding bit
        let huffmanEncoded = data[idx] & 0x80 == 0x80
        
        // read the length. There's a seven-bit prefix here (topmost bit indicated encoding)
        let len = try data.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> Int in
            let buf = UnsafeBufferPointer(start: ptr.advanced(by: idx), count: data.distance(from: idx, to: data.endIndex))
            let (length, nbytes): (UInt, Int) = try decodeInteger(from: buf, prefix: 7)
            idx = idx.advanced(by: nbytes)
            return Int(length)
        }
        
        guard idx + len <= data.endIndex else {
            throw Error.indexOutOfRange(idx + len, data.endIndex)
        }
        
        // is it huffman encoded?
        let result: String
        if huffmanEncoded {
            result = try readHuffmanString(from: data[idx..<idx+len])
        }
        else {
            result = try readPlainString(from: data[idx..<idx+len])
        }
        
        idx = idx.advanced(by: len)
        return result
    }
    
    private func readPlainString(from data: Data) throws -> String {
        guard let result = String(bytes: data, encoding: .utf8) else {
            throw Error.invalidUTF8StringData(data)
        }
        return result
    }
    
    private func readHuffmanString(from data: Data) throws -> String {
        let decoder = HuffmanDecoder()
        return try data.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> String in
            try decoder.decodeString(from: ptr, count: data.count)
        }
    }
}
