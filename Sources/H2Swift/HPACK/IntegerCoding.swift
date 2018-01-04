//
//  IntegerCoding.swift
//  H2Swift
//
//  Created by Jim Dovey on 1/2/18.
//

import Foundation

internal func encodedLength<T : UnsignedInteger>(of value: T, prefix: Int) -> Int {
    precondition(prefix <= 8)
    precondition(prefix >= 0)
    
    let k = (1 << prefix) - 1;
    if value < k {
        return 1
    }
    
    var len = 1
    var n = value - T(k)
    
    while n >= 128 {
        n >>= 7
        len += 1
    }
    
    return len + 1
}

internal func encodeInteger<T : UnsignedInteger>(_ value: T, to buffer: UnsafeMutableRawPointer,
                                                 prefix: Int) -> Int {
    precondition(prefix <= 8)
    precondition(prefix >= 0)
    
    let k = (1 << prefix) - 1
    var buf = buffer.assumingMemoryBound(to: UInt8.self)
    let start = buf
    
    if value < k {
        // it fits already!
        buf.pointee |= UInt8(truncatingIfNeeded: value)
        return 1
    }
    
    buf.pointee |= UInt8(truncatingIfNeeded: k)
    buf += 1
    
    var n = value - T(k)
    
    while n >= 128 {
        buf.pointee = (1 << 7) | UInt8(n & 0x7f)
        buf += 1
        n >>= 7
    }
    
    buf.pointee = UInt8(n)
    buf += 1
    
    return start.distance(to: buf)
}

internal func decodeInteger<T : UnsignedInteger>(from buffer: UnsafeBufferPointer<UInt8>, prefix: Int,
                                                 initial: T = 0) throws -> (T, Int) {
    precondition(prefix <= 8)
    precondition(prefix >= 0)
    
    let k = (1 << prefix) - 1
    var n = initial
    var buf = buffer.baseAddress!
    let end = buf + buffer.count
    
    if n == 0 {
        if buf.pointee & UInt8(k) != k {       // cheap form of 'if buf.pointee < k'
            return (T(buf.pointee & UInt8(k)), 1)
        }
        
        n = T(k)
        buf += 1
        if buf == end {
            return (n, buffer.baseAddress!.distance(to: buf))
        }
    }
    
    var m = 0
    var b: UInt8 = 0
    repeat {
        b = buf.pointee
        n += T((b & 127) * (1 << m))
        m += 7
        buf += 1
        
    } while b & 128 == 128
    
    return (n, buffer.baseAddress!.distance(to: buf))
}
