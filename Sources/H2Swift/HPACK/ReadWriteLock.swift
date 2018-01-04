//
//  ReadWriteLock.swift
//  H2Swift
//
//  Created by Jim Dovey on 1/2/18.
//

import Dispatch

class ReadWriteLock
{
    private var queue: DispatchQueue
    
    init(label: String) {
        queue = DispatchQueue(label: label, attributes: .concurrent)
    }
    
    func readLocked<T>(execute block: () throws -> T) rethrows -> T {
        return try queue.sync(execute: block)
    }
    
    func writeLocked<T>(execute block: () throws -> T) rethrows -> T {
        return try queue.sync(flags: .barrier, execute: block)
    }
    
    func assertLocked() {
        dispatchPrecondition(condition: .onQueue(queue))
    }
    
    func assertWriteLocked() {
        dispatchPrecondition(condition: .onQueueAsBarrier(queue))
    }
    
    func assertUnlocked() {
        dispatchPrecondition(condition: .notOnQueue(queue))
    }
}
