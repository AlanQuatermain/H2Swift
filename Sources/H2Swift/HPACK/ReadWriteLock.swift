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
    private let preconditionKey = DispatchSpecificKey<ObjectIdentifier>()
    
    init(label: String) {
        queue = DispatchQueue(label: label, attributes: .concurrent)
        queue.setSpecific(key: preconditionKey, value: ObjectIdentifier(self))
    }
    
    func readLocked<T>(execute block: () throws -> T) rethrows -> T {
        return try queue.sync(execute: block)
    }
    
    func writeLocked<T>(execute block: () throws -> T) rethrows -> T {
        return try queue.sync(flags: .barrier, execute: block)
    }
    
    func assertLocked() {
        if #available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
            dispatchPrecondition(condition: .onQueue(queue))
        }
        else {
            precondition(DispatchQueue.getSpecific(key: preconditionKey) == ObjectIdentifier(self))
        }
    }
    
    func assertWriteLocked() {
        if #available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
            dispatchPrecondition(condition: .onQueueAsBarrier(queue))
        }
        else {
            precondition(DispatchQueue.getSpecific(key: preconditionKey) == ObjectIdentifier(self))
        }
    }
    
    func assertUnlocked() {
        if #available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
            dispatchPrecondition(condition: .notOnQueue(queue))
        }
        else {
            precondition(DispatchQueue.getSpecific(key: preconditionKey) != ObjectIdentifier(self))
        }
    }
}
