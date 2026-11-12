import Foundation

/// Which of the (up to four) images of an icon is being edited.
public struct ImageSlot: Hashable, Sendable {
    public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case color, classic
        public var id: String { rawValue }
        public var displayName: String { self == .color ? "Colour (OS3.5)" : "Classic (planar)" }
    }

    public enum State: String, CaseIterable, Identifiable, Sendable {
        case normal, selected
        public var id: String { rawValue }
        public var displayName: String { self == .normal ? "Normal" : "Selected" }
    }

    public var kind: Kind
    public var state: State

    public init(_ kind: Kind, _ state: State) {
        self.kind = kind
        self.state = state
    }
}

/// Editing operations used by the editor. All of them keep the icon consistent
/// (matching colour image sizes, shared palettes, pixel indices within the palette/depth).
public extension AmigaIcon {
    static let maxClassicSize = 1024

    func hasImage(_ slot: ImageSlot) -> Bool {
        switch (slot.kind, slot.state) {
        case (.classic, .normal): return true
        case (.classic, .selected): return selectedImage != nil
        case (.color, .normal): return glow != nil
        case (.color, .selected): return glow?.selected != nil
        }
    }

    func image(_ slot: ImageSlot) -> IndexedImage? {
        switch (slot.kind, slot.state) {
        case (.classic, .normal): return normalImage.image
        case (.classic, .selected): return selectedImage?.image
        case (.color, .normal): return glow?.normal.image
        case (.color, .selected): return glow?.selected?.image
        }
    }

    /// Replaces the pixels of an existing image (sizes must match the slot's canvas).
    mutating func setImage(_ image: IndexedImage, for slot: ImageSlot) {
        switch (slot.kind, slot.state) {
        case (.classic, .normal): normalImage.image = image
        case (.classic, .selected): selectedImage?.image = image
        case (.color, .normal):
            glow?.normal.image = image
            invalidateARGB()
        case (.color, .selected):
            glow?.selected?.image = image
            invalidateARGB()
        }
    }

    /// The palette used to display/edit the slot. Classic images use the Workbench display palette.
    func palette(_ slot: ImageSlot, classicPreset: PalettePreset) -> Palette {
        switch slot.kind {
        case .classic:
            let depth = (slot.state == .selected ? selectedImage?.depth : nil) ?? normalImage.depth
            return IconRenderer.classicPalette(depth: depth, preset: classicPreset)
        case .color:
            return (slot.state == .selected ? glow?.selected?.palette : nil) ?? glow?.normal.palette ?? Palette([.black])
        }
    }

    func transparentIndex(_ slot: ImageSlot) -> Int? {
        guard slot.kind == .color else { return nil }
        return slot.state == .selected ? glow?.selected?.transparentIndex : glow?.normal.transparentIndex
    }

    /// Number of colours available in the slot (palette size, or 2^depth for classic).
    func colorCount(_ slot: ImageSlot) -> Int {
        switch slot.kind {
        case .classic: return 1 << ((slot.state == .selected ? selectedImage?.depth : nil) ?? normalImage.depth)
        case .color: return palette(slot, classicPreset: WorkbenchPalettes.workbench31).count
        }
    }

    // MARK: Adding / removing images

    /// Creates the selected image of the given kind as a copy of the normal image.
    mutating func addSelectedImage(_ kind: ImageSlot.Kind) {
        switch kind {
        case .classic:
            guard selectedImage == nil else { return }
            var copy = normalImage
            copy.header = Ignored(nil)
            selectedImage = copy
            info.highlight = .image
        case .color:
            guard var g = glow, g.selected == nil else { return }
            var copy = g.normal
            copy.source = Ignored(nil)
            g.selected = copy
            g.selectedSharesPalette = true
            glow = g
            invalidateARGB()
        }
    }

    mutating func removeSelectedImage(_ kind: ImageSlot.Kind) {
        switch kind {
        case .classic:
            selectedImage = nil
            if info.highlight == .image { info.highlight = .complement }
        case .color:
            glow?.selected = nil
            glow?.selectedSharesPalette = false
            invalidateARGB()
        }
    }

    /// Adds an empty OS3.5 colour image the size of the classic image (max 256×256).
    mutating func addColorImage(palette: Palette = WorkbenchPalettes.workbench31.palette) {
        guard glow == nil else { return }
        let w = min(256, normalImage.image.width), h = min(256, normalImage.image.height)
        glow = GlowIcon(normal: ColorImage(image: IndexedImage(width: max(1, w), height: max(1, h)),
                                           palette: palette, transparentIndex: 0))
    }

    mutating func removeColorImage() { glow = nil }

    // MARK: Palette and colours

    /// Replaces a colour image's palette (keeps a shared palette in sync).
    mutating func setPalette(_ palette: Palette, for slot: ImageSlot) {
        guard slot.kind == .color, glow != nil else { return }
        glow?.setPalette(palette, selected: slot.state == .selected)
        invalidateARGB()
    }

    mutating func setTransparentIndex(_ index: Int?, for slot: ImageSlot) {
        guard slot.kind == .color else { return }
        if slot.state == .selected { glow?.selected?.transparentIndex = index } else { glow?.normal.transparentIndex = index }
        invalidateARGB()
    }

    /// Changes the number of colours. Colour images get a resized palette (new entries from `filler`);
    /// classic images get the smallest depth that holds `count` colours. Pixels that would fall outside
    /// the new range are remapped to the nearest remaining colour.
    mutating func setColorCount(_ count: Int, for slot: ImageSlot, classicPreset: PalettePreset,
                                filler: Palette = WorkbenchPalettes.colorCube.palette) {
        switch slot.kind {
        case .classic:
            var depth = 1
            while (1 << depth) < count && depth < 8 { depth += 1 }
            setClassicDepth(depth, classicPreset: classicPreset)
        case .color:
            guard var g = glow else { return }
            let count = min(256, max(2, count))
            let shared = g.selectedSharesPalette
            func apply(_ image: inout ColorImage) {
                let old = image.palette
                let fill = Palette(Array(repeating: RGBColor.black, count: old.count) + filler.colors)
                let new = old.resized(to: count, filler: fill)
                if count < old.count {
                    let t = image.transparentIndex.flatMap { $0 < count ? $0 : nil }
                    var table = Remapper.lookupTable(from: old, to: new, sourceTransparentIndex: image.transparentIndex,
                                                     targetTransparentIndex: t)
                    for i in 0..<count { table[i] = UInt8(i) }
                    image.image = image.image.remapped(table)
                    image.transparentIndex = t
                }
                image.palette = new
            }
            if slot.state == .normal || shared {
                apply(&g.normal)
                if shared, var s = g.selected {
                    let t = s.transparentIndex
                    s.palette = g.normal.palette
                    s.image = s.image.remapped(Self.clampTable(count: count))
                    s.transparentIndex = t.flatMap { $0 < count ? $0 : nil }
                    g.selected = s
                }
            } else if var s = g.selected {
                apply(&s)
                g.selected = s
            }
            glow = g
            invalidateARGB()
        }
    }

    private static func clampTable(count: Int) -> [UInt8] {
        (0..<256).map { UInt8($0 < count ? $0 : 0) }
    }

    /// Sets the bitplane count of both classic images, remapping colours that no longer exist.
    mutating func setClassicDepth(_ depth: Int, classicPreset: PalettePreset) {
        let depth = min(8, max(1, depth))
        func apply(_ image: inout ClassicImage) {
            if depth < image.depth {
                let old = IconRenderer.classicPalette(depth: image.depth, preset: classicPreset)
                let new = IconRenderer.classicPalette(depth: depth, preset: classicPreset)
                var table = Remapper.lookupTable(from: old, to: new)
                for i in 0..<(1 << depth) { table[i] = UInt8(i) }
                image.image = image.image.remapped(table)
            }
            image.depth = depth
        }
        apply(&normalImage)
        if var s = selectedImage { apply(&s); selectedImage = s }
    }

    /// Replaces the palette with a preset and remaps the pixels to the nearest new colours.
    mutating func applyPalettePreset(_ preset: PalettePreset, for slot: ImageSlot) {
        guard slot.kind == .color, var g = glow else { return }
        let newPalette = Palette(Array(preset.palette.colors.prefix(256)))
        func apply(_ image: inout ColorImage) {
            let t = image.transparentIndex.flatMap { $0 < newPalette.count ? $0 : 0 }
            image.image = Remapper.remap(image.image, from: image.palette, to: newPalette,
                                         sourceTransparentIndex: image.transparentIndex, targetTransparentIndex: t)
            image.palette = newPalette
            image.transparentIndex = t
        }
        if slot.state == .normal || g.selectedSharesPalette {
            apply(&g.normal)
            if g.selectedSharesPalette, var s = g.selected { apply(&s); s.palette = g.normal.palette; g.selected = s }
        } else if var s = g.selected {
            apply(&s)
            g.selected = s
        }
        glow = g
        invalidateARGB()
    }

    // MARK: Canvas

    func canvasSize(_ kind: ImageSlot.Kind) -> (width: Int, height: Int) {
        switch kind {
        case .classic: return (normalImage.image.width, normalImage.image.height)
        case .color: return (glow?.width ?? 0, glow?.height ?? 0)
        }
    }

    /// Resizes (crops/extends or scales) both normal and selected images of a kind.
    mutating func resizeCanvas(_ kind: ImageSlot.Kind, width: Int, height: Int, anchor: CanvasAnchor, scale: Bool) {
        let limit = kind == .color ? 256 : Self.maxClassicSize
        let w = min(limit, max(1, width)), h = min(limit, max(1, height))
        func transform(_ image: IndexedImage, fill: UInt8) -> IndexedImage {
            scale ? image.scaled(width: w, height: h) : image.resizedCanvas(width: w, height: h, anchor: anchor, fill: fill)
        }
        switch kind {
        case .classic:
            normalImage.image = transform(normalImage.image, fill: 0)
            if var selected = selectedImage {
                selected.image = transform(selected.image, fill: 0)
                selectedImage = selected
            }
        case .color:
            guard var g = glow else { return }
            g.normal.image = transform(g.normal.image, fill: UInt8(g.normal.transparentIndex ?? 0))
            if var s = g.selected {
                s.image = transform(s.image, fill: UInt8(s.transparentIndex ?? 0))
                g.selected = s
            }
            glow = g
            invalidateARGB()
        }
    }

    // MARK: Conversion

    /// Builds the classic image(s) from the colour image(s) for pre-OS3.5 Workbench.
    mutating func generateClassicFromColor(depth: Int, classicPreset: PalettePreset, dither: DitherMode) {
        guard let g = glow else { return }
        let palette = IconRenderer.classicPalette(depth: depth, preset: classicPreset)
        func convert(_ color: ColorImage) -> ClassicImage {
            let rgba = IconRenderer.render(color)
            let indexed = Remapper.remap(rgba, to: palette, options: RemapOptions(dither: dither, transparentIndex: nil,
                                                                                  alphaThreshold: 128, backgroundIndex: 0))
            return ClassicImage(image: indexed, depth: depth)
        }
        normalImage = convert(g.normal)
        if let s = g.selected {
            selectedImage = convert(s)
            info.highlight = .image
        } else {
            selectedImage = nil
            if info.highlight == .image { info.highlight = .complement }
        }
    }

    /// The ARGB chunks of AROS icons no longer match once the colour image changes.
    mutating func invalidateARGB() {
        guard let g = glow, g.hasARGB else { return }
        glow?.extraChunks.removeAll { $0.id == "ARGB" }
    }

    /// Converts an OS4 PNG icon into an editable OS3.5 icon (palette images, max 256×256).
    init(converting png: PNGIcon, maxColors: Int = 256) {
        func indexed(_ rgba: RGBAImage) -> ImageImporter.Result {
            let target = ImageImporter.Target(canvasWidth: min(256, rgba.width), canvasHeight: min(256, rgba.height),
                                              palette: Palette([.black]), transparentIndex: nil,
                                              maxColors: maxColors, maxSize: 256, fixedPalette: false)
            var options = ImageImporter.Options()
            options.sizing = .resizeCanvas
            options.paletteSource = .generate(colors: maxColors)
            return ImageImporter.importPicture(rgba, target: target, options: options)
        }
        let normal = indexed(png.normal)
        var glow = GlowIcon(normal: ColorImage(image: normal.image, palette: normal.palette, transparentIndex: normal.transparentIndex),
                            isFrameless: png.isFrameless)
        if let sel = png.selected {
            var selected = sel
            if sel.width != png.normal.width || sel.height != png.normal.height {
                selected = ImageConversion.scaled(sel, width: png.normal.width, height: png.normal.height, smooth: true)
            }
            let s = indexed(selected)
            glow.selected = ColorImage(image: s.image, palette: s.palette, transparentIndex: s.transparentIndex)
        }
        self.init(info: png.info, normalImage: ClassicImage(image: IndexedImage(width: 1, height: 1), depth: 2), glow: glow)
        generateClassicFromColor(depth: 2, classicPreset: WorkbenchPalettes.workbench31, dither: .floydSteinberg)
        if png.info.type.hasDrawerData && info.drawer == nil { info.drawer = DrawerData() }
    }
}
