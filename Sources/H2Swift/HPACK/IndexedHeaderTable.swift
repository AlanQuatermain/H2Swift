//
//  IndexedHeaderTable.swift
//  H2Swift
//
//  Created by Jim Dovey on 1/3/18.
//

/// The unified header table used by HTTP/2, encompassing both static and dynamic tables.
public class IndexedHeaderTable
{
    // internal for testing
    var dynamicTable: DynamicHeaderTable
    
    init(maxDynamicTableSize: Int = DynamicHeaderTable.defaultSize) {
        self.dynamicTable = DynamicHeaderTable(maximumLength: maxDynamicTableSize)
    }
    
    public func header(at index: Int) -> (name: String, value: String)? {
        let entry: HeaderTableEntry
        if index < StaticHeaderTable.count {
            entry = StaticHeaderTable[index]    // Static table is already nicely 1-based
        }
        else if index - StaticHeaderTable.count < dynamicTable.count {
            entry = dynamicTable[index - StaticHeaderTable.count]
        }
        else {
            return nil
        }
        
        return (entry.name, entry.value ?? "")
    }
    
    public func firstHeaderMatch(forName name: String, value: String) -> (index: Int, matchesValue: Bool)? {
        var firstHeaderIndex: Int? = nil
        for (index, entry) in StaticHeaderTable.enumerated() where entry.name == name {
            // we've found a name, at least
            if firstHeaderIndex == nil {
                firstHeaderIndex = index
            }
            
            if entry.value == value {
                return (index, true)
            }
        }
        
        // no complete match: search the dynamic table now
        if let result = dynamicTable.findExistingHeader(named: name, value: value) {
            if let staticIndex = firstHeaderIndex, result.containsValue == false {
                // if we're unable to find an entry with a matching value, prefer a name-only result
                // referencing the static portion of the table
                return (staticIndex, false)
            }
            else {
                // return whatever the dynamic table gave us, but update the index appropriately
                return (result.index + StaticHeaderTable.count, result.containsValue)
            }
        }
        else if let staticIndex = firstHeaderIndex {
            // nothing in the dynamic table, but we found a header name match in the static table
            return (staticIndex, false)
        }
        else {
            // no match anywhere, have to encode the whole thing.
            return nil
        }
    }
    
    public func append(headerNamed name: String, value: String) throws {
        try dynamicTable.appendHeader(named: name, value: value)
    }
    
    public var dynamicTableLength: Int {
        return dynamicTable.length
    }
    
    public var maxDynamicTableLength: Int {
        get {
            return dynamicTable.maximumLength
        }
        set {
            dynamicTable.maximumLength = newValue
        }
    }
}
