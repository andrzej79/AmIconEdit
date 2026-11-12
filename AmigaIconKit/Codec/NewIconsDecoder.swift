import Foundation

/// The images of a NewIcons icon (stored in the tool types of a classic icon).
public struct NewIconsImages: Equatable, Sendable {
    public var normal: ColorImage
    public var selected: ColorImage?
}

/// Read-only decoder for NewIcons images, which are stored as text in the tool types:
///
///     *** DON'T EDIT THE FOLLOWING LINES!! ***
///     IM1=<header><palette…>
///     IM1=<pixels…>
///     IM2=…            (selected image, same layout)
///
/// - Header (5 characters after `IM1=`): `B` = colour 0 transparent / `C` = opaque,
///   width + 0x21, height + 0x21, colour count as two 6-bit digits (each + 0x21).
/// - Each character carries 7 bits: 0x20–0x6F → 0x00–0x4F, 0xA1–0xD0 → 0x50–0x7F;
///   0xD1–0xFF stands for (c − 0xD0) groups of seven zero bits.
/// - Each line is an independent bit stream: bits left over at the end of a line are discarded.
/// - The palette (8-bit R, G, B values) may span several lines; the pixels (`depth` bits each,
///   depth = bits needed for the colour count) start on the line after the palette ends.
public enum NewIconsDecoder {
    static let normalPrefix = "IM1="
    static let selectedPrefix = "IM2="

    /// Whether a tool type line holds NewIcons image data.
    public static func isImageData(_ toolType: String) -> Bool {
        toolType.hasPrefix(normalPrefix) || toolType.hasPrefix(selectedPrefix)
    }

    /// Decodes the NewIcons images from tool types; nil if there are none or they are corrupt.
    public static func decode(toolTypes: [String]?) -> NewIconsImages? {
        guard let toolTypes else { return nil }
        func lines(_ prefix: String) -> [[UInt8]] {
            toolTypes.filter { $0.hasPrefix(prefix) }.map { Array(AmigaText.encode($0).dropFirst(prefix.count)) }
        }
        let normalLines = lines(normalPrefix)
        guard !normalLines.isEmpty, let normal = try? decodeImage(lines: normalLines) else { return nil }
        let selectedLines = lines(selectedPrefix)
        let selected = selectedLines.isEmpty ? nil : try? decodeImage(lines: selectedLines)
        return NewIconsImages(normal: normal, selected: selected)
    }

    /// Decodes one image from its data lines (without the `IMx=` prefix).
    public static func decodeImage(lines: [[UInt8]]) throws -> ColorImage {
        guard let first = lines.first, first.count >= 5 else { throw AmigaIconError.truncated("NewIcons header") }
        let transparent = first[0] == UInt8(ascii: "B")
        let width = Int(first[1]) - 0x21
        let height = Int(first[2]) - 0x21
        let colorCount = ((Int(first[3]) - 0x21) << 6) + (Int(first[4]) - 0x21)
        guard width > 0, height > 0, (1...256).contains(colorCount) else {
            throw AmigaIconError.invalid("NewIcons header")
        }
        var depth = 1
        while (1 << depth) < colorCount && depth < 8 { depth += 1 }

        // Palette: may span lines; the rest of the line where it ends is unused.
        var lineIndex = 0
        var paletteBytes: [UInt8] = []
        while paletteBytes.count < colorCount * 3 {
            guard lineIndex < lines.count else { throw AmigaIconError.truncated("NewIcons palette") }
            paletteBytes += try unpack(lines[lineIndex], from: lineIndex == 0 ? 5 : 0, bits: 8)
            lineIndex += 1
        }
        let palette = Palette((0..<colorCount).map {
            RGBColor(paletteBytes[$0 * 3], paletteBytes[$0 * 3 + 1], paletteBytes[$0 * 3 + 2])
        })

        // Pixels.
        let pixelCount = width * height
        var pixels: [UInt8] = []
        pixels.reserveCapacity(pixelCount)
        while pixels.count < pixelCount && lineIndex < lines.count {
            pixels += try unpack(lines[lineIndex], from: 0, bits: depth)
            lineIndex += 1
        }
        guard pixels.count >= pixelCount else { throw AmigaIconError.truncated("NewIcons pixels") }
        pixels.removeLast(pixels.count - pixelCount)

        var image = ColorImage(image: IndexedImage(width: width, height: height, pixels: pixels),
                               palette: palette, transparentIndex: transparent ? 0 : nil)
        let maxPixel = Int(pixels.max() ?? 0)
        if maxPixel >= palette.count { image.palette = palette.resized(to: maxPixel + 1) }
        return image
    }

    /// Splits one line into `bits`-wide values; bits that do not fill a whole value are dropped.
    static func unpack(_ line: [UInt8], from start: Int, bits: Int) throws -> [UInt8] {
        var out: [UInt8] = []
        var buffer: UInt32 = 0
        var count = 0
        let mask = UInt32((1 << bits) - 1)
        func push(_ group: UInt32) {
            buffer = (buffer << 7) | group
            count += 7
            while count >= bits {
                count -= bits
                out.append(UInt8((buffer >> UInt32(count)) & mask))
            }
            buffer &= (1 << UInt32(count)) - 1
        }
        for c in line.dropFirst(start) {
            switch c {
            case 0x20...0x6F: push(UInt32(c) - 0x20)
            case 0xA1...0xD0: push(UInt32(c) - 0x51)
            case 0xD1...0xFF: for _ in 0..<(Int(c) - 0xD0) { push(0) }
            default: throw AmigaIconError.invalid("NewIcons character \(c)")
            }
        }
        return out
    }
}

public extension AmigaIcon {
    /// NewIcons images stored in the tool types, if any (read-only).
    var newIcons: NewIconsImages? { NewIconsDecoder.decode(toolTypes: info.toolTypes) }
}
