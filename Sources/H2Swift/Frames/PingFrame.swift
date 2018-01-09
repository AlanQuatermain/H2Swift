//
//  PingFrame.swift
//  H2Swift
//
//  Created by Jim Dovey on 1/8/18.
//

import Foundation

public struct PingFrame : Frame
{
    public var payloadLength: Int {
        return 8
    }
    
    public let type: FrameType = .ping
    public let flags: FrameFlags
    public let streamIdentifier: Int = 0
    
    public let payload: Data
    
    public init(data: Data, isAck: Bool = false) {
        precondition(data.count == 8, "PING frames should contain exactly 8 bytes of payload data")
        
        self.flags = isAck ? .ack : []
        self.payload = data
    }
    
    public init(payload data: Data, payloadLength: Int, flags: FrameFlags, streamIdentifier: Int) throws {
        guard payloadLength == 8 else {
            throw ProtocolError.frameSizeError
        }
        guard streamIdentifier == 0 else {
            throw ProtocolError.protocolError
        }
        
        self.flags = flags.intersection(type.allowedFlags)
        self.payload = data
    }
    
    public func encodeFrame() -> Data {
        var data = buildFrameHeader()
        data.append(payload)
        return data
    }
}
