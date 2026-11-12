import Foundation

/// Reads and writes the OS3.5 `FORM ICON` (FACE + IMAG chunks).
enum GlowIconCodec {
    static let maxDimension = 256

    // MARK: Reading

    static func read(form: IFF.Form) throws -> GlowIcon {
        guard form.type == "ICON" else { throw AmigaIconError.unsupported("IFF FORM \(form.type)") }
        guard let face = form.chunks.first(where: { $0.id == "FACE" }) else {
            throw AmigaIconError.invalid("FORM ICON without FACE chunk")
        }
        var fr = BigEndianReader(face.data)
        let width = Int(try fr.u8("FACE width")) + 1
        let height = Int(try fr.u8("FACE height")) + 1
        let flags = try fr.u8("FACE flags")
        let aspect = try fr.u8("FACE aspect")
        let maxPaletteBytes = try? fr.u16("FACE palette size")

        var images: [(ColorImage, Bool)] = []
        var extras: [IFFChunk] = []
        for chunk in form.chunks where chunk.id != "FACE" {
            if chunk.id == "IMAG" && images.count < 2 {
                let shared = images.first?.0.palette
                images.append(try readImag(chunk.data, width: width, height: height, sharedPalette: shared))
            } else {
                extras.append(chunk)
            }
        }
        guard let (normal, _) = images.first else { throw AmigaIconError.invalid("FORM ICON without IMAG chunk") }
        var glow = GlowIcon(normal: normal,
                            selected: images.count > 1 ? images[1].0 : nil,
                            selectedSharesPalette: images.count > 1 ? !images[1].1 : false,
                            aspect: aspect, extraChunks: extras)
        glow.faceFlags = flags
        glow.preservedMaxPaletteBytes = Ignored(maxPaletteBytes)
        return glow
    }

    /// Returns the image and whether the chunk carried its own palette.
    static func readImag(_ data: [UInt8], width: Int, height: Int, sharedPalette: Palette?) throws -> (ColorImage, Bool) {
        var r = BigEndianReader(data)
        let transparent = Int(try r.u8("IMAG transparent colour"))
        let numColors = Int(try r.u8("IMAG colour count")) + 1
        let flags = try r.u8("IMAG flags")
        let imageFormat = try r.u8("IMAG image format")
        let paletteFormat = try r.u8("IMAG palette format")
        let depth = Int(try r.u8("IMAG depth"))
        let imageSize = Int(try r.u16("IMAG image size")) + 1
        let paletteSize = Int(try r.u16("IMAG palette size")) + 1
        let hasTransparency = flags & 1 != 0
        let hasPalette = flags & 2 != 0

        let imageData = try r.bytes(imageSize, "IMAG pixel data")
        let pixelCount = width * height
        var pixels: [UInt8]
        switch imageFormat {
        case 0:
            guard imageData.count >= pixelCount else { throw AmigaIconError.truncated("IMAG raw pixels") }
            pixels = Array(imageData.prefix(pixelCount))
        case 1:
            pixels = try GlowRLE.decode(imageData, depth: depth, count: pixelCount)
        default:
            throw AmigaIconError.unsupported("IMAG image format \(imageFormat)")
        }

        var palette: Palette
        if hasPalette {
            let paletteData = try r.bytes(paletteSize, "IMAG palette")
            let rgb: [UInt8]
            switch paletteFormat {
            case 0: rgb = paletteData
            case 1: rgb = try GlowRLE.decode(paletteData, depth: 8, count: numColors * 3)
            default: throw AmigaIconError.unsupported("IMAG palette format \(paletteFormat)")
            }
            guard rgb.count >= numColors * 3 else { throw AmigaIconError.truncated("IMAG palette") }
            palette = Palette((0..<numColors).map { RGBColor(rgb[$0 * 3], rgb[$0 * 3 + 1], rgb[$0 * 3 + 2]) })
        } else if let sharedPalette {
            palette = sharedPalette
        } else {
            palette = WorkbenchPalettes.displayPalette(WorkbenchPalettes.workbench31, depth: max(1, depth))
        }
        // Make sure every pixel has a colour.
        let maxPixel = Int(pixels.max() ?? 0)
        if maxPixel >= palette.count { palette = palette.resized(to: maxPixel + 1) }

        let image = IndexedImage(width: width, height: height, pixels: pixels)
        let tIndex = hasTransparency ? transparent : nil
        var color = ColorImage(image: image, palette: palette, transparentIndex: tIndex)
        color.source = Ignored(ColorImageSource(chunk: data, image: image, palette: palette,
                                                transparentIndex: tIndex, hadPalette: hasPalette))
        return (color, hasPalette)
    }

    // MARK: Writing

    static func validate(_ glow: GlowIcon) throws {
        for img in [glow.normal] + (glow.selected.map { [$0] } ?? []) {
            guard (1...maxDimension).contains(img.image.width), (1...maxDimension).contains(img.image.height) else {
                throw AmigaIconError.limitExceeded("colour images must be 1…256 pixels wide and high")
            }
            guard img.image.width == glow.width, img.image.height == glow.height else {
                throw AmigaIconError.invalid("normal and selected colour images must have the same size")
            }
            guard (1...256).contains(img.palette.count) else {
                throw AmigaIconError.limitExceeded("colour images need 1…256 palette entries")
            }
        }
    }

    static func write(_ glow: GlowIcon) throws -> [UInt8] {
        try validate(glow)
        var chunks: [IFFChunk] = []
        var allReused = true

        let normalChunk = writeImag(glow.normal, includePalette: true, reused: &allReused)
        var selectedChunk: [UInt8]?
        if let selected = glow.selected {
            let share = glow.selectedSharesPalette && selected.palette == glow.normal.palette
            selectedChunk = writeImag(selected, includePalette: !share, reused: &allReused)
        }

        let maxColors = max(glow.normal.palette.count, glow.selected?.palette.count ?? 0)
        let computed = UInt16(min(0xFFFF, maxColors * 3 - 1))
        let maxPaletteBytes = (allReused ? glow.preservedMaxPaletteBytes.value : nil) ?? computed

        var face = BigEndianWriter()
        face.u8(UInt8(glow.width - 1))
        face.u8(UInt8(glow.height - 1))
        face.u8(glow.faceFlags)
        face.u8(glow.aspect)
        face.u16(maxPaletteBytes)
        chunks.append(IFFChunk(id: "FACE", data: face.bytes))
        chunks.append(IFFChunk(id: "IMAG", data: normalChunk))
        if let selectedChunk { chunks.append(IFFChunk(id: "IMAG", data: selectedChunk)) }
        chunks.append(contentsOf: glow.extraChunks)
        return IFF.writeForm(type: "ICON", chunks: chunks)
    }

    static func writeImag(_ img: ColorImage, includePalette: Bool, reused: inout Bool) -> [UInt8] {
        if let src = img.source.value, src.image == img.image, src.palette == img.palette,
           src.transparentIndex == img.transparentIndex, src.hadPalette == includePalette {
            return src.chunk
        }
        reused = false
        let colorCount = img.palette.count
        let maxPixel = Int(img.image.maxIndex)
        let depth = GlowRLE.bitsNeeded(forColorCount: max(colorCount, maxPixel + 1))

        let rle = GlowRLE.encode(img.image.pixels, depth: depth)
        let useRLE = rle.count < img.image.pixels.count
        let imageData = useRLE ? rle : img.image.pixels

        var paletteData: [UInt8] = []
        if includePalette {
            paletteData.reserveCapacity(colorCount * 3)
            for c in img.palette.colors { paletteData += [c.r, c.g, c.b] }
        }

        var w = BigEndianWriter(capacity: 10 + imageData.count + paletteData.count)
        let t = img.transparentIndex.map { min(255, max(0, $0)) }
        w.u8(UInt8(t ?? 0))
        w.u8(UInt8(colorCount - 1))
        w.u8((t != nil ? 1 : 0) | (includePalette ? 2 : 0))
        w.u8(useRLE ? 1 : 0)
        w.u8(0) // palette stored uncompressed
        w.u8(UInt8(depth))
        w.u16(UInt16(imageData.count - 1))
        w.u16(UInt16(max(1, paletteData.count) - 1))
        w.append(imageData)
        w.append(paletteData)
        return w.bytes
    }
}
