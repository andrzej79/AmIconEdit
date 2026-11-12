import AmigaIconKit
import Cocoa
import QuickLookUI
import SwiftUI

/// Quick Look preview for Amiga `.info` icons: shows every image in the icon plus its Workbench attributes.
final class PreviewViewController: NSViewController, QLPreviewingController {
    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let name = url.lastPathComponent
        let root: IconPreviewView
        do {
            root = IconPreviewView(file: try IconFile.read(contentsOf: url), fileName: name)
        } catch {
            root = IconPreviewView(errorMessage: error.localizedDescription, fileName: name)
        }
        let hosting = NSHostingView(rootView: root)
        hosting.frame = view.bounds
        hosting.autoresizingMask = [.width, .height]
        view.subviews.forEach { $0.removeFromSuperview() }
        view.addSubview(hosting)
        preferredContentSize = NSSize(width: 640, height: 480)
    }
}
