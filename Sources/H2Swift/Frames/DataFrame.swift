//
//  DataFrame.swift
//  H2Swift
//
//  Created by Jim Dovey on 1/8/18.
//

import Foundation

public struct DataFrame : Frame, Flaggable
{
    public var payloadLength: Int {
        if flags.contains(.padded) {
            return data.count + padding + 1
        }
        else {
            return data.count
        }
    }
    
    public let type: FrameType = .data
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
    
    public var suggestedPadding: Int {
        let unpaddedLength = data.count + 9
        
        if unpaddedLength & 0b11 == 0 {
            // already a nice multiple of 4 bytes
            return 0
        }
        
        let lenPlusPadLen = unpaddedLength + 1
        let result = ((lenPlusPadLen + 4) & ~0b11) - lenPlusPadLen
        return result
    }
    
    public mutating func setSuggestedPadding() {
        padding = suggestedPadding
    }
    
    public init(data: Data, stream: Int, padding: Int = 0) {
        precondition(stream != 0, "DATA frames must be associated with a stream")
        precondition(padding >= 0 && padding < 256, "DATA frame padding cannot be more than 255 bytes")
        
        self.data = data
        self.streamIdentifier = stream
        self.padding = padding
    }
    
    public init(payload data: Data, payloadLength: Int, flags: FrameFlags, streamIdentifier: Int) throws {
        self.flags = flags.intersection(type.allowedFlags)
        self.streamIdentifier = streamIdentifier
        
        if flags.contains(.padded) {
            // read padding length
            padding = Int(data[0])
            self.data = data.subdata(in: 1 ..< data.endIndex.advanced(by: -padding))
        }
        else {
            self.data = data
        }
    }
    
    public mutating func setFlags(_ flags: FrameFlags) throws {
        try type.validateFlags(flags)
        
        // we don't set the padded bit from outside-- we need a number to go with it.
        self.flags.formUnion(flags.subtracting(.padded))
    }
    
    public func encodeFrame() -> Data {
        var result = buildFrameHeader()
        
        if flags.contains(.padded) {
            // 8-bit padding length
            result.append(UInt8(padding))
        }
        
        result.append(data)
        
        if flags.contains(.padded) {
            result.append(contentsOf: repeatElement(UInt8(0), count: padding))
        }
        
        return result
    }
}
