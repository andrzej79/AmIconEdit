import Foundation

/// Converts between Amiga bitplane data (`struct Image` ImageData) and chunky indexed pixels.
///
/// Planes are stored one after another; each row of a plane is padded to a 16-bit word, and bit 7
/// of the first byte is the leftmost pixel. Plane 0 holds bit 0 of the colour index.
public enum PlanarCodec {
    public static func bytesPerRow(width: Int) -> Int { ((width + 15) / 16) * 2 }

    public static func dataSize(width: Int, height: Int, depth: Int) -> Int {
        bytesPerRow(width: width) * height * depth
    }

    public static func decode(_ data: [UInt8], width: Int, height: Int, depth: Int) throws -> IndexedImage {
        let bpr = bytesPerRow(width: width)
        guard data.count >= bpr * height * depth else { throw AmigaIconError.truncated("bitplanes") }
        var pixels = [UInt8](repeating: 0, count: width * height)
        let planeSize = bpr * height
        for plane in 0..<min(depth, 8) {
            let bit = UInt8(1 << plane)
            let base = plane * planeSize
            for y in 0..<height {
                let row = base + y * bpr
                let out = y * width
                for x in 0..<width where data[row + (x >> 3)] & (0x80 >> UInt8(x & 7)) != 0 {
                    pixels[out + x] |= bit
                }
            }
        }
        return IndexedImage(width: width, height: height, pixels: pixels)
    }

    public static func encode(_ image: IndexedImage, depth: Int) -> [UInt8] {
        let width = image.width, height = image.height
        let bpr = bytesPerRow(width: width)
        let planeSize = bpr * height
        var data = [UInt8](repeating: 0, count: planeSize * depth)
        for plane in 0..<min(depth, 8) {
            let bit = UInt8(1 << plane)
            let base = plane * planeSize
            for y in 0..<height {
                let row = base + y * bpr
                let src = y * width
                for x in 0..<width where image.pixels[src + x] & bit != 0 {
                    data[row + (x >> 3)] |= 0x80 >> UInt8(x & 7)
                }
            }
        }
        return data
    }
}
