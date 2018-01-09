//
//  Errors.swift
//  H2Swift
//
//  Created by Jim Dovey on 1/8/18.
//

public enum ProtocolError : UInt32, Error
{
    /// No error occurred. Sometimes thrown to indicate 'ignore this thing, e.g. for unknown frame types'.
    case noError                // 0
    case protocolError          // 1
    case internalError          // 2
    case flowControlError       // 3
    case settingsTimeout        // 4
    case streamClosed           // 5
    case frameSizeError         // 6
    case refusedStream          // 7
    case cancel                 // 8
    case compressionError       // 9
    case connectError           // 10
    case enhanceYourCalm        // 11
    case inadequateSecurity     // 12
    case http11Required         // 13
    
    var errorCode: Int {
        return Int(rawValue)
    }
}
