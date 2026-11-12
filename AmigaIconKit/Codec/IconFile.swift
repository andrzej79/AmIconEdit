import Foundation
import UniformTypeIdentifiers

public extension UTType {
    /// Amiga Workbench icon (`.info`), exported by AmIconEdit.
    static let amigaIcon = UTType(exportedAs: "com.andrzej79.amiga-icon", conformingTo: .data)
}

/// The contents of an `.info` file.
public enum IconFile: Equatable, Sendable {
    /// A `struct DiskObject` icon (classic, possibly with OS3.5 colour images). Editable.
    case diskObject(AmigaIcon)
    /// An OS4/MorphOS PNG icon. Read-only.
    case png(PNGIcon)

    public enum Kind: Sendable { case diskObject, png }

    /// Detects the format from the first bytes, without parsing.
    public static func kind(of bytes: [UInt8]) -> Kind? {
        if bytes.count >= 2, bytes[0] == 0xE3, bytes[1] == 0x10 { return .diskObject }
        if PNGIconDecoder.isPNG(bytes) { return .png }
        return nil
    }

    public static func read(_ data: Data) throws -> IconFile {
        let bytes = [UInt8](data)
        switch kind(of: bytes) {
        case .diskObject: return .diskObject(try DiskObjectCodec.read(bytes))
        case .png: return .png(try PNGIconDecoder.decode(bytes))
        case nil: throw AmigaIconError.notAnIcon
        }
    }

    public static func read(contentsOf url: URL) throws -> IconFile {
        try read(Data(contentsOf: url, options: .mappedIfSafe))
    }

    public var info: DiskObjectInfo {
        switch self {
        case .diskObject(let icon): return icon.info
        case .png(let png): return png.info
        }
    }
}

public extension AmigaIcon {
    /// Parses a `struct DiskObject` icon.
    init(data: Data) throws {
        self = try DiskObjectCodec.read([UInt8](data))
    }

    /// Serialises the icon to `.info` file bytes.
    func encoded() throws -> Data {
        Data(try DiskObjectCodec.write(self))
    }
}
