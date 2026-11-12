import Foundation

public enum DitherMode: String, CaseIterable, Identifiable, Sendable {
    case none
    case floydSteinberg
    case bayer4
    case bayer8

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: return "None (nearest colour)"
        case .floydSteinberg: return "Floyd–Steinberg"
        case .bayer4: return "Ordered (Bayer 4×4)"
        case .bayer8: return "Ordered (Bayer 8×8)"
        }
    }
}

public struct RemapOptions: Sendable {
    public var dither: DitherMode
    /// Pixels with alpha below `alphaThreshold` become this index. If nil they become `backgroundIndex`.
    public var transparentIndex: Int?
    public var alphaThreshold: UInt8
    /// Used for transparent pixels when there is no transparent index (classic icons use colour 0).
    public var backgroundIndex: Int
    /// Strength of ordered dithering (1 = default).
    public var orderedStrength: Double

    public init(dither: DitherMode = .floydSteinberg, transparentIndex: Int? = nil, alphaThreshold: UInt8 = 128,
                backgroundIndex: Int = 0, orderedStrength: Double = 1) {
        self.dither = dither
        self.transparentIndex = transparentIndex
        self.alphaThreshold = alphaThreshold
        self.backgroundIndex = backgroundIndex
        self.orderedStrength = orderedStrength
    }
}

/// Maps true-colour images onto a palette, with optional dithering.
public enum Remapper {
    /// Normalised Bayer threshold matrix of size n×n (n = power of two), values in [0, 1).
    public static func bayerMatrix(_ n: Int) -> [[Double]] {
        var m: [[Int]] = [[0]]
        var size = 1
        while size < n {
            var next = Array(repeating: Array(repeating: 0, count: size * 2), count: size * 2)
            for y in 0..<size { for x in 0..<size {
                let v = m[y][x] * 4
                next[y][x] = v
                next[y][x + size] = v + 2
                next[y + size][x] = v + 3
                next[y + size][x + size] = v + 1
            } }
            m = next
            size *= 2
        }
        let total = Double(size * size)
        return m.map { $0.map { Double($0) / total } }
    }

    public static func remap(_ image: RGBAImage, to palette: Palette, options: RemapOptions = RemapOptions()) -> IndexedImage {
        let w = image.width, h = image.height
        var out = IndexedImage(width: w, height: h)
        guard w > 0, h > 0, palette.count > 0 else { return out }
        let excluded: Set<Int> = options.transparentIndex.map { [$0] } ?? []
        var matcher = NearestColorMatcher(palette: palette, excluding: excluded)
        let transparentValue = UInt8(clamping: options.transparentIndex ?? options.backgroundIndex)
        let px = image.pixels

        switch options.dither {
        case .none:
            for i in 0..<(w * h) {
                let o = i * 4
                if px[o + 3] < options.alphaThreshold { out.pixels[i] = transparentValue; continue }
                out.pixels[i] = matcher.nearest(Int(px[o]), Int(px[o + 1]), Int(px[o + 2]))
            }

        case .bayer4, .bayer8:
            let n = options.dither == .bayer4 ? 4 : 8
            let matrix = bayerMatrix(n)
            let usable = max(2, palette.count - excluded.count)
            let spread = 255.0 / max(1.0, log2(Double(usable))) * options.orderedStrength
            for y in 0..<h { for x in 0..<w {
                let i = y * w + x, o = i * 4
                if px[o + 3] < options.alphaThreshold { out.pixels[i] = transparentValue; continue }
                let offset = (matrix[y % n][x % n] + 0.5 / Double(n * n) - 0.5) * spread
                out.pixels[i] = matcher.nearest(Int((Double(px[o]) + offset).rounded()),
                                                Int((Double(px[o + 1]) + offset).rounded()),
                                                Int((Double(px[o + 2]) + offset).rounded()))
            } }

        case .floydSteinberg:
            // Error buffers for the current and next row (RGB, with one pixel padding each side).
            var current = [Float](repeating: 0, count: (w + 2) * 3)
            var next = [Float](repeating: 0, count: (w + 2) * 3)
            for y in 0..<h {
                let leftToRight = y % 2 == 0
                for step in 0..<w {
                    let x = leftToRight ? step : w - 1 - step
                    let i = y * w + x, o = i * 4
                    if px[o + 3] < options.alphaThreshold { out.pixels[i] = transparentValue; continue }
                    let e = (x + 1) * 3
                    let r = Float(px[o]) + current[e], g = Float(px[o + 1]) + current[e + 1], b = Float(px[o + 2]) + current[e + 2]
                    let cr = min(255, max(0, r)), cg = min(255, max(0, g)), cb = min(255, max(0, b))
                    let index = matcher.nearest(Int(cr.rounded()), Int(cg.rounded()), Int(cb.rounded()))
                    out.pixels[i] = index
                    let chosen = palette.colors[Int(index)]
                    let er = cr - Float(chosen.r), eg = cg - Float(chosen.g), eb = cb - Float(chosen.b)
                    let dir = leftToRight ? 1 : -1
                    let ahead = (x + 1 + dir) * 3, behind = (x + 1 - dir) * 3
                    current[ahead] += er * 7 / 16; current[ahead + 1] += eg * 7 / 16; current[ahead + 2] += eb * 7 / 16
                    next[behind] += er * 3 / 16; next[behind + 1] += eg * 3 / 16; next[behind + 2] += eb * 3 / 16
                    next[e] += er * 5 / 16; next[e + 1] += eg * 5 / 16; next[e + 2] += eb * 5 / 16
                    next[ahead] += er / 16; next[ahead + 1] += eg / 16; next[ahead + 2] += eb / 16
                }
                swap(&current, &next)
                for k in next.indices { next[k] = 0 }
            }
        }
        return out
    }

    /// Re-expresses an indexed image in another palette (nearest colour per index, no dithering).
    /// `transparentIndex` in the source maps to `targetTransparentIndex` (or nearest colour if nil).
    public static func remap(_ image: IndexedImage, from source: Palette, to target: Palette,
                             sourceTransparentIndex: Int? = nil, targetTransparentIndex: Int? = nil) -> IndexedImage {
        image.remapped(lookupTable(from: source, to: target, sourceTransparentIndex: sourceTransparentIndex,
                                   targetTransparentIndex: targetTransparentIndex))
    }

    public static func lookupTable(from source: Palette, to target: Palette,
                                   sourceTransparentIndex: Int? = nil, targetTransparentIndex: Int? = nil) -> [UInt8] {
        var matcher = NearestColorMatcher(palette: target, excluding: targetTransparentIndex.map { [$0] } ?? [])
        return (0..<256).map { i in
            if i == sourceTransparentIndex, let t = targetTransparentIndex { return UInt8(t) }
            return matcher.nearest(source[i])
        }
    }
}
