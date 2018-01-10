//
//  HeadersFrame.swift
//  H2Swift
//
//  Created by Jim Dovey on 1/8/18.
//

import Foundation

struct HeadersFrame : Frame, Flaggable
{
    public var payloadLength: Int {
        switch flags {
        case let x where x.contains([.padded, .priority]):
            return data.count + 1 + padding + 4 + 1     // pad length, padding, stream dependency, weight
        case let x where x.contains(.padded):
            return data.count + 1 + padding
        case let x where x.contains(.priority):
            return data.count + 4 + 1
        default:
            return data.count
        }
    }
    
    public let type: FrameType = .headers
    public private(set) var flags: FrameFlags = []
    public var streamIdentifier: Int = 0
    
    public var padding: Int = 0 {
        didSet {
            if padding != 0 {
                flags.insert(.padded)
            }
            else {
                flags.remove(.padded)
            }
        }
    }
    public var data: Data
    
    public private(set) var isExclusive: Bool = false
    public private(set) var streamDependency: Int = 0
    public private(set) var weight: Int = 0
    
    public mutating func setStreamDependency(_ stream: Int, weight: Int, exclusive: Bool = false) {
        isExclusive = exclusive
        streamDependency = stream
        self.weight = weight
        flags.insert(.priority)
    }
    
    public mutating func clearStreamDependency() {
        flags.remove(.priority)
    }
    
    public var suggestedPadding: Int {
        var unpaddedLength = data.count + 9
        
        if flags.contains(.priority) {
            unpaddedLength += 5     // stream dependency + weight
        }
        
        if unpaddedLength & 0b11 == 0 {
            // already a nice multiple of 4 bytes
            return 0
        }
        
        // add the padding byte and round up to the next multiple of four
        let lenPlusPadLen = unpaddedLength + 1
        return ((lenPlusPadLen + 4) & ~0b11) - lenPlusPadLen
    }
    
    public mutating func setSuggestedPadding() {
        padding = suggestedPadding
    }
    
    public init(headerData: Data, stream: Int, padding: Int = 0) {
        self.data = headerData
        self.streamIdentifier = stream
        self.padding = padding
    }
    
    init(payload data: Data, payloadLength: Int, flags: FrameFlags, streamIdentifier: Int) throws {
        guard streamIdentifier != 0 else {
            throw ProtocolError.protocolError
        }
        
        self.flags = flags.intersection(type.allowedFlags)
        self.streamIdentifier = streamIdentifier
        
        var idx = data.startIndex
        if flags.contains(.padded) {
            padding = Int(data[idx])
            idx += 1
            
            guard padding < (flags.contains(.priority) ? payloadLength - 6 : payloadLength - 1) else {
                throw ProtocolError.protocolError
            }
        }
        
        if flags.contains(.priority) {
            streamDependency = Int(readNetworkLong(from: data, at: idx))
            isExclusive = streamDependency & 0x80000000 != 0
            streamDependency = streamDependency & ~0x80000000
            idx += 4
            
            weight = Int(data[idx] + 1)
            idx += 1
        }
        
        self.data = data.subdata(in: idx ..< data.endIndex.advanced(by: -padding))
    }
    
    public mutating func setFlags(_ flags: FrameFlags) throws {
        try type.validateFlags(flags)
        self.flags.formUnion(flags.subtracting(.padded))
    }
    
    public func encodeFrame() -> Data {
        var result = buildFrameHeader()
        
        if flags.contains(.padded) {
            result.append(UInt8(padding))
        }
        
        if flags.contains(.priority) {
            // grab the current index...
            let idx = result.endIndex
            // ...encode the dependency value there...
            writeNetworkLong(UInt32(streamDependency), toData: &result, at: idx)
            // ...and toggle the topmost bit appropriately.
            if isExclusive {
                result[idx] |= 0x80
            }
            else {
                result[idx] &= ~0x80
            }
            
            // finally, write the weight
            result.append(UInt8(weight - 1))
        }
        
        result.append(data)
        
        if flags.contains(.padded) {
            result.append(contentsOf: repeatElement(UInt8(0), count: padding))
        }
        
        return result
    }
}
