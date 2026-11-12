import Foundation
@testable import AmigaIconKit

final class FixtureBundleToken {}

enum Fixtures {
    static let names = ["Warp.guide", "WarpAmpVis", "WarpDashboard", "warpNET", "WUSB0"]

    static func data(_ name: String) throws -> Data {
        let bundle = Bundle(for: FixtureBundleToken.self)
        guard let url = bundle.url(forResource: name, withExtension: "info")
            ?? bundle.url(forResource: name, withExtension: "info", subdirectory: "Fixtures") else {
            throw AmigaIconError.invalid("missing fixture \(name).info")
        }
        return try Data(contentsOf: url)
    }

    static func bytes(_ name: String) throws -> [UInt8] { [UInt8](try data(name)) }

    static func icon(_ name: String) throws -> AmigaIcon { try AmigaIcon(data: data(name)) }
}

/// Deterministic pseudo random numbers for reproducible tests.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

/// CRC-32 (IEEE) for building PNG chunks in tests.
enum CRC32 {
    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for b in bytes {
            crc ^= UInt32(b)
            for _ in 0..<8 { crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }
}
