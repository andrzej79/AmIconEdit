import Foundation

/// The OS3.5 icon run-length encoding.
///
/// The stream is a bit stream (MSB first). It consists of 8-bit control values followed by
/// `depth`-bit data values, like ByteRun1:
/// - control 0…127: copy the next `control + 1` values literally;
/// - control 129…255: repeat the next value `257 - control` times;
/// - control 128: no operation.
public enum GlowRLE {
    struct BitReader {
        let data: [UInt8]
        var pos = 0
        var buffer: UInt32 = 0
        var bits = 0

        mutating func read(_ n: Int) throws -> UInt32 {
            while bits < n {
                guard pos < data.count else { throw AmigaIconError.truncated("RLE data") }
                buffer = (buffer << 8) | UInt32(data[pos])
                pos += 1
                bits += 8
            }
            bits -= n
            let value = (buffer >> UInt32(bits)) & ((1 << UInt32(n)) - 1)
            buffer &= (1 << UInt32(bits)) - 1
            return value
        }
    }

    struct BitWriter {
        var bytes: [UInt8] = []
        var buffer: UInt32 = 0
        var bits = 0

        mutating func write(_ value: UInt32, _ n: Int) {
            buffer = (buffer << UInt32(n)) | (value & ((1 << UInt32(n)) - 1))
            bits += n
            while bits >= 8 {
                bits -= 8
                bytes.append(UInt8((buffer >> UInt32(bits)) & 0xFF))
            }
            buffer &= (1 << UInt32(bits)) - 1
        }

        mutating func finish() -> [UInt8] {
            if bits > 0 {
                bytes.append(UInt8((buffer << UInt32(8 - bits)) & 0xFF))
                bits = 0
                buffer = 0
            }
            return bytes
        }
    }

    /// Decodes `count` values of `depth` bits each.
    public static func decode(_ data: [UInt8], depth: Int, count: Int) throws -> [UInt8] {
        guard (1...8).contains(depth) else { throw AmigaIconError.invalid("RLE depth \(depth)") }
        var reader = BitReader(data: data)
        var out = [UInt8]()
        out.reserveCapacity(count)
        while out.count < count {
            let control = try reader.read(8)
            if control < 128 {
                for _ in 0...Int(control) where out.count < count {
                    out.append(UInt8(try reader.read(depth)))
                }
            } else if control > 128 {
                let value = UInt8(try reader.read(depth))
                let run = min(257 - Int(control), count - out.count)
                out.append(contentsOf: repeatElement(value, count: run))
            }
        }
        return out
    }

    /// Encodes values (each must fit in `depth` bits).
    public static func encode(_ values: [UInt8], depth: Int) -> [UInt8] {
        precondition((1...8).contains(depth))
        var writer = BitWriter()
        var i = 0
        let n = values.count
        var literals: [UInt8] = []

        func flushLiterals() {
            var start = 0
            while start < literals.count {
                let chunk = min(128, literals.count - start)
                writer.write(UInt32(chunk - 1), 8)
                for v in literals[start..<start + chunk] { writer.write(UInt32(v), depth) }
                start += chunk
            }
            literals.removeAll(keepingCapacity: true)
        }

        while i < n {
            var run = 1
            while i + run < n && values[i + run] == values[i] && run < 128 { run += 1 }
            if run >= 2 {
                // A run of 2 is only worthwhile if it does not split a literal sequence.
                if run == 2 && !literals.isEmpty {
                    literals.append(values[i]); literals.append(values[i + 1])
                } else {
                    flushLiterals()
                    writer.write(UInt32(257 - run), 8)
                    writer.write(UInt32(values[i]), depth)
                }
                i += run
            } else {
                literals.append(values[i])
                i += 1
            }
        }
        flushLiterals()
        return writer.finish()
    }

    /// Packs values without compression (`depth` bits each); used to measure the raw alternative.
    static func bitsNeeded(forColorCount count: Int) -> Int {
        var depth = 1
        while (1 << depth) < count && depth < 8 { depth += 1 }
        return depth
    }
}
