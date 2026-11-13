import Foundation

/// Numeric tokens retain their original decimal representation, including unknown large values.
public struct JSONNumber: Equatable, Sendable {
    public let literal: String

    package init(_ literal: String) { self.literal = literal }

    /// Exact nonnegative integer conversion; never rounds through binary floating point.
    package var safeInteger: Int? {
        let parts = literal.lowercased().split(separator: "e", omittingEmptySubsequences: false)
        let negative = parts[0].first == "-"
        let mantissa = negative ? String(parts[0].dropFirst()) : String(parts[0])
        let decimal = mantissa.split(separator: ".", omittingEmptySubsequences: false)
        var digits = Array(decimal.joined().utf8).drop(while: { $0 == 48 })
        if digits.isEmpty { return 0 }
        guard !negative else { return nil }
        let exponent: Int
        if parts.count == 2 {
            guard let parsed = Int(parts[1]) else { return nil }
            exponent = parsed
        } else {
            exponent = 0
        }
        let fractionDigits = decimal.count == 2 ? decimal[1].utf8.count : 0
        let (scale, overflow) = exponent.subtractingReportingOverflow(fractionDigits)
        guard !overflow else { return nil }
        if scale < 0 {
            guard scale != Int.min, -scale <= digits.count else { return nil }
            guard digits.suffix(-scale).allSatisfy({ $0 == 48 }) else { return nil }
            digits = digits.dropLast(-scale)
        }
        let zeros = max(0, scale)
        guard digits.count <= 16, zeros <= 16 - digits.count else { return nil }
        let integer = String(decoding: digits, as: UTF8.self) + String(repeating: "0", count: zeros)
        guard let value = Int(integer), value <= 9_007_199_254_740_991 else { return nil }
        return value
    }
}

public struct JSONMember: Equatable, Sendable {
    public let key: String
    public let value: JSONValue

    package init(key: String, value: JSONValue) {
        self.key = key
        self.value = value
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key.utf8.elementsEqual(rhs.key.utf8) && lhs.value == rhs.value
    }
}

/// Object members remain ordered. Swift dictionaries would merge canonically equivalent keys.
public indirect enum JSONValue: Equatable, Sendable {
    case object([JSONMember])
    case array([JSONValue])
    case string(String)
    case number(JSONNumber)
    case bool(Bool)
    case null

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.object(let left), .object(let right)): left == right
        case (.array(let left), .array(let right)): left == right
        case (.string(let left), .string(let right)): left.utf8.elementsEqual(right.utf8)
        case (.number(let left), .number(let right)): left == right
        case (.bool(let left), .bool(let right)): left == right
        case (.null, .null): true
        default: false
        }
    }

    public subscript(key: String) -> JSONValue? {
        guard case .object(let members) = self else { return nil }
        return members.first { $0.key.utf8.elementsEqual(key.utf8) }?.value
    }

    public var string: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var array: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    package var safeInteger: Int? {
        guard case .number(let number) = self else { return nil }
        return number.safeInteger
    }

    var isFiniteNumber: Bool {
        guard case .number(let number) = self,
              let value = Double(number.literal) else { return false }
        return value.isFinite
    }

    package var isObject: Bool {
        if case .object = self { return true }
        return false
    }

    package func encoded(maximum: Int) throws -> Data {
        var data = Data()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        func write(_ bytes: Data) throws {
            guard bytes.count <= maximum - data.count else {
                throw BlueprintCodecError.limitExceeded(.decodedBytes)
            }
            data.append(bytes)
        }
        func punctuation(_ byte: UInt8) throws { try write(Data([byte])) }
        func append(_ value: JSONValue) throws {
            switch value {
            case .object(let members):
                try punctuation(123)
                for (index, member) in members.enumerated() {
                    if index > 0 { try punctuation(44) }
                    try write(encoder.encode(member.key))
                    try punctuation(58)
                    try append(member.value)
                }
                try punctuation(125)
            case .array(let values):
                try punctuation(91)
                for (index, value) in values.enumerated() {
                    if index > 0 { try punctuation(44) }
                    try append(value)
                }
                try punctuation(93)
            case .string(let text): try write(encoder.encode(text))
            case .number(let number): try write(Data(number.literal.utf8))
            case .bool(let value): try write(Data((value ? "true" : "false").utf8))
            case .null: try write(Data("null".utf8))
            }
        }
        try append(self)
        return data
    }
}
