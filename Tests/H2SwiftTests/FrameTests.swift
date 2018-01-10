//
//  FrameTests.swift
//  H2SwiftTests
//
//  Created by Jim Dovey on 1/9/18.
//

import XCTest
@testable import H2Swift

class FrameTests: XCTestCase
{
    let allFlags: [FrameFlags] = [.endStream, .endHeaders, .padded, .priority]

    func testDataFrameEncoding() {
        let payload = "Hello, World!".data(using: .utf8)!
        let stream = 1
        let noPadding: Data = {
            var r = Data(bytes: [
                0x00, 0x00, 0x0d,       // 3-byte payload length (13 bytes)
                0x00,                   // 1-byte type
                0x01,                   // 1-byte flags (0x01 = end-stream)
                0x00, 0x00, 0x00, 0x01, // 4-byte stream identifier
            ])
            r.reserveCapacity(r.count + payload.count)
            r.append(payload)
            return r
        }()
        
        // un-padded frame is 22 bytes. When we add padding, we get +1 byte for pad length, +1 byte of padding, for 24 bytes total
        let padLength = 1
        let withPadding: Data = {
            var r = Data(bytes: [
                0x00, 0x00, 0x0f,       // 3-byte payload length (15 bytes)
                0x00,                   // 1-byte type
                0x09,                   // 1-byte flags (0x08 = padded, 0x1 = end-stream)
                0x00, 0x00, 0x00, 0x01, // 4-byte stream identifier
                0x01,                   // 1-byte padding length
            ])
            r.reserveCapacity(r.count + payload.count + padLength)
            r.append(payload)
            r.append(contentsOf: repeatElement(UInt8(0), count: padLength))
            return r
        }()
        
        var unpaddedFrame = DataFrame(data: payload, stream: stream)
        XCTAssertNoThrow(try unpaddedFrame.setFlags(.endStream))
        var paddedFrame = DataFrame(data: payload, stream: stream)
        XCTAssertEqual(paddedFrame.suggestedPadding, padLength)
        XCTAssertNoThrow(try paddedFrame.setFlags(.endStream))
        paddedFrame.setSuggestedPadding()
        
        let unpaddedResult = unpaddedFrame.encodeFrame()
        let paddedResult = paddedFrame.encodeFrame()
        
        XCTAssertEqual(unpaddedResult, noPadding)
        XCTAssertEqual(paddedResult, withPadding)
    }
    
    func decodeSpecificFrame<F : Frame>(from data: Data, ofType: F.Type) -> F? {
        do {
            let frame = try decodeFrame(from: data)
            guard let result = frame as? F else {
                throw ProtocolError.protocolError
            }
            
            return result
        }
        catch {
            XCTFail("Failed to decode frame of type \(F.self): \(error)")
            return nil
        }
    }
    
    func testDataFrameDecoding() {
        let payload = "Hello, World!".data(using: .utf8)!
        let stream = 1
        let noPadding: Data = {
            var r = Data(bytes: [
                0x00, 0x00, 0x0d,       // 3-byte payload length (13 bytes)
                0x00,                   // 1-byte type
                0x00,                   // 1-byte flags
                0x00, 0x00, 0x00, 0x01, // 4-byte stream identifier
                ])
            r.reserveCapacity(r.count + payload.count)
            r.append(payload)
            return r
        }()
        
        // un-padded frame is 22 bytes. When we add padding, we get +1 byte for pad length, +1 byte of padding, for 24 bytes total
        let padLength = 1
        let withPadding: Data = {
            var r = Data(bytes: [
                0x00, 0x00, 0x0f,       // 3-byte payload length (15 bytes)
                0x00,                   // 1-byte type
                0x08,                   // 1-byte flags (0x08 = padded)
                0x00, 0x00, 0x00, 0x01, // 4-byte stream identifier
                0x01,                   // 1-byte padding length
                ])
            r.reserveCapacity(r.count + payload.count + padLength)
            r.append(payload)
            r.append(contentsOf: repeatElement(UInt8(0), count: padLength))
            return r
        }()
        
        guard let noPaddingFrame = decodeSpecificFrame(from: noPadding, ofType: DataFrame.self) else {
            return
        }
        guard let withPaddingFrame = decodeSpecificFrame(from: withPadding, ofType: DataFrame.self) else {
            return
        }
        
        XCTAssertEqual(noPaddingFrame.streamIdentifier, stream)
        XCTAssertEqual(withPaddingFrame.streamIdentifier, stream)
        XCTAssertFalse(noPaddingFrame.flags.contains(.padded))
        XCTAssertTrue(withPaddingFrame.flags.contains(.padded))
        
        XCTAssertEqual(noPaddingFrame.data, payload)
        XCTAssertEqual(withPaddingFrame.data, payload)
    }
    
    func testHeadersFrameEncoding() {
        // nicked from the HPACK tests
        let payload = Data(bytes: [0x82, 0x86, 0x84, 0x41, 0x8c, 0xf1, 0xe3, 0xc2, 0xe5, 0xf2, 0x3a, 0x6b, 0xa0, 0xab, 0x90, 0xf4, 0xff])
        let stream = 1
        let dependency = 2
        let weight = 5
        let noPriority: Data = {
            var data = Data(bytes: [
                0x00, 0x00, 0x11,       // 3-byte payload length (17 bytes)
                0x01,                   // 1-byte type
                0x04,                   // 1-byte flags (0x04 = end-headers)
                0x00, 0x00, 0x00, 0x01, // 4-byte stream identifier
            ])
            data.append(payload)
            return data
        }()
        let withPriority: Data = {
            var data = Data(bytes: [
                0x00, 0x00, 0x16,       // 3-byte payload length (17 bytes headers + 5 bytes priority/weight)
                0x01,                   // 1-byte type
                0x24,                   // 1-byte flags (0x04 = end-headers, 0x20 = priority))
                0x00, 0x00, 0x00, 0x01, // 4-byte stream identifier
                0x80, 0x00, 0x00, 0x02, // 4-byte dependent stream, with 'exclusive' bit set
                0x04                    // 1-byte weight (encodes weight - 1 on the wire)
            ])
            data.append(payload)
            return data
        }()
        
        var noPriorityFrame = HeadersFrame(headerData: payload, stream: stream)
        XCTAssertNoThrow(try noPriorityFrame.setFlags(.endHeaders))
        let noPriorityEncoded = noPriorityFrame.encodeFrame()
        XCTAssertEqual(noPriorityEncoded, noPriority)
        
        var priorityFrame = HeadersFrame(headerData: payload, stream: stream)
        priorityFrame.setStreamDependency(dependency, weight: weight, exclusive: true)
        XCTAssertNoThrow(try priorityFrame.setFlags(.endHeaders))
        let priorityEncoded = priorityFrame.encodeFrame()
        XCTAssertEqual(priorityEncoded, withPriority)
    }
    
    func testHeadersFrameDecoding() {
        // nicked from the HPACK tests
        let payload = Data(bytes: [0x82, 0x86, 0x84, 0x41, 0x8c, 0xf1, 0xe3, 0xc2, 0xe5, 0xf2, 0x3a, 0x6b, 0xa0, 0xab, 0x90, 0xf4, 0xff])
        let stream = 1
        let dependency = 2
        let weight = 5
        let noPriority: Data = {
            var data = Data(bytes: [
                0x00, 0x00, 0x11,       // 3-byte payload length (17 bytes)
                0x01,                   // 1-byte type
                0x04,                   // 1-byte flags (0x04 = end-headers)
                0x00, 0x00, 0x00, 0x01, // 4-byte stream identifier
                ])
            data.append(payload)
            return data
        }()
        let withPriority: Data = {
            var data = Data(bytes: [
                0x00, 0x00, 0x16,       // 3-byte payload length (17 bytes headers + 5 bytes priority/weight)
                0x01,                   // 1-byte type
                0x24,                   // 1-byte flags (0x04 = end-headers, 0x20 = priority))
                0x00, 0x00, 0x00, 0x01, // 4-byte stream identifier
                0x80, 0x00, 0x00, 0x02, // 4-byte dependent stream, with 'exclusive' bit set
                0x04                    // 1-byte weight (encodes weight - 1 on the wire)
                ])
            data.append(payload)
            return data
        }()
        
        guard let noPriorityFrame = decodeSpecificFrame(from: noPriority, ofType: HeadersFrame.self) else {
            return
        }
        XCTAssertEqual(noPriorityFrame.flags, [.endHeaders])
        XCTAssertEqual(noPriorityFrame.streamIdentifier, stream)
        XCTAssertEqual(noPriorityFrame.data, payload)
        
        guard let priorityFrame = decodeSpecificFrame(from: withPriority, ofType: HeadersFrame.self) else {
            return
        }
        XCTAssertEqual(priorityFrame.flags, [.endHeaders, .priority])
        XCTAssertEqual(priorityFrame.streamIdentifier, stream)
        XCTAssertEqual(priorityFrame.streamDependency, dependency)
        XCTAssertEqual(priorityFrame.weight, weight)
        XCTAssertEqual(priorityFrame.isExclusive, true)
        XCTAssertEqual(priorityFrame.data, payload)
    }
    
    func testEncodePriorityFrame() {
        let stream = 1
        let dependency = 2
        let weight = 5
        let data = Data(bytes: [
            0x00, 0x00, 0x05,       // 3-byte payload length (5 bytes)
            0x02,                   // 1-byte type
            0x00,                   // 1-byte flags
            0x00, 0x00, 0x00, 0x01, // 4-byte stream identifier
            0x80, 0x00, 0x00, 0x02, // 4-byte stream identifier, high bit = exclusive
            0x04                    // 1-byte weight (encoded as weight - 1)
        ])
        
        let frame = PriorityFrame(stream: stream, dependency: dependency, exclusive: true, weight: weight)
        let encoded = frame.encodeFrame()
        XCTAssertEqual(encoded, data)
    }
    
    func testDecodePriorityFrame() {
        let stream = 1
        let dependency = 2
        let weight = 5
        let data = Data(bytes: [
            0x00, 0x00, 0x05,       // 3-byte payload length (5 bytes)
            0x02,                   // 1-byte type
            0x00,                   // 1-byte flags
            0x00, 0x00, 0x00, 0x01, // 4-byte stream identifier
            0x80, 0x00, 0x00, 0x02, // 4-byte stream identifier, high bit = exclusive
            0x04                    // 1-byte weight (encoded as weight - 1)
        ])
        
        guard let frame = decodeSpecificFrame(from: data, ofType: PriorityFrame.self) else {
            return
        }
        XCTAssertEqual(frame.streamIdentifier, stream)
        XCTAssertEqual(frame.streamDependency, dependency)
        XCTAssertEqual(frame.weight, weight)
        XCTAssertEqual(frame.isExclusive, true)
    }
    
    func testEncodeResetStream() {
        let stream = 1
        let errorCode = ProtocolError.flowControlError
        let data = Data(bytes: [
            0x00, 0x00, 0x04,       // 3-byte payload length (4 bytes)
            0x03,                   // 1-byte type
            0x00,                   // 1-byte flags
            0x00, 0x00, 0x00, 0x01, // 4-byte stream identifier
            0x00, 0x00, 0x00, 0x03, // 4-byte error (0x03 = FLOW_CONTROL_ERROR)
        ])
        
        let frame = ResetStreamFrame(stream: stream, error: errorCode)
        let encoded = frame.encodeFrame()
        XCTAssertEqual(encoded, data)
    }
    
    func testDecodeResetStream() {
        let data = Data(bytes: [
            0x00, 0x00, 0x04,       // 3-byte payload length (4 bytes)
            0x03,                   // 1-byte type
            0x00,                   // 1-byte flags
            0x00, 0x00, 0x00, 0x01, // 4-byte stream identifier
            0x00, 0x00, 0x00, 0x03, // 4-byte error (0x03 = FLOW_CONTROL_ERROR)
        ])
        
        guard let frame = decodeSpecificFrame(from: data, ofType: ResetStreamFrame.self) else {
            return
        }
        XCTAssertEqual(frame.flags, [])
        XCTAssertEqual(frame.payloadLength, 4)
        XCTAssertEqual(frame.streamIdentifier, 1)
        XCTAssertEqual(frame.error, ProtocolError.flowControlError)
    }
    
    func testEncodeSettings() {
        let settings: [SettingsParameters] = [
            .headerTableSize(8192),         // default = 4096
            .enablePush(false),             // default = true
            .maxConcurrentStreams(128),     // default = unlimited
            .initialWindowSize(1024 * 24),  // default = 64KiB
            .maxFrameSize(1024 * 16),       // default = 16KiB
            .maxHeaderListSize(2048)        // default = unlimited
        ]
        let stream = 0  // SETTINGS frames are connection-wide
        let data = Data(bytes: [
            0x00, 0x00, 0x24,       // 3-byte payload length (6 bytes * 6 settings)
            0x04,                   // 1-byte type
            0x00,                   // 1-byte flags
            0x00, 0x00, 0x00, 0x00, // 4-byte stream identifier
            
            0x00, 0x01,             // setting: HEADER_TABLE_SIZE
            0x00, 0x00, 0x20, 0x00, // value: 8192
            0x00, 0x02,             // setting: ENABLE_PUSH
            0x00, 0x00, 0x00, 0x00, // value: 0
            0x00, 0x03,             // setting: MAX_CONCURRENT_STREAMS
            0x00, 0x00, 0x00, 0x80, // value: 128
            0x00, 0x04,             // setting: INITIAL_WINDOW_SIZE
            0x00, 0x00, 0x60, 0x00, // value: 24576
            0x00, 0x05,             // setting: MAX_FRAME_SIZE
            0x00, 0x00, 0x40, 0x00, // value: 16384
            0x00, 0x06,             // setting: MAX_HEADER_LIST_SIZE
            0x00, 0x00, 0x08, 0x00, // value: 2048
        ])
        let ack = Data(bytes: [
            0x00, 0x00, 0x00,       // 3-byte payload length (0 bytes)
            0x04,                   // 1-byte type
            0x01,                   // 1-byte flags (0x01 = ACK)
            0x00, 0x00, 0x00, 0x00, // 4-byte stream identifier
        ])
        
        let frame = SettingsFrame(sendingSettings: settings)
        XCTAssertEqual(frame.flags, [])
        XCTAssertEqual(frame.streamIdentifier, stream)
        XCTAssertEqual(frame.payloadLength, 36)
        
        let frameData = frame.encodeFrame()
        XCTAssertEqual(frameData, data)
        
        let ackFrame = SettingsFrame()
        XCTAssertEqual(ackFrame.flags, .ack)
        XCTAssertEqual(ackFrame.streamIdentifier, stream)
        XCTAssertEqual(ackFrame.payloadLength, 0)
        
        let ackFrameData = ackFrame.encodeFrame()
        XCTAssertEqual(ackFrameData, ack)
    }
    
    func testDecodeSettings() {
        let settings: [SettingsParameters] = [
            .headerTableSize(8192),         // default = 4096
            .enablePush(false),             // default = true
            .maxConcurrentStreams(128),     // default = unlimited
            .initialWindowSize(1024 * 24),  // default = 64KiB
            .maxFrameSize(1024 * 16),       // default = 16KiB
            .maxHeaderListSize(2048)        // default = unlimited
        ]
        let stream = 0  // SETTINGS frames are connection-wide
        let data = Data(bytes: [
            0x00, 0x00, 0x24,       // 3-byte payload length (6 bytes * 6 settings)
            0x04,                   // 1-byte type
            0x00,                   // 1-byte flags
            0x00, 0x00, 0x00, 0x00, // 4-byte stream identifier
            
            0x00, 0x01,             // setting: HEADER_TABLE_SIZE
            0x00, 0x00, 0x20, 0x00, // value: 8192
            0x00, 0x02,             // setting: ENABLE_PUSH
            0x00, 0x00, 0x00, 0x00, // value: 0
            0x00, 0x03,             // setting: MAX_CONCURRENT_STREAMS
            0x00, 0x00, 0x00, 0x80, // value: 128
            0x00, 0x04,             // setting: INITIAL_WINDOW_SIZE
            0x00, 0x00, 0x60, 0x00, // value: 24576
            0x00, 0x05,             // setting: MAX_FRAME_SIZE
            0x00, 0x00, 0x40, 0x00, // value: 16384
            0x00, 0x06,             // setting: MAX_HEADER_LIST_SIZE
            0x00, 0x00, 0x08, 0x00, // value: 2048
        ])
        let ack = Data(bytes: [
            0x00, 0x00, 0x00,       // 3-byte payload length (0 bytes)
            0x04,                   // 1-byte type
            0x01,                   // 1-byte flags (0x01 = ACK)
            0x00, 0x00, 0x00, 0x00, // 4-byte stream identifier
        ])
        
        guard let frame = decodeSpecificFrame(from: data, ofType: SettingsFrame.self) else {
            return
        }
        XCTAssertEqual(frame.flags, [])
        XCTAssertEqual(frame.streamIdentifier, stream)
        XCTAssertEqual(frame.payloadLength, 36)
        XCTAssertEqual(frame.settings, settings)
        
        guard let ackFrame = decodeSpecificFrame(from: ack, ofType: SettingsFrame.self) else {
            return
        }
        XCTAssertEqual(ackFrame.flags, .ack)
        XCTAssertEqual(ackFrame.streamIdentifier, stream)
        XCTAssertEqual(ackFrame.payloadLength, 0)
        XCTAssertEqual(ackFrame.settings, [])
    }
    
    func testEncodePushPromise() {
        let headerData = Data(bytes: [0x82, 0x86, 0x84, 0xbe, 0x58, 0x86, 0xa8, 0xeb, 0x10, 0x64, 0x9c, 0xbf])
        let stream = 1
        let promisedStream = 2
        let data: Data = {
            var d = Data(bytes: [
                0x00, 0x00, 0x13,       // 3-byte payload length (19 bytes)
                0x05,                   // 1-byte type
                0x0c,                   // 1-byte flags (0x04 = END_HEADERS, 0x08 = PADDED)
                0x00, 0x00, 0x00, 0x01, // 4-byte stream identifier
                
                0x02,                   // padding length
                0x00, 0x00, 0x00, 0x02, // 4-byte promised stream id
            ])
            d.append(headerData)
            d.append(contentsOf: repeatElement(UInt8(0), count: 2))
            XCTAssertEqual(d.count % 4, 0)
            return d
        }()
        
        var frame = PushPromiseFrame(headerData: headerData, flags: .endHeaders, stream: stream, promisedStreamId: promisedStream)
        XCTAssertEqual(frame.suggestedPadding, 2)   // should already be a multiple of 4 octets in length
        frame.setSuggestedPadding()
        XCTAssertEqual(frame.flags, [.endHeaders, .padded])
        
        let encoded = frame.encodeFrame()
        XCTAssertEqual(encoded, data)
    }
    
    func testDecodePushPromise() {
        let headerData = Data(bytes: [0x82, 0x86, 0x84, 0xbe, 0x58, 0x86, 0xa8, 0xeb, 0x10, 0x64, 0x9c, 0xbf])
        let stream = 1
        let promisedStream = 2
        let data: Data = {
            var d = Data(bytes: [
                0x00, 0x00, 0x13,       // 3-byte payload length (19 bytes)
                0x05,                   // 1-byte type
                0x0c,                   // 1-byte flags (0x04 = END_HEADERS, 0x08 = PADDED)
                0x00, 0x00, 0x00, 0x01, // 4-byte stream identifier
                
                0x02,                   // padding length
                0x00, 0x00, 0x00, 0x02, // 4-byte promised stream id
                ])
            d.append(headerData)
            d.append(contentsOf: repeatElement(UInt8(0), count: 2))
            return d
        }()
        
        guard let frame = decodeSpecificFrame(from: data, ofType: PushPromiseFrame.self) else {
            return
        }
        XCTAssertEqual(frame.payloadLength, 19)
        XCTAssertEqual(frame.flags, [.endHeaders, .padded])
        XCTAssertEqual(frame.streamIdentifier, stream)
        XCTAssertEqual(frame.promisedStreamId, promisedStream)
        XCTAssertEqual(frame.headerData, headerData)
    }
    
    func testEncodePing() {
        let ping = Data(bytes: [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        let data = Data(bytes: [
            0x00, 0x00, 0x08,       // 3-byte payload length (8 bytes)
            0x06,                   // 1-byte type
            0x00,                   // 1-byte flags
            0x00, 0x00, 0x00, 0x00, // 4-byte stream identifier
            
            0x01, 0x02, 0x03, 0x04,
            0x05, 0x06, 0x07, 0x08
        ])
        var ack = data
        ack[4] = 0x01           // flags; 0x01 = ACK
        
        let frame = PingFrame(data: ping)
        let encoded = frame.encodeFrame()
        XCTAssertEqual(encoded, data)
        
        let ackFrame = PingFrame(data: ping, isAck: true)
        let ackEncoded = ackFrame.encodeFrame()
        XCTAssertEqual(ackEncoded, ack)
    }
    
    func testDecodePing() {
        let ping = Data(bytes: [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        let data = Data(bytes: [
            0x00, 0x00, 0x08,       // 3-byte payload length (8 bytes)
            0x06,                   // 1-byte type
            0x00,                   // 1-byte flags
            0x00, 0x00, 0x00, 0x00, // 4-byte stream identifier
            
            0x01, 0x02, 0x03, 0x04,
            0x05, 0x06, 0x07, 0x08
            ])
        var ack = data
        ack[4] = 0x01           // flags; 0x01 = ACK
        
        guard let frame = decodeSpecificFrame(from: data, ofType: PingFrame.self) else {
            return
        }
        XCTAssertEqual(frame.flags, [])
        XCTAssertEqual(frame.payload, ping)
        
        guard let ackFrame = decodeSpecificFrame(from: ack, ofType: PingFrame.self) else {
            return
        }
        XCTAssertEqual(ackFrame.flags, .ack)
        XCTAssertEqual(ackFrame.payload, ping)
    }
    
    func testEncodeGoAway() {
        let debugDataString = "This is some debug data, containing multi-byte UTF-8 ćhåräčtęrß" // 69 bytes of UTF-8
        let lastStream = 2
        let error = ProtocolError.inadequateSecurity    // 12 / 0x0c
        let data: Data = {
            var d = Data(bytes: [
                0x00, 0x00, 0x4d,       // 3-byte payload length (77 bytes)
                0x07,                   // 1-byte type
                0x00,                   // 1-byte flags
                0x00, 0x00, 0x00, 0x00, // 4-byte stream identifier (always zero)
                
                0x00, 0x00, 0x00, 0x02, // 4-byte last-stream-id
                0x00, 0x00, 0x00, 0x0c, // 4-byte error code (0xc = INADEQUATE_SECURITY)
            ])
            d.append(debugDataString.data(using: .utf8)!)
            return d
        }()
        
        let frame = GoAwayFrame(error: error, lastStreamID: lastStream, debugData: debugDataString.data(using: .utf8))
        XCTAssertEqual(frame.streamIdentifier, 0)
        XCTAssertEqual(frame.flags, [])
        
        let encoded = frame.encodeFrame()
        XCTAssertEqual(encoded, data)
    }
    
    func testDecodeGoAway() {
        let debugDataString = "This is some debug data, containing multi-byte UTF-8 ćhåräčtęrß" // 69 bytes of UTF-8
        let lastStream = 2
        let error = ProtocolError.inadequateSecurity    // 12 / 0x0c
        let data: Data = {
            var d = Data(bytes: [
                0x00, 0x00, 0x4d,       // 3-byte payload length (77 bytes)
                0x07,                   // 1-byte type
                0x00,                   // 1-byte flags
                0x00, 0x00, 0x00, 0x00, // 4-byte stream identifier (always zero)
                
                0x00, 0x00, 0x00, 0x02, // 4-byte last-stream-id
                0x00, 0x00, 0x00, 0x0c, // 4-byte error code (0xc = INADEQUATE_SECURITY)
                ])
            d.append(debugDataString.data(using: .utf8)!)
            return d
        }()
        
        guard let frame = decodeSpecificFrame(from: data, ofType: GoAwayFrame.self) else {
            return
        }
        
        XCTAssertEqual(frame.streamIdentifier, 0)
        XCTAssertEqual(frame.payloadLength, 77)
        XCTAssertEqual(frame.lastStreamID, lastStream)
        XCTAssertEqual(frame.error, error)
        XCTAssertNotNil(frame.debugData)
        XCTAssertEqual(debugDataString, String(data: frame.debugData!, encoding: .utf8))
    }
    
    func testEncodeWindowUpdate() {
        let increment = 256     // 0x100
        let stream = 1
        let data = Data(bytes: [
            0x00, 0x00, 0x04,       // 3-byte payload length (4 bytes)
            0x08,                   // 1-byte type
            0x00,                   // 1-byte flags
            0x00, 0x00, 0x00, 0x01, // 4-byte stream identifier
            
            0x00, 0x00, 0x01, 0x00  // 4-byte window increment
        ])
        
        let frame = WindowUpdateFrame(increment: increment, stream: stream)
        XCTAssertEqual(frame.flags, [])
        XCTAssertEqual(frame.payloadLength, 4)
        
        let encoded = frame.encodeFrame()
        XCTAssertEqual(encoded, data)
    }
    
    func testDecodeWindowUpdate() {
        let increment = 256     // 0x100
        let stream = 1
        let data = Data(bytes: [
            0x00, 0x00, 0x04,       // 3-byte payload length (4 bytes)
            0x08,                   // 1-byte type
            0x00,                   // 1-byte flags
            0x00, 0x00, 0x00, 0x01, // 4-byte stream identifier
            
            0x00, 0x00, 0x01, 0x00  // 4-byte window increment
        ])
        
        guard let frame = decodeSpecificFrame(from: data, ofType: WindowUpdateFrame.self) else {
            return
        }
        
        XCTAssertEqual(frame.streamIdentifier, stream)
        XCTAssertEqual(frame.flags, [])
        XCTAssertEqual(frame.payloadLength, 4)
        XCTAssertEqual(frame.windowSizeIncrement, increment)
    }
    
    func testEncodeContinuation() {
        let stream = 1
        let headerData = Data(bytes: [0x40, 0x0a, 0x63, 0x75, 0x73, 0x74, 0x6f, 0x6d, 0x2d, 0x6b, 0x65, 0x79, 0x0c, 0x63, 0x75, 0x73, 0x74, 0x6f, 0x6d, 0x2d, 0x76, 0x61, 0x6c, 0x75, 0x65])
        let data: Data = {
            var d = Data(bytes: [
                0x00, 0x00, 0x19,       // 3-byte payload length (25 bytes)
                0x09,                   // 1-byte type (0x09 = CONTINUATION)
                0x04,                   // 1-byte flags (0x04 = END_HEADERS)
                0x00, 0x00, 0x00, 0x01, // 4-byte stream identifier
            ])
            d.append(headerData)
            return d
        }()
        
        let frame = ContinuationFrame(headerData: headerData, stream: stream, isLast: true)
        XCTAssertEqual(frame.flags, .endHeaders)
        
        let encoded = frame.encodeFrame()
        XCTAssertEqual(encoded, data)
    }
    
    func testDecodeContinuation() {
        let stream = 1
        let headerData = Data(bytes: [0x40, 0x0a, 0x63, 0x75, 0x73, 0x74, 0x6f, 0x6d, 0x2d, 0x6b, 0x65, 0x79, 0x0c, 0x63, 0x75, 0x73, 0x74, 0x6f, 0x6d, 0x2d, 0x76, 0x61, 0x6c, 0x75, 0x65])
        let data: Data = {
            var d = Data(bytes: [
                0x00, 0x00, 0x19,       // 3-byte payload length (25 bytes)
                0x09,                   // 1-byte type (0x09 = CONTINUATION)
                0x04,                   // 1-byte flags (0x04 = END_HEADERS)
                0x00, 0x00, 0x00, 0x01, // 4-byte stream identifier
                ])
            d.append(headerData)
            return d
        }()
        
        guard let frame = decodeSpecificFrame(from: data, ofType: ContinuationFrame.self) else {
            return
        }
        
        XCTAssertEqual(frame.flags, .endHeaders)
        XCTAssertEqual(frame.payloadLength, 25)
        XCTAssertEqual(frame.streamIdentifier, stream)
        XCTAssertEqual(frame.headerData, headerData)
    }
    
    func testFrameFlagSetters() {
        func failsOn(_ expected: FrameFlags, _ error: Error) -> Bool {
            guard let fe = error as? FrameError else {
                return false
            }
            guard case let .invalidFlags(flags) = fe else {
                return false
            }
            return flags == expected
        }
        
        func failsWhenExpected(_ frame: inout Frame & Flaggable) {
            for flag in allFlags {
                if frame.type.allowedFlags.contains(flag) {
                    XCTAssertNoThrow(try frame.setFlags(flag))
                }
                else {
                    XCTAssertThrowsError(try frame.setFlags(flag)) { XCTAssertTrue(failsOn(flag, $0)) }
                }
            }
        }
        
        var frame: Frame & Flaggable = DataFrame(data: Data(), stream: 1)
        failsWhenExpected(&frame)
        
        frame = HeadersFrame(headerData: Data(), stream: 1)
        failsWhenExpected(&frame)
        
        frame = SettingsFrame()
        failsWhenExpected(&frame)
        
        frame = PushPromiseFrame(headerData: Data(), flags: [], stream: 1, promisedStreamId: 2)
        failsWhenExpected(&frame)
        
        frame = PingFrame(data: Data(count: 8))
        failsWhenExpected(&frame)
        
        frame = ContinuationFrame(headerData: Data(), stream: 1)
        failsWhenExpected(&frame)
    }
    
    static let allTests = [
        (testDataFrameEncoding, "testDataFrameEncoding"),
        (testDataFrameDecoding, "testDataFrameDecoding"),
        (testFrameFlagSetters, "testFrameFlagSetters"),
        (testHeadersFrameEncoding, "testHeadersFrameEncoding"),
        (testHeadersFrameDecoding, "testHeadersFrameDecoding"),
        (testEncodePriorityFrame, "testEncodePriorityFrame"),
        (testDecodePriorityFrame, "testDecodePriorityFrame"),
        (testEncodeResetStream, "testEncodeResetStream"),
        (testDecodeResetStream, "testDecodeResetStream"),
        (testEncodeSettings, "testEncodeSettings"),
        (testDecodeSettings, "testDecodeSettings"),
        (testEncodePushPromise, "testEncodePushPromise"),
        (testDecodePushPromise, "testDecodePushPromise"),
        (testEncodePing, "testEncodePing"),
        (testDecodePing, "testDecodePing"),
        (testEncodeGoAway, "testEncodeGoAway"),
        (testDecodeGoAway, "testDecodeGoAway"),
        (testEncodeWindowUpdate, "testEncodeWindowUpdate"),
        (testDecodeWindowUpdate, "testDecodeWindowUpdate"),
        (testEncodeContinuation, "testEncodeContinuation"),
        (testDecodeContinuation, "testDecodeContinuation"),
    ]

}
