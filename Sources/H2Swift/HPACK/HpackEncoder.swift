//
//  HpackEncoder.swift
//  H2Swift
//
//  Created by Jim Dovey on 1/3/18.
//

import Foundation

fileprivate let temporaryBufferTSDKey = "H2Swift.HPACK.IntegerBuffer"
fileprivate let largestEncodedIntegerLength = 11 // the largest possible encoded length of a 64-bit unsigned integer is 11 bytes.
fileprivate func temporaryIntegerBuffer() -> Data {
    if let mutableData = Thread.current.threadDictionary[temporaryBufferTSDKey] as? NSMutableData {
        return mutableData as Data
    }
    else {
        if let mutableData = NSMutableData(length: largestEncodedIntegerLength) {
            Thread.current.threadDictionary[temporaryBufferTSDKey] = mutableData
            return mutableData as Data
        }
        else {
            // return an un-cached value
            return Data(count: largestEncodedIntegerLength)
        }
    }
}

/// A class which performs HPACK encoding of a list of headers.
public class HpackEncoder
{
    public static let defaultDynamicHeaderTableSize = 4096
    private static let defaultDataBufferSize = 128
    
    private let headerIndexTable: IndexedHeaderTable
    
    private var huffmanEncoder = HuffmanEncoder()
    private var data = Data(capacity: HpackEncoder.defaultDataBufferSize)
    
    public var dynamicTableSize: Int {
        return headerIndexTable.dynamicTableLength
    }
    
    public var maxDynamicTableSize: Int {
        get {
            return headerIndexTable.maxDynamicTableLength
        }
        set {
            headerIndexTable.maxDynamicTableLength = newValue
        }
    }
    
    public init(maxDynamicTableSize: Int = HpackEncoder.defaultDynamicHeaderTableSize) {
        headerIndexTable = IndexedHeaderTable(maxDynamicTableSize: maxDynamicTableSize)
    }
    
    /// Resets the internal data buffers and variables, ready to begin encoding a new header block.
    public func reset() {
        data.removeAll(keepingCapacity: true)
    }
    
    public func updateDynamicTable(for headers: [(String, String)]) throws {
        for (name, value) in headers {
            try headerIndexTable.append(headerNamed: name, value: value)
        }
    }
    
    /// Appends headers in the default fashion: indexed if possible, literal+indexable if not.
    /// - returns: A set containing the indices of each pair that should be inserted into the dynamic table.
    public func append(headers: [(String, String)]) -> IndexSet {
        var appendedIndices = IndexSet()
        for (index, pair) in headers.enumerated() {
            if append(header: pair.0, value: pair.1) {
                appendedIndices.insert(index)
            }
        }
        return appendedIndices
    }
    
    /// Appends a header/value pair, using indexed names/values is possible. If no indexed pair is available,
    /// it will use an indexed header and literal value, or a literal header and value. The name/value pair
    /// will be indexed for future use.
    ///
    /// - returns: `true` if this name/value pair should be inserted into the dynamic table.
    public func append(header: String, value: String) -> Bool {
        if let (index, hasValue) = headerIndexTable.firstHeaderMatch(forName: header, value: value) {
            // guarantee memory is available for an index
            var d = temporaryIntegerBuffer()
            
            if hasValue {
                // purely indexed. Nice & simple.
                d.withUnsafeMutableBytes { (ptr: UnsafeMutablePointer<UInt8>) -> Void in
                    ptr.pointee = 0b10000000    // set top bit to indicate index-only name/value pair
                    let count = encodeInteger(UInt(index), to: ptr, prefix: 7)
                    
                    // append to our data
                    self.data.append(ptr, count: count)
                }
                
                // everything is indexed-- nothing more to do!
                return false
            }
            else {
                // no value, so append the index to represent the name, followed by the value's length
                d.withUnsafeMutableBytes { (ptr: UnsafeMutablePointer<UInt8>) -> Void in
                    ptr.pointee = 0b01000000    // top bit zero, next bit 1, six prefix bits available for encoding
                    let count = encodeInteger(UInt(index), to: ptr, prefix: 6)
                    self.data.append(ptr, count: count)
                }
                
                // now encode and append the value string
                appendEncodedString(value)
            }
        }
        else {
            // no indexed name or value. Have to add them both, with a zero index
            data.append(0b01000000)
            appendEncodedString(header)
            appendEncodedString(value)
        }
        
        return true
    }
    
    private func appendEncodedString(_ string: String) {
        var d = temporaryIntegerBuffer()
        
        // encode the value
        let encoder = HuffmanEncoder()
        let len = encoder.encode(string)
        
        // store the encoded value's length
        d.withUnsafeMutableBytes { (ptr: UnsafeMutablePointer<UInt8>) -> Void in
            ptr.pointee = 0b10000000    // set the huffman-encoded bit of the first byte of the length
            let nameLenCount = encodeInteger(UInt(len), to: ptr, prefix: 7)
            self.data.append(ptr, count: nameLenCount)
        }
        
        self.data.append(encoder.data)
    }
    
    /// Appends a header that is *not* to be entered into the dynamic header table, but allows that
    /// stipulation to be overriden by a proxy server/rewriter.
    public func appendNonIndexed(header: String, value: String) {
        if let (index, _) = headerIndexTable.firstHeaderMatch(forName: header, value: "") {
            // we actually don't care if it has a value, because we only use an indexed name here.
            var d = temporaryIntegerBuffer()
            d.withUnsafeMutableBytes { (ptr: UnsafeMutablePointer<UInt8>) -> Void in
                ptr.pointee = 0     // no special bits set-- top four bits are unset, 4 for prefix.
                let count = encodeInteger(UInt(index), to: ptr, prefix: 4)
                self.data.append(ptr, count: count)
            }
            
            // now append the value
            appendEncodedString(value)
        }
        else {
            data.append(0)      // all zeroes now
            appendEncodedString(header)
            appendEncodedString(value)
        }
    }
    
    /// Appends a header that is *never* indexed, preventing even rewriting proxies from doing so.
    public func appendNeverIndexed(header: String, value: String) {
        if let (index, _) = headerIndexTable.firstHeaderMatch(forName: header, value: "") {
            // we actually don't care if it has a value, because we only use an indexed name here.
            var d = temporaryIntegerBuffer()
            d.withUnsafeMutableBytes { (ptr: UnsafeMutablePointer<UInt8>) -> Void in
                ptr.pointee = 0b00010000     // top four bits are 0001, 4 prefix bits.
                let count = encodeInteger(UInt(index), to: ptr, prefix: 4)
                self.data.append(ptr, count: count)
            }
            
            // now append the value
            appendEncodedString(value)
        }
        else {
            data.append(0b00010000)
            appendEncodedString(header)
            appendEncodedString(value)
        }
    }
}
