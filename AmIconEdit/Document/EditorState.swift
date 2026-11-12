import AmigaIconKit
import AppKit
import Combine
import SwiftUI

enum EditorTool: String, CaseIterable, Identifiable {
    case pencil, eraser, line, rectangle, filledRectangle, ellipse, filledEllipse, fill, picker

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pencil: return "Pencil"
        case .eraser: return "Eraser"
        case .line: return "Line"
        case .rectangle: return "Rectangle"
        case .filledRectangle: return "Filled Rectangle"
        case .ellipse: return "Ellipse"
        case .filledEllipse: return "Filled Ellipse"
        case .fill: return "Flood Fill"
        case .picker: return "Colour Picker"
        }
    }

    var symbol: String {
        switch self {
        case .pencil: return "pencil"
        case .eraser: return "eraser"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .filledRectangle: return "rectangle.fill"
        case .ellipse: return "circle"
        case .filledEllipse: return "circle.fill"
        case .fill: return "drop.fill"
        case .picker: return "eyedropper"
        }
    }
}

/// Per-window editor state (tool, colours, zoom, current image) plus editing commands.
@MainActor
final class EditorState: ObservableObject {
    let document: IconDocument
    weak var undoManager: UndoManager?

    @Published var slot = ImageSlot(.color, .normal)
    @Published var tool: EditorTool = .pencil
    @Published var primaryColor: UInt8 = 1
    @Published var secondaryColor: UInt8 = 0
    @Published var zoom: Int = 8
    @Published var showGrid = true
    @Published var hover: (point: PixelPoint, index: UInt8)?
    @Published var classicPresetID: String {
        didSet { UserDefaults.standard.set(classicPresetID, forKey: "classicPalettePreset") }
    }

    // Sheets
    @Published var importPicture: RGBAImage?
    @Published var showCanvasSize = false
    @Published var errorMessage: String?

    static let zoomLevels = [1, 2, 3, 4, 6, 8, 12, 16, 24, 32]
    private var documentObserver: AnyCancellable?

    init(document: IconDocument) {
        self.document = document
        self.classicPresetID = UserDefaults.standard.string(forKey: "classicPalettePreset") ?? WorkbenchPalettes.workbench31.id
        if document.icon.glow == nil { slot = ImageSlot(.classic, .normal) }
        // Views observe the editor; re-publish document changes (including undo/redo).
        documentObserver = document.objectWillChange.sink { [weak self] _ in
            MainActor.assumeIsolated { self?.objectWillChange.send() }
        }
        fitZoom()
    }

    var icon: AmigaIcon { document.icon }

    var classicPreset: PalettePreset {
        WorkbenchPalettes.preset(id: classicPresetID) ?? WorkbenchPalettes.workbench31
    }

    var currentImage: IndexedImage? { icon.image(slot) }
    var currentPalette: Palette { icon.palette(slot, classicPreset: classicPreset) }
    var currentTransparentIndex: Int? { icon.transparentIndex(slot) }
    var hasCurrentImage: Bool { icon.hasImage(slot) }

    /// Colour used by the eraser: the transparent colour, or 0 (Workbench background).
    var eraseColor: UInt8 { UInt8(currentTransparentIndex ?? 0) }

    func modify(_ name: String, coalesceKey: String? = nil, _ change: (inout AmigaIcon) -> Void) {
        document.modify(name, undoManager: undoManager, coalesceKey: coalesceKey, change)
        clampColors()
    }

    /// Keeps the selected colours inside the current palette.
    func clampColors() {
        let count = max(1, currentPalette.count)
        if Int(primaryColor) >= count { primaryColor = UInt8(min(1, count - 1)) }
        if Int(secondaryColor) >= count { secondaryColor = 0 }
    }

    func select(_ newSlot: ImageSlot) {
        slot = newSlot
        clampColors()
    }

    // MARK: Zoom

    func fitZoom() {
        let (w, h) = icon.canvasSize(slot.kind)
        let size = max(1, max(w, h))
        zoom = Self.zoomLevels.last { $0 * size <= 520 } ?? 1
    }

    func zoomIn() { zoom = Self.zoomLevels.first { $0 > zoom } ?? zoom }
    func zoomOut() { zoom = Self.zoomLevels.last { $0 < zoom } ?? zoom }

    // MARK: Image commands

    func commit(_ image: IndexedImage, actionName: String) {
        let slot = self.slot
        modify(actionName) { $0.setImage(image, for: slot) }
    }

    func transformCurrent(_ name: String, _ transform: (IndexedImage) -> IndexedImage) {
        guard let image = currentImage else { return }
        commit(transform(image), actionName: name)
    }

    func clearCurrent() {
        guard let image = currentImage else { return }
        commit(IndexedImage(width: image.width, height: image.height, fill: eraseColor), actionName: "Clear Image")
    }

    func pickColor(_ index: UInt8, secondary: Bool) {
        if secondary { secondaryColor = index } else { primaryColor = index }
    }

    func swapColors() { swap(&primaryColor, &secondaryColor) }

    // MARK: Files

    func beginImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .bmp, .image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a picture to import into the \(slot.state.displayName.lowercased()) \(slot.kind == .color ? "colour" : "classic") image."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let picture = ImageConversion.rgbaImage(contentsOf: url) else {
            errorMessage = "“\(url.lastPathComponent)” could not be read as a picture."
            return
        }
        if !hasCurrentImage { createCurrentImage() }
        importPicture = picture
    }

    func applyImport(_ result: ImageImporter.Result) {
        let slot = self.slot
        modify("Import Picture") { icon in
            if slot.kind == .color {
                let (w, h) = icon.canvasSize(.color)
                if result.image.width != w || result.image.height != h {
                    icon.resizeCanvas(.color, width: result.image.width, height: result.image.height, anchor: .topLeft, scale: false)
                }
                icon.setPalette(result.palette, for: slot)
                icon.setTransparentIndex(result.transparentIndex, for: slot)
                if slot.state == .normal, icon.glow?.selectedSharesPalette == true {
                    // The selected image keeps its own colours; stop sharing.
                    icon.glow?.selectedSharesPalette = false
                }
            } else {
                let (w, h) = icon.canvasSize(.classic)
                if result.image.width != w || result.image.height != h {
                    icon.resizeCanvas(.classic, width: result.image.width, height: result.image.height, anchor: .topLeft, scale: false)
                }
            }
            icon.setImage(result.image, for: slot)
        }
        fitZoom()
    }

    func exportPNG() {
        guard let image = currentImage else { return }
        let rgba = ImageConversion.rgbaImage(from: image, palette: currentPalette,
                                             transparentIndex: slot.kind == .color ? currentTransparentIndex : 0)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "icon-\(slot.kind.rawValue)-\(slot.state.rawValue).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let data = ImageConversion.pngData(from: rgba) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url)
        } catch {
            errorMessage = "Could not export the PNG: \(error.localizedDescription)"
        }
    }

    func createCurrentImage() {
        let slot = self.slot
        switch (slot.kind, slot.state) {
        case (.color, .normal): modify("Add Colour Image") { $0.addColorImage() }
        case (.color, .selected):
            if icon.glow == nil { modify("Add Colour Image") { $0.addColorImage() } }
            modify("Add Selected Image") { $0.addSelectedImage(.color) }
        case (.classic, .selected): modify("Add Selected Image") { $0.addSelectedImage(.classic) }
        case (.classic, .normal): break
        }
        fitZoom()
    }

    func removeCurrentImage() {
        let slot = self.slot
        switch (slot.kind, slot.state) {
        case (.color, .normal): modify("Remove Colour Images") { $0.removeColorImage() }
        case (.color, .selected), (.classic, .selected): modify("Remove Selected Image") { $0.removeSelectedImage(slot.kind) }
        case (.classic, .normal): break
        }
    }

    func generateClassic(depth: Int, dither: DitherMode) {
        let preset = classicPreset
        modify("Generate Classic Image") { $0.generateClassicFromColor(depth: depth, classicPreset: preset, dither: dither) }
    }

    func savePalette() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "gpl") ?? .plainText]
        panel.nameFieldStringValue = "palette.gpl"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try GIMPPalette.encode(currentPalette).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "Could not save the palette: \(error.localizedDescription)"
        }
    }

    func loadPalette() {
        guard slot.kind == .color else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "gpl") ?? .plainText, .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let palette = try GIMPPalette.decode(String(contentsOf: url, encoding: .utf8))
            let preset = PalettePreset(id: "file", name: url.lastPathComponent, palette: palette)
            let slot = self.slot
            modify("Load Palette") { $0.applyPalettePreset(preset, for: slot) }
        } catch {
            errorMessage = "Could not load the palette: \(error.localizedDescription)"
        }
    }
}
