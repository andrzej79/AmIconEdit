import Foundation
import Testing
@testable import AmigaIconKit

@Suite("DiskObject codec")
struct DiskObjectCodecTests {
    @Test func parsesWarpGuide() throws {
        let icon = try Fixtures.icon("Warp.guide")
        #expect(icon.info.type == .project)
        #expect(icon.info.defaultTool == "MultiView")
        #expect(icon.info.stackSize == 4096)
        #expect(icon.info.position == nil)
        #expect(icon.info.toolTypes == nil)
        #expect(icon.info.highlight == .complement)
        #expect(icon.normalImage.image.width == 54)
        #expect(icon.normalImage.image.height == 22)
        #expect(icon.normalImage.depth == 2)
        #expect(icon.selectedImage == nil)
        #expect(icon.trailingData.isEmpty)
        #expect(icon.warnings.value.isEmpty)

        let glow = try #require(icon.glow)
        #expect(glow.width == 42)
        #expect(glow.height == 46)
        #expect(glow.normal.palette.count == 10)
        #expect(glow.normal.transparentIndex == 0)
        let selected = try #require(glow.selected)
        #expect(selected.palette.count == 12)
        #expect(!glow.selectedSharesPalette)
        #expect(!glow.isFrameless)
    }

    @Test func parsesToolWithToolTypes() throws {
        let icon = try Fixtures.icon("WarpAmpVis")
        #expect(icon.info.type == .tool)
        #expect(icon.info.defaultTool == nil)
        let types = try #require(icon.info.toolTypes)
        #expect(types.first == "BARCOLORS=10C010,E0D010,F03010")
        #expect(types.contains("FPS=25"))
        #expect(icon.glow != nil)
    }

    @Test func parsesMountlistIconWithAlternateImage() throws {
        let icon = try Fixtures.icon("WUSB0")
        #expect(icon.info.type == .project)
        #expect(icon.info.defaultTool == "C:Mount")
        #expect(icon.info.highlight == .image)
        #expect(icon.info.toolTypes?.contains("ACTIVATE=1") == true)
        let selected = try #require(icon.selectedImage)
        #expect(selected.depth == 3)
        #expect(selected.image.width == 50 && selected.image.height == 29)
        #expect(icon.glow == nil)
    }

    @Test func parsesPlanarOnlyIconWithPosition() throws {
        let icon = try Fixtures.icon("warpNET")
        #expect(icon.glow == nil)
        #expect(icon.info.position == IconPosition(x: 8, y: 232))
        #expect(icon.info.defaultTool == "AddNetInterface")
    }

    @Test func parsesSharedSelectedPalette() throws {
        let glow = try #require(try Fixtures.icon("WarpDashboard").glow)
        #expect(glow.selectedSharesPalette)
        #expect(glow.selected?.palette == glow.normal.palette)
        #expect(glow.normal.palette.count == 49)
    }

    @Test(arguments: Fixtures.names)
    func unmodifiedIconsRoundTripByteIdentical(name: String) throws {
        let original = try Fixtures.bytes(name)
        let icon = try DiskObjectCodec.read(original)
        let written = try DiskObjectCodec.write(icon)
        #expect(written == original, "\(name) changed on round trip")
    }

    @Test(arguments: Fixtures.names)
    func modifiedIconsRoundTripSemantically(name: String) throws {
        var icon = try Fixtures.icon(name)
        icon.info.stackSize = 12345
        icon.info.position = IconPosition(x: 10, y: 20)
        icon.info.defaultTool = "SYS:Utilities/MultiView"
        icon.info.toolTypes = ["DONOTWAIT", "ÄÖÜ=latin1"]
        icon.info.highlight = .backfill
        icon.normalImage.image[0, 0] = 1
        if var glow = icon.glow {
            glow.normal.image[1, 1] = UInt8(glow.normal.palette.count - 1)
            var palette = glow.normal.palette
            palette[0] = RGBColor(1, 2, 3)
            glow.setPalette(palette, selected: false)
            glow.isFrameless = true
            icon.glow = glow
        }
        let reread = try AmigaIcon(data: icon.encoded())
        #expect(reread == icon)
    }

    @Test func resizedClassicImageUpdatesGadgetSize() throws {
        var icon = try Fixtures.icon("Warp.guide")
        icon.normalImage.image = icon.normalImage.image.resizedCanvas(width: 60, height: 30, anchor: .center)
        let bytes = try DiskObjectCodec.write(icon)
        #expect(bytes[12] == 0 && bytes[13] == 60)
        #expect(bytes[14] == 0 && bytes[15] == 30)
        #expect(try DiskObjectCodec.read(bytes).normalImage.image == icon.normalImage.image)
    }

    @Test func changedDepthRewritesPlanePick() throws {
        var icon = try Fixtures.icon("Warp.guide")
        icon.normalImage.depth = 3
        let reread = try AmigaIcon(data: icon.encoded())
        #expect(reread.normalImage.depth == 3)
        #expect(reread.normalImage.header.value?.planePick == 7)
        #expect(reread.normalImage.image == icon.normalImage.image)
    }

    @Test(arguments: IconType.allCases)
    func blankIconsRoundTrip(type: IconType) throws {
        var icon = AmigaIcon.blank(type: type)
        icon.info.toolTypes = ["A=1", "B"]
        icon.normalImage.image.drawRect(from: PixelPoint(2, 2), to: PixelPoint(20, 10), color: 3, filled: false)
        let reread = try AmigaIcon(data: icon.encoded())
        #expect(reread == icon)
        #expect(reread.info.drawer != nil || !type.hasDrawerData)
    }

    @Test func drawerDataFieldsRoundTrip() throws {
        var icon = AmigaIcon.blank(type: .drawer)
        var drawer = try #require(icon.info.drawer)
        drawer.left = 11; drawer.top = 22; drawer.width = 333; drawer.height = 144
        drawer.flags = 2; drawer.viewModes = 3
        icon.info.drawer = drawer
        let reread = try AmigaIcon(data: icon.encoded())
        #expect(reread.info.drawer?.width == 333)
        #expect(reread.info.drawer?.flags == 2)
        #expect(reread.info.drawer?.viewModes == 3)
    }

    @Test func emptyToolTypeArrayIsDistinctFromNone() throws {
        var icon = AmigaIcon.blank(type: .project)
        icon.info.toolTypes = []
        #expect(try AmigaIcon(data: icon.encoded()).info.toolTypes == [])
        icon.info.toolTypes = nil
        #expect(try AmigaIcon(data: icon.encoded()).info.toolTypes == nil)
    }

    @Test func rejectsNonIcons() {
        #expect(throws: AmigaIconError.notAnIcon) { try IconFile.read(Data("% hyphenation licence".utf8)) }
        #expect(throws: AmigaIconError.notAnIcon) { try IconFile.read(Data()) }
    }

    @Test(arguments: Fixtures.names)
    func truncatedInputNeverCrashes(name: String) throws {
        let bytes = try Fixtures.bytes(name)
        for length in 0..<bytes.count {
            _ = try? IconFile.read(Data(bytes.prefix(length)))
        }
    }

    @Test func randomGarbageNeverCrashes() {
        var rng = SeededGenerator(seed: 42)
        for _ in 0..<300 {
            let count = Int.random(in: 0..<600, using: &rng)
            var bytes = (0..<count).map { _ in UInt8.random(in: 0...255, using: &rng) }
            if bytes.count >= 2 { bytes[0] = 0xE3; bytes[1] = 0x10 }
            _ = try? IconFile.read(Data(bytes))
        }
    }

    @Test func rejectsOversizedColorImage() {
        var icon = AmigaIcon.blank()
        icon.glow?.normal.image = IndexedImage(width: 300, height: 10)
        #expect(throws: AmigaIconError.self) { try icon.encoded() }
    }

    @Test func rejectsClassicPixelsBeyondDepth() {
        var icon = AmigaIcon.blank()
        icon.normalImage.image[0, 0] = 9 // depth 2 allows 0…3
        #expect(throws: AmigaIconError.self) { try icon.encoded() }
    }
}
