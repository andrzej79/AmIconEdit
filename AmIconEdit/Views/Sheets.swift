import AmigaIconKit
import SwiftUI

/// Converts a picture to the current image: sizing, palette and dithering options with live preview.
struct ImportPictureSheet: View {
    @ObservedObject var editor: EditorState
    let picture: RGBAImage
    @Environment(\.dismiss) private var dismiss

    enum PaletteChoice: String, CaseIterable, Identifiable {
        case generate, keep, preset
        var id: String { rawValue }
    }

    @State private var sizing = ImageImporter.Sizing.fitCanvas
    @State private var smooth = true
    @State private var paletteChoice = PaletteChoice.generate
    @State private var colors = 32
    @State private var presetID = WorkbenchPalettes.workbench31.id
    @State private var dither = DitherMode.floydSteinberg
    @State private var keepTransparency = true
    @State private var alphaThreshold = 128.0
    @State private var orderedStrength = 1.0
    @State private var result: ImageImporter.Result?

    private var isClassic: Bool { editor.slot.kind == .classic }

    private var target: ImageImporter.Target {
        let icon = editor.icon
        if isClassic {
            let (w, h) = icon.canvasSize(.classic)
            return .init(canvasWidth: w, canvasHeight: h, palette: editor.currentPalette, transparentIndex: nil,
                         maxColors: editor.currentPalette.count, maxSize: AmigaIcon.maxClassicSize, fixedPalette: true)
        }
        let (w, h) = icon.glow != nil ? icon.canvasSize(.color) : (min(256, icon.normalImage.image.width), min(256, icon.normalImage.image.height))
        return .init(canvasWidth: w, canvasHeight: h, palette: editor.currentPalette, transparentIndex: editor.currentTransparentIndex,
                     maxColors: 256, maxSize: 256, fixedPalette: false)
    }

    private var options: ImageImporter.Options {
        var o = ImageImporter.Options()
        o.sizing = sizing
        o.smoothScaling = smooth
        switch paletteChoice {
        case .generate: o.paletteSource = .generate(colors: colors)
        case .keep: o.paletteSource = .keepCurrent
        case .preset: o.paletteSource = .preset(WorkbenchPalettes.preset(id: presetID) ?? WorkbenchPalettes.workbench31)
        }
        if isClassic { o.paletteSource = .keepCurrent }
        o.dither = dither
        o.keepTransparency = keepTransparency
        o.alphaThreshold = UInt8(alphaThreshold)
        o.orderedStrength = orderedStrength
        return o
    }

    /// Changes whenever an option changes; drives recomputation of the preview.
    private var optionsKey: String {
        "\(sizing)\(smooth)\(paletteChoice)\(colors)\(presetID)\(dither)\(keepTransparency)\(Int(alphaThreshold))\(orderedStrength)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Picture").font(.title2.bold())
            HStack(alignment: .center, spacing: 20) {
                preview(title: "Picture (\(picture.width)×\(picture.height))", image: picture)
                Image(systemName: "arrow.right").font(.title).foregroundStyle(.secondary)
                if let result {
                    preview(title: "Result (\(result.image.width)×\(result.image.height), \(result.palette.count) colours)",
                            image: ImageConversion.rgbaImage(from: result.image, palette: result.palette,
                                                             transparentIndex: isClassic ? 0 : result.transparentIndex))
                } else {
                    ProgressView().frame(width: 220, height: 220)
                }
            }
            Form {
                Picker("Size", selection: $sizing) {
                    ForEach(ImageImporter.Sizing.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("Smooth scaling", isOn: $smooth)
                if isClassic {
                    LabeledContent("Palette", value: "Workbench display palette (\(editor.currentPalette.count) colours)")
                } else {
                    Picker("Palette", selection: $paletteChoice) {
                        Text("Generate optimal palette").tag(PaletteChoice.generate)
                        Text("Keep current palette").tag(PaletteChoice.keep)
                        Text("Use preset").tag(PaletteChoice.preset)
                    }
                    if paletteChoice == .generate {
                        Stepper(value: $colors, in: 2...256) { LabeledContent("Colours", value: "\(colors)") }
                    }
                    if paletteChoice == .preset {
                        Picker("Preset", selection: $presetID) {
                            ForEach(WorkbenchPalettes.all) { Text($0.name).tag($0.id) }
                        }
                    }
                }
                Picker("Dithering", selection: $dither) {
                    ForEach(DitherMode.allCases) { Text($0.displayName).tag($0) }
                }
                if dither == .bayer4 || dither == .bayer8 {
                    LabeledContent("Dither strength") {
                        Slider(value: $orderedStrength, in: 0.25...2)
                    }
                }
                Toggle(isClassic ? "Transparent areas become colour 0" : "Keep transparency", isOn: $keepTransparency)
                if keepTransparency {
                    LabeledContent("Alpha threshold") {
                        Slider(value: $alphaThreshold, in: 1...255)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(height: 300)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Import") {
                    if let result { editor.applyImport(result) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(result == nil)
            }
        }
        .padding(20)
        .frame(width: 620)
        .task(id: optionsKey) {
            let picture = self.picture, target = self.target, options = self.options
            result = nil
            result = await Task.detached(priority: .userInitiated) {
                ImageImporter.importPicture(picture, target: target, options: options)
            }.value
        }
    }

    private func preview(title: String, image: RGBAImage) -> some View {
        let scale = Double(220) / Double(max(image.width, image.height))
        return VStack {
            Group {
                if let cg = ImageConversion.cgImage(from: image) {
                    Image(decorative: cg, scale: 1).resizable().interpolation(scale >= 1 ? .none : .high)
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: 220, height: 220)
            .background(Checkerboard(cell: 8))
            .overlay(Rectangle().stroke(.separator))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Resize or scale the canvas of the current image kind (normal and selected together).
struct CanvasSizeSheet: View {
    @ObservedObject var editor: EditorState
    @Environment(\.dismiss) private var dismiss
    @State private var width = 46
    @State private var height = 46
    @State private var anchor = CanvasAnchor.center
    @State private var scale = false

    private var limit: Int { editor.slot.kind == .color ? 256 : AmigaIcon.maxClassicSize }
    private let presets = [(32, 32), (46, 46), (48, 48), (54, 22), (64, 64), (80, 80)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Canvas Size – \(editor.slot.kind.displayName)").font(.title2.bold())
            Form {
                Stepper(value: $width, in: 1...limit) {
                    LabeledContent("Width") { TextField("Width", value: $width, format: .number.grouping(.never)).frame(width: 60) }
                }
                Stepper(value: $height, in: 1...limit) {
                    LabeledContent("Height") { TextField("Height", value: $height, format: .number.grouping(.never)).frame(width: 60) }
                }
                LabeledContent("Presets") {
                    HStack {
                        ForEach(presets, id: \.0) { p in
                            Button("\(p.0)×\(p.1)") { width = p.0; height = p.1 }.buttonStyle(.link)
                        }
                    }
                }
                Toggle("Scale image (nearest neighbour)", isOn: $scale)
                if !scale {
                    LabeledContent("Anchor") {
                        Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                            ForEach(0..<3) { row in
                                GridRow {
                                    ForEach(0..<3) { col in
                                        let a = CanvasAnchor(rawValue: row * 3 + col)!
                                        Button { anchor = a } label: {
                                            Image(systemName: a == anchor ? "square.fill" : "square")
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply") {
                    let kind = editor.slot.kind, w = min(limit, max(1, width)), h = min(limit, max(1, height))
                    let anchor = self.anchor, scale = self.scale
                    editor.modify(scale ? "Scale Image" : "Resize Canvas") {
                        $0.resizeCanvas(kind, width: w, height: h, anchor: anchor, scale: scale)
                    }
                    editor.fitZoom()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            let (w, h) = editor.icon.canvasSize(editor.slot.kind)
            width = max(1, w)
            height = max(1, h)
        }
    }
}
