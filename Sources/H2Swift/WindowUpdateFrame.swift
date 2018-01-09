//
//  WindowUpdateFrame.swift
//  H2Swift
//
//  Created by Jim Dovey on 1/8/18.
//

import Foundation

public struct WindowUpdateFrame : Frame
{
    public var payloadLength: Int {
        return 4
    }
    
    public let type: FrameType = .windowUpdate
    public let flags: FrameFlags = []
    public let streamIdentifier: Int
    
    public let windowSizeIncrement: Int
    
    public init(increment: Int, stream: Int) {
        self.windowSizeIncrement = increment
        self.streamIdentifier = stream
    }
    
    public init(payload data: Data, payloadLength: Int, flags: FrameFlags, streamIdentifier: Int) throws {
        if payloadLength != 4 {
            throw ProtocolError.frameSizeError
        }
        
        self.streamIdentifier = streamIdentifier
        self.windowSizeIncrement = Int(readNetworkLong(from: data) & ~0x80000000)
        
        guard windowSizeIncrement != 0 else {
            throw ProtocolError.protocolError
        }
    }
    
    public func encodeFrame() -> Data {
        var data = buildFrameHeader()
        writeNetworkLong(UInt32(windowSizeIncrement & ~0x80000000), to: &data, at: data.endIndex)
        return data
    }
}
