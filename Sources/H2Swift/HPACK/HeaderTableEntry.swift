//
//  HeaderTableEntry.swift
//  H2Swift
//
//  Created by Jim Dovey on 1/2/18.
//

struct HeaderTableEntry
{
    var name: String
    var value: String?
    
    init(name: String, value: String? = nil) {
        self.name = name
        self.value = value
    }
    
    var length: Int {
        return name.utf8.count + (value?.utf8.count ?? 0) + 32
    }
}

extension HeaderTableEntry : Equatable, Hashable
{
    static func == (lhs: HeaderTableEntry, rhs: HeaderTableEntry) -> Bool {
        return lhs.name == rhs.name && lhs.value == rhs.value
    }
    
    var hashValue: Int {
        var result = name.hashValue
        if let value = value {
            result = result * 31 + value.hashValue
        }
        return result
    }
}
