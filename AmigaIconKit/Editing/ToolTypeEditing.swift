import Foundation

/// Tool type list operations that hide NewIcons image data (`IM1=`/`IM2=` lines) from the user.
/// Positions are "visible indices" (rows the user sees); hidden lines keep their order and content.
public enum ToolTypeEditing {
    /// Real indices of the tool types shown to the user.
    public static func visibleIndices(_ types: [String]) -> [Int] {
        types.indices.filter { !NewIconsDecoder.isImageData(types[$0]) }
    }

    public static func hiddenCount(_ types: [String]) -> Int {
        types.count - visibleIndices(types).count
    }

    /// Where new tool types are appended: before the NewIcons block (its " " separator,
    /// "*** DON'T EDIT…" marker and image lines), so the block stays together at the end.
    public static func appendIndex(_ types: [String]) -> Int {
        guard var start = types.firstIndex(where: { NewIconsDecoder.isImageData($0) || $0 == newIconsMarker }) else {
            return types.count
        }
        if start > 0 && types[start - 1].trimmingCharacters(in: .whitespaces).isEmpty { start -= 1 }
        return start
    }

    public static let newIconsMarker = "*** DON'T EDIT THE FOLLOWING LINES!! ***"

    public static func value(_ types: [String], visible: Int) -> String {
        let v = visibleIndices(types)
        return v.indices.contains(visible) ? types[v[visible]] : ""
    }

    public static func set(_ value: String, visible: Int, in types: inout [String]) {
        let v = visibleIndices(types)
        guard v.indices.contains(visible) else { return }
        types[v[visible]] = value
    }

    /// Inserts after the given visible row (or appends when nil); returns the new row's visible index.
    @discardableResult
    public static func insert(_ value: String, afterVisible visible: Int?, in types: inout [String]) -> Int {
        let v = visibleIndices(types)
        let real = visible.flatMap { v.indices.contains($0) ? v[$0] + 1 : nil } ?? appendIndex(types)
        types.insert(value, at: real)
        return visibleIndices(types).firstIndex(of: real) ?? 0
    }

    public static func remove(visible: Int, in types: inout [String]) {
        let v = visibleIndices(types)
        guard v.indices.contains(visible) else { return }
        types.remove(at: v[visible])
    }

    /// Swaps a visible row with its visible neighbour; returns the new visible index.
    @discardableResult
    public static func move(visible: Int, by delta: Int, in types: inout [String]) -> Int {
        let v = visibleIndices(types)
        let target = visible + delta
        guard v.indices.contains(visible), v.indices.contains(target) else { return visible }
        types.swapAt(v[visible], v[target])
        return target
    }
}
