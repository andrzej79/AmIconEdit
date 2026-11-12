import Testing
@testable import AmigaIconKit

@Suite("Pixel operations")
struct PixelOpsTests {
    @Test func lineIncludesEndpointsAndIsContinuous() {
        let points = IndexedImage.linePoints(from: PixelPoint(0, 0), to: PixelPoint(7, 3))
        #expect(points.first == PixelPoint(0, 0))
        #expect(points.last == PixelPoint(7, 3))
        #expect(points.count == 8)
        for (a, b) in zip(points, points.dropFirst()) {
            #expect(abs(a.x - b.x) <= 1 && abs(a.y - b.y) <= 1)
        }
        #expect(IndexedImage.linePoints(from: PixelPoint(3, 3), to: PixelPoint(3, 3)) == [PixelPoint(3, 3)])
    }

    @Test func drawingClipsToCanvas() {
        var img = IndexedImage(width: 4, height: 4)
        img.drawLine(from: PixelPoint(-5, 1), to: PixelPoint(10, 1), color: 2)
        #expect((0..<4).allSatisfy { img[$0, 1] == 2 })
        #expect(img.pixels.filter { $0 == 2 }.count == 4)
    }

    @Test func rectangleOutlineAndFill() {
        var img = IndexedImage(width: 5, height: 5)
        img.drawRect(from: PixelPoint(4, 4), to: PixelPoint(0, 0), color: 1, filled: false)
        #expect(img.pixels.filter { $0 == 1 }.count == 16)
        #expect(img[2, 2] == 0)
        img.drawRect(from: PixelPoint(1, 1), to: PixelPoint(3, 3), color: 2, filled: true)
        #expect(img.pixels.filter { $0 == 2 }.count == 9)
    }

    @Test func ellipseIsSymmetricAndInsideBounds() {
        let points = IndexedImage.ellipsePoints(from: PixelPoint(0, 0), to: PixelPoint(10, 6), filled: true)
        let set = Set(points)
        #expect(points.allSatisfy { $0.x >= 0 && $0.x <= 10 && $0.y >= 0 && $0.y <= 6 })
        #expect(points.allSatisfy { set.contains(PixelPoint(10 - $0.x, $0.y)) && set.contains(PixelPoint($0.x, 6 - $0.y)) })
        let outline = IndexedImage.ellipsePoints(from: PixelPoint(0, 0), to: PixelPoint(10, 6), filled: false)
        #expect(outline.count < points.count)
        #expect(!Set(outline).contains(PixelPoint(5, 3)))
    }

    @Test func floodFillStopsAtBorders() {
        var img = IndexedImage(width: 6, height: 6)
        img.drawRect(from: PixelPoint(1, 1), to: PixelPoint(4, 4), color: 1, filled: false)
        img.floodFill(at: PixelPoint(2, 2), color: 3)
        #expect(img.pixels.filter { $0 == 3 }.count == 4)
        #expect(img[0, 0] == 0)
        img.floodFill(at: PixelPoint(0, 0), color: 2)
        #expect(img.pixels.filter { $0 == 2 }.count == 20)
        img.floodFill(at: PixelPoint(-1, 0), color: 5) // out of bounds: no-op
        #expect(!img.pixels.contains(5))
    }

    @Test func flipsAndShiftsAreReversible() {
        var rng = SeededGenerator(seed: 7)
        let img = IndexedImage(width: 7, height: 5, pixels: (0..<35).map { _ in UInt8.random(in: 0...15, using: &rng) })
        #expect(img.flippedHorizontally().flippedHorizontally() == img)
        #expect(img.flippedVertically().flippedVertically() == img)
        #expect(img.flippedHorizontally()[0, 0] == img[6, 0])
        #expect(img.shifted(dx: 3, dy: -2).shifted(dx: -3, dy: 2) == img)
        #expect(img.shifted(dx: 1, dy: 0)[1, 0] == img[0, 0])
    }

    @Test(arguments: CanvasAnchor.allCases)
    func resizeCanvasKeepsContentAtAnchor(anchor: CanvasAnchor) {
        var img = IndexedImage(width: 2, height: 2, fill: 1)
        img[0, 0] = 2
        let out = img.resizedCanvas(width: 6, height: 4, anchor: anchor, fill: 0)
        #expect(out.width == 6 && out.height == 4)
        #expect(out.pixels.filter { $0 != 0 }.count == 4)
        let ox = Int(4 * anchor.fx), oy = Int(2 * anchor.fy)
        #expect(out[ox, oy] == 2)
        // Shrinking crops.
        let cropped = out.resizedCanvas(width: 2, height: 2, anchor: anchor)
        #expect(cropped == img)
    }

    @Test func nearestScalingAndColorSwap() {
        let img = IndexedImage(width: 2, height: 1, pixels: [1, 2])
        #expect(img.scaled(width: 4, height: 2).pixels == [1, 1, 2, 2, 1, 1, 2, 2])
        #expect(img.swappingColors(1, 2).pixels == [2, 1])
        #expect(img.complemented(depth: 2).pixels == [2, 1])
    }
}
