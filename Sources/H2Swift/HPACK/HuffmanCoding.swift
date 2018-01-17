//
//  HuffmanCoding.swift
//  H2Swift
//
//  Created by Jim Dovey on 1/2/18.
//

import Foundation

public class HuffmanEncoder
{
    private static let initialBufferCount = 256
    
    private var buffer = Data(count: HuffmanEncoder.initialBufferCount)
    private var offset = 0
    private var remainingBits = 8
    
    public var data: Data {
        buffer.count = self.count
        return buffer
    }
    
    public var count: Int {
        return offset + (remainingBits == 0 || remainingBits == 8 ? 0 : 1)
    }
    
    public func reset() {
        buffer.removeAll(keepingCapacity: true)
        buffer.append(contentsOf: repeatElement(UInt8(0), count: HuffmanEncoder.initialBufferCount))
        offset = 0
        remainingBits = 8
    }
    
    // Returns the number of *bits* required to store a given string.
    private func encodedLength(of string: String) -> Int {
        let clen = string.utf8.reduce(0) { $0 + StaticHuffmanTable[Int($1)].nbits }
        
        // round up to nearest multiple of 8 for EOS prefix
        return (clen + 7) & ~7
    }
    
    public func encode(_ string: String) -> Int {
        let clen = encodedLength(of: string)
        ensureBitsAvailable(clen)
        let startCount = self.count
        
        for ch in string.utf8 {
            appendSym_fast(StaticHuffmanTable[Int(ch)])
        }
        
        //appendSym_fast(StaticHuffmanTable[256]) // EOS symbol
        if remainingBits > 0 && remainingBits < 8 {
            // set all remaining bits of the last byte to 1 and advance the offset
            buffer[offset] |= UInt8(1 << remainingBits) - 1
            offset += 1
            remainingBits = (offset == buffer.count ? 0 : 8)
        }
        
        return self.count - startCount
    }
    
    private func appendSym(_ sym: HuffmanTableEntry) {
        ensureBitsAvailable(sym.nbits)
        appendSym_fast(sym)
    }
    
    private func appendSym_fast(_ sym: HuffmanTableEntry) {
        // will it fit as-is?
        if sym.nbits == remainingBits {
            buffer[offset] |= UInt8(sym.bits)
            offset += 1
            remainingBits = offset == buffer.count ? 0 : 8
        }
        else if sym.nbits < remainingBits {
            let diff = remainingBits - sym.nbits
            buffer[offset] |= UInt8(sym.bits << diff)
            remainingBits -= sym.nbits
        }
        else {
            var (code, nbits) = sym
            
            buffer[offset] |= UInt8(code >> (nbits - remainingBits))
            offset += 1
            
            nbits -= remainingBits
            if (nbits & 0x7) != 0 {
                // align code to MSB
                code <<= 8 - (nbits & 0x7)
            }
            
            // we can short-circuit if less than 8 bits are remaining
            if nbits < 8 {
                buffer[offset] = UInt8(truncatingIfNeeded: code)
                remainingBits = 8 - nbits
                return
            }
            
            // longer path for larger amounts
            if nbits > 24 {
                buffer[offset] = UInt8(truncatingIfNeeded: code >> 24)
                nbits -= 8
                offset += 1
            }
            
            if nbits > 16 {
                buffer[offset] = UInt8(truncatingIfNeeded: code >> 16)
                nbits -= 8
                offset += 1
            }
            
            if nbits > 8 {
                buffer[offset] = UInt8(truncatingIfNeeded: code >> 8)
                nbits -= 8
                offset += 1
            }
            
            if nbits == 8 {
                buffer[offset] = UInt8(truncatingIfNeeded: code)
                offset += 1
                remainingBits = offset == buffer.count ? 0 : 8
            }
            else {
                remainingBits = 8 - nbits
                buffer[offset] = UInt8(truncatingIfNeeded: code)
            }
        }
    }
    
    private func ensureBitsAvailable(_ bits: Int) {
        let bitsLeft = ((buffer.count - offset) * 8) + remainingBits
        if bitsLeft >= bits {
            return
        }
        
        // we need more space. Deduct our remaining unused bits from the amount we're looking for to get a byte-rounded value
        let nbits = bits - remainingBits
        let bytesNeeded: Int
        if (nbits & 0b111) != 0 {
            // trim to byte length and add one more
            bytesNeeded = (nbits & ~0b111) + 8
        }
        else {
            // just trim to byte length
            bytesNeeded = (nbits & ~0b111)
        }
        
        let bytesAvailable = (buffer.count - offset) - (remainingBits == 0 ? 0 : 1)
        var neededToAdd = bytesNeeded - bytesAvailable
        
        // find a nice multiple of 128 bytes
        var newLength = buffer.count + 128
        while neededToAdd > 128 {
            neededToAdd -= 128
            newLength += 128
        }
        
        buffer.append(contentsOf: repeatElement(UInt8(0), count: newLength - buffer.count))
        if remainingBits == 0 {
            remainingBits = 8
            if offset != 0 {
                offset += 1
            }
        }
    }
}

public enum HuffmanDecoderError : Error
{
    case invalidState
    case decodeFailed
}

public class HuffmanDecoder
{
    private var acceptable = false
    private var state = 0
    
    public func decodeString(from data: Data) throws -> String {
        return try data.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> String in
            try decodeString(from: ptr, count: data.count)
        }
    }
    
    // Per the nghttp2 implementation, this uses the decoding algorithm & tables described at
    // http://graphics.ics.uci.edu/pub/Prefix.pdf (which is apparently no longer available, sigh).
    public func decodeString(from bytes: UnsafeRawPointer, count: Int) throws -> String {
        var decoded = [UInt8]()
        decoded.reserveCapacity(256)
        
        let input = UnsafeBufferPointer(start: bytes.assumingMemoryBound(to: UInt8.self), count: count)
        
        for ch in input {
            var t = HuffmanDecoderTable[state][Int(ch >> 4)]
            if t.flags.contains(.failure) {
                throw HuffmanDecoderError.invalidState
            }
            if t.flags.contains(.symbol) {
                decoded.append(t.sym)
            }
            
            t = HuffmanDecoderTable[Int(t.state)][Int(ch) & 0xf]
            if t.flags.contains(.failure) {
                throw HuffmanDecoderError.invalidState
            }
            if t.flags.contains(.symbol) {
                decoded.append(t.sym)
            }
            
            state = Int(t.state)
            acceptable = t.flags.contains(.accepted)
        }
        
        guard acceptable else {
            throw HuffmanDecoderError.invalidState
        }
        guard let result = String(bytes: decoded, encoding: .utf8) else {
            throw HuffmanDecoderError.decodeFailed
        }
        
        return result
    }
    
    public func reset() {
        state = 0
        acceptable = false
    }
}
