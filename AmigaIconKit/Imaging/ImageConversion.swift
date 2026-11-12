import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Conversions between `RGBAImage`/`IndexedImage` and CoreGraphics / encoded image files.
public enum ImageConversion {
    /// Decodes PNG/JPEG/… data into straight-alpha RGBA.
    public static func rgbaImage(fromEncoded bytes: [UInt8]) -> RGBAImage? {
        rgbaImage(fromEncoded: Data(bytes))
    }

    public static func rgbaImage(fromEncoded data: Data) -> RGBAImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return rgbaImage(from: image)
    }

    public static func rgbaImage(contentsOf url: URL) -> RGBAImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return rgbaImage(from: image)
    }

    /// Renders a CGImage into straight-alpha RGBA8 (sRGB).
    public static func rgbaImage(from image: CGImage, width: Int? = nil, height: Int? = nil,
                                 interpolation: CGInterpolationQuality = .none) -> RGBAImage? {
        let w = width ?? image.width, h = height ?? image.height
        guard w > 0, h > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let ok = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = interpolation
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        // Un-premultiply.
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let a = Int(pixels[i + 3])
            if a > 0 && a < 255 {
                pixels[i] = UInt8(min(255, (Int(pixels[i]) * 255 + a / 2) / a))
                pixels[i + 1] = UInt8(min(255, (Int(pixels[i + 1]) * 255 + a / 2) / a))
                pixels[i + 2] = UInt8(min(255, (Int(pixels[i + 2]) * 255 + a / 2) / a))
            }
        }
        return RGBAImage(width: w, height: h, pixels: pixels)
    }

    /// Creates a CGImage from straight-alpha RGBA.
    public static func cgImage(from image: RGBAImage) -> CGImage? {
        guard image.width > 0, image.height > 0 else { return nil }
        let data = Data(image.pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Converts an indexed image to RGBA using a palette. `transparentIndex` pixels get alpha 0.
    public static func rgbaImage(from image: IndexedImage, palette: Palette, transparentIndex: Int? = nil) -> RGBAImage {
        var out = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let colors = palette.colors
        for (i, index) in image.pixels.enumerated() {
            let idx = Int(index)
            if idx == transparentIndex { continue }
            let c = idx < colors.count ? colors[idx] : RGBColor.black
            out[i * 4] = c.r; out[i * 4 + 1] = c.g; out[i * 4 + 2] = c.b; out[i * 4 + 3] = 255
        }
        return RGBAImage(width: image.width, height: image.height, pixels: out)
    }

    public static func cgImage(from image: IndexedImage, palette: Palette, transparentIndex: Int? = nil) -> CGImage? {
        cgImage(from: rgbaImage(from: image, palette: palette, transparentIndex: transparentIndex))
    }

    /// Scales an RGBA image to an exact size.
    public static func scaled(_ image: RGBAImage, width: Int, height: Int, smooth: Bool) -> RGBAImage {
        if image.width == width && image.height == height { return image }
        guard let cg = cgImage(from: image),
              let out = rgbaImage(from: cg, width: width, height: height, interpolation: smooth ? .high : .none) else {
            return RGBAImage(width: max(1, width), height: max(1, height))
        }
        return out
    }

    /// Encodes RGBA as PNG data.
    public static func pngData(from image: RGBAImage) -> Data? {
        guard let cg = cgImage(from: image) else { return nil }
        return pngData(from: cg)
    }

    public static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
