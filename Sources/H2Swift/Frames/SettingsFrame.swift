//
//  SettingsFrame.swift
//  H2Swift
//
//  Created by Jim Dovey on 1/8/18.
//

import Foundation

public struct SettingsFrame : Frame, Flaggable
{
    public var payloadLength: Int {
        if flags.contains(.ack) {
            return 0
        }
        else {
            return settings.count * 6   // two-byte length + four-byte value per setting
        }
    }
    
    public var type: FrameType = .settings
    public private(set) var flags: FrameFlags = []
    public let streamIdentifier: Int = 0
    
    public mutating func setFlags(_ flags: FrameFlags) throws {
        try type.validateFlags(flags)
        self.flags.formUnion(flags)
    }
    
    public private(set) var settings: [SettingsParameters] = []
    
    /// Creates a `SETTINGS` frame to send the specified values.
    public init(sendingSettings settings: [SettingsParameters]) {
        self.settings = settings
    }
    
    // Creates an acknowledgement frame.
    public init() {
        self.flags = .ack
    }
    
    public init(payload data: Data, payloadLength: Int, flags: FrameFlags, streamIdentifier: Int) throws {
        if flags.contains(.ack) {
            precondition(payloadLength == 0, "SETTINGS acknowledgements should contain no payload.")
        }
        else {
            precondition(payloadLength % 6 == 0, "SETTINGS payload should be a multiple of six bytes in size")
        }
        
        self.flags = flags.intersection(type.allowedFlags)
        
        var idx = data.startIndex
        while idx < data.endIndex {
            if data.distance(from: idx, to: data.endIndex) < 6 {
                throw ProtocolError.frameSizeError
            }
            
            let subdata = data.subdata(in: idx ..< idx.advanced(by: 6))
            if let setting = try SettingsParameters.decode(from: subdata) {
                settings.append(setting)
            }
            
            idx = idx.advanced(by: 6)
        }
    }
    
    public func encodeFrame() -> Data {
        var data = buildFrameHeader()
        if flags.contains(.ack) {
            return data
        }
        
        for setting in settings {
            data.append(setting.compiled)
        }
        
        return data
    }
}
