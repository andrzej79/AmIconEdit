import AmigaIconKit
import SwiftUI

struct EditorView: View {
    @ObservedObject var document: IconDocument
    @StateObject private var editor: EditorState
    @Environment(\.undoManager) private var undoManager
    @State private var showInspector = true

    init(document: IconDocument) {
        self.document = document
        _editor = StateObject(wrappedValue: EditorState(document: document))
    }

    var body: some View {
        VStack(spacing: 0) {
            SlotBar(editor: editor)
            Divider()
            canvasArea
            Divider()
            PaletteBar(editor: editor)
            Divider()
            StatusBar(editor: editor)
        }
        .frame(minWidth: 560, minHeight: 480)
        .toolbar { toolbarContent }
        .inspector(isPresented: $showInspector) {
            InspectorView(editor: editor)
                .inspectorColumnWidth(min: 300, ideal: 330, max: 460)
        }
        .focusedSceneObject(editor)
        .onAppear { editor.undoManager = undoManager }
        .onChange(of: undoManager) { _, new in editor.undoManager = new }
        .sheet(isPresented: Binding(get: { editor.importPicture != nil }, set: { if !$0 { editor.importPicture = nil } })) {
            if let picture = editor.importPicture {
                ImportPictureSheet(editor: editor, picture: picture)
            }
        }
        .sheet(isPresented: $editor.showCanvasSize) { CanvasSizeSheet(editor: editor) }
        .alert("AmIconEdit", isPresented: Binding(get: { editor.errorMessage != nil }, set: { if !$0 { editor.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(editor.errorMessage ?? "")
        }
        .alert("Note", isPresented: Binding(get: { document.notice != nil }, set: { if !$0 { document.notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(document.notice ?? "")
        }
    }

    @ViewBuilder
    private var canvasArea: some View {
        if let image = editor.currentImage {
            ScrollView([.horizontal, .vertical]) {
                PixelCanvas(editor: editor, image: image)
                    .frame(width: CGFloat(image.width * editor.zoom), height: CGFloat(image.height * editor.zoom))
                    .padding(24)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            }
            .defaultScrollAnchor(.center)
            .background(Color(nsColor: .underPageBackgroundColor))
        } else {
            ContentUnavailableView {
                Label(missingTitle, systemImage: "photo.badge.plus")
            } description: {
                Text(missingDescription)
            } actions: {
                Button(createTitle) { editor.createCurrentImage() }
                    .buttonStyle(.borderedProminent)
                if editor.slot.kind == .color && editor.slot.state == .normal {
                    Button("Import Picture…") { editor.beginImport() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .underPageBackgroundColor))
        }
    }

    private var missingTitle: String {
        editor.slot.state == .selected ? "No selected image" : "No colour image"
    }

    private var missingDescription: String {
        switch (editor.slot.kind, editor.slot.state) {
        case (.color, .normal):
            return "This is a classic icon. Add an OS3.5 colour image (up to 256×256, 256 colours)."
        case (.color, .selected), (.classic, .selected):
            return "Workbench highlights the icon automatically. Add a separate image to show when the icon is selected."
        default:
            return ""
        }
    }

    private var createTitle: String {
        editor.slot.state == .selected ? "Create from Normal Image" : "Add Colour Image"
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Tool", selection: $editor.tool) {
                ForEach(EditorTool.allCases) { tool in
                    Label(tool.title, systemImage: tool.symbol).tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .help("Drawing tool (left click: primary colour, right or ⌥-click: secondary colour)")
        }
        ToolbarItemGroup {
            Button { editor.zoomOut() } label: { Label("Zoom Out", systemImage: "minus.magnifyingglass") }
            Text("\(editor.zoom)×").monospacedDigit().frame(minWidth: 30)
            Button { editor.zoomIn() } label: { Label("Zoom In", systemImage: "plus.magnifyingglass") }
            Toggle(isOn: $editor.showGrid) { Label("Grid", systemImage: "grid") }
                .help("Show pixel grid")
            Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.right") }
        }
    }
}

/// Selects which image is edited.
struct SlotBar: View {
    @ObservedObject var editor: EditorState

    var body: some View {
        HStack(spacing: 12) {
            Picker("Image", selection: Binding(get: { editor.slot.kind }, set: { editor.select(ImageSlot($0, editor.slot.state)); editor.fitZoom() })) {
                ForEach(ImageSlot.Kind.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Picker("State", selection: Binding(get: { editor.slot.state }, set: { editor.select(ImageSlot(editor.slot.kind, $0)) })) {
                ForEach(ImageSlot.State.allCases) { state in
                    Text(state.displayName + (editor.icon.hasImage(ImageSlot(editor.slot.kind, state)) ? "" : " (none)")).tag(state)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
            let (w, h) = editor.icon.canvasSize(editor.slot.kind)
            if editor.hasCurrentImage {
                Text("\(w) × \(h)  ·  \(editor.icon.colorCount(editor.slot)) colours")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct StatusBar: View {
    @ObservedObject var editor: EditorState

    var body: some View {
        HStack {
            if let hover = editor.hover {
                Text("x \(hover.point.x)  y \(hover.point.y)  ·  colour \(hover.index)")
                    .monospacedDigit()
            } else {
                Text(editor.tool.title)
            }
            Spacer()
            if editor.icon.glow?.hasARGB == true {
                Text("Contains AROS ARGB images (kept until the colour image is edited)")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }
}
