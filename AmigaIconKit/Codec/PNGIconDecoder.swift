import Foundation

/// An AmigaOS 4 / MorphOS style icon: one or two concatenated PNG files whose `icOn` chunk
/// carries the Workbench attributes. Read-only.
public struct PNGIcon: Equatable, Sendable {
    public var normal: RGBAImage
    public var selected: RGBAImage?
    public var info: DiskObjectInfo
    public var isFrameless: Bool

    public init(normal: RGBAImage, selected: RGBAImage?, info: DiskObjectInfo, isFrameless: Bool) {
        self.normal = normal
        self.selected = selected
        self.info = info
        self.isFrameless = isFrameless
    }
}

public enum PNGIconDecoder {
    static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    // icOn attribute tags (TAG_USER | 0x1000 + n). String attributes are stored inline, NUL-terminated.
    enum Tag: UInt32 {
        case iconX = 0x8000_1001
        case iconY = 0x8000_1002
        case drawerX = 0x8000_1003
        case drawerY = 0x8000_1004
        case drawerWidth = 0x8000_1005
        case drawerHeight = 0x8000_1006
        case drawerFlags = 0x8000_1007
        case toolWindow = 0x8000_1008
        case stackSize = 0x8000_1009
        case defaultTool = 0x8000_100A
        case toolType = 0x8000_100B
        case viewModes = 0x8000_100C
        case currentX = 0x8000_100D
        case currentY = 0x8000_100E
        case type = 0x8000_100F
        case frameless = 0x8000_1010
        case drawerFlags3 = 0x8000_1011
        case viewModes2 = 0x8000_1012
        case drawerFlags2 = 0x8000_1107

        var isString: Bool { self == .toolWindow || self == .defaultTool || self == .toolType }
    }

    public static func isPNG(_ bytes: [UInt8]) -> Bool { bytes.starts(with: signature) }

    /// Splits concatenated PNG streams and returns each stream with its `icOn` chunk data, if any.
    static func splitPNGs(_ bytes: [UInt8]) throws -> [(png: [UInt8], icOn: [UInt8]?)] {
        var result: [(png: [UInt8], icOn: [UInt8]?)] = []
        var offset = 0
        while offset + 8 <= bytes.count, bytes[offset..<offset + 8].elementsEqual(signature) {
            let start = offset
            var r = BigEndianReader(bytes, offset: offset + 8)
            var icOn: [UInt8]?
            var finished = false
            while !finished {
                let length = Int(try r.u32("PNG chunk length"))
                let type = IFF.fourCC(try r.bytes(4, "PNG chunk type"))
                let data = try r.bytes(length, "PNG chunk \(type)")
                try r.skip(4, "PNG CRC")
                if type == "icOn" { icOn = data }
                if type == "IEND" { finished = true }
            }
            offset = r.offset
            result.append((Array(bytes[start..<offset]), icOn))
        }
        guard !result.isEmpty else { throw AmigaIconError.notAnIcon }
        return result
    }

    public static func decode(_ bytes: [UInt8]) throws -> PNGIcon {
        let parts = try splitPNGs(bytes)
        guard let normal = ImageConversion.rgbaImage(fromEncoded: parts[0].png) else {
            throw AmigaIconError.invalid("PNG image data")
        }
        let selected = parts.count > 1 ? ImageConversion.rgbaImage(fromEncoded: parts[1].png) : nil
        var info = DiskObjectInfo(type: .project)
        var frameless = false
        if let tags = parts.compactMap({ $0.icOn }).first {
            parseTags(tags, into: &info, frameless: &frameless)
        }
        return PNGIcon(normal: normal, selected: selected, info: info, isFrameless: frameless)
    }

    static func parseTags(_ data: [UInt8], into info: inout DiskObjectInfo, frameless: inout Bool) {
        var r = BigEndianReader(data)
        var x: Int32?, y: Int32?
        var drawer = DrawerData()
        var hasDrawer = false
        while r.remaining >= 4 {
            guard let rawTag = try? r.u32(), let tag = Tag(rawValue: rawTag) else { break }
            if tag.isString {
                var s: [UInt8] = []
                while let b = try? r.u8(), b != 0 { s.append(b) }
                let text = AmigaText.decode(s)
                switch tag {
                case .defaultTool: info.defaultTool = text
                case .toolType: info.toolTypes = (info.toolTypes ?? []) + [text]
                case .toolWindow: info.toolWindow = text
                default: break
                }
                continue
            }
            guard let value = try? r.u32() else { break }
            let signed = Int32(bitPattern: value)
            switch tag {
            case .iconX: x = signed
            case .iconY: y = signed
            case .stackSize: info.stackSize = signed
            case .type: info.type = IconType(rawValue: UInt8(truncatingIfNeeded: value)) ?? .project
            case .frameless: frameless = value != 0
            case .drawerX: drawer.left = Int16(truncatingIfNeeded: signed); hasDrawer = true
            case .drawerY: drawer.top = Int16(truncatingIfNeeded: signed); hasDrawer = true
            case .drawerWidth: drawer.width = Int16(truncatingIfNeeded: signed); hasDrawer = true
            case .drawerHeight: drawer.height = Int16(truncatingIfNeeded: signed); hasDrawer = true
            case .drawerFlags: drawer.flags = value; hasDrawer = true
            case .viewModes: drawer.viewModes = UInt16(truncatingIfNeeded: value); hasDrawer = true
            case .currentX: drawer.currentX = signed
            case .currentY: drawer.currentY = signed
            default: break
            }
        }
        if let x, let y, x != DiskObjectCodec.noIconPosition, y != DiskObjectCodec.noIconPosition {
            info.position = IconPosition(x: x, y: y)
        }
        if hasDrawer { info.drawer = drawer }
    }
}
