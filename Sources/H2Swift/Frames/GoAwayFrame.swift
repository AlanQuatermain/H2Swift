//
//  GoAwayFrame.swift
//  H2Swift
//
//  Created by Jim Dovey on 1/8/18.
//

import Foundation

public struct GoAwayFrame : Frame
{
    public var payloadLength: Int {
        return 8 + (debugData?.count ?? 0)
    }
    
    public var type: FrameType = .goAway
    public let flags: FrameFlags = []
    public let streamIdentifier: Int = 0
    
    public let lastStreamID: Int
    public let errorCode: UInt32
    public let debugData: Data?
    
    public init(errorCode: UInt32, lastStreamID: Int, debugData: Data? = nil) {
        self.lastStreamID = lastStreamID
        self.errorCode = errorCode
        self.debugData = debugData
    }
    
    public init(error: ProtocolError, lastStreamID: Int, debugData: Data? = nil) {
        self.init(errorCode: error.rawValue, lastStreamID: lastStreamID, debugData: debugData)
    }
    
    public init(payload data: Data, payloadLength: Int, flags: FrameFlags, streamIdentifier: Int) throws {
        guard payloadLength >= 8 else {
            throw ProtocolError.frameSizeError
        }
        
        var idx = data.startIndex
        self.lastStreamID = Int(readNetworkLong(from: data, at: idx) & ~0x80000000)
        idx += 4
        
        self.errorCode = readNetworkLong(from: data, at: idx)
        idx += 4
        
        if idx < data.endIndex {
            self.debugData = data.subdata(in: idx ..< data.endIndex)
        }
        else {
            self.debugData = nil
        }
    }
    
    public func encodeFrame() -> Data {
        var data = buildFrameHeader()
        writeNetworkLong(UInt32(lastStreamID & ~0x80000000), to: &data, at: data.endIndex)
        writeNetworkLong(errorCode, to: &data, at: data.endIndex)
        
        if let debugData = debugData {
            data.append(debugData)
        }
        
        return data
    }
}
