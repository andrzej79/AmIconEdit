import AmigaIconKit
import AppKit
import SwiftUI

/// AppKit view that draws an indexed image magnified and handles the drawing tools.
/// Edits happen on a working copy and are committed once per stroke (one undo step).
final class PixelCanvasNSView: NSView {
    var image = IndexedImage(width: 1, height: 1) {
        didSet { if !isDrawing { invalidateImage() } }
    }
    var palette = Palette([.black]) { didSet { invalidateImage() } }
    var transparentIndex: Int? { didSet { invalidateImage() } }
    var zoom = 8 { didSet { if zoom != oldValue { invalidateIntrinsicContentSize(); needsDisplay = true } } }
    var showGrid = true { didSet { needsDisplay = true } }
    var tool: EditorTool = .pencil
    var primaryColor: UInt8 = 1
    var secondaryColor: UInt8 = 0
    var eraseColor: UInt8 = 0

    var onCommit: ((IndexedImage, String) -> Void)?
    var onPick: ((UInt8, Bool) -> Void)?
    var onHover: ((PixelPoint?, UInt8) -> Void)?

    private var working: IndexedImage?
    private var strokeBase: IndexedImage?
    private var startPoint: PixelPoint?
    private var lastPoint: PixelPoint?
    private var strokeColor: UInt8 = 0
    private var isSecondary = false
    private var isDrawing: Bool { working != nil }
    private var cachedImage: CGImage?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: image.width * zoom, height: image.height * zoom)
    }

    private func invalidateImage() {
        cachedImage = nil
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    private var displayedImage: IndexedImage { working ?? image }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let img = displayedImage
        let size = CGSize(width: img.width * zoom, height: img.height * zoom)
        let bounds = CGRect(origin: .zero, size: size)

        // Checkerboard behind transparent pixels.
        ctx.setFillColor(NSColor(white: 0.93, alpha: 1).cgColor)
        ctx.fill(bounds)
        ctx.setFillColor(NSColor(white: 0.82, alpha: 1).cgColor)
        let cell = CGFloat(max(4, zoom))
        var y: CGFloat = 0
        var row = 0
        while y < size.height {
            var x: CGFloat = row % 2 == 0 ? 0 : cell
            while x < size.width {
                ctx.fill(CGRect(x: x, y: y, width: min(cell, size.width - x), height: min(cell, size.height - y)))
                x += cell * 2
            }
            y += cell
            row += 1
        }

        if cachedImage == nil || working != nil {
            cachedImage = ImageConversion.cgImage(from: img, palette: palette, transparentIndex: transparentIndex)
        }
        if let cg = cachedImage {
            ctx.saveGState()
            ctx.interpolationQuality = .none
            // Flip for CGImage drawing in a flipped view.
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(cg, in: bounds)
            ctx.restoreGState()
        }

        if showGrid && zoom >= 4 {
            ctx.setStrokeColor(NSColor(white: 0.5, alpha: zoom >= 8 ? 0.35 : 0.2).cgColor)
            ctx.setLineWidth(1 / (window?.backingScaleFactor ?? 2))
            for gx in 0...img.width {
                let x = CGFloat(gx * zoom)
                ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: size.height))
            }
            for gy in 0...img.height {
                let y = CGFloat(gy * zoom)
                ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: size.width, y: y))
            }
            ctx.strokePath()
        }
        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(bounds.insetBy(dx: 0.5, dy: 0.5))
    }

    // MARK: Mouse handling

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    private func pixel(for event: NSEvent) -> PixelPoint {
        let p = convert(event.locationInWindow, from: nil)
        return PixelPoint(Int(floor(p.x / CGFloat(zoom))), Int(floor(p.y / CGFloat(zoom))))
    }

    override func mouseMoved(with event: NSEvent) {
        let p = pixel(for: event)
        onHover?(image.contains(x: p.x, y: p.y) ? p : nil, image[p.x, p.y])
    }

    override func mouseExited(with event: NSEvent) { onHover?(nil, 0) }

    override func mouseDown(with event: NSEvent) {
        begin(event, secondary: event.modifierFlags.contains(.control) || event.modifierFlags.contains(.option))
    }
    override func rightMouseDown(with event: NSEvent) { begin(event, secondary: true) }
    override func mouseDragged(with event: NSEvent) { drag(event) }
    override func rightMouseDragged(with event: NSEvent) { drag(event) }
    override func mouseUp(with event: NSEvent) { end(event) }
    override func rightMouseUp(with event: NSEvent) { end(event) }

    private func begin(_ event: NSEvent, secondary: Bool) {
        window?.makeFirstResponder(self)
        let p = pixel(for: event)
        isSecondary = secondary
        strokeColor = tool == .eraser ? eraseColor : (secondary ? secondaryColor : primaryColor)
        switch tool {
        case .picker:
            if image.contains(x: p.x, y: p.y) { onPick?(image[p.x, p.y], secondary) }
        case .fill:
            guard image.contains(x: p.x, y: p.y) else { return }
            var copy = image
            copy.floodFill(at: p, color: strokeColor)
            if copy != image { onCommit?(copy, "Flood Fill") }
        case .pencil, .eraser:
            var copy = image
            copy.plot(p, strokeColor)
            working = copy
            lastPoint = p
            needsDisplay = true
        case .line, .rectangle, .filledRectangle, .ellipse, .filledEllipse:
            strokeBase = image
            startPoint = p
            updateShape(to: p, constrain: event.modifierFlags.contains(.shift))
        }
    }

    private func drag(_ event: NSEvent) {
        let p = pixel(for: event)
        onHover?(image.contains(x: p.x, y: p.y) ? p : nil, displayedImage[p.x, p.y])
        switch tool {
        case .picker:
            if image.contains(x: p.x, y: p.y) { onPick?(image[p.x, p.y], isSecondary) }
        case .pencil, .eraser:
            guard var copy = working, let last = lastPoint, last != p else { return }
            copy.drawLine(from: last, to: p, color: strokeColor)
            working = copy
            lastPoint = p
            needsDisplay = true
        case .line, .rectangle, .filledRectangle, .ellipse, .filledEllipse:
            updateShape(to: p, constrain: event.modifierFlags.contains(.shift))
        case .fill:
            break
        }
    }

    private func end(_ event: NSEvent) {
        defer {
            working = nil; strokeBase = nil; startPoint = nil; lastPoint = nil
            cachedImage = nil
            needsDisplay = true
        }
        guard let result = working, result != image else { return }
        onCommit?(result, tool.title)
    }

    private func updateShape(to end: PixelPoint, constrain: Bool) {
        guard var copy = strokeBase, let start = startPoint else { return }
        var end = end
        if constrain {
            let dx = end.x - start.x, dy = end.y - start.y
            if tool == .line {
                // Snap to horizontal, vertical or 45°.
                if abs(dx) > 2 * abs(dy) { end.y = start.y } else if abs(dy) > 2 * abs(dx) { end.x = start.x } else {
                    let d = max(abs(dx), abs(dy))
                    end = PixelPoint(start.x + d * (dx < 0 ? -1 : 1), start.y + d * (dy < 0 ? -1 : 1))
                }
            } else {
                let d = max(abs(dx), abs(dy))
                end = PixelPoint(start.x + d * (dx < 0 ? -1 : 1), start.y + d * (dy < 0 ? -1 : 1))
            }
        }
        switch tool {
        case .line: copy.drawLine(from: start, to: end, color: strokeColor)
        case .rectangle: copy.drawRect(from: start, to: end, color: strokeColor, filled: false)
        case .filledRectangle: copy.drawRect(from: start, to: end, color: strokeColor, filled: true)
        case .ellipse: copy.drawEllipse(from: start, to: end, color: strokeColor, filled: false)
        case .filledEllipse: copy.drawEllipse(from: start, to: end, color: strokeColor, filled: true)
        default: break
        }
        working = copy
        needsDisplay = true
    }
}

/// SwiftUI wrapper for `PixelCanvasNSView`.
struct PixelCanvas: NSViewRepresentable {
    @ObservedObject var editor: EditorState
    let image: IndexedImage

    func makeNSView(context: Context) -> PixelCanvasNSView {
        let view = PixelCanvasNSView()
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }

    func updateNSView(_ view: PixelCanvasNSView, context: Context) {
        if view.image != image { view.image = image }
        let palette = editor.currentPalette
        if view.palette != palette { view.palette = palette }
        let transparent = editor.slot.kind == .color ? editor.currentTransparentIndex : nil
        if view.transparentIndex != transparent { view.transparentIndex = transparent }
        view.zoom = editor.zoom
        view.showGrid = editor.showGrid
        view.tool = editor.tool
        view.primaryColor = editor.primaryColor
        view.secondaryColor = editor.secondaryColor
        view.eraseColor = editor.eraseColor
        let editor = self.editor
        view.onCommit = { image, name in editor.commit(image, actionName: name) }
        view.onPick = { index, secondary in editor.pickColor(index, secondary: secondary) }
        view.onHover = { point, index in editor.hover = point.map { ($0, index) } }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PixelCanvasNSView, context: Context) -> CGSize? {
        CGSize(width: image.width * editor.zoom, height: image.height * editor.zoom)
    }
}
