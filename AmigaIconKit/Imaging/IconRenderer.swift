import CoreGraphics
import Foundation

/// One renderable picture of an icon, with a label.
public struct IconPicture: Identifiable, Sendable {
    public enum Kind: String, Sendable { case color, classic, argb, png }
    public let id: String
    public let title: String
    public let kind: Kind
    public let image: RGBAImage
}

/// Turns icons into RGBA pictures for previews, thumbnails and export.
public enum IconRenderer {
    /// Palette used to show classic (planar) images.
    public static func classicPalette(depth: Int, preset: PalettePreset = WorkbenchPalettes.workbench31) -> Palette {
        WorkbenchPalettes.displayPalette(preset, depth: depth)
    }

    /// Classic image as RGBA. If `transparentBackground`, colour 0 (Workbench background) is transparent.
    public static func render(_ image: ClassicImage, palette: Palette? = nil, transparentBackground: Bool = true) -> RGBAImage {
        ImageConversion.rgbaImage(from: image.image, palette: palette ?? classicPalette(depth: image.depth),
                                  transparentIndex: transparentBackground ? 0 : nil)
    }

    public static func render(_ image: ColorImage) -> RGBAImage {
        ImageConversion.rgbaImage(from: image.image, palette: image.palette, transparentIndex: image.transparentIndex)
    }

    /// The selected classic image, synthesised from the highlight mode when the icon has none.
    public static func selectedClassic(of icon: AmigaIcon) -> ClassicImage {
        if let selected = icon.selectedImage { return selected }
        var copy = icon.normalImage
        if icon.info.highlight == .complement { copy.image = copy.image.complemented(depth: copy.depth) }
        return copy
    }

    /// Decoded AROS ARGB images, if any.
    public static func argbImages(of glow: GlowIcon) -> [RGBAImage] {
        glow.extraChunks.filter { $0.id == "ARGB" }
            .compactMap { ARGBChunkDecoder.decode($0.data, width: glow.width, height: glow.height) }
    }

    /// All pictures contained in an icon file, best quality first.
    public static func pictures(of file: IconFile, classicPreset: PalettePreset = WorkbenchPalettes.workbench31) -> [IconPicture] {
        switch file {
        case .png(let png):
            var out = [IconPicture(id: "png-normal", title: "Normal", kind: .png, image: png.normal)]
            if let s = png.selected { out.append(IconPicture(id: "png-selected", title: "Selected", kind: .png, image: s)) }
            return out
        case .diskObject(let icon):
            var out: [IconPicture] = []
            if let glow = icon.glow {
                for (i, img) in argbImages(of: glow).enumerated() {
                    out.append(IconPicture(id: "argb-\(i)", title: i == 0 ? "ARGB normal" : "ARGB selected", kind: .argb, image: img))
                }
                out.append(IconPicture(id: "color-normal", title: "OS3.5 normal", kind: .color, image: render(glow.normal)))
                if let s = glow.selected {
                    out.append(IconPicture(id: "color-selected", title: "OS3.5 selected", kind: .color, image: render(s)))
                }
            }
            let palette = { (depth: Int) in classicPalette(depth: depth, preset: classicPreset) }
            out.append(IconPicture(id: "classic-normal", title: "Classic normal", kind: .classic,
                                   image: render(icon.normalImage, palette: palette(icon.normalImage.depth))))
            if let s = icon.selectedImage {
                out.append(IconPicture(id: "classic-selected", title: "Classic selected", kind: .classic,
                                       image: render(s, palette: palette(s.depth))))
            }
            return out
        }
    }

    /// The single best picture to represent the icon (for thumbnails).
    public static func primaryPicture(of file: IconFile) -> RGBAImage? {
        pictures(of: file).first?.image
    }

    /// Integer nearest-neighbour upscaling.
    public static func scaled(_ image: RGBAImage, factor: Int) -> RGBAImage {
        let f = max(1, factor)
        if f == 1 { return image }
        let w = image.width * f, h = image.height * f
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            let sy = y / f
            for x in 0..<w {
                let s = (sy * image.width + x / f) * 4, d = (y * w + x) * 4
                out[d] = image.pixels[s]; out[d + 1] = image.pixels[s + 1]
                out[d + 2] = image.pixels[s + 2]; out[d + 3] = image.pixels[s + 3]
            }
        }
        return RGBAImage(width: w, height: h, pixels: out)
    }

    /// Largest integer factor so the image fits inside `size`×`size` (at least 1).
    public static func integerScale(for image: RGBAImage, fitting size: Int) -> Int {
        max(1, size / max(1, max(image.width, image.height)))
    }
}
