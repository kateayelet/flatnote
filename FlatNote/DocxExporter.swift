import Foundation
import CoreGraphics
import ImageIO
import zlib

/// Builds a .docx (Word) file from a note's markdown, with no third-party
/// dependencies: a .docx is a zip of a few XML parts, and the zip writer
/// below stores entries uncompressed, which Word accepts happily.
///
/// The conversion is deliberately simple, mirroring what the cards and
/// editor understand: headings, bullet/numbered/check lists, quotes,
/// callouts, images that live with the note, and bold/italic/strike/code
/// inline. Anything fancier degrades to plain text rather than failing.
enum DocxExporter {

    /// Converts markdown to a .docx at `dest`. Relative image paths resolve
    /// against `baseURL` (the note's own folder), like every other reader.
    static func export(markdown: String, baseURL: URL, to dest: URL) throws {
        var media: [(name: String, data: Data, ext: String)] = []
        let bodyXML = buildBody(markdown: markdown, baseURL: baseURL, media: &media)

        var entries: [(path: String, data: Data)] = []
        entries.append(("[Content_Types].xml", Data(contentTypesXML(media: media).utf8)))
        entries.append(("_rels/.rels", Data(rootRelsXML.utf8)))
        entries.append(("word/document.xml", Data(documentXML(body: bodyXML).utf8)))
        entries.append(("word/_rels/document.xml.rels", Data(documentRelsXML(media: media).utf8)))
        for item in media {
            entries.append(("word/media/\(item.name)", item.data))
        }
        try ZipWriter.write(entries: entries, to: dest)
    }

    // MARK: - Block conversion

    private static func buildBody(markdown: String, baseURL: URL, media: inout [(name: String, data: Data, ext: String)]) -> String {
        var xml = ""
        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            // A line that is exactly one image reference becomes a picture.
            if let img = matchImage(line) {
                if let drawing = imageXML(path: img.path, baseURL: baseURL, media: &media) {
                    xml += "<w:p>\(drawing)</w:p>"
                    if !img.alt.isEmpty {
                        xml += paragraph(runs: runsXML(for: img.alt, italic: true), spacingAfter: 160)
                    }
                } else if !img.alt.isEmpty {
                    xml += paragraph(runs: runsXML(for: img.alt, italic: true), spacingAfter: 160)
                }
                continue
            }

            if let m = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                let level = line[m].filter { $0 == "#" }.count
                let text = String(line[m.upperBound...])
                // Direct formatting instead of a styles part: fewer moving
                // pieces, and Word renders it the same.
                let sizes = [48, 40, 34, 30, 28, 26]
                let sz = sizes[min(level, sizes.count) - 1]
                xml += paragraph(
                    runs: runsXML(for: text, bold: true, halfPointSize: sz),
                    spacingBefore: 240, spacingAfter: 120
                )
                continue
            }

            if let m = line.range(of: #"^>\s?\[!(\w+)\]\s?"#, options: .regularExpression) {
                let label = line[m].drop { $0 != "!" }.dropFirst().prefix { $0 != "]" }
                let rest = String(line[m.upperBound...])
                let head = runsXML(for: String(label).capitalized + (rest.isEmpty ? "" : ": "), bold: true)
                xml += paragraph(runs: head + runsXML(for: rest), indentLeft: 360, spacingAfter: 120)
                continue
            }

            if let m = line.range(of: #"^>\s?"#, options: .regularExpression) {
                let rest = String(line[m.upperBound...])
                xml += paragraph(runs: runsXML(for: rest, italic: true), indentLeft: 360, spacingAfter: 120)
                continue
            }

            if let m = line.range(of: #"^[-*+]\s+\[([ xX])\]\s+"#, options: .regularExpression) {
                let checked = line[m].contains("x") || line[m].contains("X")
                let rest = String(line[m.upperBound...])
                let box = checked ? "\u{2611} " : "\u{2610} "
                xml += paragraph(runs: runsXML(for: box) + runsXML(for: rest), indentLeft: 360, spacingAfter: 80)
                continue
            }

            if let m = line.range(of: #"^[-*+]\s+"#, options: .regularExpression) {
                let rest = String(line[m.upperBound...])
                xml += paragraph(runs: runsXML(for: "\u{2022} ") + runsXML(for: rest), indentLeft: 360, spacingAfter: 80)
                continue
            }

            if let m = line.range(of: #"^(\d+)\.\s+"#, options: .regularExpression) {
                let prefix = line[m].trimmingCharacters(in: .whitespaces)
                let rest = String(line[m.upperBound...])
                xml += paragraph(runs: runsXML(for: prefix + " ") + runsXML(for: rest), indentLeft: 360, spacingAfter: 80)
                continue
            }

            xml += paragraph(runs: runsXML(for: line), spacingAfter: 160)
        }
        if xml.isEmpty {
            xml = paragraph(runs: runsXML(for: ""), spacingAfter: 0)
        }
        return xml
    }

    private static func matchImage(_ line: String) -> (alt: String, path: String)? {
        guard let regex = try? NSRegularExpression(pattern: #"^!\[([^\]]*)\]\(([^)\s]+)\)$"#),
              let m = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let altRange = Range(m.range(at: 1), in: line),
              let pathRange = Range(m.range(at: 2), in: line) else { return nil }
        return (String(line[altRange]), String(line[pathRange]))
    }

    // MARK: - Inline runs

    /// Splits a line into styled runs: **bold**, *italic*, ~~strike~~,
    /// `code`, and [text](url) as "text (url)". Unclosed markers stay
    /// literal text.
    private static func runsXML(for text: String, bold: Bool = false, italic: Bool = false, halfPointSize: Int? = nil) -> String {
        var xml = ""
        var plain = ""
        var rest = Substring(text)

        func flush() {
            guard !plain.isEmpty else { return }
            xml += run(plain, bold: bold, italic: italic, halfPointSize: halfPointSize)
            plain = ""
        }
        func styled(_ inner: String, innerBold: Bool = false, innerItalic: Bool = false, strike: Bool = false, code: Bool = false) {
            flush()
            xml += run(inner, bold: bold || innerBold, italic: italic || innerItalic,
                       strike: strike, code: code, halfPointSize: halfPointSize)
        }
        func take(marker: String, closer: String) -> String? {
            guard rest.hasPrefix(marker),
                  let end = rest.dropFirst(marker.count).range(of: closer) else { return nil }
            let inner = String(rest[rest.index(rest.startIndex, offsetBy: marker.count)..<end.lowerBound])
            rest = rest[end.upperBound...]
            return inner
        }

        while let first = rest.first {
            if let inner = take(marker: "***", closer: "***") { styled(inner, innerBold: true, innerItalic: true); continue }
            if let inner = take(marker: "**", closer: "**") { styled(inner, innerBold: true); continue }
            if let inner = take(marker: "*", closer: "*") { styled(inner, innerItalic: true); continue }
            if let inner = take(marker: "~~", closer: "~~") { styled(inner, strike: true); continue }
            if let inner = take(marker: "`", closer: "`") { styled(inner, code: true); continue }
            if first == "[",
               let regex = try? NSRegularExpression(pattern: #"^\[([^\]]+)\]\(([^)\s]+)\)"#),
               let m = regex.firstMatch(in: String(rest), range: NSRange(location: 0, length: rest.utf16.count)),
               let full = Range(m.range, in: String(rest)) {
                let s = String(rest)
                let label = Range(m.range(at: 1), in: s).map { String(s[$0]) } ?? ""
                let url = Range(m.range(at: 2), in: s).map { String(s[$0]) } ?? ""
                plain += "\(label) (\(url))"
                rest = rest.dropFirst(s.distance(from: full.lowerBound, to: full.upperBound))
                continue
            }
            plain.append(first)
            rest = rest.dropFirst()
        }
        flush()
        return xml
    }

    private static func run(_ text: String, bold: Bool = false, italic: Bool = false, strike: Bool = false, code: Bool = false, halfPointSize: Int? = nil) -> String {
        var props = ""
        if bold { props += "<w:b/>" }
        if italic { props += "<w:i/>" }
        if strike { props += "<w:strike/>" }
        if code { props += "<w:rFonts w:ascii=\"Courier New\" w:hAnsi=\"Courier New\"/>" }
        if let sz = halfPointSize { props += "<w:sz w:val=\"\(sz)\"/><w:szCs w:val=\"\(sz)\"/>" }
        let rPr = props.isEmpty ? "" : "<w:rPr>\(props)</w:rPr>"
        return "<w:r>\(rPr)<w:t xml:space=\"preserve\">\(escape(text))</w:t></w:r>"
    }

    private static func paragraph(runs: String, indentLeft: Int = 0, spacingBefore: Int = 0, spacingAfter: Int = 160) -> String {
        var pPr = "<w:spacing w:before=\"\(spacingBefore)\" w:after=\"\(spacingAfter)\"/>"
        if indentLeft > 0 { pPr += "<w:ind w:left=\"\(indentLeft)\"/>" }
        return "<w:p><w:pPr>\(pPr)</w:pPr>\(runs)</w:p>"
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - Images

    private static func imageXML(path: String, baseURL: URL, media: inout [(name: String, data: Data, ext: String)]) -> String? {
        guard !path.contains("://") else { return nil }
        let url = path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : baseURL.appendingPathComponent(path)
        guard let data = try? Data(contentsOf: url) else { return nil }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pxW = props[kCGImagePropertyPixelWidth] as? Double,
              let pxH = props[kCGImagePropertyPixelHeight] as? Double,
              pxW > 0, pxH > 0 else { return nil }

        let ext: String
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": ext = "jpeg"
        case "gif": ext = "gif"
        default: ext = "png"
        }
        let index = media.count + 1
        let name = "image\(index).\(ext)"
        media.append((name, data, ext))

        // 9525 EMU per pixel at 96dpi; cap at 6 inches wide to fit the page.
        var cx = Int(pxW * 9525)
        var cy = Int(pxH * 9525)
        let maxWidth = 6 * 914_400
        if cx > maxWidth {
            cy = cy * maxWidth / cx
            cx = maxWidth
        }
        let rid = "rIdImg\(index)"
        return """
        <w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">\
        <wp:extent cx="\(cx)" cy="\(cy)"/>\
        <wp:docPr id="\(index)" name="\(name)"/>\
        <a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">\
        <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">\
        <pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">\
        <pic:nvPicPr><pic:cNvPr id="\(index)" name="\(name)"/><pic:cNvPicPr/></pic:nvPicPr>\
        <pic:blipFill><a:blip r:embed="\(rid)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>\
        <pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm>\
        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>\
        </pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>
        """
    }

    // MARK: - Fixed parts

    private static func contentTypesXML(media: [(name: String, data: Data, ext: String)]) -> String {
        var defaults = """
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
        <Default Extension="xml" ContentType="application/xml"/>
        """
        let exts = Set(media.map(\.ext))
        for ext in exts.sorted() {
            defaults += "<Default Extension=\"\(ext)\" ContentType=\"image/\(ext)\"/>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\(defaults)\
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\
        </Types>
        """
    }

    private static let rootRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>\
    </Relationships>
    """

    private static func documentRelsXML(media: [(name: String, data: Data, ext: String)]) -> String {
        var rels = ""
        for (i, item) in media.enumerated() {
            rels += "<Relationship Id=\"rIdImg\(i + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/\(item.name)\"/>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(rels)</Relationships>
        """
    }

    private static func documentXML(body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
        xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing">\
        <w:body>\(body)\
        <w:sectPr><w:pgSz w:w="12240" w:h="15840"/>\
        <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>\
        </w:body></w:document>
        """
    }
}

/// The smallest useful zip writer: stored (uncompressed) entries with CRC32,
/// a central directory, and an end record. Word, Pages, and Finder all read
/// it; nothing here needs a compression library.
enum ZipWriter {
    static func write(entries: [(path: String, data: Data)], to dest: URL) throws {
        var out = Data()
        var central = Data()
        let (dosTime, dosDate) = dosDateTime(Date())

        for entry in entries {
            let nameBytes = Data(entry.path.utf8)
            let crc = entry.data.withUnsafeBytes { buf -> UInt32 in
                UInt32(crc32(0, buf.bindMemory(to: UInt8.self).baseAddress, uInt(entry.data.count)))
            }
            let offset = UInt32(out.count)

            var local = Data()
            local.append(le32(0x04034b50))
            local.append(le16(20))            // version needed
            local.append(le16(0))             // flags
            local.append(le16(0))             // method: stored
            local.append(le16(dosTime))
            local.append(le16(dosDate))
            local.append(le32(crc))
            local.append(le32(UInt32(entry.data.count)))
            local.append(le32(UInt32(entry.data.count)))
            local.append(le16(UInt16(nameBytes.count)))
            local.append(le16(0))             // extra length
            local.append(nameBytes)
            out.append(local)
            out.append(entry.data)

            var dir = Data()
            dir.append(le32(0x02014b50))
            dir.append(le16(20))              // version made by
            dir.append(le16(20))              // version needed
            dir.append(le16(0))
            dir.append(le16(0))
            dir.append(le16(dosTime))
            dir.append(le16(dosDate))
            dir.append(le32(crc))
            dir.append(le32(UInt32(entry.data.count)))
            dir.append(le32(UInt32(entry.data.count)))
            dir.append(le16(UInt16(nameBytes.count)))
            dir.append(le16(0))               // extra
            dir.append(le16(0))               // comment
            dir.append(le16(0))               // disk
            dir.append(le16(0))               // internal attrs
            dir.append(le32(0))               // external attrs
            dir.append(le32(offset))
            dir.append(nameBytes)
            central.append(dir)
        }

        let dirOffset = UInt32(out.count)
        out.append(central)
        var eocd = Data()
        eocd.append(le32(0x06054b50))
        eocd.append(le16(0))
        eocd.append(le16(0))
        eocd.append(le16(UInt16(entries.count)))
        eocd.append(le16(UInt16(entries.count)))
        eocd.append(le32(UInt32(central.count)))
        eocd.append(le32(dirOffset))
        eocd.append(le16(0))
        out.append(eocd)

        try out.write(to: dest, options: .atomic)
    }

    private static func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private static func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

    private static func dosDateTime(_ date: Date) -> (UInt16, UInt16) {
        let c = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max(1980, c.year ?? 1980)
        let time = UInt16((c.hour ?? 0) << 11 | (c.minute ?? 0) << 5 | (c.second ?? 0) / 2)
        let day = UInt16((year - 1980) << 9 | (c.month ?? 1) << 5 | (c.day ?? 1))
        return (time, day)
    }
}
