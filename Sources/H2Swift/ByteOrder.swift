//
//  ByteOrder.swift
//  H2Swift
//
//  Created by Jim Dovey on 1/8/18.
//

import Foundation

func readNetworkShort(from ptr: UnsafeRawPointer) -> UInt16 {
    return NSSwapBigShortToHost(ptr.assumingMemoryBound(to: UInt16.self).pointee)
}

func readNetworkLong(from ptr: UnsafeRawPointer) -> UInt32 {
    return NSSwapBigIntToHost(ptr.assumingMemoryBound(to: UInt32.self).pointee)
}

func readFrameLength(from ptr: UnsafeRawPointer) -> Int {
    let bytes = ptr.assumingMemoryBound(to: UInt8.self)
    return Int(bytes[0]) << 16 | Int(bytes[1]) << 8 | Int(bytes[2])      // three-byte quantity only
}

func writeNetworkShort(_ value: UInt16, to ptr: UnsafeMutableRawPointer) {
    ptr.assumingMemoryBound(to: UInt16.self).pointee = NSSwapHostShortToBig(value)
}

func writeNetworkLong(_ value: UInt32, to ptr: UnsafeMutableRawPointer) {
    ptr.assumingMemoryBound(to: UInt32.self).pointee = NSSwapHostIntToBig(value)
}

func writeFrameLength(_ value: Int, to ptr: UnsafeMutableRawPointer) {
    let bytes = ptr.assumingMemoryBound(to: UInt8.self)
    // write out the least-significant three bytes
    bytes[0] = UInt8(truncatingIfNeeded: value >> 16)
    bytes[1] = UInt8(truncatingIfNeeded: value >> 8)
    bytes[2] = UInt8(truncatingIfNeeded: value)
}

func readNetworkShort(from data: Data, at offset: Data.Index = 0) -> UInt16 {
    return data.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> UInt16 in
        readNetworkShort(from: ptr.advanced(by: offset))
    }
}

func readNetworkLong(from data: Data, at offset: Data.Index = 0) -> UInt32 {
    return data.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> UInt32 in
        readNetworkLong(from: ptr.advanced(by: offset))
    }
}

func readFrameLength(from data: Data, at offset: Data.Index = 0) -> Int {
    return data.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> Int in
        readFrameLength(from: ptr.advanced(by: offset))
    }
}

func writeNetworkShort(_ value: UInt16, toData data: inout Data, at offset: Data.Index = 0) {
    if data.count < offset + 2 {
        data.count = offset + 2
    }
    data.withUnsafeMutableBytes { (ptr: UnsafeMutablePointer<UInt8>) -> Void in
        writeNetworkShort(value, to: ptr.advanced(by: offset))
    }
}

func writeNetworkLong(_ value: UInt32, toData data: inout Data, at offset: Data.Index = 0) {
    if data.count < offset + 4 {
        data.count = offset + 4
    }
    data.withUnsafeMutableBytes { (ptr: UnsafeMutablePointer<UInt8>) -> Void in
        writeNetworkLong(value, to: ptr.advanced(by: offset))
    }
}

func writeFrameLength(_ value: Int, toData data: inout Data, at offset: Data.Index = 0) {
    if data.count < offset + 3 {
        data.count = offset + 3
    }
    data.withUnsafeMutableBytes { (ptr: UnsafeMutablePointer<UInt8>) -> Void in
        writeFrameLength(value, to: ptr.advanced(by: offset))
    }
}
