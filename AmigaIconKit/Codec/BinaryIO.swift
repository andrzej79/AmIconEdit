import Foundation

/// Errors raised while reading or writing Amiga icon files.
public enum AmigaIconError: Error, Equatable, LocalizedError, Sendable {
    case notAnIcon
    case truncated(String)
    case invalid(String)
    case unsupported(String)
    case limitExceeded(String)

    public var errorDescription: String? {
        switch self {
        case .notAnIcon: return "The file is not an Amiga icon."
        case .truncated(let what): return "The icon file is truncated (\(what))."
        case .invalid(let what): return "The icon file is invalid (\(what))."
        case .unsupported(let what): return "Unsupported icon feature: \(what)."
        case .limitExceeded(let what): return "Icon limit exceeded: \(what)."
        }
    }
}

/// Sequential big-endian reader over a byte array. Every read is bounds checked.
struct BigEndianReader {
    let bytes: [UInt8]
    private(set) var offset: Int

    init(_ bytes: [UInt8], offset: Int = 0) {
        self.bytes = bytes
        self.offset = offset
    }

    var remaining: Int { max(0, bytes.count - offset) }
    var isAtEnd: Bool { offset >= bytes.count }

    private func need(_ count: Int, _ what: String) throws {
        guard count >= 0, offset + count <= bytes.count else { throw AmigaIconError.truncated(what) }
    }

    mutating func u8(_ what: String = "byte") throws -> UInt8 {
        try need(1, what)
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func u16(_ what: String = "word") throws -> UInt16 {
        try need(2, what)
        defer { offset += 2 }
        return UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    mutating func i16(_ what: String = "word") throws -> Int16 {
        Int16(bitPattern: try u16(what))
    }

    mutating func u32(_ what: String = "long") throws -> UInt32 {
        try need(4, what)
        defer { offset += 4 }
        return UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
    }

    mutating func i32(_ what: String = "long") throws -> Int32 {
        Int32(bitPattern: try u32(what))
    }

    mutating func bytes(_ count: Int, _ what: String = "data") throws -> [UInt8] {
        try need(count, what)
        defer { offset += count }
        return Array(bytes[offset..<offset + count])
    }

    mutating func skip(_ count: Int, _ what: String = "data") throws {
        try need(count, what)
        offset += count
    }

    func peek(_ count: Int) -> [UInt8]? {
        guard offset + count <= bytes.count else { return nil }
        return Array(bytes[offset..<offset + count])
    }
}

/// Big-endian byte writer.
struct BigEndianWriter {
    private(set) var bytes: [UInt8] = []

    init(capacity: Int = 0) { bytes.reserveCapacity(capacity) }

    mutating func u8(_ v: UInt8) { bytes.append(v) }
    mutating func u16(_ v: UInt16) { bytes.append(UInt8(v >> 8)); bytes.append(UInt8(v & 0xFF)) }
    mutating func i16(_ v: Int16) { u16(UInt16(bitPattern: v)) }
    mutating func u32(_ v: UInt32) {
        bytes.append(UInt8(v >> 24)); bytes.append(UInt8((v >> 16) & 0xFF))
        bytes.append(UInt8((v >> 8) & 0xFF)); bytes.append(UInt8(v & 0xFF))
    }
    mutating func i32(_ v: Int32) { u32(UInt32(bitPattern: v)) }
    mutating func append(_ data: [UInt8]) { bytes.append(contentsOf: data) }

    /// Overwrites a big-endian long at an existing offset.
    mutating func patchU32(_ v: UInt32, at offset: Int) {
        bytes[offset] = UInt8(v >> 24); bytes[offset + 1] = UInt8((v >> 16) & 0xFF)
        bytes[offset + 2] = UInt8((v >> 8) & 0xFF); bytes[offset + 3] = UInt8(v & 0xFF)
    }
}

/// Amiga strings are ISO-8859-1 (Latin-1).
enum AmigaText {
    static func decode(_ bytes: [UInt8]) -> String {
        let end = bytes.firstIndex(of: 0) ?? bytes.count
        // Latin-1 maps every byte, so this never fails.
        return String(bytes: bytes[..<end], encoding: .isoLatin1) ?? ""
    }

    /// Encodes as Latin-1; characters outside Latin-1 become "?". No NUL terminator added.
    static func encode(_ string: String) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(string.unicodeScalars.count)
        for scalar in string.unicodeScalars {
            if scalar.value == 0 { continue }
            out.append(scalar.value < 256 ? UInt8(scalar.value) : UInt8(ascii: "?"))
        }
        return out
    }
}
