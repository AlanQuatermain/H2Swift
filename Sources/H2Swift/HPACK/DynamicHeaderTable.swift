//
//  DynamicHeaderTable.swift
//  H2Swift
//
//  Created by Jim Dovey on 1/2/18.
//

import Foundation

class DynamicHeaderTable
{
    typealias HeaderTableStore = Array<HeaderTableEntry>
    
    /// The actual table, with items looked up by index.
    fileprivate var table: HeaderTableStore = []
    
    fileprivate var lock = ReadWriteLock(label: "HTTP/2 Dynamic Header Table")
    
    var length: Int {
        return table.reduce(0) { $0 + $1.length }
    }
    
    var maximumLength: Int {
        didSet {
            if length > maximumLength {
                purge()
            }
        }
    }
    
    var count: Int {
        return table.count
    }
    
    enum Error : Swift.Error
    {
        case entryTooLarge(HeaderTableEntry)
    }
    
    init(maximumLength: Int) {
        self.maximumLength = maximumLength
    }
    
    subscript(i: Int) -> HeaderTableEntry {
        return table[i]
    }
    
    func findExistingHeader(named name: String, value: String? = nil) -> (index: Int, containsValue: Bool)? {
        return lock.readLocked {
            if let value = value {
                // looking for both name and value, but can settle for just name
                // thus we'll search manually
                var firstNameMatch: Int? = nil
                for (index, entry) in table.enumerated() where entry.name == name {
                    if firstNameMatch == nil {
                        // record the first (most recent) index with a matching header name,
                        // in case there's no value match.
                        firstNameMatch = index
                    }
                    
                    if entry.value == value {
                        return (index, true)
                    }
                }
                
                // no value matches -- did we find a name match?
                if let index = firstNameMatch {
                    return (index, false)
                }
                else {
                    // no matches at all
                    return nil
                }
            }
            else {
                // just looking for a name, so we can use the stdlib to find that
                guard let index = table.index(where: { $0.name == name }) else {
                    return nil
                }
                
                return (index, false)
            }
        }
    }
    
    // Appends a header to the tables. Note that if this succeeds, the new item's index is always 0.
    func appendHeader(named name: String, value: String) throws {
        try lock.writeLocked {
            let entry = HeaderTableEntry(name: name, value: value)
            if length + entry.length > maximumLength {
                evict(atLeast: entry.length - (maximumLength - length))
                
                // if there's still not enough room, then the entry is too large for the table
                // note that the HTTP2 spec states that we should make this check AFTER evicting
                // the table's contents: http://httpwg.org/specs/rfc7541.html#entry.addition
                //
                //  "It is not an error to attempt to add an entry that is larger than the maximum size; an
                //   attempt to add an entry larger than the maximum size causes the table to be emptied of
                //   all existing entries and results in an empty table."
                
                guard length + entry.length <= maximumLength else {
                    throw Error.entryTooLarge(entry)
                }
            }
            
            // insert the new item at the start of the array
            // trust to the implementation to handle this nicely
            table.insert(entry, at: 0)
        }
    }
    
    private func purge() {
        lock.writeLocked {
            if length <= maximumLength {
                return
            }
            
            evict(atLeast: length - maximumLength)
        }
    }
    
    fileprivate func evict(atLeast lengthToRelease: Int) {
        lock.assertWriteLocked()
        
        var lenReleased = 0
        var numRemoved = 0
        
        for entry in table.reversed() {
            lenReleased = entry.length
            numRemoved += 1
            
            if (lenReleased >= lengthToRelease) {
                break
            }
        }
        
        table.removeLast(numRemoved)
    }
}

/// An alternative which maintains a pair of fast lookup tables in addition to the real header list.
class DynamicHeaderTableWithFastLookup : DynamicHeaderTable
{
    /// A pair of lookup tables, searching by name or name and value and retrieving a current index.
    private var nameLookup: [String : Int] = [:]
    private var nameValueLookup: [HeaderTableEntry : Int] = [:]
    
    override func findExistingHeader(named name: String, value: String? = nil) -> (index: Int, containsValue: Bool)? {
        return lock.readLocked {
            guard let value = value else {
                // just look for the name
                if let found = nameLookup[name] {
                    return (found, false)
                }
                else {
                    return nil
                }
            }
            
            let entry = HeaderTableEntry(name: name, value: value)
            if let found = nameValueLookup[entry] {
                return (found, true)
            }
            else if let found = nameLookup[name] {
                return (found, false)
            }
            else {
                return nil
            }
        }
    }
    
    // Appends a header to the tables. Note that if this succeeds, the new item's index is always 0.
    override func appendHeader(named name: String, value: String) throws {
        try lock.writeLocked {
            let entry = HeaderTableEntry(name: name, value: value)
            if length + entry.length > maximumLength {
                evict(atLeast: entry.length - (maximumLength - length))
                
                // if there's still not enough room, then the entry is too large for the table
                // note that the HTTP2 spec states that we should make this check AFTER evicting
                // the table's contents: http://httpwg.org/specs/rfc7541.html#entry.addition
                //
                //  "It is not an error to attempt to add an entry that is larger than the maximum size; an
                //   attempt to add an entry larger than the maximum size causes the table to be emptied of
                //   all existing entries and results in an empty table."
                
                guard length + entry.length <= maximumLength else {
                    throw Error.entryTooLarge(entry)
                }
            }
            
            // insert the new item at the start of the array
            // trust to the implementation to handle this nicely
            table.insert(entry, at: 0)
            
            // increment all the values in the lookup tables
            nameLookup = nameLookup.mapValues { $0 + 1 }
            nameValueLookup = nameValueLookup.mapValues { $0 + 1 }
            
            // insert the new item into the lookup tables
            nameLookup[entry.name] = 0
            nameValueLookup[entry] = 0
        }
    }
    
    override func evict(atLeast lengthToRelease: Int) {
        super.evict(atLeast: lengthToRelease)
        
        // now purge the lookup tables
        // I wish I knew a better way of handling this
        var nidx = nameLookup.startIndex
        repeat {
            if nameLookup[nidx].value >= table.endIndex {
                nameLookup.remove(at: nidx)
            }
            nidx = nameLookup.index(after: nidx)
        } while nidx < nameLookup.endIndex
        
        var vidx = nameValueLookup.startIndex
        repeat {
            if nameValueLookup[vidx].value >= table.endIndex {
                nameValueLookup.remove(at: vidx)
            }
            vidx = nameValueLookup.index(after: vidx)
        } while vidx < nameValueLookup.endIndex
    }
}
