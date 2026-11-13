import Foundation

/// Checks structural budgets during parsing, before constructing an unbounded object tree.
package struct BoundedJSONParser {
    private let bytes: [UInt8]
    private let limits: BlueprintCodecLimits
    private var cursor = 0
    private var nodes = 0

    package init(data: Data, limits: BlueprintCodecLimits) throws {
        guard String(data: data, encoding: .utf8) != nil else {
            throw BlueprintCodecError.invalidSource("Decoded JSON is not valid UTF-8.")
        }
        self.bytes = Array(data)
        self.limits = limits
        if bytes.starts(with: [0xef, 0xbb, 0xbf]) { cursor = 3 }
    }

    package mutating func parse() throws -> JSONValue {
        let value = try parseValue(depth: 0)
        skipWhitespace()
        guard cursor == bytes.count else { throw invalidJSON() }
        return value
    }

    private mutating func parseValue(depth: Int) throws -> JSONValue {
        guard depth <= limits.jsonDepth else { throw BlueprintCodecError.limitExceeded(.jsonDepth) }
        guard nodes < limits.jsonNodes else { throw BlueprintCodecError.limitExceeded(.jsonNodes) }
        nodes += 1
        skipWhitespace()
        guard cursor < bytes.count else { throw invalidJSON() }
        switch bytes[cursor] {
        case 123: return try parseObject(depth: depth)
        case 91: return try parseArray(depth: depth)
        case 34: return .string(try parseString())
        case 116:
            try consume("true")
            return .bool(true)
        case 102:
            try consume("false")
            return .bool(false)
        case 110:
            try consume("null")
            return .null
        case 45, 48...57: return .number(try parseNumber())
        default: throw invalidJSON()
        }
    }

    private mutating func parseObject(depth: Int) throws -> JSONValue {
        cursor += 1
        skipWhitespace()
        var members: [JSONMember] = []
        var keys = Set<Data>()
        if take(125) { return .object(members) }
        while true {
            skipWhitespace()
            let key = try parseString()
            guard keys.insert(Data(key.utf8)).inserted else {
                throw BlueprintCodecError.invalidSource("Duplicate JSON object key.")
            }
            skipWhitespace()
            guard take(58) else { throw invalidJSON() }
            let value = try parseValue(depth: depth + 1)
            members.append(JSONMember(key: key, value: value))
            skipWhitespace()
            if take(125) { break }
            guard take(44) else { throw invalidJSON() }
        }
        return .object(members)
    }

    private mutating func parseArray(depth: Int) throws -> JSONValue {
        cursor += 1
        skipWhitespace()
        var values: [JSONValue] = []
        if take(93) { return .array(values) }
        while true {
            values.append(try parseValue(depth: depth + 1))
            skipWhitespace()
            if take(93) { break }
            guard take(44) else { throw invalidJSON() }
        }
        return .array(values)
    }

    private mutating func parseString() throws -> String {
        let start = cursor
        guard take(34) else { throw invalidJSON() }
        while cursor < bytes.count {
            let byte = bytes[cursor]
            cursor += 1
            if byte == 34 {
                do {
                    return try JSONDecoder().decode(String.self, from: Data(bytes[start..<cursor]))
                } catch {
                    throw BlueprintCodecError.invalidSource("Invalid JSON string or Unicode escape.")
                }
            }
            guard byte >= 32 else { throw invalidJSON() }
            if byte == 92 {
                guard cursor < bytes.count else { throw invalidJSON() }
                cursor += 1
            }
        }
        throw invalidJSON()
    }

    private mutating func parseNumber() throws -> JSONNumber {
        let start = cursor
        _ = take(45)
        if !take(48) {
            guard cursor < bytes.count, (49...57).contains(bytes[cursor]) else { throw invalidJSON() }
            consumeDigits()
        }
        if take(46) {
            guard cursor < bytes.count, (48...57).contains(bytes[cursor]) else { throw invalidJSON() }
            consumeDigits()
        }
        if take(101) || take(69) {
            if !take(43) { _ = take(45) }
            guard cursor < bytes.count, (48...57).contains(bytes[cursor]) else { throw invalidJSON() }
            consumeDigits()
        }
        return JSONNumber(String(decoding: bytes[start..<cursor], as: UTF8.self))
    }

    private mutating func consumeDigits() {
        while cursor < bytes.count, (48...57).contains(bytes[cursor]) { cursor += 1 }
    }

    private mutating func consume(_ literal: String) throws {
        for byte in literal.utf8 {
            guard take(byte) else { throw invalidJSON() }
        }
    }

    private mutating func skipWhitespace() {
        while cursor < bytes.count, [9, 10, 13, 32].contains(bytes[cursor]) { cursor += 1 }
    }

    private mutating func take(_ byte: UInt8) -> Bool {
        guard cursor < bytes.count, bytes[cursor] == byte else { return false }
        cursor += 1
        return true
    }

    private func invalidJSON() -> BlueprintCodecError { .invalidSource("Invalid blueprint JSON.") }
}
