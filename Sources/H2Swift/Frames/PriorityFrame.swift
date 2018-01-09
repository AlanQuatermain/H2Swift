//
//  PriorityFrame.swift
//  H2Swift
//
//  Created by Jim Dovey on 1/8/18.
//

import Foundation

public struct PriorityFrame : Frame
{
    public var payloadLength: Int {
        return 5        // four-byte stream dependency, one-byte weight
    }
    
    public let type: FrameType = .priority
    public private(set) var flags: FrameFlags = []
    public var streamIdentifier: Int = 0
    
    public var streamDependency: Int
    public var isExclusive: Bool
    public var weight: Int
    
    public init(stream: Int, dependency: Int, exclusive: Bool, weight: Int) {
        self.streamIdentifier = stream
        self.streamDependency = dependency
        self.isExclusive = exclusive
        self.weight = weight
    }
    
    public init(payload data: Data, payloadLength: Int, flags: FrameFlags, streamIdentifier: Int) throws {
        precondition(payloadLength >= 5, "PRIORITY frame payload should be (at least) five bytes in size")
        
        self.flags = flags.intersection(type.allowedFlags)
        self.streamIdentifier = streamIdentifier
        
        self.isExclusive = data[0] & 0x80 == 0x80
        self.streamDependency = Int(readNetworkLong(from: data) & ~0x80000000)
        self.weight = Int(data[4] + 1)
    }
    
    public func encodeFrame() -> Data {
        var data = buildFrameHeader()
        
        writeNetworkLong(UInt32(streamDependency), to: &data)
        if isExclusive {
            data[0] |= 0x80
        }
        else {
            data[0] &= ~0x80
        }
        
        data.append(UInt8(weight - 1))
        
        return data
    }
}
