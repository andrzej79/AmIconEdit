import Foundation

/// A named palette preset.
public struct PalettePreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let palette: Palette

    public init(id: String, name: String, palette: Palette) {
        self.id = id
        self.name = name
        self.palette = palette
    }
}

/// Common Workbench screen palettes, used to display classic (planar) icons and as starting palettes.
public enum WorkbenchPalettes {
    /// Workbench 1.x (blue background, orange highlight).
    public static let workbench13 = PalettePreset(
        id: "wb13", name: "Workbench 1.3",
        palette: Palette(hex: [0x0055AA, 0xFFFFFF, 0x000022, 0xFF8800]))

    /// Workbench 2.x/3.x default 4 colours, extended with the 3.1 default pens 4–7.
    public static let workbench31 = PalettePreset(
        id: "wb31", name: "Workbench 3.1",
        palette: Palette(hex: [0xAAAAAA, 0x000000, 0xFFFFFF, 0x6688BB,
                               0xEE4444, 0x55DD55, 0x0044DD, 0xEE9900]))

    /// MagicWB 8-colour palette.
    public static let magicWB = PalettePreset(
        id: "magicwb", name: "MagicWB",
        palette: Palette(hex: [0x959595, 0x000000, 0xFFFFFF, 0x3B67A2,
                               0x7B7B7B, 0xAFAFAF, 0xAA907C, 0xFFA997]))

    /// MagicWB extended to 16 colours with the common "MWB+" additions.
    public static let magicWB16 = PalettePreset(
        id: "magicwb16", name: "MagicWB 16",
        palette: Palette(hex: [0x959595, 0x000000, 0xFFFFFF, 0x3B67A2,
                               0x7B7B7B, 0xAFAFAF, 0xAA907C, 0xFFA997,
                               0x0000FF, 0x323232, 0x606060, 0xE2E2E2,
                               0xFF0000, 0x00FF00, 0xFFFF00, 0x8C5A2C]))

    /// 256 greys.
    public static let grayscale = PalettePreset(
        id: "gray", name: "Grayscale 256",
        palette: Palette((0..<256).map { RGBColor(UInt8($0), UInt8($0), UInt8($0)) }))

    /// 6×6×6 colour cube followed by a grey ramp (256 colours).
    public static let colorCube = PalettePreset(id: "cube", name: "Colour cube 256", palette: {
        var colors: [RGBColor] = []
        for r in 0..<6 { for g in 0..<6 { for b in 0..<6 {
            colors.append(RGBColor(UInt8(r * 51), UInt8(g * 51), UInt8(b * 51)))
        } } }
        for i in 0..<40 { let v = UInt8(i * 255 / 39); colors.append(RGBColor(v, v, v)) }
        return Palette(colors)
    }())

    public static let all: [PalettePreset] = [workbench31, magicWB, magicWB16, workbench13, grayscale, colorCube]

    public static func preset(id: String) -> PalettePreset? { all.first { $0.id == id } }

    /// A display palette for classic icons of the given depth: the preset, padded with the
    /// colour cube so every possible index has a colour.
    public static func displayPalette(_ preset: PalettePreset, depth: Int) -> Palette {
        let count = 1 << min(8, max(1, depth))
        return preset.palette.resized(to: count, filler: Palette(
            Array(repeating: RGBColor.black, count: preset.palette.count) + colorCube.palette.colors))
    }
}
