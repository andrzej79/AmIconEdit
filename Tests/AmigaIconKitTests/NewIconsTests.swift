import Foundation
import Testing
@testable import AmigaIconKit

/// Minimal NewIcons encoder used to produce test data (follows the format rules the decoder documents).
enum NewIconsTestEncoder {
    static func char(_ value: UInt8) -> UInt8 { value < 0x50 ? value + 0x20 : value + 0x51 }

    /// Packs values of `bits` width into 7-bit characters (zero padded).
    static func pack(_ values: [UInt8], bits: Int) -> [UInt8] {
        var bitList: [UInt8] = []
        for v in values { for i in stride(from: bits - 1, through: 0, by: -1) { bitList.append((v >> UInt8(i)) & 1) } }
        while bitList.count % 7 != 0 { bitList.append(0) }
        return stride(from: 0, to: bitList.count, by: 7).map { start in
            char(bitList[start..<start + 7].reduce(0) { $0 << 1 | $1 })
        }
    }

    static func lines(prefix: String, image: IndexedImage, palette: Palette, transparent: Bool,
                      paletteBytesPerLine: Int = 1000, groupsPerLine: Int = 100) -> [String] {
        var depth = 1
        while (1 << depth) < palette.count { depth += 1 }
        let n = palette.count
        let header: [UInt8] = [transparent ? 0x42 : 0x43, UInt8(image.width + 0x21), UInt8(image.height + 0x21),
                               UInt8((n >> 6) + 0x21), UInt8((n & 63) + 0x21)]
        let rgb = palette.colors.flatMap { [$0.r, $0.g, $0.b] }
        var out: [[UInt8]] = []
        var start = 0
        while start < rgb.count {
            let chunk = Array(rgb[start..<min(rgb.count, start + paletteBytesPerLine)])
            out.append((start == 0 ? header : []) + pack(chunk, bits: 8))
            start += paletteBytesPerLine
        }
        // Like the real encoder: each line holds as many whole pixels as fit into its 7-bit groups,
        // so the unused bits at the end of a line are always fewer than one pixel.
        let pixelsPerLine = max(1, groupsPerLine * 7 / depth)
        start = 0
        while start < image.pixels.count {
            out.append(pack(Array(image.pixels[start..<min(image.pixels.count, start + pixelsPerLine)]), bits: depth))
            start += pixelsPerLine
        }
        return out.map { prefix + String(bytes: $0, encoding: .isoLatin1)! }
    }
}

@Suite("NewIcons decoding")
struct NewIconsTests {
    func randomImage(_ w: Int, _ h: Int, colors: Int, seed: UInt64) -> IndexedImage {
        var rng = SeededGenerator(seed: seed)
        return IndexedImage(width: w, height: h, pixels: (0..<(w * h)).map { _ in UInt8.random(in: 0..<UInt8(colors), using: &rng) })
    }

    func randomPalette(_ n: Int, seed: UInt64) -> Palette {
        var rng = SeededGenerator(seed: seed)
        return Palette((0..<n).map { _ in RGBColor(UInt8.random(in: 0...255, using: &rng), UInt8.random(in: 0...255, using: &rng),
                                                   UInt8.random(in: 0...255, using: &rng)) })
    }

    @Test func decodesSingleLinePalette() throws {
        let palette = randomPalette(5, seed: 1)
        let image = randomImage(7, 3, colors: 5, seed: 2)
        let lines = NewIconsTestEncoder.lines(prefix: "IM1=", image: image, palette: palette, transparent: true, groupsPerLine: 4)
        let decoded = try #require(NewIconsDecoder.decode(toolTypes: ["FILETYPE=TEXT", " "] + lines))
        #expect(decoded.normal.image == image)
        #expect(decoded.normal.palette == palette)
        #expect(decoded.normal.transparentIndex == 0)
        #expect(decoded.selected == nil)
    }

    @Test(arguments: [2, 8, 40, 63, 200])
    func decodesPaletteSpanningLinesAndBothImages(colors: Int) throws {
        let palette = randomPalette(colors, seed: UInt64(colors))
        let normal = randomImage(36, 40, colors: colors, seed: 3)
        let selected = randomImage(36, 40, colors: colors, seed: 4)
        let lines = NewIconsTestEncoder.lines(prefix: "IM1=", image: normal, palette: palette, transparent: false,
                                              paletteBytesPerLine: 99, groupsPerLine: 17)
            + NewIconsTestEncoder.lines(prefix: "IM2=", image: selected, palette: palette, transparent: true,
                                        paletteBytesPerLine: 60, groupsPerLine: 101)
        let decoded = try #require(NewIconsDecoder.decode(toolTypes: lines))
        #expect(decoded.normal.image == normal)
        #expect(decoded.normal.palette == palette)
        #expect(decoded.normal.transparentIndex == nil)
        #expect(decoded.selected?.image == selected)
        #expect(decoded.selected?.transparentIndex == 0)
    }

    @Test func expandsZeroRunCharacters() throws {
        // 2 colours (depth 1), 14×1 image; palette black/white in line 1.
        let header: [UInt8] = [0x43, 14 + 0x21, 1 + 0x21, 0x21, 2 + 0x21]
        let paletteChars = NewIconsTestEncoder.pack([0, 0, 0, 255, 255, 255], bits: 8)
        // Pixels: 0xD2 = two zero groups = 14 zero bits = 14 pixels of colour 0.
        let lines = ["IM1=" + String(bytes: header + paletteChars, encoding: .isoLatin1)!,
                     "IM1=" + String(bytes: [0xD2], encoding: .isoLatin1)!]
        let decoded = try #require(NewIconsDecoder.decode(toolTypes: lines))
        #expect(decoded.normal.image.pixels == Array(repeating: 0, count: 14))
        #expect(decoded.normal.palette.colors == [.black, .white])
    }

    @Test func dropsBitsThatCrossTheEndOfALine() throws {
        // depth 3 (5 colours): one 7-bit group per line holds two pixels plus one unused bit.
        let palette = randomPalette(5, seed: 9)
        let image = IndexedImage(width: 4, height: 1, pixels: [1, 2, 3, 4])
        let lines = NewIconsTestEncoder.lines(prefix: "IM1=", image: image, palette: palette, transparent: false, groupsPerLine: 1)
        #expect(lines.count == 3)
        #expect(try NewIconsDecoder.decode(toolTypes: lines)?.normal.image == image)
    }

    @Test func rejectsCorruptData() {
        #expect(NewIconsDecoder.decode(toolTypes: nil) == nil)
        #expect(NewIconsDecoder.decode(toolTypes: ["IM1=B"]) == nil)                    // short header
        #expect(NewIconsDecoder.decode(toolTypes: ["IM1=BEI!.", "IM1=\u{7F}"]) == nil)  // palette truncated / bad char
        let palette = randomPalette(4, seed: 5)
        var lines = NewIconsTestEncoder.lines(prefix: "IM1=", image: randomImage(10, 10, colors: 4, seed: 6),
                                              palette: palette, transparent: true, groupsPerLine: 5)
        lines.removeLast()
        #expect(NewIconsDecoder.decode(toolTypes: lines) == nil)                        // pixels truncated
    }

    @Test func rendererAndPreviewShowNewIcons() throws {
        let palette = randomPalette(6, seed: 7)
        var icon = try Fixtures.icon("warpNET")
        icon.info.toolTypes = ["DONOTWAIT", " ", "*** DON'T EDIT THE FOLLOWING LINES!! ***"]
            + NewIconsTestEncoder.lines(prefix: "IM1=", image: randomImage(20, 18, colors: 6, seed: 8), palette: palette, transparent: true)
        let pictures = IconRenderer.pictures(of: .diskObject(icon))
        #expect(pictures.map(\.id) == ["newicons-normal", "classic-normal"])
        #expect(pictures[0].image.width == 20)
        // Tool types (and therefore the NewIcons data) survive saving unchanged.
        #expect(try AmigaIcon(data: icon.encoded()).newIcons == icon.newIcons)
    }
}
