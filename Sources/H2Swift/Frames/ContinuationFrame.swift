//
//  ContinuationFrame.swift
//  H2Swift
//
//  Created by Jim Dovey on 1/8/18.
//

import Foundation

public struct ContinuationFrame : Frame
{
    public var payloadLength: Int {
        return headerData.count
    }
    
    public let type: FrameType = .continuation
    public let flags: FrameFlags
    public let streamIdentifier: Int
    
    public let headerData: Data
    
    public init(headerData: Data, stream: Int, isLast: Bool = false) {
        self.flags = isLast ? .endHeaders : []
        self.streamIdentifier = stream
        self.headerData = headerData
    }
    
    public init(payload data: Data, payloadLength: Int, flags: FrameFlags, streamIdentifier: Int) throws {
        self.flags = flags.intersection(type.allowedFlags)
        self.streamIdentifier = streamIdentifier
        self.headerData = data
    }
    
    public func encodeFrame() -> Data {
        var data = buildFrameHeader()
        data.append(headerData)
        return data
    }
}
