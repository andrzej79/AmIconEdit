import Foundation

/// Converts a true-colour picture (e.g. a PNG) into an indexed icon image.
public enum ImageImporter {
    public enum Sizing: String, CaseIterable, Identifiable, Sendable {
        /// Scale to fit inside the current canvas, keeping the aspect ratio (centred, transparent margins).
        case fitCanvas
        /// Scale to exactly the canvas size.
        case stretchToCanvas
        /// Keep the picture size and resize the canvas to match (limited by `maxSize`).
        case resizeCanvas

        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .fitCanvas: return "Fit into canvas"
            case .stretchToCanvas: return "Stretch to canvas"
            case .resizeCanvas: return "Resize canvas to picture"
            }
        }
    }

    public enum PaletteSource: Hashable, Sendable {
        /// Remap onto the image's current palette.
        case keepCurrent
        /// Build an optimal palette with this many colours (median cut).
        case generate(colors: Int)
        /// Use a preset palette.
        case preset(PalettePreset)
    }

    public struct Options: Sendable {
        public var sizing: Sizing = .fitCanvas
        public var smoothScaling = true
        public var paletteSource: PaletteSource = .generate(colors: 32)
        public var dither: DitherMode = .floydSteinberg
        public var alphaThreshold: UInt8 = 128
        /// Map transparent picture pixels to a transparent colour index (colour icons) / colour 0 (classic).
        public var keepTransparency = true
        public var orderedStrength: Double = 1
        public init() {}
    }

    public struct Target: Sendable {
        public var canvasWidth: Int
        public var canvasHeight: Int
        public var palette: Palette
        public var transparentIndex: Int?
        /// Upper bound for the palette size (256 for colour icons, 2^depth for classic).
        public var maxColors: Int
        /// Largest allowed canvas edge.
        public var maxSize: Int
        /// Classic icons have a fixed display palette; generating palettes is not possible.
        public var fixedPalette: Bool

        public init(canvasWidth: Int, canvasHeight: Int, palette: Palette, transparentIndex: Int?,
                    maxColors: Int, maxSize: Int, fixedPalette: Bool) {
            self.canvasWidth = canvasWidth
            self.canvasHeight = canvasHeight
            self.palette = palette
            self.transparentIndex = transparentIndex
            self.maxColors = maxColors
            self.maxSize = maxSize
            self.fixedPalette = fixedPalette
        }
    }

    public struct Result: Equatable, Sendable {
        public var image: IndexedImage
        public var palette: Palette
        public var transparentIndex: Int?
    }

    /// Scales/places the picture according to the sizing option.
    public static func prepare(_ picture: RGBAImage, target: Target, options: Options) -> RGBAImage {
        switch options.sizing {
        case .stretchToCanvas:
            return ImageConversion.scaled(picture, width: target.canvasWidth, height: target.canvasHeight,
                                          smooth: options.smoothScaling)
        case .resizeCanvas:
            let (w, h) = fitted(picture.width, picture.height, maxWidth: target.maxSize, maxHeight: target.maxSize,
                                allowUpscale: false)
            return ImageConversion.scaled(picture, width: w, height: h, smooth: options.smoothScaling)
        case .fitCanvas:
            let (w, h) = fitted(picture.width, picture.height, maxWidth: target.canvasWidth,
                                maxHeight: target.canvasHeight, allowUpscale: true)
            let scaled = ImageConversion.scaled(picture, width: w, height: h, smooth: options.smoothScaling)
            var canvas = RGBAImage(width: target.canvasWidth, height: target.canvasHeight)
            let ox = (target.canvasWidth - w) / 2, oy = (target.canvasHeight - h) / 2
            for y in 0..<h { for x in 0..<w {
                let s = (y * w + x) * 4, d = ((y + oy) * target.canvasWidth + (x + ox)) * 4
                for k in 0..<4 { canvas.pixels[d + k] = scaled.pixels[s + k] }
            } }
            return canvas
        }
    }

    static func fitted(_ w: Int, _ h: Int, maxWidth: Int, maxHeight: Int, allowUpscale: Bool) -> (Int, Int) {
        guard w > 0, h > 0 else { return (max(1, maxWidth), max(1, maxHeight)) }
        var scale = min(Double(maxWidth) / Double(w), Double(maxHeight) / Double(h))
        if !allowUpscale { scale = min(1, scale) }
        return (max(1, Int((Double(w) * scale).rounded())), max(1, Int((Double(h) * scale).rounded())))
    }

    public static func importPicture(_ picture: RGBAImage, target: Target, options: Options) -> Result {
        let prepared = prepare(picture, target: target, options: options)
        let hasTransparentPixels = stride(from: 3, to: prepared.pixels.count, by: 4)
            .contains { prepared.pixels[$0] < options.alphaThreshold }

        var palette = target.palette
        var transparentIndex = target.transparentIndex
        var source = options.paletteSource
        if target.fixedPalette, !paletteIsPreset(source) { source = .keepCurrent }

        switch source {
        case .keepCurrent:
            break
        case .preset(let preset):
            if target.fixedPalette {
                palette = WorkbenchPalettes.displayPalette(preset, depth: depthFor(target.maxColors))
            } else {
                palette = Palette(Array(preset.palette.colors.prefix(target.maxColors)))
                // Workbench convention: colour 0 is the background, so it doubles as the transparent colour.
                if options.keepTransparency && hasTransparentPixels { transparentIndex = 0 }
            }
        case .generate(let colors):
            let limit = max(2, min(target.maxColors, colors))
            if options.keepTransparency && hasTransparentPixels {
                let generated = Quantizer.medianCut(prepared, maxColors: limit - 1, alphaThreshold: options.alphaThreshold)
                palette = Palette([.black] + generated.colors)
                transparentIndex = 0
            } else {
                palette = Quantizer.medianCut(prepared, maxColors: limit, alphaThreshold: options.alphaThreshold)
                if !options.keepTransparency { transparentIndex = nil }
            }
        }

        if target.fixedPalette {
            // Classic icons: transparency is colour 0 (the Workbench background).
            transparentIndex = nil
        } else if options.keepTransparency && hasTransparentPixels && transparentIndex == nil {
            // Need a transparent colour: reuse index 0.
            transparentIndex = 0
        }

        let remapOptions = RemapOptions(dither: options.dither,
                                        transparentIndex: options.keepTransparency ? transparentIndex : nil,
                                        alphaThreshold: options.keepTransparency ? options.alphaThreshold : 0,
                                        backgroundIndex: 0,
                                        orderedStrength: options.orderedStrength)
        let image = Remapper.remap(prepared, to: palette, options: remapOptions)
        return Result(image: image, palette: palette, transparentIndex: transparentIndex)
    }

    static func paletteIsPreset(_ source: PaletteSource) -> Bool {
        if case .preset = source { return true }
        return false
    }

    static func depthFor(_ colors: Int) -> Int {
        var d = 1
        while (1 << d) < colors && d < 8 { d += 1 }
        return d
    }
}
