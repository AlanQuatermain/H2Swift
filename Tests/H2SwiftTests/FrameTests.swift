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
        (testHeadersFrameDecoding, "testHeadersFrameDecoding")
    ]

}
