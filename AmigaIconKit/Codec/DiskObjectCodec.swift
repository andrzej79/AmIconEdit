import Foundation

/// Reads and writes `struct DiskObject` based `.info` files (Workbench 1.x – 3.x, plus OS3.5 FORM ICON).
public enum DiskObjectCodec {
    public static let magic: UInt16 = 0xE310
    static let headerSize = 78
    static let imageHeaderSize = 20
    static let noIconPosition: Int32 = Int32(bitPattern: 0x8000_0000)
    /// Non-NULL marker written for pointer fields that only signal presence.
    static let placeholderPointer: UInt32 = 0x0010_0000
    static let gadgetImageFlag: UInt16 = 0x0004
    static let diskRevision: UInt32 = 1
    static let maxStringLength = 1 << 20

    // Header offsets
    enum Offset {
        static let version = 2
        static let gadgetNext = 4
        static let gadgetLeft = 8
        static let gadgetTop = 10
        static let gadgetWidth = 12
        static let gadgetHeight = 14
        static let gadgetFlags = 16
        static let gadgetActivation = 18
        static let gadgetType = 20
        static let gadgetRender = 22
        static let selectRender = 26
        static let gadgetUserData = 44
        static let type = 48
        static let defaultTool = 50
        static let toolTypes = 54
        static let currentX = 58
        static let currentY = 62
        static let drawerData = 66
        static let toolWindow = 70
        static let stackSize = 74
    }

    // MARK: - Reading

    public static func read(_ bytes: [UInt8]) throws -> AmigaIcon {
        var r = BigEndianReader(bytes)
        guard bytes.count >= 2, try r.u16() == magic else { throw AmigaIconError.notAnIcon }
        guard bytes.count >= headerSize else { throw AmigaIconError.truncated("DiskObject header") }
        let header = Array(bytes[0..<headerSize])
        func u16(_ o: Int) -> UInt16 { UInt16(header[o]) << 8 | UInt16(header[o + 1]) }
        func u32(_ o: Int) -> UInt32 {
            UInt32(header[o]) << 24 | UInt32(header[o + 1]) << 16 | UInt32(header[o + 2]) << 8 | UInt32(header[o + 3])
        }
        var warnings: [String] = []

        let gadgetFlags = u16(Offset.gadgetFlags)
        let hasSelect = u32(Offset.selectRender) != 0
        let userData = u32(Offset.gadgetUserData)
        let rawType = header[Offset.type]
        let type = IconType(rawValue: rawType) ?? {
            warnings.append("Unknown icon type \(rawType); treated as Project.")
            return .project
        }()
        let cx = Int32(bitPattern: u32(Offset.currentX))
        let cy = Int32(bitPattern: u32(Offset.currentY))
        let hasDefaultTool = u32(Offset.defaultTool) != 0
        let hasToolTypes = u32(Offset.toolTypes) != 0
        let hasDrawer = u32(Offset.drawerData) != 0
        let hasToolWindow = u32(Offset.toolWindow) != 0

        var info = DiskObjectInfo(
            type: type,
            stackSize: Int32(bitPattern: u32(Offset.stackSize)),
            position: (cx == noIconPosition || cy == noIconPosition) ? nil : IconPosition(x: cx, y: cy),
            highlight: HighlightMode(rawValue: gadgetFlags & 3) ?? .complement)
        info.preservedHeader = Ignored(header)

        r = BigEndianReader(bytes, offset: headerSize)
        var drawerRaw: [UInt8]?
        if hasDrawer { drawerRaw = try r.bytes(DrawerData.rawSize, "drawer data") }

        let normal = try readImage(&r)
        let selected = hasSelect ? try readImage(&r) : nil

        // Strings. Some old tools wrote sloppy string sections, so failures here are not fatal.
        var trailing: [UInt8] = []
        let stringStart = r.offset
        do {
            if hasDefaultTool { info.defaultTool = try readString(&r, "default tool") }
            if hasToolTypes {
                let countField = Int(try r.u32("tool type count"))
                let n = max(0, countField / 4 - 1)
                guard n <= r.remaining / 4 else { throw AmigaIconError.invalid("tool type count") }
                var types: [String] = []
                for _ in 0..<n { types.append(try readString(&r, "tool type")) }
                info.toolTypes = types
            }
            if hasToolWindow { info.toolWindow = try readString(&r, "tool window") }
            if let drawerRaw {
                if userData & 0xFF == diskRevision, r.remaining >= 6, r.peek(4) != Array("FORM".utf8) {
                    let flags = try r.u32()
                    let modes = try r.u16()
                    info.drawer = DrawerData(raw: drawerRaw, flags: flags, viewModes: modes)
                } else {
                    info.drawer = DrawerData(raw: drawerRaw)
                }
            }
        } catch {
            warnings.append("Could not read the text part of the icon (\(error.localizedDescription)); the remaining bytes are preserved.")
            if let drawerRaw, info.drawer == nil { info.drawer = DrawerData(raw: drawerRaw) }
            r = BigEndianReader(bytes, offset: max(stringStart, r.offset))
            trailing = Array(bytes[r.offset...])
            r = BigEndianReader(bytes, offset: bytes.count)
        }

        var glow: GlowIcon?
        if r.peek(4) == Array("FORM".utf8) {
            let save = r.offset
            do {
                let form = try IFF.readForm(&r)
                glow = try GlowIconCodec.read(form: form)
            } catch {
                warnings.append("Could not read the OS3.5 colour image (\(error.localizedDescription)); it is preserved as raw data.")
                r = BigEndianReader(bytes, offset: save)
            }
        }
        if !r.isAtEnd { trailing += Array(bytes[r.offset...]) }

        var icon = AmigaIcon(info: info, normalImage: normal, selectedImage: selected, glow: glow, trailingData: trailing)
        icon.warnings = Ignored(warnings)
        return icon
    }

    static func readImage(_ r: inout BigEndianReader) throws -> ClassicImage {
        var h = ClassicImageHeader()
        h.leftEdge = try r.i16("image header")
        h.topEdge = try r.i16("image header")
        let width = Int(try r.u16("image width"))
        let height = Int(try r.u16("image height"))
        h.depth = try r.u16("image depth")
        h.imageDataPointer = try r.u32("image data pointer")
        h.planePick = try r.u8("image plane pick")
        h.planeOnOff = try r.u8("image plane on/off")
        h.nextImage = try r.u32("image next")
        h.originalWidth = width
        h.originalHeight = height
        let depth = Int(h.depth)
        guard depth <= 8 else { throw AmigaIconError.unsupported("classic image depth \(depth)") }
        guard width <= 4096, height <= 4096 else { throw AmigaIconError.limitExceeded("classic image size") }

        var image: IndexedImage
        if h.imageDataPointer != 0 && depth > 0 {
            let data = try r.bytes(PlanarCodec.dataSize(width: width, height: height, depth: depth), "bitplanes")
            image = try PlanarCodec.decode(data, width: width, height: height, depth: depth)
        } else {
            image = IndexedImage(width: width, height: height)
        }
        var classic = ClassicImage(image: image, depth: max(1, depth))
        classic.header = Ignored(h)
        return classic
    }

    static func readString(_ r: inout BigEndianReader, _ what: String) throws -> String {
        let length = Int(try r.u32("\(what) length"))
        guard length <= maxStringLength else { throw AmigaIconError.invalid("\(what) length") }
        return AmigaText.decode(try r.bytes(length, what))
    }

    // MARK: - Writing

    public static func write(_ icon: AmigaIcon) throws -> [UInt8] {
        let info = icon.info
        let template = info.preservedHeader.value
        var w = BigEndianWriter(capacity: 2048)
        func t16(_ o: Int, _ fallback: UInt16) -> UInt16 {
            guard let h = template else { return fallback }
            return UInt16(h[o]) << 8 | UInt16(h[o + 1])
        }
        func t32(_ o: Int, _ fallback: UInt32) -> UInt32 {
            guard let h = template else { return fallback }
            return UInt32(h[o]) << 24 | UInt32(h[o + 1]) << 16 | UInt32(h[o + 2]) << 8 | UInt32(h[o + 3])
        }
        func pointer(_ o: Int, present: Bool) -> UInt32 {
            guard present else { return 0 }
            let p = t32(o, 0)
            return p != 0 ? p : placeholderPointer
        }

        let normal = icon.normalImage
        for img in [normal] + (icon.selectedImage.map { [$0] } ?? []) {
            guard img.image.width <= 0xFFFF, img.image.height <= 0xFFFF, (1...8).contains(img.depth) else {
                throw AmigaIconError.limitExceeded("classic image size or depth")
            }
            guard Int(img.image.maxIndex) < img.colorCount else {
                throw AmigaIconError.invalid("classic image uses colours beyond its depth")
            }
        }

        // Gadget size follows the normal image unless the image kept its original size.
        var gadgetWidth = UInt16(normal.image.width)
        var gadgetHeight = UInt16(normal.image.height)
        if let h = normal.header.value, h.originalWidth == normal.image.width, h.originalHeight == normal.image.height {
            gadgetWidth = t16(Offset.gadgetWidth, gadgetWidth)
            gadgetHeight = t16(Offset.gadgetHeight, gadgetHeight)
        }
        var userData = t32(Offset.gadgetUserData, diskRevision)
        if info.drawer?.flags != nil || info.drawer?.viewModes != nil { userData = (userData & ~0xFF) | diskRevision }

        w.u16(magic)
        w.u16(t16(Offset.version, 1))
        // struct Gadget
        w.u32(t32(Offset.gadgetNext, 0))
        w.u16(t16(Offset.gadgetLeft, 0))
        w.u16(t16(Offset.gadgetTop, 0))
        w.u16(gadgetWidth)
        w.u16(gadgetHeight)
        w.u16((t16(Offset.gadgetFlags, 0) & ~3) | gadgetImageFlag | info.highlight.rawValue)
        w.u16(t16(Offset.gadgetActivation, 3))
        w.u16(t16(Offset.gadgetType, 1))
        w.u32(pointer(Offset.gadgetRender, present: true))
        w.u32(pointer(Offset.selectRender, present: icon.selectedImage != nil))
        w.u32(t32(30, 0)) // GadgetText
        w.u32(t32(34, 0)) // MutualExclude
        w.u32(t32(38, 0)) // SpecialInfo
        w.u16(t16(42, 0)) // GadgetID
        w.u32(userData)
        // DiskObject
        w.u8(info.type.rawValue)
        w.u8(template?[49] ?? 0)
        w.u32(pointer(Offset.defaultTool, present: info.defaultTool != nil))
        w.u32(pointer(Offset.toolTypes, present: info.toolTypes != nil))
        w.i32(info.position?.x ?? noIconPosition)
        w.i32(info.position?.y ?? noIconPosition)
        w.u32(pointer(Offset.drawerData, present: info.drawer != nil))
        w.u32(pointer(Offset.toolWindow, present: info.toolWindow != nil))
        w.i32(info.stackSize)

        if let drawer = info.drawer { w.append(drawer.raw) }
        writeImage(normal, into: &w)
        if let selected = icon.selectedImage { writeImage(selected, into: &w) }

        if let tool = info.defaultTool { writeString(tool, into: &w) }
        if let types = info.toolTypes {
            w.u32(UInt32((types.count + 1) * 4))
            for t in types { writeString(t, into: &w) }
        }
        if let window = info.toolWindow { writeString(window, into: &w) }
        if let drawer = info.drawer, userData & 0xFF == diskRevision {
            w.u32(drawer.flags ?? 0)
            w.u16(drawer.viewModes ?? 0)
        }
        if let glow = icon.glow { w.append(try GlowIconCodec.write(glow)) }
        w.append(icon.trailingData)
        return w.bytes
    }

    static func writeImage(_ img: ClassicImage, into w: inout BigEndianWriter) {
        let h = img.header.value
        let sameDepth = h.map { Int($0.depth) == img.depth } ?? false
        w.i16(h?.leftEdge ?? 0)
        w.i16(h?.topEdge ?? 0)
        w.u16(UInt16(img.image.width))
        w.u16(UInt16(img.image.height))
        w.u16(UInt16(img.depth))
        let ptr = h?.imageDataPointer ?? 0
        w.u32(ptr != 0 ? ptr : placeholderPointer)
        w.u8(sameDepth ? h!.planePick : UInt8((1 << img.depth) - 1))
        w.u8(sameDepth ? h!.planeOnOff : 0)
        w.u32(h?.nextImage ?? 0)
        w.append(PlanarCodec.encode(img.image, depth: img.depth))
    }

    static func writeString(_ s: String, into w: inout BigEndianWriter) {
        let bytes = AmigaText.encode(s) + [0]
        w.u32(UInt32(bytes.count))
        w.append(bytes)
    }
}
