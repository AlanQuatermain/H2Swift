//
//  Stream.swift
//  H2Swift
//
//  Created by Jim Dovey on 1/8/18.
//

import Foundation

class Stream
{
    /// Possible states for a stream.
    enum State
    {
        /// Stream is reserved following transmission or receipt of a `PUSH_PROMISE` frame.
        ///
        /// If `local` is `true`, then this stream was created by the endpoint which sent the
        /// `PUSH_PROMISE`. If `false`, this is a remote stream created by the peer whose
        /// `PUSH_PROMISE` frame has been received.
        case reserved(local: Bool)
        
        /// Stream is open and available to both endpoints it connects to send frames of any
        /// type.
        case open
        
        /// One endpoint has closed this stream, while the other has it open.
        ///
        /// If `local` is `true`, then the local endpoint has closed this stream, and may send
        /// no more frames. If `local` is `false`, then the remote endpoint has signaled its
        /// closure of the stream via a frame with the `END_STREAM` flag set. It should not
        /// receive any frames other than `WINDOW_UPDATE`, `PRIORITY`, or `RST_STREAM`, but
        /// may be used to send any frame type.
        case halfClosed(local: Bool)
        
        /// The stream is closed and may not be used for sending or recieving frames, with the
        /// exception of `PRIORITY` frames.
        case closed
    }
}
