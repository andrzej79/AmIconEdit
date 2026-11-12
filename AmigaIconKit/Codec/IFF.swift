import Foundation

/// Minimal IFF (EA-85) FORM reader/writer.
enum IFF {
    struct Form {
        var type: String
        var chunks: [IFFChunk]
        /// Total bytes consumed from the input, including the FORM header and pad byte.
        var byteCount: Int
    }

    static func fourCC(_ bytes: [UInt8]) -> String {
        String(bytes: bytes, encoding: .isoLatin1) ?? "????"
    }

    static func fourCCBytes(_ id: String) -> [UInt8] {
        let b = AmigaText.encode(id)
        return Array((b + [0x20, 0x20, 0x20, 0x20]).prefix(4))
    }

    /// Reads a FORM starting at the reader's current offset.
    static func readForm(_ reader: inout BigEndianReader) throws -> Form {
        let start = reader.offset
        let id = fourCC(try reader.bytes(4, "FORM id"))
        guard id == "FORM" else { throw AmigaIconError.invalid("expected IFF FORM") }
        let length = Int(try reader.u32("FORM length"))
        guard length >= 4, length <= reader.remaining else { throw AmigaIconError.truncated("IFF FORM") }
        let end = reader.offset + length
        let type = fourCC(try reader.bytes(4, "FORM type"))
        var chunks: [IFFChunk] = []
        while reader.offset + 8 <= end {
            let cid = fourCC(try reader.bytes(4, "chunk id"))
            let clen = Int(try reader.u32("chunk length"))
            guard reader.offset + clen <= end else { throw AmigaIconError.truncated("IFF chunk \(cid)") }
            let data = try reader.bytes(clen, "chunk \(cid)")
            chunks.append(IFFChunk(id: cid, data: data))
            if clen & 1 == 1, reader.offset < end { try reader.skip(1) }
        }
        // Skip to the end of the FORM plus its pad byte, if any.
        let target = min(reader.bytes.count, end + (length & 1))
        if reader.offset < target { try reader.skip(target - reader.offset) }
        return Form(type: type, chunks: chunks, byteCount: reader.offset - start)
    }

    static func writeForm(type: String, chunks: [IFFChunk]) -> [UInt8] {
        var body = BigEndianWriter()
        body.append(fourCCBytes(type))
        for chunk in chunks {
            body.append(fourCCBytes(chunk.id))
            body.u32(UInt32(chunk.data.count))
            body.append(chunk.data)
            if chunk.data.count & 1 == 1 { body.u8(0) }
        }
        var out = BigEndianWriter(capacity: body.bytes.count + 8)
        out.append(fourCCBytes("FORM"))
        out.u32(UInt32(body.bytes.count))
        out.append(body.bytes)
        return out.bytes
    }
}
