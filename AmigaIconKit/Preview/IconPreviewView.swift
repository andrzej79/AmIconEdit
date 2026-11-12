import SwiftUI

/// Read-only presentation of an icon file: all images plus Workbench attributes.
/// Used by the Quick Look extension and by the editor's info panel.
public struct IconPreviewView: View {
    let file: IconFile?
    let fileName: String
    let errorMessage: String?
    let pictures: [IconPicture]

    public init(file: IconFile, fileName: String) {
        self.file = file
        self.fileName = fileName
        self.errorMessage = nil
        self.pictures = IconRenderer.pictures(of: file)
    }

    public init(errorMessage: String, fileName: String) {
        self.file = nil
        self.fileName = fileName
        self.errorMessage = errorMessage
        self.pictures = []
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(fileName).font(.title2.bold()).lineLimit(1).truncationMode(.middle)
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                } else if let file {
                    picturesRow
                    Divider()
                    AttributesGrid(file: file)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var picturesRow: some View {
        let maxDim = pictures.map { max($0.image.width, $0.image.height) }.max() ?? 1
        let factor = max(1, min(6, 160 / max(1, maxDim)))
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 20) {
                ForEach(pictures) { picture in
                    VStack(spacing: 6) {
                        PixelImage(image: picture.image, scale: factor)
                        Text(picture.title).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// Crisp, nearest-neighbour rendering of an RGBA image on a checkerboard.
public struct PixelImage: View {
    let cgImage: CGImage?
    let width: CGFloat
    let height: CGFloat

    public init(image: RGBAImage, scale: Int) {
        self.cgImage = ImageConversion.cgImage(from: image)
        self.width = CGFloat(image.width * scale)
        self.height = CGFloat(image.height * scale)
    }

    public var body: some View {
        ZStack {
            Checkerboard(cell: 6)
            if let cgImage {
                Image(decorative: cgImage, scale: 1)
                    .resizable()
                    .interpolation(.none)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(.separator))
    }
}

/// Transparency checkerboard.
public struct Checkerboard: View {
    let cell: CGFloat
    public init(cell: CGFloat = 8) { self.cell = cell }

    public var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.92)))
            var path = Path()
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = (row % 2 == 0) ? 0 : cell
                while x < size.width {
                    path.addRect(CGRect(x: x, y: y, width: cell, height: cell))
                    x += cell * 2
                }
                y += cell
                row += 1
            }
            ctx.fill(path, with: .color(Color(white: 0.8)))
        }
    }
}

struct AttributesGrid: View {
    let file: IconFile

    var body: some View {
        let info = file.info
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
            row("Format", formatDescription)
            row("Type", info.type.displayName)
            row("Default tool", info.defaultTool ?? "—")
            row("Stack", "\(info.stackSize) bytes")
            row("Position", info.position.map { "\($0.x), \($0.y)" } ?? "Not set (Workbench places the icon)")
            if case .diskObject(let icon) = file {
                row("Highlight", info.highlight.displayName)
                row("Classic image", "\(icon.normalImage.image.width)×\(icon.normalImage.image.height), \(icon.normalImage.depth) bitplane(s)")
                if let glow = icon.glow {
                    row("OS3.5 image", "\(glow.width)×\(glow.height), \(glow.normal.palette.count) colours"
                        + (glow.isFrameless ? ", frameless" : ""))
                }
            }
            if let drawer = info.drawer {
                row("Drawer window", "\(drawer.left), \(drawer.top)  \(drawer.width)×\(drawer.height)")
            }
            if let window = info.toolWindow { row("Tool window", window) }
            GridRow {
                Text("Tool types").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                let all = info.toolTypes ?? []
                // NewIcons image data is binary-looking text; summarise it instead of listing it.
                let imageLines = all.filter(NewIconsDecoder.isImageData).count
                let types = all.filter { !NewIconsDecoder.isImageData($0) && $0 != Self.newIconsMarker }
                if !types.isEmpty || imageLines > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(types.enumerated()), id: \.offset) { _, t in
                            Text(t).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        }
                        if imageLines > 0 {
                            Text("NewIcons image data (\(imageLines) lines)").foregroundStyle(.secondary).italic()
                        }
                    }
                } else {
                    Text("—")
                }
            }
            if case .diskObject(let icon) = file, !icon.warnings.value.isEmpty {
                row("Warnings", icon.warnings.value.joined(separator: "\n"))
            }
        }
    }

    static let newIconsMarker = "*** DON'T EDIT THE FOLLOWING LINES!! ***"

    private var formatDescription: String {
        switch file {
        case .png: return "OS4 / MorphOS PNG icon"
        case .diskObject(let icon):
            if icon.glow?.hasARGB == true { return "OS3.5 colour icon with ARGB images" }
            if icon.glow != nil { return "OS3.5 colour icon (GlowIcon)" }
            if let newIcons = icon.newIcons {
                return "NewIcons icon (\(newIcons.normal.image.width)×\(newIcons.normal.image.height), \(newIcons.normal.palette.count) colours)"
            }
            return "Classic Workbench icon"
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled)
        }
    }
}
