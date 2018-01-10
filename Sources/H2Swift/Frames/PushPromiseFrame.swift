//
//  PushPromiseFrame.swift
//  H2Swift
//
//  Created by Jim Dovey on 1/8/18.
//

import Foundation

public struct PushPromiseFrame : Frame, Flaggable
{
    public var payloadLength: Int {
        if padding != 0 {
            return headerData.count + 1 + 4 + padding   // headers, pad length, promised stream ID, padding
        }
        else {
            return headerData.count + 4                 // headers, promisedStreamId
        }
    }
    
    public let type: FrameType = .pushPromise
    public private(set) var flags: FrameFlags
    public private(set) var streamIdentifier: Int
    
    public let headerData: Data
    public let promisedStreamId: Int
    
    public var padding: Int = 0 {
        didSet {
            if padding == 0 {
                flags.remove(.padded)
            }
            else {
                flags.insert(.padded)
            }
        }
    }
    
    public init(headerData: Data, flags: FrameFlags, stream: Int, promisedStreamId: Int, padding: Int = 0) {
        self.flags = flags.intersection(type.allowedFlags)
        self.headerData = headerData
        self.streamIdentifier = stream
        self.padding = padding
        self.promisedStreamId = promisedStreamId
    }
    
    public init(payload data: Data, payloadLength: Int, flags: FrameFlags, streamIdentifier: Int) throws {
        self.flags = flags.intersection(type.allowedFlags)
        self.streamIdentifier = streamIdentifier
        
        var idx = data.startIndex
        if flags.contains(.padded) {
            self.padding = Int(data[idx])
            idx += 1
        }
        
        // remember to clear the reserved bit
        self.promisedStreamId = Int(readNetworkLong(from: data, at: idx)) & ~0x80000000
        idx += 4
        
        // read the rest of the data
        self.headerData = data.subdata(in: idx ..< data.endIndex.advanced(by: -padding))
    }
    
    public mutating func setFlags(_ flags: FrameFlags) throws {
        try type.validateFlags(flags)
        self.flags.formUnion(flags.subtracting(.padded))
    }
    
    public var suggestedPadding: Int {
        let unpaddedLen = 9 + 4 + headerData.count
        
        if unpaddedLen & 0b11 == 0 {
            // already lines up to a four-byte boundary
            return 0
        }
        
        // add a padding length byte and round up to nearest multiple of four
        let lenWithPadByte = unpaddedLen + 1
        return ((lenWithPadByte + 4) & ~0b11) - lenWithPadByte
    }
    
    public mutating func setSuggestedPadding() {
        padding = suggestedPadding
    }
    
    public func encodeFrame() -> Data {
        var data = buildFrameHeader()
        
        if flags.contains(.padded) {
            data.append(UInt8(padding))
        }
        
        writeNetworkLong(UInt32(promisedStreamId & ~0x80000000), toData: &data, at: data.endIndex)
        data.append(headerData)
        
        if flags.contains(.padded) {
            data.append(contentsOf: repeatElement(UInt8(0), count: padding))
        }
        
        return data
    }
}
