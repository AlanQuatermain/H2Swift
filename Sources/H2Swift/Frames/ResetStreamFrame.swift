//
//  ResetStreamFrame.swift
//  H2Swift
//
//  Created by Jim Dovey on 1/8/18.
//

import Foundation

public struct ResetStreamFrame : Frame
{
    public var payloadLength: Int {
        return 4
    }
    
    public var type: FrameType = .resetStream
    public let flags: FrameFlags = []
    
    public var streamIdentifier: Int
    public let errorCode: UInt32
    
    public init(stream: Int, error: ProtocolError) {
        self.init(stream: stream, errorCode: error.rawValue)
    }
    
    public init(stream: Int, errorCode: UInt32) {
        self.streamIdentifier = stream
        self.errorCode = errorCode
    }
    
    public init(payload data: Data, payloadLength: Int, flags: FrameFlags, streamIdentifier: Int) throws {
        precondition(payloadLength >= 4, "RST_STREAM must have at least 4 bytes of payload data")
        
        self.streamIdentifier = streamIdentifier
        self.errorCode = readNetworkLong(from: data)
    }
    
    public func encodeFrame() -> Data {
        var data = buildFrameHeader()
        writeNetworkLong(errorCode, to: &data, at: data.endIndex)
        return data
    }
    
}
