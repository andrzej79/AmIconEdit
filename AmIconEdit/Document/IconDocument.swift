import AmigaIconKit
import SwiftUI
import UniformTypeIdentifiers

/// An open `.info` file. All edits go through `modify(_:…)`, which records undo snapshots.
/// The icon is only mutated on the main actor; SwiftUI reads snapshots there as well.
final class IconDocument: ReferenceFileDocument, @unchecked Sendable {
    static var readableContentTypes: [UTType] { [.amigaIcon] }
    static var writableContentTypes: [UTType] { [.amigaIcon] }

    @Published private(set) var icon: AmigaIcon
    /// Shown once when the file had to be converted (e.g. an OS4 PNG icon).
    @Published var notice: String?

    private var lastCoalesceKey: String?

    init(icon: AmigaIcon = .blank()) {
        self.icon = icon
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        switch try IconFile.read(data) {
        case .diskObject(let icon):
            self.icon = icon
            if !icon.warnings.value.isEmpty { notice = icon.warnings.value.joined(separator: "\n") }
        case .png(let png):
            self.icon = AmigaIcon(converting: png)
            notice = "This is an OS4/MorphOS PNG icon. It was converted to an OS3.5 palette icon; saving writes the OS3.5 format."
        }
    }

    func snapshot(contentType: UTType) throws -> AmigaIcon { icon }

    func fileWrapper(snapshot: AmigaIcon, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try snapshot.encoded())
    }

    // MARK: Editing with undo

    /// Applies a change and registers an undo step.
    /// Consecutive changes with the same non-nil `coalesceKey` (e.g. typing in a field) form one undo step.
    @MainActor
    func modify(_ actionName: String, undoManager: UndoManager?, coalesceKey: String? = nil,
                _ change: (inout AmigaIcon) -> Void) {
        let before = icon
        var after = icon
        change(&after)
        guard after != before || after.glow?.extraChunks != before.glow?.extraChunks else { return }
        let coalesce = coalesceKey != nil && coalesceKey == lastCoalesceKey
            && undoManager?.undoActionName == actionName && undoManager?.canUndo == true
        icon = after
        lastCoalesceKey = coalesceKey
        if !coalesce { registerUndo(restoring: before, actionName: actionName, undoManager: undoManager) }
    }

    /// Replaces the whole icon (used by undo/redo).
    @MainActor
    private func replace(with value: AmigaIcon, actionName: String, undoManager: UndoManager?) {
        let current = icon
        icon = value
        lastCoalesceKey = nil
        registerUndo(restoring: current, actionName: actionName, undoManager: undoManager)
    }

    @MainActor
    private func registerUndo(restoring value: AmigaIcon, actionName: String, undoManager: UndoManager?) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { document in
            MainActor.assumeIsolated {
                document.replace(with: value, actionName: actionName, undoManager: undoManager)
            }
        }
        undoManager.setActionName(actionName)
    }

    /// Ends any running coalesced edit, so the next change gets its own undo step.
    @MainActor
    func breakCoalescing() { lastCoalesceKey = nil }
}
