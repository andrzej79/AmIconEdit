#if DEBUG
import AppKit

/// Debug builds only: when launched with `-snapshotDelay <seconds>`, renders the key window into
/// `<sandbox container>/tmp/AmIconEdit-window.png` (used for automated UI checks and README screenshots).
enum DebugSnapshot {
    @MainActor
    static func scheduleIfRequested() {
        let delay = UserDefaults.standard.double(forKey: "snapshotDelay")
        guard delay > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                  let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("AmIconEdit-window.png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            NSLog("DebugSnapshot written to %@", url.path)
        }
    }
}
#endif
