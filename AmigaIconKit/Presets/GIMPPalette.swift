import Foundation

/// Reads and writes GIMP palette files (`.gpl`), a simple text format understood by most paint programs.
public enum GIMPPalette {
    public static func encode(_ palette: Palette, name: String = "AmIconEdit") -> String {
        var out = "GIMP Palette\nName: \(name)\nColumns: 16\n#\n"
        for (i, c) in palette.colors.enumerated() {
            out += String(format: "%3d %3d %3d\tColour %d\n", c.r, c.g, c.b, i)
        }
        return out
    }

    public static func decode(_ text: String) throws -> Palette {
        var lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "GIMP Palette" else {
            throw AmigaIconError.invalid("not a GIMP palette")
        }
        lines.removeFirst()
        var colors: [RGBColor] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.contains(":") { continue }
            let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).prefix(3).compactMap { Int($0) }
            guard parts.count == 3 else { continue }
            colors.append(RGBColor(UInt8(clamping: parts[0]), UInt8(clamping: parts[1]), UInt8(clamping: parts[2])))
            if colors.count == 256 { break }
        }
        guard !colors.isEmpty else { throw AmigaIconError.invalid("palette has no colours") }
        return Palette(colors)
    }
}
