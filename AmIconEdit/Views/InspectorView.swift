import AmigaIconKit
import SwiftUI

struct InspectorView: View {
    @ObservedObject var editor: EditorState
    @AppStorage("inspectorTab") private var tab = Tab.image

    enum Tab: String, CaseIterable, Identifiable {
        case image = "Image", icon = "Icon"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)
            Divider()
            switch tab {
            case .image: ImageInspector(editor: editor)
            case .icon: IconInspector(editor: editor)
            }
        }
    }
}

// MARK: - Image

struct ImageInspector: View {
    @ObservedObject var editor: EditorState
    @State private var classicDepth = 2
    @State private var classicDither = DitherMode.floydSteinberg
    @State private var hexText = ""

    var body: some View {
        let slot = editor.slot
        Form {
            Section("Canvas") {
                let (w, h) = editor.icon.canvasSize(slot.kind)
                LabeledContent("Size") {
                    HStack {
                        Text(editor.hasCurrentImage || slot.kind == .classic ? "\(w) × \(h) px" : "—").monospacedDigit()
                        Spacer()
                        Button("Resize…") { editor.showCanvasSize = true }
                            .disabled(!editor.hasCurrentImage)
                    }
                }
                if slot.kind == .color, editor.icon.glow != nil {
                    Toggle("Frameless", isOn: Binding(
                        get: { editor.icon.glow?.isFrameless ?? false },
                        set: { v in editor.modify("Frameless") { $0.glow?.isFrameless = v } }))
                        .help("Workbench draws OS3.5 icons without the default frame.")
                }
            }

            if editor.hasCurrentImage {
                colorsSection(slot)
                paletteSection(slot)
            }

            Section("Image") {
                Button("Import Picture…") { editor.beginImport() }
                Button("Export as PNG…") { editor.exportPNG() }.disabled(!editor.hasCurrentImage)
                if slot.state == .selected, editor.hasCurrentImage {
                    Button("Copy Normal Image Here") {
                        if let normal = editor.icon.image(ImageSlot(slot.kind, .normal)) {
                            editor.modify("Copy Normal Image") { icon in
                                icon.setImage(normal, for: slot)
                                if slot.kind == .color, var g = icon.glow, !g.selectedSharesPalette, var s = g.selected {
                                    s.palette = g.normal.palette
                                    s.transparentIndex = g.normal.transparentIndex
                                    g.selected = s
                                    icon.glow = g
                                }
                            }
                        }
                    }
                }
                if editor.hasCurrentImage && !(slot.kind == .classic && slot.state == .normal) {
                    Button(slot.kind == .color && slot.state == .normal ? "Remove Colour Images" : "Remove Selected Image",
                           role: .destructive) { editor.removeCurrentImage() }
                }
            }

            if editor.icon.glow != nil {
                Section("Classic Image") {
                    Picker("Bitplanes", selection: $classicDepth) {
                        ForEach(1...3, id: \.self) { Text("\($0) (\(1 << $0) colours)").tag($0) }
                    }
                    Picker("Dithering", selection: $classicDither) {
                        ForEach(DitherMode.allCases) { Text($0.displayName).tag($0) }
                    }
                    Button("Generate from Colour Image") {
                        editor.generateClassic(depth: classicDepth, dither: classicDither)
                    }
                    Text("Creates the planar image shown by Workbench 1.x–3.1, using the display palette.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func colorsSection(_ slot: ImageSlot) -> some View {
        Section("Colours") {
            if slot.kind == .color {
                let count = editor.icon.colorCount(slot)
                Stepper(value: Binding(get: { count }, set: { n in
                    let preset = editor.classicPreset
                    editor.modify("Number of Colours", coalesceKey: "colorCount") { $0.setColorCount(n, for: slot, classicPreset: preset) }
                }), in: 2...256) {
                    LabeledContent("Number of colours", value: "\(count)")
                }
                Toggle("Transparent colour", isOn: Binding(
                    get: { editor.currentTransparentIndex != nil },
                    set: { on in editor.modify("Transparent Colour") { $0.setTransparentIndex(on ? 0 : nil, for: slot) } }))
                if let t = editor.currentTransparentIndex {
                    Stepper(value: Binding(get: { t }, set: { v in
                        editor.modify("Transparent Colour", coalesceKey: "transparent") { $0.setTransparentIndex(v, for: slot) }
                    }), in: 0...(count - 1)) {
                        LabeledContent("Transparent index", value: "\(t)")
                    }
                }
                if slot.state == .selected, editor.icon.glow?.selected != nil {
                    Toggle("Use normal image's palette", isOn: Binding(
                        get: { editor.icon.glow?.selectedSharesPalette ?? false },
                        set: { share in
                            editor.modify("Share Palette") { icon in
                                guard var g = icon.glow, var s = g.selected else { return }
                                if share {
                                    s.image = Remapper.remap(s.image, from: s.palette, to: g.normal.palette,
                                                             sourceTransparentIndex: s.transparentIndex,
                                                             targetTransparentIndex: g.normal.transparentIndex)
                                    s.palette = g.normal.palette
                                    s.transparentIndex = g.normal.transparentIndex
                                }
                                g.selected = s
                                g.selectedSharesPalette = share
                                icon.glow = g
                            }
                        }))
                }
            } else {
                let depth = (slot.state == .selected ? editor.icon.selectedImage?.depth : nil) ?? editor.icon.normalImage.depth
                Picker("Bitplanes", selection: Binding(get: { depth }, set: { d in
                    let preset = editor.classicPreset
                    editor.modify("Bitplanes") { $0.setClassicDepth(d, classicPreset: preset) }
                })) {
                    ForEach(1...8, id: \.self) { Text("\($0) (\(1 << $0) colours)").tag($0) }
                }
            }
        }
    }

    @ViewBuilder
    private func paletteSection(_ slot: ImageSlot) -> some View {
        Section("Palette") {
            if slot.kind == .color {
                let index = Int(editor.primaryColor)
                let color = editor.currentPalette[index]
                // One row: "Colour  <index> <well> <#RRGGBB>". Inner controls hide their own labels,
                // otherwise the grouped form lays out the TextField's title as a second column.
                LabeledContent("Colour") {
                    HStack(spacing: 8) {
                        Text("\(index)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                        ColorPicker("Colour \(index)", selection: Binding(
                            get: { color.swiftUIColor },
                            set: { new in setColor(AmigaIconKit.RGBColor(new), index: index, slot: slot) }),
                                    supportsOpacity: false)
                            .labelsHidden()
                        TextField("Hex", text: $hexText, prompt: Text("#RRGGBB"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 92)
                            .onSubmit {
                                if let c = AmigaIconKit.RGBColor(hexString: hexText) { setColor(c, index: index, slot: slot) }
                                hexText = editor.currentPalette[index].description
                            }
                            .onAppear { hexText = color.description }
                            .onChange(of: color) { _, new in hexText = new.description }
                    }
                }
                Menu("Apply Preset") {
                    ForEach(WorkbenchPalettes.all) { preset in
                        Button("\(preset.name) (\(preset.palette.count))") {
                            editor.modify("Apply Palette") { $0.applyPalettePreset(preset, for: slot) }
                        }
                    }
                }
                .help("Replaces the palette and remaps the pixels to the nearest new colours.")
                HStack {
                    Button("Load .gpl…") { editor.loadPalette() }
                    Button("Save .gpl…") { editor.savePalette() }
                }
            } else {
                Picker("Display palette", selection: $editor.classicPresetID) {
                    ForEach(WorkbenchPalettes.all) { Text($0.name).tag($0.id) }
                }
                Text("Classic icons take their colours from the Workbench screen palette; this choice only changes how they are shown here.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Save .gpl…") { editor.savePalette() }
            }
        }
    }

    private func setColor(_ color: AmigaIconKit.RGBColor, index: Int, slot: ImageSlot) {
        var palette = editor.currentPalette
        guard index < palette.count, palette[index] != color else { return }
        palette[index] = color
        editor.modify("Edit Colour", coalesceKey: "color-\(index)") { $0.setPalette(palette, for: slot) }
    }
}

// MARK: - Icon attributes

struct IconInspector: View {
    @ObservedObject var editor: EditorState

    var body: some View {
        let info = editor.icon.info
        Form {
            Section("Workbench") {
                Picker("Type", selection: Binding(get: { info.type }, set: { t in
                    editor.modify("Icon Type") { icon in
                        icon.info.type = t
                        if t.hasDrawerData && icon.info.drawer == nil { icon.info.drawer = DrawerData() }
                        if !t.hasDrawerData { icon.info.drawer = nil }
                    }
                })) {
                    ForEach(IconType.allCases) { Text($0.displayName).tag($0) }
                }
                TextField("Stack size", value: field("Stack Size", \.info.stackSize), format: .number.grouping(.never))
                Picker("Highlight", selection: field("Highlight Mode", \.info.highlight)) {
                    ForEach(HighlightMode.allCases) { Text($0.displayName).tag($0) }
                }
            }

            Section("Position") {
                Toggle("Fixed position", isOn: Binding(get: { info.position != nil }, set: { on in
                    editor.modify("Icon Position") { $0.info.position = on ? IconPosition(x: 10, y: 10) : nil }
                }))
                if info.position != nil {
                    TextField("X", value: Binding(get: { info.position?.x ?? 0 }, set: { v in
                        editor.modify("Icon Position", coalesceKey: "posx") { $0.info.position?.x = v }
                    }), format: .number.grouping(.never))
                    TextField("Y", value: Binding(get: { info.position?.y ?? 0 }, set: { v in
                        editor.modify("Icon Position", coalesceKey: "posy") { $0.info.position?.y = v }
                    }), format: .number.grouping(.never))
                }
            }

            Section("Default Tool") {
                TextField("Default tool", text: Binding(get: { info.defaultTool ?? "" }, set: { v in
                    editor.modify("Default Tool", coalesceKey: "defaultTool") { $0.info.defaultTool = v.isEmpty ? nil : v }
                }), prompt: Text("e.g. SYS:Utilities/MultiView"))
                .labelsHidden()
            }

            Section("Tool Types") {
                ToolTypesEditor(editor: editor)
            }

            if let drawer = info.drawer {
                drawerSection(drawer)
            }

            Section("Tool Window") {
                TextField("Tool window", text: Binding(get: { info.toolWindow ?? "" }, set: { v in
                    editor.modify("Tool Window", coalesceKey: "toolWindow") { $0.info.toolWindow = v.isEmpty ? nil : v }
                }), prompt: Text("Rarely used"))
                .labelsHidden()
            }
        }
        .formStyle(.grouped)
    }

    private func field<T: Equatable>(_ name: String, _ keyPath: WritableKeyPath<AmigaIcon, T>) -> Binding<T> {
        Binding(get: { editor.icon[keyPath: keyPath] },
                set: { v in editor.modify(name, coalesceKey: name) { $0[keyPath: keyPath] = v } })
    }

    @ViewBuilder
    private func drawerSection(_ drawer: DrawerData) -> some View {
        Section("Drawer Window") {
            drawerField("Left", \.left)
            drawerField("Top", \.top)
            drawerField("Width", \.width)
            drawerField("Height", \.height)
            Picker("View by", selection: Binding(get: { drawer.viewModes ?? 0 }, set: { v in
                editor.modify("Drawer View Mode") { $0.info.drawer?.viewModes = v }
            })) {
                Text("Default").tag(UInt16(0))
                Text("Icons").tag(UInt16(1))
                Text("Name").tag(UInt16(2))
                Text("Date").tag(UInt16(3))
                Text("Size").tag(UInt16(4))
                Text("Type").tag(UInt16(5))
            }
            Picker("Show", selection: Binding(get: { drawer.flags ?? 0 }, set: { v in
                editor.modify("Drawer Show Mode") { $0.info.drawer?.flags = v }
            })) {
                Text("Default").tag(UInt32(0))
                Text("Only icons").tag(UInt32(1))
                Text("All files").tag(UInt32(2))
            }
        }
    }

    private func drawerField(_ title: String, _ keyPath: WritableKeyPath<DrawerData, Int16>) -> some View {
        TextField(title, value: Binding(get: { editor.icon.info.drawer?[keyPath: keyPath] ?? 0 }, set: { v in
            editor.modify("Drawer Window", coalesceKey: "drawer-\(title)") { $0.info.drawer?[keyPath: keyPath] = v }
        }), format: .number.grouping(.never))
    }
}

/// Editable list of tool types (one `KEY=value` string per line).
/// NewIcons image data lines (`IM1=`/`IM2=`) are hidden and left untouched.
struct ToolTypesEditor: View {
    @ObservedObject var editor: EditorState
    /// Selected row, as a visible index.
    @State private var selection: Int?

    private var types: [String] { editor.icon.info.toolTypes ?? [] }
    private var rowCount: Int { ToolTypeEditing.visibleIndices(types).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if rowCount == 0 {
                Text("No tool types").foregroundStyle(.secondary)
            }
            ForEach(0..<rowCount, id: \.self) { row in
                HStack(spacing: 6) {
                    Image(systemName: selection == row ? "smallcircle.filled.circle" : "circle")
                        .foregroundStyle(selection == row ? Color.accentColor : .secondary)
                        .onTapGesture { selection = row }
                    TextField("KEY=value", text: Binding(
                        get: { ToolTypeEditing.value(types, visible: row) },
                        set: { v in update("Edit Tool Type", key: "tt-\(row)") { ToolTypeEditing.set(v, visible: row, in: &$0) } }))
                        .font(.system(.body, design: .monospaced))
                        .labelsHidden()
                        .onTapGesture { selection = row }
                }
            }
            let hidden = ToolTypeEditing.hiddenCount(types)
            if hidden > 0 {
                Label("NewIcons image data: \(hidden) hidden lines, kept unchanged", systemImage: "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Button { add() } label: { Image(systemName: "plus") }.help("Add tool type")
                Button { remove() } label: { Image(systemName: "minus") }
                    .disabled(selection == nil).help("Remove selected tool type")
                Button { move(-1) } label: { Image(systemName: "arrow.up") }
                    .disabled((selection ?? 0) <= 0).help("Move up")
                Button { move(1) } label: { Image(systemName: "arrow.down") }
                    .disabled(selection == nil || selection! >= rowCount - 1).help("Move down")
                Spacer()
                Text("(KEY) = disabled").font(.caption).foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .onChange(of: rowCount) { _, count in
            if let s = selection, s >= count { selection = count > 0 ? count - 1 : nil }
        }
    }

    private func update(_ name: String, key: String? = nil, _ change: (inout [String]) -> Void) {
        editor.modify(name, coalesceKey: key) { icon in
            var list = icon.info.toolTypes ?? []
            change(&list)
            icon.info.toolTypes = (list.isEmpty && icon.info.toolTypes == nil) ? nil : list
        }
    }

    private func add() {
        var newRow = 0
        update("Add Tool Type") { newRow = ToolTypeEditing.insert("NEWTOOLTYPE=", afterVisible: selection, in: &$0) }
        selection = newRow
    }

    private func remove() {
        guard let row = selection, row < rowCount else { return }
        update("Remove Tool Type") { ToolTypeEditing.remove(visible: row, in: &$0) }
        selection = rowCount == 0 ? nil : min(row, rowCount - 1)
    }

    private func move(_ delta: Int) {
        guard let row = selection else { return }
        var newRow = row
        update("Move Tool Type") { newRow = ToolTypeEditing.move(visible: row, by: delta, in: &$0) }
        selection = newRow
    }
}
