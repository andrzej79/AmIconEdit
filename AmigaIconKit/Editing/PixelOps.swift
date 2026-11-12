import Foundation

/// Where existing pixels stay when the canvas is resized.
public enum CanvasAnchor: Int, CaseIterable, Identifiable, Sendable {
    case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight

    public var id: Int { rawValue }
    /// Horizontal factor: 0 = left, 0.5 = centre, 1 = right.
    public var fx: Double { [0, 0.5, 1][rawValue % 3] }
    /// Vertical factor: 0 = top, 0.5 = centre, 1 = bottom.
    public var fy: Double { [0, 0.5, 1][rawValue / 3] }
}

public struct PixelPoint: Hashable, Sendable {
    public var x: Int
    public var y: Int
    public init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
}

public extension IndexedImage {
    // MARK: Drawing

    mutating func plot(_ p: PixelPoint, _ color: UInt8) { self[p.x, p.y] = color }

    /// Bresenham line, inclusive of both end points.
    static func linePoints(from a: PixelPoint, to b: PixelPoint) -> [PixelPoint] {
        var points: [PixelPoint] = []
        var x0 = a.x, y0 = a.y
        let dx = abs(b.x - x0), sx = x0 < b.x ? 1 : -1
        let dy = -abs(b.y - y0), sy = y0 < b.y ? 1 : -1
        var err = dx + dy
        while true {
            points.append(PixelPoint(x0, y0))
            if x0 == b.x && y0 == b.y { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x0 += sx }
            if e2 <= dx { err += dx; y0 += sy }
        }
        return points
    }

    mutating func drawLine(from a: PixelPoint, to b: PixelPoint, color: UInt8) {
        for p in Self.linePoints(from: a, to: b) { plot(p, color) }
    }

    mutating func drawRect(from a: PixelPoint, to b: PixelPoint, color: UInt8, filled: Bool) {
        let x0 = min(a.x, b.x), x1 = max(a.x, b.x), y0 = min(a.y, b.y), y1 = max(a.y, b.y)
        for y in y0...y1 { for x in x0...x1 where filled || x == x0 || x == x1 || y == y0 || y == y1 {
            self[x, y] = color
        } }
    }

    /// Points of an ellipse inscribed in the rectangle spanned by `a` and `b`.
    static func ellipsePoints(from a: PixelPoint, to b: PixelPoint, filled: Bool) -> [PixelPoint] {
        let x0 = min(a.x, b.x), x1 = max(a.x, b.x), y0 = min(a.y, b.y), y1 = max(a.y, b.y)
        let cx = Double(x0 + x1) / 2, cy = Double(y0 + y1) / 2
        let rx = Double(x1 - x0 + 1) / 2, ry = Double(y1 - y0 + 1) / 2
        func inside(_ x: Int, _ y: Int) -> Bool {
            guard x >= x0, x <= x1, y >= y0, y <= y1 else { return false }
            let nx = (Double(x) - cx) / rx, ny = (Double(y) - cy) / ry
            return nx * nx + ny * ny <= 1.0001
        }
        var points: [PixelPoint] = []
        for y in y0...y1 { for x in x0...x1 where inside(x, y) {
            if filled || !inside(x - 1, y) || !inside(x + 1, y) || !inside(x, y - 1) || !inside(x, y + 1) {
                points.append(PixelPoint(x, y))
            }
        } }
        return points
    }

    mutating func drawEllipse(from a: PixelPoint, to b: PixelPoint, color: UInt8, filled: Bool) {
        for p in Self.ellipsePoints(from: a, to: b, filled: filled) { plot(p, color) }
    }

    /// 4-connected flood fill.
    mutating func floodFill(at start: PixelPoint, color: UInt8) {
        guard contains(x: start.x, y: start.y) else { return }
        let target = self[start.x, start.y]
        guard target != color else { return }
        var stack = [start]
        while let p = stack.popLast() {
            var x = p.x
            while x > 0 && self[x - 1, p.y] == target { x -= 1 }
            var spanAbove = false, spanBelow = false
            while x < width && self[x, p.y] == target {
                self[x, p.y] = color
                if p.y > 0 {
                    let match = self[x, p.y - 1] == target
                    if match && !spanAbove { stack.append(PixelPoint(x, p.y - 1)) }
                    spanAbove = match
                }
                if p.y < height - 1 {
                    let match = self[x, p.y + 1] == target
                    if match && !spanBelow { stack.append(PixelPoint(x, p.y + 1)) }
                    spanBelow = match
                }
                x += 1
            }
        }
    }

    // MARK: Transformations

    func flippedHorizontally() -> IndexedImage {
        var out = self
        for y in 0..<height { for x in 0..<width { out[x, y] = self[width - 1 - x, y] } }
        return out
    }

    func flippedVertically() -> IndexedImage {
        var out = self
        for y in 0..<height { for x in 0..<width { out[x, y] = self[x, height - 1 - y] } }
        return out
    }

    /// Moves the content, wrapping around the edges.
    func shifted(dx: Int, dy: Int) -> IndexedImage {
        guard width > 0, height > 0 else { return self }
        var out = self
        for y in 0..<height { for x in 0..<width {
            let sx = ((x - dx) % width + width) % width, sy = ((y - dy) % height + height) % height
            out[x, y] = self[sx, sy]
        } }
        return out
    }

    /// Changes the canvas size without scaling; new areas are filled with `fill`.
    func resizedCanvas(width newWidth: Int, height newHeight: Int, anchor: CanvasAnchor, fill: UInt8 = 0) -> IndexedImage {
        var out = IndexedImage(width: newWidth, height: newHeight, fill: fill)
        let ox = Int((Double(newWidth - width) * anchor.fx).rounded(.down))
        let oy = Int((Double(newHeight - height) * anchor.fy).rounded(.down))
        for y in 0..<height { for x in 0..<width { out[x + ox, y + oy] = self[x, y] } }
        return out
    }

    /// Nearest-neighbour scaling.
    func scaled(width newWidth: Int, height newHeight: Int) -> IndexedImage {
        var out = IndexedImage(width: newWidth, height: newHeight)
        guard width > 0, height > 0 else { return out }
        for y in 0..<newHeight { for x in 0..<newWidth {
            out[x, y] = self[x * width / max(1, newWidth), y * height / max(1, newHeight)]
        } }
        return out
    }

    /// Swaps all pixels of two colour indices.
    func swappingColors(_ a: UInt8, _ b: UInt8) -> IndexedImage {
        var table = (0...255).map { UInt8($0) }
        table[Int(a)] = b
        table[Int(b)] = a
        return remapped(table)
    }

    /// Workbench "complement" highlight: inverts all bitplanes.
    func complemented(depth: Int) -> IndexedImage {
        let mask = UInt8(truncatingIfNeeded: (1 << min(8, max(1, depth))) - 1)
        var out = self
        for i in out.pixels.indices { out.pixels[i] ^= mask }
        return out
    }
}
