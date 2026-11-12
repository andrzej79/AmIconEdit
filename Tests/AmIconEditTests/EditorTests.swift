import AmigaIconKit
import AppKit
import SwiftUI
import Testing
@testable import AmIconEdit

@MainActor
@Suite("Editor document and state")
struct EditorTests {
    func makeEditor(_ icon: AmigaIcon = .blank()) -> (EditorState, UndoManager) {
        let document = IconDocument(icon: icon)
        let editor = EditorState(document: document)
        let undo = UndoManager()
        undo.groupsByEvent = false
        editor.undoManager = undo
        return (editor, undo)
    }

    /// Runs `body` inside an explicit undo group (tests have no run loop to group by event).
    func grouped(_ undo: UndoManager, _ body: () -> Void) {
        undo.beginUndoGrouping()
        body()
        undo.endUndoGrouping()
    }

    @Test func strokeCommitIsUndoable() {
        let (editor, undo) = makeEditor()
        let before = editor.icon
        var image = editor.currentImage!
        image.drawLine(from: PixelPoint(0, 0), to: PixelPoint(10, 10), color: 3)
        grouped(undo) { editor.commit(image, actionName: "Pencil") }
        #expect(editor.currentImage == image)
        #expect(undo.undoActionName == "Pencil")
        undo.undo()
        #expect(editor.icon == before)
        undo.redo()
        #expect(editor.currentImage == image)
    }

    @Test func typingCoalescesIntoOneUndoStep() {
        let (editor, undo) = makeEditor()
        grouped(undo) {
            for text in ["S", "SY", "SYS", "SYS:"] {
                editor.modify("Default Tool", coalesceKey: "defaultTool") { $0.info.defaultTool = text }
            }
        }
        #expect(editor.icon.info.defaultTool == "SYS:")
        undo.undo()
        #expect(editor.icon.info.defaultTool == nil)
        #expect(!undo.canUndo)
    }

    @Test func noOpChangesDoNotRegisterUndo() {
        let (editor, undo) = makeEditor()
        // No grouping: an empty explicit group would itself count as undoable.
        editor.modify("Nothing") { $0.info.stackSize = $0.info.stackSize }
        #expect(!undo.canUndo)
    }

    @Test func reducingColorCountRemapsPixelsAndClampsSelection() {
        let (editor, _) = makeEditor()
        var image = editor.currentImage!
        image[0, 0] = 7
        editor.commit(image, actionName: "Pencil")
        editor.primaryColor = 7
        editor.modify("Number of Colours") { $0.setColorCount(4, for: editor.slot, classicPreset: editor.classicPreset) }
        #expect(editor.currentPalette.count == 4)
        #expect(editor.currentImage!.pixels.allSatisfy { $0 < 4 })
        #expect(editor.primaryColor < 4)
    }

    @Test func classicDepthChangeKeepsPixelsInRange() {
        var icon = AmigaIcon.blank()
        icon.normalImage.depth = 3
        icon.normalImage.image[1, 1] = 7
        let (editor, _) = makeEditor(icon)
        editor.select(ImageSlot(.classic, .normal))
        editor.modify("Bitplanes") { $0.setClassicDepth(1, classicPreset: editor.classicPreset) }
        #expect(editor.icon.normalImage.depth == 1)
        #expect(editor.currentImage!.pixels.allSatisfy { $0 < 2 })
        #expect(editor.currentPalette.count == 2)
    }

    @Test func importReplacesImageAndPalette() {
        let (editor, _) = makeEditor()
        var picture = RGBAImage(width: 80, height: 40)
        for i in 0..<(80 * 40) {
            picture.pixels[i * 4] = UInt8(i % 80 * 3); picture.pixels[i * 4 + 2] = 200; picture.pixels[i * 4 + 3] = 255
        }
        let target = ImageImporter.Target(canvasWidth: 46, canvasHeight: 46, palette: editor.currentPalette,
                                          transparentIndex: editor.currentTransparentIndex, maxColors: 256,
                                          maxSize: 256, fixedPalette: false)
        var options = ImageImporter.Options()
        options.sizing = .resizeCanvas
        options.paletteSource = .generate(colors: 16)
        let result = ImageImporter.importPicture(picture, target: target, options: options)
        editor.applyImport(result)
        #expect(editor.icon.canvasSize(.color) == (80, 40))
        #expect(editor.currentPalette == result.palette)
        #expect(editor.currentImage == result.image)
    }

    @Test func selectedImageLifecycle() {
        let (editor, _) = makeEditor()
        editor.select(ImageSlot(.color, .selected))
        #expect(!editor.hasCurrentImage)
        editor.createCurrentImage()
        #expect(editor.hasCurrentImage)
        #expect(editor.icon.glow?.selectedSharesPalette == true)
        editor.removeCurrentImage()
        #expect(!editor.hasCurrentImage)

        editor.select(ImageSlot(.classic, .selected))
        editor.createCurrentImage()
        #expect(editor.icon.info.highlight == .image)
        editor.removeCurrentImage()
        #expect(editor.icon.info.highlight == .complement)
    }

    @Test func sharedPaletteEditsBothImages() {
        let (editor, _) = makeEditor()
        editor.select(ImageSlot(.color, .selected))
        editor.createCurrentImage()
        var palette = editor.currentPalette
        palette[2] = AmigaIconKit.RGBColor(1, 2, 3)
        editor.modify("Edit Colour") { $0.setPalette(palette, for: ImageSlot(.color, .selected)) }
        #expect(editor.icon.glow?.normal.palette[2] == AmigaIconKit.RGBColor(1, 2, 3))
        #expect(editor.icon.glow?.selected?.palette[2] == AmigaIconKit.RGBColor(1, 2, 3))
    }

    @Test func generateClassicFromColor() {
        let (editor, _) = makeEditor()
        var image = editor.currentImage!
        image.drawRect(from: PixelPoint(5, 5), to: PixelPoint(30, 30), color: 2, filled: true) // white
        editor.commit(image, actionName: "Rectangle")
        editor.generateClassic(depth: 2, dither: .none)
        #expect(editor.icon.normalImage.depth == 2)
        #expect(editor.icon.normalImage.image[10, 10] == 2) // white in the Workbench palette
        #expect(editor.icon.normalImage.image[0, 0] == 0)   // transparent -> background colour
    }

    @Test func canvasResizeAppliesToNormalAndSelected() {
        let (editor, _) = makeEditor()
        editor.select(ImageSlot(.color, .selected))
        editor.createCurrentImage()
        editor.modify("Resize Canvas") { $0.resizeCanvas(.color, width: 64, height: 32, anchor: .center, scale: false) }
        #expect(editor.icon.glow?.normal.image.width == 64)
        #expect(editor.icon.glow?.selected?.image.height == 32)
    }

    @Test func documentSnapshotRoundTripsThroughFileFormat() throws {
        let (editor, _) = makeEditor(.blank(type: .tool))
        editor.modify("Tool Types") { $0.info.toolTypes = ["DONOTWAIT", "PUBSCREEN=Workbench"] }
        editor.modify("Stack") { $0.info.stackSize = 65536 }
        let data = try editor.icon.encoded()
        let reread = try AmigaIcon(data: data)
        #expect(reread == editor.icon)
    }

    @Test func pngIconOpensAsConvertedDocument() throws {
        var rgba = RGBAImage(width: 20, height: 20)
        for i in 0..<400 { rgba.pixels[i * 4 + 1] = UInt8(i % 256); rgba.pixels[i * 4 + 3] = i < 20 ? 0 : 255 }
        let png = PNGIcon(normal: rgba, selected: nil, info: DiskObjectInfo(type: .tool, stackSize: 8192), isFrameless: false)
        let icon = AmigaIcon(converting: png)
        #expect(icon.glow?.width == 20)
        #expect(icon.glow?.normal.transparentIndex == 0)
        #expect(icon.info.stackSize == 8192)
        #expect(icon.normalImage.depth == 2)
        _ = try icon.encoded()
    }

    @Test func editorViewRendersForEveryIconKind() throws {
        for icon in [AmigaIcon.blank(), .blank(type: .drawer)] {
            let document = IconDocument(icon: icon)
            let host = NSHostingView(rootView: EditorView(document: document))
            host.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            #expect(rep.pixelsWide > 0)
        }
    }

    @Test func canvasViewCommitsStrokeOnce() {
        let view = PixelCanvasNSView(frame: NSRect(x: 0, y: 0, width: 80, height: 80))
        view.image = IndexedImage(width: 10, height: 10)
        view.palette = WorkbenchPalettes.workbench31.palette
        view.zoom = 8
        var commits: [(IndexedImage, String)] = []
        view.onCommit = { commits.append(($0, $1)) }
        view.tool = .filledRectangle
        view.primaryColor = 3
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        func event(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) -> NSEvent {
            // Window coordinates are bottom-up; the view is flipped.
            NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: view.bounds.height - y), modifierFlags: [],
                               timestamp: 0, windowNumber: window.windowNumber, context: nil,
                               eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        view.mouseDown(with: event(.leftMouseDown, 4, 4))
        view.mouseDragged(with: event(.leftMouseDragged, 20, 20))
        view.mouseDragged(with: event(.leftMouseDragged, 28, 20))
        #expect(commits.isEmpty)
        view.mouseUp(with: event(.leftMouseUp, 28, 20))
        #expect(commits.count == 1)
        let result = commits[0].0
        #expect(result.pixels.filter { $0 == 3 }.count == 4 * 3) // x 0…3, y 0…2
        #expect(commits[0].1 == "Filled Rectangle")
    }
}
