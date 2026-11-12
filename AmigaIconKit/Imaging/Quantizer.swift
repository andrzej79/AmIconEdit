import Foundation

/// Colour distance ("redmean" weighted Euclidean), a cheap approximation of perceptual difference.
public enum ColorDistance {
    @inlinable
    public static func squared(_ r1: Int, _ g1: Int, _ b1: Int, _ r2: Int, _ g2: Int, _ b2: Int) -> Int {
        let rmean: Int = (r1 + r2) / 2
        let dr: Int = r1 - r2
        let dg: Int = g1 - g2
        let db: Int = b1 - b2
        let red: Int = ((512 + rmean) * dr * dr) >> 8
        let green: Int = 4 * dg * dg
        let blue: Int = ((767 - rmean) * db * db) >> 8
        return red + green + blue
    }

    public static func squared(_ a: RGBColor, _ b: RGBColor) -> Int {
        squared(Int(a.r), Int(a.g), Int(a.b), Int(b.r), Int(b.g), Int(b.b))
    }
}

/// Finds the nearest palette entry for RGB values, with a cache.
public struct NearestColorMatcher {
    public let palette: Palette
    private let candidates: [Int]
    private var cache: [UInt32: UInt8] = [:]

    /// - Parameter excluding: palette indices that must never be chosen (e.g. the transparent colour).
    public init(palette: Palette, excluding: Set<Int> = []) {
        self.palette = palette
        let all = Array(palette.colors.indices).filter { !excluding.contains($0) }
        self.candidates = all.isEmpty ? Array(palette.colors.indices) : all
    }

    public mutating func nearest(_ r: Int, _ g: Int, _ b: Int) -> UInt8 {
        let r = min(255, max(0, r)), g = min(255, max(0, g)), b = min(255, max(0, b))
        let key = UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b)
        if let hit = cache[key] { return hit }
        var best = candidates.first ?? 0
        var bestDistance = Int.max
        for i in candidates {
            let c = palette.colors[i]
            let d = ColorDistance.squared(r, g, b, Int(c.r), Int(c.g), Int(c.b))
            if d < bestDistance { bestDistance = d; best = i; if d == 0 { break } }
        }
        let result = UInt8(best)
        cache[key] = result
        return result
    }

    public mutating func nearest(_ color: RGBColor) -> UInt8 {
        nearest(Int(color.r), Int(color.g), Int(color.b))
    }
}

/// Median-cut colour quantisation.
public enum Quantizer {
    struct ColorCount { var color: RGBColor; var count: Int }

    /// Builds a palette of at most `maxColors` colours from the opaque pixels of `image`
    /// (pixels with alpha below `alphaThreshold` are ignored).
    /// If the image has no more than `maxColors` distinct colours, they are returned exactly.
    public static func medianCut(_ image: RGBAImage, maxColors: Int, alphaThreshold: UInt8 = 128) -> Palette {
        let maxColors = max(1, min(256, maxColors))
        var histogram: [UInt32: Int] = [:]
        for i in stride(from: 0, to: image.pixels.count, by: 4) where image.pixels[i + 3] >= alphaThreshold {
            let key = UInt32(image.pixels[i]) << 16 | UInt32(image.pixels[i + 1]) << 8 | UInt32(image.pixels[i + 2])
            histogram[key, default: 0] += 1
        }
        if histogram.isEmpty { return Palette([.black]) }
        var colors = histogram.map { ColorCount(color: RGBColor(hex: $0.key), count: $0.value) }
        if colors.count <= maxColors {
            // Exact palette, most frequent first for a stable, sensible order.
            colors.sort { $0.count != $1.count ? $0.count > $1.count : $0.color.hex < $1.color.hex }
            return Palette(colors.map(\.color))
        }

        var boxes: [[ColorCount]] = [colors]
        while boxes.count < maxColors {
            // Split the box with the largest (range × population) score.
            var bestIndex = -1
            var bestScore = 0
            for (i, box) in boxes.enumerated() where box.count > 1 {
                let (range, _) = largestRange(box)
                let population = box.reduce(0) { $0 + $1.count }
                let score = range * Int(Double(population).squareRoot().rounded(.up))
                if score > bestScore { bestScore = score; bestIndex = i }
            }
            guard bestIndex >= 0 else { break }
            let box = boxes.remove(at: bestIndex)
            let (_, channel) = largestRange(box)
            let sorted = box.sorted { channelValue($0.color, channel) < channelValue($1.color, channel) }
            let total = sorted.reduce(0) { $0 + $1.count }
            var running = 0
            var split = 1
            for (i, c) in sorted.enumerated() {
                running += c.count
                if running * 2 >= total { split = min(max(1, i + 1), sorted.count - 1); break }
            }
            boxes.append(Array(sorted[..<split]))
            boxes.append(Array(sorted[split...]))
        }

        var result: [(RGBColor, Int)] = boxes.map { box in
            var r = 0, g = 0, b = 0, n = 0
            for c in box {
                r += Int(c.color.r) * c.count; g += Int(c.color.g) * c.count; b += Int(c.color.b) * c.count; n += c.count
            }
            n = max(1, n)
            return (RGBColor(UInt8((r + n / 2) / n), UInt8((g + n / 2) / n), UInt8((b + n / 2) / n)), n)
        }
        result.sort { $0.1 > $1.1 }
        var unique: [RGBColor] = []
        for (c, _) in result where !unique.contains(c) { unique.append(c) }
        return Palette(unique)
    }

    static func channelValue(_ c: RGBColor, _ channel: Int) -> UInt8 {
        channel == 0 ? c.r : (channel == 1 ? c.g : c.b)
    }

    static func largestRange(_ box: [ColorCount]) -> (Int, Int) {
        var lo = [255, 255, 255], hi = [0, 0, 0]
        for c in box {
            let v = [Int(c.color.r), Int(c.color.g), Int(c.color.b)]
            for k in 0..<3 { lo[k] = min(lo[k], v[k]); hi[k] = max(hi[k], v[k]) }
        }
        // Weight green higher and blue lower (perceptual importance).
        let ranges = [(hi[0] - lo[0]) * 3, (hi[1] - lo[1]) * 4, (hi[2] - lo[2]) * 2]
        let channel = ranges.firstIndex(of: ranges.max()!)!
        return (ranges[channel], channel)
    }
}
