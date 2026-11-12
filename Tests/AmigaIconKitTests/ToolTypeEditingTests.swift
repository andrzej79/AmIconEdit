import Testing
@testable import AmigaIconKit

@Suite("Tool type editing with hidden NewIcons data")
struct ToolTypeEditingTests {
    let withNewIcons = ["FILETYPE=TEXT", "DONOTWAIT", " ", ToolTypeEditing.newIconsMarker,
                        "IM1=BEI!.abc", "IM1=def", "IM2=BEI!+ghi", "IM2=jkl"]

    @Test func hidesOnlyImageDataLines() {
        #expect(ToolTypeEditing.visibleIndices(withNewIcons) == [0, 1, 2, 3])
        #expect(ToolTypeEditing.hiddenCount(withNewIcons) == 4)
        #expect(ToolTypeEditing.value(withNewIcons, visible: 3) == ToolTypeEditing.newIconsMarker)
        #expect(ToolTypeEditing.value(withNewIcons, visible: 4) == "")
    }

    @Test func appendGoesBeforeNewIconsBlock() {
        var types = withNewIcons
        let row = ToolTypeEditing.insert("NEW=1", afterVisible: nil, in: &types)
        #expect(types == ["FILETYPE=TEXT", "DONOTWAIT", "NEW=1", " ", ToolTypeEditing.newIconsMarker,
                          "IM1=BEI!.abc", "IM1=def", "IM2=BEI!+ghi", "IM2=jkl"])
        #expect(row == 2)
        var plain = ["A"]
        #expect(ToolTypeEditing.insert("B", afterVisible: nil, in: &plain) == 1)
        #expect(plain == ["A", "B"])
    }

    @Test func insertAfterSelectedRow() {
        var types = withNewIcons
        let row = ToolTypeEditing.insert("X", afterVisible: 0, in: &types)
        #expect(row == 1)
        #expect(types[1] == "X")
        #expect(types.suffix(4) == withNewIcons.suffix(4))
    }

    @Test func editRemoveAndMoveNeverTouchImageData() {
        var types = withNewIcons
        ToolTypeEditing.set("FILETYPE=GUIDE", visible: 0, in: &types)
        #expect(types[0] == "FILETYPE=GUIDE")
        #expect(ToolTypeEditing.move(visible: 0, by: 1, in: &types) == 1)
        #expect(Array(types.prefix(2)) == ["DONOTWAIT", "FILETYPE=GUIDE"])
        #expect(ToolTypeEditing.move(visible: 3, by: 1, in: &types) == 3) // last visible row: no-op
        ToolTypeEditing.remove(visible: 0, in: &types)
        #expect(types.first == "FILETYPE=GUIDE")
        #expect(types.suffix(4) == withNewIcons.suffix(4))
        ToolTypeEditing.set("IGNORED", visible: 9, in: &types)
        #expect(!types.contains("IGNORED"))
    }
}
