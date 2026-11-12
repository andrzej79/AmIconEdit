import Foundation

/// A 24-bit RGB colour.
public struct RGBColor: Hashable, Sendable, Codable, CustomStringConvertible {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r; self.g = g; self.b = b
    }

    /// Creates a colour from a 0xRRGGBB value.
    public init(hex: UInt32) {
        self.init(UInt8((hex >> 16) & 0xFF), UInt8((hex >> 8) & 0xFF), UInt8(hex & 0xFF))
    }

    public var hex: UInt32 { UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b) }

    public var description: String { String(format: "#%06X", hex) }

    public static let black = RGBColor(0, 0, 0)
    public static let white = RGBColor(255, 255, 255)
}

/// An ordered list of colours. Index = colour number.
public struct Palette: Hashable, Sendable, Codable {
    public var colors: [RGBColor]

    public init(_ colors: [RGBColor]) { self.colors = colors }
    public init(hex: [UInt32]) { self.colors = hex.map(RGBColor.init(hex:)) }

    public var count: Int { colors.count }

    public subscript(index: Int) -> RGBColor {
        get { colors.indices.contains(index) ? colors[index] : .black }
        set {
            guard index >= 0 else { return }
            if index >= colors.count {
                colors.append(contentsOf: repeatElement(.black, count: index - colors.count + 1))
            }
            colors[index] = newValue
        }
    }

    /// Returns a palette with exactly `count` colours: truncated, or padded with entries of `filler`
    /// (falling back to black).
    public func resized(to count: Int, filler: Palette? = nil) -> Palette {
        let count = max(0, count)
        if count <= colors.count { return Palette(Array(colors.prefix(count))) }
        var out = colors
        for i in colors.count..<count {
            out.append(filler.flatMap { $0.colors.indices.contains(i) ? $0.colors[i] : nil } ?? .black)
        }
        return Palette(out)
    }
}

/// A chunky 8-bit indexed image (one byte per pixel, row-major).
public struct IndexedImage: Hashable, Sendable {
    public private(set) var width: Int
    public private(set) var height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, fill: UInt8 = 0) {
        self.width = max(0, width)
        self.height = max(0, height)
        self.pixels = [UInt8](repeating: fill, count: self.width * self.height)
    }

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height, "pixel count does not match dimensions")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    @inlinable public func contains(x: Int, y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height
    }

    public subscript(x: Int, y: Int) -> UInt8 {
        get { contains(x: x, y: y) ? pixels[y * width + x] : 0 }
        set { if contains(x: x, y: y) { pixels[y * width + x] = newValue } }
    }

    /// Largest colour index used (0 for an empty image).
    public var maxIndex: UInt8 { pixels.max() ?? 0 }

    /// Applies a lookup table to every pixel.
    public func remapped(_ table: [UInt8]) -> IndexedImage {
        var copy = self
        for i in copy.pixels.indices {
            let v = Int(copy.pixels[i])
            copy.pixels[i] = v < table.count ? table[v] : 0
        }
        return copy
    }
}

/// A straight-alpha RGBA8 image, row-major.
public struct RGBAImage: Hashable, Sendable {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height * 4, "pixel count does not match dimensions")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public init(width: Int, height: Int) {
        self.init(width: width, height: height, pixels: [UInt8](repeating: 0, count: width * height * 4))
    }

    public func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let o = (y * width + x) * 4
        return (pixels[o], pixels[o + 1], pixels[o + 2], pixels[o + 3])
    }
}

/// Wraps a value that is carried along for lossless writing but must not influence equality.
public struct Ignored<Value: Sendable>: Equatable, Hashable, Sendable {
    public var value: Value
    public init(_ value: Value) { self.value = value }
    public static func == (lhs: Ignored, rhs: Ignored) -> Bool { true }
    public func hash(into hasher: inout Hasher) {}
}
