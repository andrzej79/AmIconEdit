import AmigaIconKit
import SwiftUI

extension AmigaIconKit.RGBColor {
    var swiftUIColor: Color {
        Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(UInt8((ns.redComponent * 255).rounded()), UInt8((ns.greenComponent * 255).rounded()),
                  UInt8((ns.blueComponent * 255).rounded()))
    }

    init?(hexString: String) {
        let s = hexString.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }
}

/// Palette swatches: click = primary colour, ⌥-click = secondary, context menu for more.
struct PaletteBar: View {
    @ObservedObject var editor: EditorState

    var body: some View {
        let palette = editor.currentPalette
        HStack(alignment: .top, spacing: 12) {
            ColorWell(editor: editor)
            ScrollView(.vertical) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 18, maximum: 18), spacing: 3)], alignment: .leading, spacing: 3) {
                    ForEach(0..<palette.count, id: \.self) { index in
                        Swatch(color: palette[index], index: index,
                               isPrimary: index == Int(editor.primaryColor),
                               isSecondary: index == Int(editor.secondaryColor),
                               isTransparent: index == editor.currentTransparentIndex)
                            .onTapGesture { editor.primaryColor = UInt8(index) }
                            .simultaneousGesture(TapGesture().modifiers(.option).onEnded { editor.secondaryColor = UInt8(index) })
                            .contextMenu { contextMenu(for: index) }
                    }
                }
                .padding(2)
            }
            .frame(maxHeight: 88)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func contextMenu(for index: Int) -> some View {
        Button("Use as Primary Colour") { editor.primaryColor = UInt8(index) }
        Button("Use as Secondary Colour") { editor.secondaryColor = UInt8(index) }
        if editor.slot.kind == .color {
            Divider()
            let slot = editor.slot
            if editor.currentTransparentIndex == index {
                Button("No Transparent Colour") { editor.modify("Transparent Colour") { $0.setTransparentIndex(nil, for: slot) } }
            } else {
                Button("Make Transparent Colour") { editor.modify("Transparent Colour") { $0.setTransparentIndex(index, for: slot) } }
            }
        }
        if let image = editor.currentImage {
            Divider()
            Button("Swap with Primary in Image") {
                editor.commit(image.swappingColors(UInt8(index), editor.primaryColor), actionName: "Swap Colours")
            }
        }
    }
}

struct Swatch: View {
    let color: AmigaIconKit.RGBColor
    let index: Int
    let isPrimary: Bool
    let isSecondary: Bool
    let isTransparent: Bool

    var body: some View {
        ZStack {
            if isTransparent {
                Checkerboard(cell: 4)
                color.swiftUIColor.opacity(0.35)
                Path { p in p.move(to: CGPoint(x: 0, y: 18)); p.addLine(to: CGPoint(x: 18, y: 0)) }
                    .stroke(.red, lineWidth: 1.5)
            } else {
                color.swiftUIColor
            }
        }
        .frame(width: 18, height: 18)
        .overlay(Rectangle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
        .overlay {
            if isPrimary {
                Rectangle().stroke(Color.accentColor, lineWidth: 2.5)
            } else if isSecondary {
                Rectangle().stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
            }
        }
        .help("Colour \(index): \(color.description)\(isTransparent ? " (transparent)" : "")")
    }
}

/// Primary/secondary colour indicator; click to swap.
struct ColorWell: View {
    @ObservedObject var editor: EditorState

    var body: some View {
        let palette = editor.currentPalette
        ZStack(alignment: .topLeading) {
            square(palette[Int(editor.secondaryColor)], index: editor.secondaryColor).offset(x: 14, y: 14)
            square(palette[Int(editor.primaryColor)], index: editor.primaryColor)
        }
        .frame(width: 46, height: 46, alignment: .topLeading)
        .onTapGesture { editor.swapColors() }
        .help("Primary (front) and secondary colour. Click to swap.")
    }

    private func square(_ color: AmigaIconKit.RGBColor, index: UInt8) -> some View {
        ZStack {
            if Int(index) == editor.currentTransparentIndex { Checkerboard(cell: 4) } else { color.swiftUIColor }
        }
        .frame(width: 30, height: 30)
        .overlay(Rectangle().stroke(Color.primary.opacity(0.5), lineWidth: 1))
    }
}
