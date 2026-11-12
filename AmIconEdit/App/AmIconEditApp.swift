import AmigaIconKit
import SwiftUI

@main
struct AmIconEditApp: App {
    init() {
        // Classic document behaviour for this app, whatever the system-wide setting: the .info file
        // is only written on Save, and closing (or quitting) with unsaved edits asks
        // Save / Don't Save / Cancel instead of silently autosaving into the original file.
        UserDefaults.standard.set(true, forKey: "NSCloseAlwaysConfirmsChanges")
        #if DEBUG
        DebugSnapshot.scheduleIfRequested()
        #endif
    }

    var body: some Scene {
        DocumentGroup(newDocument: { IconDocument() }) { file in
            EditorView(document: file.document)
        }
        .commands { EditorCommands() }
    }
}

/// Menu commands acting on the focused editor window.
struct EditorCommands: Commands {
    @FocusedObject private var editor: EditorState?

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Import Picture…") { editor?.beginImport() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(editor == nil)
            Button("Export Image as PNG…") { editor?.exportPNG() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(editor?.hasCurrentImage != true)
        }

        CommandMenu("Image") {
            Group {
                Button("Flip Horizontally") { editor?.transformCurrent("Flip Horizontally") { $0.flippedHorizontally() } }
                Button("Flip Vertically") { editor?.transformCurrent("Flip Vertically") { $0.flippedVertically() } }
                Divider()
                Button("Shift Left") { editor?.transformCurrent("Shift") { $0.shifted(dx: -1, dy: 0) } }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                Button("Shift Right") { editor?.transformCurrent("Shift") { $0.shifted(dx: 1, dy: 0) } }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                Button("Shift Up") { editor?.transformCurrent("Shift") { $0.shifted(dx: 0, dy: -1) } }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                Button("Shift Down") { editor?.transformCurrent("Shift") { $0.shifted(dx: 0, dy: 1) } }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                Divider()
                Button("Clear Image") { editor?.clearCurrent() }
                Button("Canvas Size…") { editor?.showCanvasSize = true }
                    .keyboardShortcut("r", modifiers: [.command, .option])
            }
            .disabled(editor?.hasCurrentImage != true)
            Divider()
            Picker("Image", selection: Binding(get: { editor?.slot ?? ImageSlot(.color, .normal) },
                                               set: { editor?.select($0); editor?.fitZoom() })) {
                Text("Colour – Normal").tag(ImageSlot(.color, .normal))
                Text("Colour – Selected").tag(ImageSlot(.color, .selected))
                Text("Classic – Normal").tag(ImageSlot(.classic, .normal))
                Text("Classic – Selected").tag(ImageSlot(.classic, .selected))
            }
            .disabled(editor == nil)
        }

        CommandGroup(after: .toolbar) {
            Button("Zoom In") { editor?.zoomIn() }.keyboardShortcut("+", modifiers: .command)
            Button("Zoom Out") { editor?.zoomOut() }.keyboardShortcut("-", modifiers: .command)
            Button("Zoom to Fit") { editor?.fitZoom() }.keyboardShortcut("0", modifiers: .command)
            Button(editor?.showGrid == true ? "Hide Grid" : "Show Grid") { editor?.showGrid.toggle() }
                .keyboardShortcut("'", modifiers: .command)
            Divider()
        }
    }
}
