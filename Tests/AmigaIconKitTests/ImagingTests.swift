import Foundation
import Testing
@testable import AmigaIconKit

@Suite("Quantisation, dithering and import")
struct ImagingTests {
    static let blackWhite = Palette([.black, .white])

    func solid(_ w: Int, _ h: Int, _ c: RGBColor, alpha: UInt8 = 255) -> RGBAImage {
        var img = RGBAImage(width: w, height: h)
        for i in 0..<(w * h) {
            img.pixels[i * 4] = c.r; img.pixels[i * 4 + 1] = c.g; img.pixels[i * 4 + 2] = c.b; img.pixels[i * 4 + 3] = alpha
        }
        return img
    }

    func gradient(_ w: Int, _ h: Int) -> RGBAImage {
        var img = RGBAImage(width: w, height: h)
        for y in 0..<h { for x in 0..<w {
            let o = (y * w + x) * 4
            img.pixels[o] = UInt8(x * 255 / max(1, w - 1))
            img.pixels[o + 1] = UInt8(y * 255 / max(1, h - 1))
            img.pixels[o + 2] = UInt8((x + y) * 255 / max(1, w + h - 2))
            img.pixels[o + 3] = 255
        } }
        return img
    }

    @Test func medianCutKeepsExactColorsWhenFew() {
        var img = solid(4, 4, RGBColor(10, 20, 30))
        img.pixels[0] = 200; img.pixels[1] = 100; img.pixels[2] = 0
        let palette = Quantizer.medianCut(img, maxColors: 8)
        #expect(Set(palette.colors) == [RGBColor(10, 20, 30), RGBColor(200, 100, 0)])
        #expect(palette.colors.first == RGBColor(10, 20, 30)) // most frequent first
    }

    @Test(arguments: [2, 4, 16, 31, 64, 256])
    func medianCutRespectsLimit(colors: Int) {
        let palette = Quantizer.medianCut(gradient(64, 64), maxColors: colors)
        #expect(palette.count <= colors)
        #expect(palette.count >= min(colors, 2))
    }

    @Test func medianCutIgnoresTransparentPixels() {
        var img = solid(2, 1, .white)
        img.pixels[0] = 255; img.pixels[1] = 0; img.pixels[2] = 0; img.pixels[3] = 0 // transparent red
        #expect(Quantizer.medianCut(img, maxColors: 4).colors == [.white])
    }

    @Test func floydSteinbergHalftonesMidGray() {
        let img = solid(64, 64, RGBColor(128, 128, 128))
        let out = Remapper.remap(img, to: Self.blackWhite, options: RemapOptions(dither: .floydSteinberg))
        let black = out.pixels.filter { $0 == 0 }.count
        let ratio = Double(black) / Double(out.pixels.count)
        #expect(abs(ratio - 0.5) < 0.05)
    }

    @Test func bayerProducesRegularPattern() {
        let img = solid(8, 8, RGBColor(128, 128, 128))
        let out = Remapper.remap(img, to: Self.blackWhite, options: RemapOptions(dither: .bayer4))
        // Every 4×4 tile has exactly half the pixels white.
        for ty in 0..<2 { for tx in 0..<2 {
            var white = 0
            for y in 0..<4 { for x in 0..<4 where out[tx * 4 + x, ty * 4 + y] == 1 { white += 1 } }
            #expect(white == 8)
        } }
        // And the pattern repeats.
        #expect(out[0, 0] == out[4, 4])
    }

    @Test func bayerMatrixIsPermutation() {
        let m = Remapper.bayerMatrix(8).flatMap { $0 }
        #expect(Set(m.map { Int($0 * 64) }) == Set(0..<64))
    }

    @Test(arguments: DitherMode.allCases)
    func ditherOutputUsesValidIndicesAndTransparency(mode: DitherMode) {
        var img = gradient(32, 32)
        for i in 0..<32 { img.pixels[i * 4 + 3] = 0 } // first row transparent
        let palette = WorkbenchPalettes.magicWB.palette
        let out = Remapper.remap(img, to: palette, options: RemapOptions(dither: mode, transparentIndex: 0))
        #expect(out.pixels.allSatisfy { Int($0) < palette.count })
        #expect((0..<32).allSatisfy { out[$0, 0] == 0 })
        // Opaque pixels never use the transparent index.
        #expect((0..<32).allSatisfy { x in (1..<32).allSatisfy { out[x, $0] != 0 } })
    }

    @Test func noDitherPicksNearestColor() {
        let out = Remapper.remap(solid(2, 2, RGBColor(250, 240, 245)), to: WorkbenchPalettes.workbench31.palette,
                                 options: RemapOptions(dither: .none))
        #expect(out.pixels == [2, 2, 2, 2]) // white
    }

    @Test func indexedRemapBetweenPalettes() {
        let source = Palette([.white, .black])
        let target = Palette([.black, RGBColor(250, 250, 250)])
        let image = IndexedImage(width: 2, height: 1, pixels: [0, 1])
        #expect(Remapper.remap(image, from: source, to: target).pixels == [1, 0])
    }

    @Test func importGeneratesPaletteWithTransparency() {
        var img = gradient(100, 50)
        for i in 0..<100 { img.pixels[i * 4 + 3] = 0 }
        let target = ImageImporter.Target(canvasWidth: 46, canvasHeight: 46, palette: Palette([.black]), transparentIndex: nil,
                                          maxColors: 256, maxSize: 256, fixedPalette: false)
        var options = ImageImporter.Options()
        options.paletteSource = .generate(colors: 16)
        let result = ImageImporter.importPicture(img, target: target, options: options)
        #expect(result.image.width == 46 && result.image.height == 46)
        #expect(result.palette.count <= 16)
        #expect(result.transparentIndex == 0)
        #expect(result.image[0, 0] == 0) // margin is transparent (fit keeps aspect ratio)
    }

    @Test func importResizeCanvasKeepsPictureSize() {
        let target = ImageImporter.Target(canvasWidth: 10, canvasHeight: 10, palette: Self.blackWhite, transparentIndex: nil,
                                          maxColors: 256, maxSize: 256, fixedPalette: false)
        var options = ImageImporter.Options()
        options.sizing = .resizeCanvas
        options.paletteSource = .keepCurrent
        let result = ImageImporter.importPicture(gradient(40, 30), target: target, options: options)
        #expect(result.image.width == 40 && result.image.height == 30)
        #expect(result.palette == Self.blackWhite)
    }

    @Test func importForClassicKeepsFixedPalette() {
        let palette = IconRenderer.classicPalette(depth: 2)
        let target = ImageImporter.Target(canvasWidth: 20, canvasHeight: 20, palette: palette, transparentIndex: nil,
                                          maxColors: 4, maxSize: 4096, fixedPalette: true)
        var options = ImageImporter.Options()
        options.paletteSource = .generate(colors: 64) // ignored for classic images
        let result = ImageImporter.importPicture(gradient(20, 20), target: target, options: options)
        #expect(result.palette == palette)
        #expect(result.transparentIndex == nil)
        #expect(result.image.pixels.allSatisfy { $0 < 4 })
    }

    @Test func rendererAppliesTransparency() {
        let image = IndexedImage(width: 2, height: 1, pixels: [0, 1])
        let rgba = ImageConversion.rgbaImage(from: image, palette: Self.blackWhite, transparentIndex: 0)
        #expect(rgba.pixels == [0, 0, 0, 0, 255, 255, 255, 255])
        let scaled = IconRenderer.scaled(rgba, factor: 3)
        #expect(scaled.width == 6 && scaled.height == 3)
        #expect(scaled.pixel(x: 5, y: 2).a == 255 && scaled.pixel(x: 2, y: 2).a == 0)
    }

    @Test func rendererListsAllPictures() throws {
        let pictures = IconRenderer.pictures(of: .diskObject(try Fixtures.icon("Warp.guide")))
        #expect(pictures.map(\.id) == ["color-normal", "color-selected", "classic-normal"])
        let classicOnly = IconRenderer.pictures(of: .diskObject(try Fixtures.icon("WUSB0")))
        #expect(classicOnly.map(\.id) == ["classic-normal", "classic-selected"])
    }

    @Test func pngEncodingRoundTrips() throws {
        let img = gradient(9, 7)
        let data = try #require(ImageConversion.pngData(from: img))
        #expect(ImageConversion.rgbaImage(fromEncoded: data) == img)
    }
}
