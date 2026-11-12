import Foundation
import Testing
@testable import AmigaIconKit

@Suite("RLE, planar and IFF codecs")
struct LowLevelCodecTests {
    @Test func rleDecodesKnownVectors() throws {
        // depth 8: literal run of 3, then a repeat of 4 (control 0xFD = -3 -> 4 values), then no-op 0x80.
        let data: [UInt8] = [0x02, 10, 20, 30, 0xFD, 7, 0x80, 0x00, 99]
        #expect(try GlowRLE.decode(data, depth: 8, count: 8) == [10, 20, 30, 7, 7, 7, 7, 99])
    }

    @Test func rleDecodesBitPackedValues() throws {
        // depth 4: control 0x01 (2 literals) = 0000 0001, then values 0xA, 0x5 -> bytes 0x01 0xA5.
        #expect(try GlowRLE.decode([0x01, 0xA5], depth: 4, count: 2) == [0xA, 0x5])
    }

    @Test(arguments: 1...8)
    func rleRoundTripsRandomData(depth: Int) throws {
        var rng = SeededGenerator(seed: UInt64(depth))
        for length in [1, 2, 3, 7, 128, 129, 300, 2116] {
            let maxValue = UInt8((1 << depth) - 1)
            // Mix of runs and noise.
            var values: [UInt8] = []
            while values.count < length {
                let v = UInt8.random(in: 0...maxValue, using: &rng)
                let run = Bool.random(using: &rng) ? Int.random(in: 1...200, using: &rng) : 1
                values += Array(repeating: v, count: run)
            }
            values = Array(values.prefix(length))
            let encoded = GlowRLE.encode(values, depth: depth)
            #expect(try GlowRLE.decode(encoded, depth: depth, count: values.count) == values)
        }
    }

    @Test func rleCompressesRuns() {
        let values = [UInt8](repeating: 3, count: 1000)
        #expect(GlowRLE.encode(values, depth: 2).count < 30)
    }

    @Test func rleRejectsTruncatedData() {
        #expect(throws: AmigaIconError.self) { try GlowRLE.decode([0x05, 1, 2], depth: 8, count: 6) }
    }

    @Test func planarDecodesKnownRow() throws {
        // 8×1, depth 1: 0b10000001 + pad byte.
        let image = try PlanarCodec.decode([0x81, 0x00], width: 8, height: 1, depth: 1)
        #expect(image.pixels == [1, 0, 0, 0, 0, 0, 0, 1])
        // Two planes: plane 0 = 0xF0, plane 1 = 0xCC -> indices 3,3,1,1,2,2,0,0.
        let two = try PlanarCodec.decode([0xF0, 0, 0xCC, 0], width: 8, height: 1, depth: 2)
        #expect(two.pixels == [3, 3, 1, 1, 2, 2, 0, 0])
    }

    @Test(arguments: [1, 7, 15, 16, 17, 33, 54])
    func planarRoundTrips(width: Int) throws {
        var rng = SeededGenerator(seed: UInt64(width))
        for depth in 1...8 {
            let height = 5
            let maxValue = UInt8((1 << depth) - 1)
            let pixels = (0..<(width * height)).map { _ in UInt8.random(in: 0...maxValue, using: &rng) }
            let image = IndexedImage(width: width, height: height, pixels: pixels)
            let data = PlanarCodec.encode(image, depth: depth)
            #expect(data.count == PlanarCodec.dataSize(width: width, height: height, depth: depth))
            #expect(try PlanarCodec.decode(data, width: width, height: height, depth: depth) == image)
        }
    }

    @Test func iffRoundTripsOddChunks() throws {
        let chunks = [IFFChunk(id: "FACE", data: [1, 2, 3]), IFFChunk(id: "TEST", data: [9]), IFFChunk(id: "EVEN", data: [1, 2])]
        let bytes = IFF.writeForm(type: "ICON", chunks: chunks)
        #expect(bytes.count % 2 == 0)
        var reader = BigEndianReader(bytes)
        let form = try IFF.readForm(&reader)
        #expect(form.type == "ICON")
        #expect(form.chunks == chunks)
        #expect(form.byteCount == bytes.count)
    }

    @Test func latin1Strings() {
        let s = "Grüße ©"
        #expect(AmigaText.decode(AmigaText.encode(s)) == s)
        #expect(AmigaText.encode("€") == [UInt8(ascii: "?")])
        #expect(AmigaText.decode([65, 66, 0, 67]) == "AB")
    }

    @Test func argbChunkDecodes() throws {
        var image = RGBAImage(width: 3, height: 2)
        for i in 0..<6 { image.pixels[i * 4] = UInt8(i * 40); image.pixels[i * 4 + 3] = UInt8(255 - i) }
        let chunk = try #require(ARGBChunkDecoder.encodeForTesting(image))
        #expect(ARGBChunkDecoder.decode(chunk, width: 3, height: 2) == image)
        #expect(ARGBChunkDecoder.decode([1, 2, 3], width: 3, height: 2) == nil)
    }

    @Test func pngIconDecodesImagesAndAttributes() throws {
        var rgba = RGBAImage(width: 4, height: 4)
        for i in 0..<16 { rgba.pixels[i * 4] = 200; rgba.pixels[i * 4 + 3] = 255 }
        let png = [UInt8](try #require(ImageConversion.pngData(from: rgba)))

        var tags = BigEndianWriter()
        tags.u32(PNGIconDecoder.Tag.type.rawValue); tags.u32(3)
        tags.u32(PNGIconDecoder.Tag.stackSize.rawValue); tags.u32(65536)
        tags.u32(PNGIconDecoder.Tag.defaultTool.rawValue); tags.append(Array("SYS:Tool".utf8) + [0])
        tags.u32(PNGIconDecoder.Tag.toolType.rawValue); tags.append(Array("A=1".utf8) + [0])
        tags.u32(PNGIconDecoder.Tag.toolType.rawValue); tags.append(Array("B".utf8) + [0])
        tags.u32(PNGIconDecoder.Tag.iconX.rawValue); tags.u32(5)
        tags.u32(PNGIconDecoder.Tag.iconY.rawValue); tags.u32(6)
        let withChunk = insertChunk(type: "icOn", data: tags.bytes, intoPNG: png)

        guard case .png(let icon) = try IconFile.read(Data(withChunk + png)) else {
            Issue.record("not detected as PNG icon"); return
        }
        #expect(icon.normal.width == 4)
        #expect(icon.selected != nil)
        #expect(icon.info.type == .tool)
        #expect(icon.info.stackSize == 65536)
        #expect(icon.info.defaultTool == "SYS:Tool")
        #expect(icon.info.toolTypes == ["A=1", "B"])
        #expect(icon.info.position == IconPosition(x: 5, y: 6))
    }

    /// Inserts a chunk right after IHDR.
    private func insertChunk(type: String, data: [UInt8], intoPNG png: [UInt8]) -> [UInt8] {
        let ihdrEnd = 8 + 4 + 4 + 13 + 4
        var w = BigEndianWriter()
        w.u32(UInt32(data.count))
        let body = Array(type.utf8) + data
        w.append(body)
        w.u32(CRC32.checksum(body))
        return Array(png[..<ihdrEnd]) + w.bytes + Array(png[ihdrEnd...])
    }
}
