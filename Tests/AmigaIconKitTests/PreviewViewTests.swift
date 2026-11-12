import AppKit
import SwiftUI
import Testing
@testable import AmigaIconKit

@MainActor
@Suite("Quick Look preview view")
struct PreviewViewTests {
    func render(_ view: IconPreviewView) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    @Test(arguments: Fixtures.names)
    func rendersFixtures(name: String) throws {
        let file = try IconFile.read(Fixtures.data(name))
        let rep = try render(IconPreviewView(file: file, fileName: "\(name).info"))
        #expect(rep.pixelsWide >= 640)
    }

    @Test func rendersErrorState() throws {
        _ = try render(IconPreviewView(errorMessage: AmigaIconError.notAnIcon.localizedDescription, fileName: "x.info"))
    }
}
