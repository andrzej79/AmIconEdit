import Compression
import Foundation

/// Best-effort decoder for AROS `ARGB` chunks (zlib-compressed 32-bit ARGB images) inside FORM ICON.
/// Read-only: the chunk is preserved verbatim on save but never generated.
public enum ARGBChunkDecoder {
    /// Decodes an `ARGB` chunk for an image of the given size.
    public static func decode(_ chunk: [UInt8], width: Int, height: Int) -> RGBAImage? {
        let expected = width * height * 4
        guard expected > 0 else { return nil }
        // The chunk starts with a small header; locate the zlib stream (CMF 0x78, valid FCHECK).
        for start in 0..<min(32, max(0, chunk.count - 2)) {
            let cmf = chunk[start], flg = chunk[start + 1]
            guard cmf == 0x78, (UInt16(cmf) << 8 | UInt16(flg)) % 31 == 0 else { continue }
            let deflate = Array(chunk[(start + 2)...])
            guard let argb = inflate(deflate, expectedSize: expected) else { continue }
            var rgba = [UInt8](repeating: 0, count: expected)
            for i in stride(from: 0, to: expected, by: 4) {
                rgba[i] = argb[i + 1]
                rgba[i + 1] = argb[i + 2]
                rgba[i + 2] = argb[i + 3]
                rgba[i + 3] = argb[i]
            }
            return RGBAImage(width: width, height: height, pixels: rgba)
        }
        return nil
    }

    /// Inflates raw DEFLATE data; returns nil unless exactly `expectedSize` bytes come out.
    static func inflate(_ data: [UInt8], expectedSize: Int) -> [UInt8]? {
        guard !data.isEmpty else { return nil }
        var out = [UInt8](repeating: 0, count: expectedSize + 1)
        let written = data.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                compression_decode_buffer(dst.baseAddress!, dst.count, src.baseAddress!, src.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expectedSize else { return nil }
        return Array(out.prefix(expectedSize))
    }

    /// Builds an `ARGB` chunk payload (used by tests to exercise the decoder).
    static func encodeForTesting(_ image: RGBAImage) -> [UInt8]? {
        var argb = [UInt8](repeating: 0, count: image.pixels.count)
        for i in stride(from: 0, to: argb.count, by: 4) {
            argb[i] = image.pixels[i + 3]
            argb[i + 1] = image.pixels[i]
            argb[i + 2] = image.pixels[i + 1]
            argb[i + 3] = image.pixels[i + 2]
        }
        var dst = [UInt8](repeating: 0, count: argb.count + 1024)
        let n = argb.withUnsafeBufferPointer { src in
            dst.withUnsafeMutableBufferPointer { d in
                compression_encode_buffer(d.baseAddress!, d.count, src.baseAddress!, src.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard n > 0 else { return nil }
        // 10-byte header (layout unknown to us; zeros), zlib header, deflate data.
        return [UInt8](repeating: 0, count: 10) + [0x78, 0x9C] + Array(dst.prefix(n))
    }
}
