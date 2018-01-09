//
//  Frame.swift
//  H2Swift
//
//  Created by Jim Dovey on 1/8/18.
//

import Foundation

public enum FrameError : Error
{
    case invalidFlags(FrameFlags)
}

public enum FrameType : UInt8
{
    case data               // 0
    case headers            // 1
    case priority           // 2
    case resetStream        // 3
    case settings           // 4
    case pushPromise        // 5
    case ping               // 6
    case goAway             // 7
    case windowUpdate       // 8
    case continuation       // 9
    
    var allowedFlags: FrameFlags {
        switch self {
        case .data:
            return [.endStream, .padded]
        case .headers:
            return [.endStream, .endHeaders, .padded, .priority]
        case .priority:
            return []
        case .resetStream:
            return []
        case .settings:
            return [.ack]
        case .pushPromise:
            return [.endHeaders, .padded]
        case .ping:
            return [.ack]
        case .goAway:
            return []
        case .windowUpdate:
            return []
        case .continuation:
            return [.endHeaders]
        }
    }
    
    func validateFlags(_ flags: FrameFlags) throws {
        guard flags.isSubset(of: allowedFlags) else {
            throw FrameError.invalidFlags(flags.subtracting(allowedFlags))
        }
    }
}

public enum SettingsParameters
{
    case headerTableSize(Int)           // 0x1
    case enablePush(Bool)               // 0x2
    case maxConcurrentStreams(Int)      // 0x3
    case initialWindowSize(Int)         // 0x4
    case maxFrameSize(Int)              // 0x5
    case maxHeaderListSize(Int)         // 0x6
    
    var identifier: UInt16 {
        switch self {
        case .headerTableSize:
            return 1
        case .enablePush:
            return 2
        case .maxConcurrentStreams:
            return 3
        case .initialWindowSize:
            return 4
        case .maxFrameSize:
            return 5
        case .maxHeaderListSize:
            return 6
        }
    }
    
    static func decode(from data: Data) throws -> SettingsParameters? {
        if data.count < 6 {
            throw ProtocolError.frameSizeError
        }
        
        let identifier = readNetworkShort(from: data)
        let value = Int(readNetworkLong(from: data, at: data.startIndex.advanced(by: 2)))
        
        switch identifier {
        case 1:
            return .headerTableSize(value)
        case 2:
            guard value == 0 || value == 1 else {
                throw ProtocolError.protocolError
            }
            return .enablePush(value == 1)
        case 3:
            return .maxConcurrentStreams(value)
        case 4:
            guard value <= UInt32.max else {
                throw ProtocolError.flowControlError
            }
            return .initialWindowSize(value)
        case 5:
            guard value <= 16_777_215 else {        // 2^24-1
                throw ProtocolError.protocolError
            }
            return .maxFrameSize(value)
        case 6:
            return .maxHeaderListSize(value)
        default:
            // ignore any unknown settings
            return nil
        }
    }
    
    var compiled: Data {
        var data = Data(count: 6)
        
        data.withUnsafeMutableBytes { (ptr: UnsafeMutablePointer<UInt8>) -> Void in
            var p = ptr
            writeNetworkShort(identifier, to: p)
            p += 2
            
            switch self {
            case .headerTableSize(let v):
                writeNetworkLong(UInt32(v), to: p)
            case .enablePush(let b):
                writeNetworkLong(b ? 1 : 0, to: p)
            case .maxConcurrentStreams(let v):
                writeNetworkLong(UInt32(v), to: p)
            case .initialWindowSize(let v):
                writeNetworkLong(UInt32(v), to: p)
            case .maxFrameSize(let v):
                writeNetworkLong(UInt32(v), to: p)
            case .maxHeaderListSize(let v):
                writeNetworkLong(UInt32(v), to: p)
            }
        }
        
        return data
    }
}

public struct FrameFlags : OptionSet
{
    public typealias RawValue = UInt8
    
    public private(set) var rawValue: UInt8
    
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
    
    public static let endStream     = FrameFlags(rawValue: 0x01)
    public static let ack           = FrameFlags(rawValue: 0x01)
    public static let endHeaders    = FrameFlags(rawValue: 0x04)
    public static let padded        = FrameFlags(rawValue: 0x08)
    public static let priority      = FrameFlags(rawValue: 0x20)
    
    // for unit tests
    static let allFlags: FrameFlags = [.endStream, .endHeaders, .padded, .priority]
}

public protocol Frame
{
    var payloadLength: Int { get }
    var type: FrameType { get }
    var flags: FrameFlags { get }
    var streamIdentifier: Int { get }
    
    func encodeFrame() -> Data
    init(payload data: Data, payloadLength: Int, flags: FrameFlags, streamIdentifier: Int) throws
}

public protocol Flaggable
{
    mutating func setFlags(_ flags: FrameFlags) throws
}

extension Frame
{
    /// Returns a data blob allocated to the right capacity to hold the entire frame,
    /// with the first nine bytes 'used,' containing the frame header.
    func buildFrameHeader() -> Data {
        var bytes = Data(count: 9)
        let payloadLen = payloadLength
        
        bytes.reserveCapacity(9 + payloadLen)
        
        // three-byte length
        writeFrameLength(payloadLen, toData: &bytes)
        // one-byte type
        bytes[3] = type.rawValue
        // one-byte flags
        bytes[4] = flags.rawValue
        // four-byte stream identifier, masking out topmost bit
        writeNetworkLong(UInt32(streamIdentifier & ~0x80000000), toData: &bytes, at: bytes.startIndex.advanced(by: 5))
        
        return bytes
    }
}

func decodeFrameHeader(from data: Data) throws -> (payloadLen: Int, type: FrameType, flags: FrameFlags, stream: Int) {
    guard data.count >= 9 else {
        throw ProtocolError.frameSizeError
    }
    
    // three-byte length
    let payloadLen = readFrameLength(from: data)
    guard payloadLen + 3 <= data.count else {
        throw ProtocolError.frameSizeError
    }
    
    // one-byte type
    guard let type = FrameType(rawValue: data[3]) else {
        throw ProtocolError.noError
    }
    
    // one-byte flags
    // Sender MUST NOT send invalid flags, but receiver MUST ignore any invalid flags (§ 4.1)
    // Therefore, we don't
    let flags = FrameFlags(rawValue: data[4])
    
    // we MUST ignore the topmost bit of the stream identifier when receiving-- it's a reserved flag bit.
    let stream = readNetworkLong(from: data, at: data.startIndex.advanced(by: 5)) & ~0x80000000
    
    return (payloadLen, type, flags, Int(stream))
}

func decodeFrame(from data: Data) throws -> Frame {
    let (payloadLen, type, flags, stream) = try decodeFrameHeader(from: data)
    let payload = data.subdata(in: 9 ..< 9 + payloadLen)
    
    switch type {
    case .data:
        return try DataFrame(payload: payload, payloadLength: payloadLen, flags: flags, streamIdentifier: stream)
    case .headers:
        return try HeadersFrame(payload: payload, payloadLength: payloadLen, flags: flags, streamIdentifier: stream)
    case .priority:
        return try PriorityFrame(payload: payload, payloadLength: payloadLen, flags: flags, streamIdentifier: stream)
    case .resetStream:
        return try ResetStreamFrame(payload: payload, payloadLength: payloadLen, flags: flags, streamIdentifier: stream)
    case .settings:
        return try SettingsFrame(payload: payload, payloadLength: payloadLen, flags: flags, streamIdentifier: stream)
    case .pushPromise:
        return try PushPromiseFrame(payload: payload, payloadLength: payloadLen, flags: flags, streamIdentifier: stream)
    case .ping:
        return try PingFrame(payload: payload, payloadLength: payloadLen, flags: flags, streamIdentifier: stream)
    case .goAway:
        return try GoAwayFrame(payload: payload, payloadLength: payloadLen, flags: flags, streamIdentifier: stream)
    case .windowUpdate:
        return try WindowUpdateFrame(payload: payload, payloadLength: payloadLen, flags: flags, streamIdentifier: stream)
    case .continuation:
        return try ContinuationFrame(payload: payload, payloadLength: payloadLen, flags: flags, streamIdentifier: stream)
    }
}
