import Foundation

/// Workbench object type (`do_Type`).
public enum IconType: UInt8, CaseIterable, Sendable, Identifiable {
    case disk = 1, drawer, tool, project, garbage, device, kick, appIcon

    public var id: UInt8 { rawValue }

    public var displayName: String {
        switch self {
        case .disk: return "Disk"
        case .drawer: return "Drawer"
        case .tool: return "Tool"
        case .project: return "Project"
        case .garbage: return "Trashcan"
        case .device: return "Device"
        case .kick: return "Kickstart"
        case .appIcon: return "AppIcon"
        }
    }

    /// Types that carry drawer window data.
    public var hasDrawerData: Bool { self == .disk || self == .drawer || self == .garbage }
}

/// How Workbench highlights a selected icon (low two bits of the gadget flags).
public enum HighlightMode: UInt16, CaseIterable, Sendable, Identifiable {
    case complement = 0
    case backfill = 1
    case image = 2
    case none = 3

    public var id: UInt16 { rawValue }

    public var displayName: String {
        switch self {
        case .complement: return "Complement"
        case .backfill: return "Backfill"
        case .image: return "Alternate image"
        case .none: return "None"
        }
    }
}

public struct IconPosition: Hashable, Sendable {
    public var x: Int32
    public var y: Int32
    public init(x: Int32, y: Int32) { self.x = x; self.y = y }
}

/// Drawer window information (`struct OldDrawerData` + OS 2.x `DrawerData` extension).
public struct DrawerData: Equatable, Sendable {
    /// Raw 56 bytes: `struct NewWindow` (48) + dd_CurrentX (4) + dd_CurrentY (4).
    public internal(set) var raw: [UInt8]
    /// dd_Flags (OS 2.x): 0 = default, 1 = show only icons, 2 = show all files.
    public var flags: UInt32?
    /// dd_ViewModes (OS 2.x): 0 = default, 1 = icons, 2 = name, 3 = date, 4 = size, 5 = type.
    public var viewModes: UInt16?

    public static let rawSize = 56

    public init(raw: [UInt8], flags: UInt32? = nil, viewModes: UInt16? = nil) {
        var r = raw
        if r.count < Self.rawSize { r += [UInt8](repeating: 0, count: Self.rawSize - r.count) }
        self.raw = Array(r.prefix(Self.rawSize))
        self.flags = flags
        self.viewModes = viewModes
    }

    /// A default drawer window at the given rectangle.
    public init(left: Int16 = 50, top: Int16 = 50, width: Int16 = 400, height: Int16 = 200) {
        self.init(raw: [UInt8](repeating: 0, count: Self.rawSize), flags: 0, viewModes: 1)
        self.left = left; self.top = top; self.width = width; self.height = height
        // DetailPen/BlockPen = 0xFF ("use screen defaults").
        raw[8] = 0xFF; raw[9] = 0xFF
    }

    private func word(_ o: Int) -> Int16 { Int16(bitPattern: UInt16(raw[o]) << 8 | UInt16(raw[o + 1])) }
    private mutating func setWord(_ o: Int, _ v: Int16) {
        let u = UInt16(bitPattern: v); raw[o] = UInt8(u >> 8); raw[o + 1] = UInt8(u & 0xFF)
    }
    private func long(_ o: Int) -> Int32 {
        Int32(bitPattern: UInt32(raw[o]) << 24 | UInt32(raw[o + 1]) << 16 | UInt32(raw[o + 2]) << 8 | UInt32(raw[o + 3]))
    }
    private mutating func setLong(_ o: Int, _ v: Int32) {
        let u = UInt32(bitPattern: v)
        raw[o] = UInt8(u >> 24); raw[o + 1] = UInt8((u >> 16) & 0xFF); raw[o + 2] = UInt8((u >> 8) & 0xFF); raw[o + 3] = UInt8(u & 0xFF)
    }

    public var left: Int16 { get { word(0) } set { setWord(0, newValue) } }
    public var top: Int16 { get { word(2) } set { setWord(2, newValue) } }
    public var width: Int16 { get { word(4) } set { setWord(4, newValue) } }
    public var height: Int16 { get { word(6) } set { setWord(6, newValue) } }
    /// Scroll offset of the drawer contents.
    public var currentX: Int32 { get { long(48) } set { setLong(48, newValue) } }
    public var currentY: Int32 { get { long(52) } set { setLong(52, newValue) } }
}

/// Non-image DiskObject fields.
public struct DiskObjectInfo: Equatable, Sendable {
    public var type: IconType
    public var stackSize: Int32
    /// `nil` means NO_ICON_POSITION (Workbench places the icon).
    public var position: IconPosition?
    public var defaultTool: String?
    /// `nil` = no tool type array; `[]` = an empty array.
    public var toolTypes: [String]?
    public var toolWindow: String?
    public var highlight: HighlightMode
    public var drawer: DrawerData?

    /// The original 78-byte DiskObject header, used to keep fields the editor does not model
    /// (pointers, gadget internals) byte-identical. Ignored for equality.
    var preservedHeader: Ignored<[UInt8]?>

    public init(type: IconType = .project, stackSize: Int32 = 4096, position: IconPosition? = nil,
                defaultTool: String? = nil, toolTypes: [String]? = nil, toolWindow: String? = nil,
                highlight: HighlightMode = .complement, drawer: DrawerData? = nil) {
        self.type = type
        self.stackSize = stackSize
        self.position = position
        self.defaultTool = defaultTool
        self.toolTypes = toolTypes
        self.toolWindow = toolWindow
        self.highlight = highlight
        self.drawer = drawer
        self.preservedHeader = Ignored(nil)
    }
}

/// `struct Image` fields that the editor keeps but does not edit.
struct ClassicImageHeader: Equatable, Sendable {
    var leftEdge: Int16 = 0
    var topEdge: Int16 = 0
    var imageDataPointer: UInt32 = 0
    var planePick: UInt8 = 0
    var planeOnOff: UInt8 = 0
    var nextImage: UInt32 = 0
    var depth: UInt16 = 0
    var originalWidth = 0
    var originalHeight = 0
}

/// A planar (pre-OS3.5) icon image. Colours come from the Workbench screen palette.
public struct ClassicImage: Equatable, Sendable {
    public var image: IndexedImage
    /// Number of bitplanes (1–8).
    public var depth: Int
    var header: Ignored<ClassicImageHeader?>

    public init(image: IndexedImage, depth: Int) {
        self.image = image
        self.depth = min(8, max(1, depth))
        self.header = Ignored(nil)
    }

    public var colorCount: Int { 1 << depth }
}

/// An OS3.5 ("GlowIcon") palette image.
public struct ColorImage: Equatable, Sendable {
    public var image: IndexedImage
    public var palette: Palette
    /// Colour index rendered transparent, if any.
    public var transparentIndex: Int?
    /// Original IMAG chunk plus the values it decoded to; reused when nothing changed.
    var source: Ignored<ColorImageSource?>

    public init(image: IndexedImage, palette: Palette, transparentIndex: Int? = nil) {
        self.image = image
        self.palette = palette
        self.transparentIndex = transparentIndex
        self.source = Ignored(nil)
    }
}

struct ColorImageSource: Sendable {
    var chunk: [UInt8]
    var image: IndexedImage
    var palette: Palette
    var transparentIndex: Int?
    var hadPalette: Bool
}

/// A raw IFF chunk kept for lossless saving (e.g. AROS `ARGB`).
public struct IFFChunk: Hashable, Sendable {
    public var id: String
    public var data: [UInt8]
    public init(id: String, data: [UInt8]) { self.id = id; self.data = data }
}

/// The OS3.5 `FORM ICON` part of an icon.
public struct GlowIcon: Equatable, Sendable {
    public var normal: ColorImage
    public var selected: ColorImage?
    /// The selected image is stored without its own palette and uses the normal image's palette.
    public var selectedSharesPalette: Bool
    /// Raw FACE flags; bit 0 = frameless.
    public var faceFlags: UInt8
    public var aspect: UInt8
    /// Chunks other than FACE/IMAG, written back after the images.
    public var extraChunks: [IFFChunk]
    var preservedMaxPaletteBytes: Ignored<UInt16?>

    public init(normal: ColorImage, selected: ColorImage? = nil, selectedSharesPalette: Bool = false,
                isFrameless: Bool = false, aspect: UInt8 = 0x11, extraChunks: [IFFChunk] = []) {
        self.normal = normal
        self.selected = selected
        self.selectedSharesPalette = selectedSharesPalette
        self.faceFlags = isFrameless ? 1 : 0
        self.aspect = aspect
        self.extraChunks = extraChunks
        self.preservedMaxPaletteBytes = Ignored(nil)
    }

    public var width: Int { normal.image.width }
    public var height: Int { normal.image.height }

    public var isFrameless: Bool {
        get { faceFlags & 1 != 0 }
        set { faceFlags = newValue ? (faceFlags | 1) : (faceFlags & ~1) }
    }

    /// Replaces the palette of the normal or selected image, keeping a shared palette in sync.
    public mutating func setPalette(_ palette: Palette, selected: Bool) {
        if selected && !selectedSharesPalette {
            self.selected?.palette = palette
            return
        }
        normal.palette = palette
        if selectedSharesPalette { self.selected?.palette = palette }
    }

    /// Whether the icon also contains AROS true-colour (`ARGB`) images.
    public var hasARGB: Bool { extraChunks.contains { $0.id == "ARGB" } }
}

/// A classic Workbench icon (`struct DiskObject`), optionally with OS3.5 colour images.
public struct AmigaIcon: Equatable, Sendable {
    public var info: DiskObjectInfo
    public var normalImage: ClassicImage
    public var selectedImage: ClassicImage?
    public var glow: GlowIcon?
    /// Unrecognised bytes found after the icon data, written back unchanged.
    public var trailingData: [UInt8]
    /// Non-fatal problems found while reading.
    public var warnings: Ignored<[String]>

    public init(info: DiskObjectInfo, normalImage: ClassicImage, selectedImage: ClassicImage? = nil,
                glow: GlowIcon? = nil, trailingData: [UInt8] = []) {
        self.info = info
        self.normalImage = normalImage
        self.selectedImage = selectedImage
        self.glow = glow
        self.trailingData = trailingData
        self.warnings = Ignored([])
    }

    /// A blank icon of the given type, with a 4-colour classic image and an 8-colour OS3.5 image.
    public static func blank(type: IconType = .project, width: Int = 46, height: Int = 46) -> AmigaIcon {
        var info = DiskObjectInfo(type: type)
        if type.hasDrawerData { info.drawer = DrawerData() }
        if type == .tool { info.toolTypes = [] }
        let classic = ClassicImage(image: IndexedImage(width: width, height: height), depth: 2)
        let color = ColorImage(image: IndexedImage(width: width, height: height),
                               palette: WorkbenchPalettes.workbench31.palette, transparentIndex: 0)
        return AmigaIcon(info: info, normalImage: classic, glow: GlowIcon(normal: color))
    }
}
