import Foundation
#if canImport(Compression)
import Compression
#endif

/// Tipo di file riconosciuto dai primi byte (non ci si fida dell'estensione ne' del tipo dichiarato).
public enum FileKind: Equatable, Sendable { case pdf, zip, legacyOffice, image, other }

/// Lettura di schede da Excel (.xlsx), Word (.docx) e CSV, senza librerie esterne (equivalente di OfficeText.kt).
/// Il risultato e' testo con una riga per ogni riga della tabella e le celle separate da TAB:
/// TrainingPlanParser riconosce l'intestazione (Esercizio, Serie, Ripetizioni, Peso...) e legge le colonne.
public enum OfficeText {
    public enum OfficeError: Error { case badArchive, tooLarge }

    /// Dimensione massima di un file XML interno (per non esaurire la memoria con file anomali).
    public static let maxEntryBytes = 20 * 1024 * 1024

    public static func detect(_ data: Data) -> FileKind {
        let b = [UInt8](data.prefix(1024))
        func at(_ offset: Int, _ bytes: [UInt8]) -> Bool {
            b.count >= offset + bytes.count && Array(b[offset..<offset + bytes.count]) == bytes
        }
        func ascii(_ offset: Int, _ s: String) -> Bool { at(offset, Array(s.utf8)) }
        if ascii(0, "%PDF") { return .pdf }
        // Il PDF puo' avere qualche byte prima dell'intestazione: si cerca nei primi 1024.
        if String(decoding: b, as: Unicode.ASCII.self).contains("%PDF-") { return .pdf }
        if at(0, [0x50, 0x4B, 0x03, 0x04]) { return .zip }
        if at(0, [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) { return .legacyOffice }   // .xls e .doc (formato vecchio)
        if at(0, [0xFF, 0xD8, 0xFF]) || at(0, [0x89, 0x50, 0x4E, 0x47]) || ascii(0, "GIF8") || ascii(0, "BM")
            || (ascii(0, "RIFF") && ascii(8, "WEBP")) || at(0, [0x49, 0x49, 0x2A, 0x00]) || at(0, [0x4D, 0x4D, 0x00, 0x2A])
            || (ascii(4, "ftyp") && ["heic", "heix", "hevc", "mif1", "msf1", "avif"].contains(where: { ascii(8, $0) })) {
            return .image
        }
        return .other
    }

    // MARK: Zip

    /// File XML contenuti in uno zip (.xlsx / .docx), come testo. Lettore minimo: directory centrale, metodi "stored" e "deflate".
    public static func unzipXML(_ data: Data) throws -> [String: String] {
        let bytes = [UInt8](data)
        func u16(_ i: Int) -> Int { Int(bytes[i]) | Int(bytes[i + 1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        // Fine della directory centrale: firma 0x06054b50 negli ultimi 64 KB.
        guard bytes.count >= 22 else { throw OfficeError.badArchive }
        var eocd = -1
        var i = bytes.count - 22
        while i >= max(0, bytes.count - 22 - 65_535) {
            if bytes[i] == 0x50 && bytes[i + 1] == 0x4B && bytes[i + 2] == 0x05 && bytes[i + 3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw OfficeError.badArchive }
        let count = u16(eocd + 10)
        var p = u32(eocd + 16)
        var out: [String: String] = [:]
        for _ in 0..<count {
            guard p + 46 <= bytes.count, u32(p) == 0x02014b50 else { throw OfficeError.badArchive }
            let method = u16(p + 10)
            let compressed = u32(p + 20), size = u32(p + 24)
            let nameLen = u16(p + 28), extraLen = u16(p + 30), commentLen = u16(p + 32)
            let local = u32(p + 42)
            guard p + 46 + nameLen <= bytes.count else { throw OfficeError.badArchive }
            let name = String(decoding: bytes[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
            p += 46 + nameLen + extraLen + commentLen
            guard name.hasSuffix(".xml") || name.hasSuffix(".rels") else { continue }
            guard size <= maxEntryBytes else { throw OfficeError.tooLarge }
            guard local + 30 <= bytes.count, u32(local) == 0x04034b50 else { throw OfficeError.badArchive }
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            guard start + compressed <= bytes.count else { throw OfficeError.badArchive }
            let raw = Array(bytes[start..<(start + compressed)])
            let content: [UInt8]
            switch method {
            case 0: content = raw
            case 8: content = try inflate(raw, size: size)
            default: continue
            }
            out[name] = String(decoding: content, as: UTF8.self)
        }
        return out
    }

    /// Deflate "raw" (RFC 1951): e' il formato che Compression chiama COMPRESSION_ZLIB.
    static func inflate(_ input: [UInt8], size: Int) throws -> [UInt8] {
        #if canImport(Compression)
        if size == 0 { return [] }
        var output = [UInt8](repeating: 0, count: size)
        let written = input.withUnsafeBufferPointer { src in
            output.withUnsafeMutableBufferPointer { dst in
                compression_decode_buffer(dst.baseAddress!, size, src.baseAddress!, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw OfficeError.badArchive }
        return output
        #else
        throw OfficeError.badArchive
        #endif
    }

    /// Testo di un documento Office moderno (xlsx o docx); nil se lo zip non e' ne' l'uno ne' l'altro.
    public static func fromOOXML(_ entries: [String: String]) -> String? {
        if let workbook = entries["xl/workbook.xml"] {
            var sheets = sheetPaths(workbook: workbook, rels: entries["xl/_rels/workbook.xml.rels"])
                .compactMap { pair in entries[pair.path].map { (name: pair.name, xml: $0) } }
            if sheets.isEmpty {
                sheets = entries.keys.filter { $0.hasPrefix("xl/worksheets/") && $0.hasSuffix(".xml") }.sorted()
                    .map { key in
                        let file = key.split(separator: "/").last.map(String.init) ?? key
                        return (name: file.split(separator: ".").first.map(String.init) ?? file, xml: entries[key]!)
                    }
            }
            return xlsxText(shared: entries["xl/sharedStrings.xml"], sheets: sheets)
        }
        if let document = entries["word/document.xml"] { return docxText(document) }
        return nil
    }

    // MARK: Excel

    /// Fogli in ordine: (nome, percorso nello zip).
    static func sheetPaths(workbook: String, rels: String?) -> [(name: String, path: String)] {
        var targets: [String: String] = [:]
        if let rels {
            for case .tag(let t) in XMLTokens.parse(rels) where !t.closing && t.name == "Relationship" {
                guard let id = t.attrs["Id"], let target = t.attrs["Target"] else { continue }
                if target.hasPrefix("/") { targets[id] = String(target.dropFirst()) }
                else { targets[id] = "xl/" + (target.hasPrefix("./") ? String(target.dropFirst(2)) : target) }
            }
        }
        var out: [(name: String, path: String)] = []
        var index = 1
        for case .tag(let t) in XMLTokens.parse(workbook) where !t.closing && t.name == "sheet" {
            let name = t.attrs["name"] ?? "Sheet\(index)"
            let path = t.attrs["id"].flatMap { targets[$0] } ?? "xl/worksheets/sheet\(index).xml"
            out.append((name: name, path: path))
            index += 1
        }
        return out
    }

    static func sharedStrings(_ xml: String?) -> [String] {
        guard let xml else { return [] }
        var out: [String] = []
        var current: String?
        var inText = false
        var phonetic = 0
        for token in XMLTokens.parse(xml) {
            switch token {
            case .tag(let t):
                switch t.name {
                case "si":
                    if t.closing { out.append(current ?? ""); current = nil }
                    else if t.selfClosing { out.append("") } else { current = "" }
                case "t": inText = !t.closing && !t.selfClosing
                case "rPh": if t.closing { phonetic -= 1 } else if !t.selfClosing { phonetic += 1 }
                default: break
                }
            case .text(let s):
                if inText && phonetic == 0 { current? += s }
            }
        }
        return out
    }

    /// Righe di un foglio: celle per colonna (le colonne vuote restano stringhe vuote).
    static func sheetRows(_ xml: String, shared: [String]) -> [[String]] {
        var rows: [[String]] = []
        var row: [Int: String]?
        var col = 0, nextCol = 0
        var type = ""
        var value: String?
        var inValue = false, inInline = false
        for token in XMLTokens.parse(xml) {
            switch token {
            case .tag(let t):
                switch t.name {
                case "row":
                    if !t.closing {
                        row = [:]; nextCol = 0
                        if t.selfClosing { rows.append([]); row = nil }
                    } else {
                        if let r = row { let last = r.keys.max() ?? -1; rows.append(last >= 0 ? (0...last).map { r[$0] ?? "" } : []) }
                        row = nil
                    }
                case "c":
                    if !t.closing {
                        col = t.attrs["r"].map(columnIndex) ?? nextCol
                        nextCol = col + 1
                        type = t.attrs["t"] ?? ""
                        value = t.selfClosing ? nil : ""
                    } else {
                        let raw = value ?? ""
                        let text: String
                        switch type {
                        case "s":
                            let idx = Int(raw.trimmingCharacters(in: .whitespaces)) ?? -1
                            text = shared.indices.contains(idx) ? shared[idx] : ""
                        case "inlineStr", "str", "e": text = raw
                        case "b": text = raw.trimmingCharacters(in: .whitespaces) == "1" ? "TRUE" : "FALSE"
                        default: text = formatNumber(raw)
                        }
                        let clean = text.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
                            .trimmingCharacters(in: .whitespaces)
                        if !clean.isEmpty { row?[col] = clean }
                        value = nil
                    }
                case "v": inValue = !t.closing && !t.selfClosing
                case "is": inInline = !t.closing && !t.selfClosing
                case "t": if inInline { inValue = !t.closing && !t.selfClosing }
                default: break
                }
            case .text(let s):
                if inValue { value? += s }
            }
        }
        return rows
    }

    /// "C12" -> 2 (colonne da 0).
    static func columnIndex(_ ref: String) -> Int {
        var n = 0
        for ch in ref.uppercased() {
            guard ch.isLetter, let a = ch.asciiValue else { break }
            n = n * 26 + Int(a) - 64
        }
        return max(n - 1, 0)
    }

    /// Numeri come li mostra Excel: 8 e non 8.0, 62.5 e non 62.500000001.
    static func formatNumber(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let d = Double(trimmed) else { return trimmed }
        let rounded = (d * 100).rounded() / 100
        if rounded == rounded.rounded(.down) && abs(rounded) < 1e15 { return String(Int64(rounded)) }
        return String(rounded)
    }

    static func xlsxText(shared sharedXML: String?, sheets: [(name: String, xml: String)]) -> String {
        let shared = sharedStrings(sharedXML)
        var out = ""
        for sheet in sheets {
            let rows = sheetRows(sheet.xml, shared: shared)
            guard rows.contains(where: { $0.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }) else { continue }
            if sheets.count > 1 { out += sheet.name + "\n" }      // il nome del foglio puo' essere il giorno ("Giorno A")
            let width = rows.map(\.count).max() ?? 0
            for r in rows {
                if r.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { out += "\n"; continue }
                out += (r + Array(repeating: "", count: width - r.count)).joined(separator: "\t") + "\n"
            }
        }
        return out
    }

    // MARK: Word

    /// Paragrafi su righe separate; le tabelle diventano righe con le celle separate da TAB.
    static func docxText(_ xml: String) -> String {
        var out = ""
        var paragraph = ""
        var tableDepth = 0
        var row: [String]?
        var cell: String?
        var inText = false
        var inTabStops = false      // <w:tabs> nelle proprieta' del paragrafo: non sono tabulazioni nel testo
        for token in XMLTokens.parse(xml) {
            switch token {
            case .tag(let t):
                switch t.name {
                case "tbl": if t.closing { tableDepth -= 1 } else if !t.selfClosing { tableDepth += 1 }
                case "tr":
                    guard tableDepth == 1 else { break }
                    if !t.closing { row = [] }
                    else {
                        if let r = row, r.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                            out += r.joined(separator: "\t") + "\n"
                        }
                        row = nil
                    }
                case "tc":
                    guard tableDepth == 1 else { break }
                    if !t.closing { cell = "" }
                    else {
                        let clean = (cell ?? "").components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
                        row?.append(clean)
                        cell = nil
                    }
                case "p":
                    if t.closing || t.selfClosing {
                        let text = paragraph
                        paragraph = ""
                        if cell != nil { if !(cell!.isEmpty) { cell! += " " }; cell! += text }
                        else if tableDepth == 0 { out += text + "\n" }
                    }
                case "t": inText = !t.closing && !t.selfClosing
                case "tabs": inTabStops = !t.closing && !t.selfClosing
                case "tab": if !t.closing && !inTabStops { paragraph += cell != nil ? " " : "\t" }
                case "br", "cr": if !t.closing { paragraph += cell != nil ? " " : "\n" }
                default: break
                }
            case .text(let s):
                if inText { paragraph += s }
            }
        }
        return out
    }

    // MARK: CSV e testo

    /// CSV con separatore ";" "," o TAB (rilevato) e virgolette, convertito in righe con TAB.
    public static func csvToTabs(_ text: String) -> String {
        let sample = text.components(separatedBy: "\n").prefix(10).joined(separator: "\n")
        let candidates: [Character] = [";", "\t", ","]
        let delimiter = candidates.max(by: { a, b in sample.filter { $0 == a }.count < sample.filter { $0 == b }.count }) ?? ";"
        var out = ""
        var cell = ""
        var row: [String] = []
        var quoted = false
        let chars = Array(text.unicodeScalars).map(Character.init)
        func endRow() {
            row.append(cell.trimmingCharacters(in: .whitespaces)); cell = ""
            out += row.joined(separator: "\t") + "\n"; row = []
        }
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if quoted && ch == "\"" && i + 1 < chars.count && chars[i + 1] == "\"" { cell.append("\""); i += 1 }
            else if ch == "\"" { quoted.toggle() }
            else if !quoted && ch == delimiter { row.append(cell.trimmingCharacters(in: .whitespaces)); cell = "" }
            else if !quoted && (ch == "\n" || ch == "\r") {
                if ch == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
                endRow()
            }
            else if ch == "\t" || ch == "\n" { cell.append(" ") }
            else { cell.append(ch) }
            i += 1
        }
        if !cell.isEmpty || !row.isEmpty { endRow() }
        return out
    }

    /// Testo che in realta' e' un file binario (formato non supportato).
    public static func looksBinary(_ text: String) -> Bool {
        let sample = Array(text.unicodeScalars.prefix(4000))
        guard !sample.isEmpty else { return false }
        let control = sample.filter { ($0.value < 32 && $0 != "\n" && $0 != "\r" && $0 != "\t") || $0.value == 0xFFFD }.count
        return control > sample.count / 20
    }
}

/// Lettore XML minimale (sufficiente per i file Office): tag con attributi e testo, entita' decodificate.
enum XMLTokens {
    /// name senza prefisso (w:t -> t); attributi anche loro senza prefisso (r:id -> id).
    struct Tag { var name: String; var closing: Bool; var selfClosing: Bool; var attrs: [String: String] }
    enum Token { case tag(Tag), text(String) }

    static func parse(_ xml: String) -> [Token] {
        let s = Array(xml.unicodeScalars)
        let n = s.count
        var out: [Token] = []
        var i = 0
        func starts(_ prefix: String, at k: Int) -> Bool {
            let p = Array(prefix.unicodeScalars)
            return k + p.count <= n && Array(s[k..<k + p.count]) == p
        }
        func find(_ token: String, from k: Int) -> Int? {
            let p = Array(token.unicodeScalars)
            var j = k
            while j + p.count <= n { if Array(s[j..<j + p.count]) == p { return j }; j += 1 }
            return nil
        }
        func string(_ a: Int, _ b: Int) -> String { var u = String.UnicodeScalarView(); u.append(contentsOf: s[a..<max(a, b)]); return String(u) }
        while i < n {
            if s[i] != "<" {
                var end = i
                while end < n && s[end] != "<" { end += 1 }
                out.append(.text(decode(string(i, end))))
                i = end
                continue
            }
            if starts("<![CDATA[", at: i) {
                let end = find("]]>", from: i) ?? n
                out.append(.text(string(i + 9, end))); i = end + 3
            } else if starts("<!--", at: i) {
                i = (find("-->", from: i) ?? n) + 3
            } else if starts("<?", at: i) || starts("<!", at: i) {
                i = (find(">", from: i) ?? n) + 1
            } else {
                // Fine del tag, saltando i ">" dentro i valori degli attributi.
                var end = i + 1
                var quote: Unicode.Scalar?
                while end < n {
                    let ch = s[end]
                    if let q = quote { if ch == q { quote = nil } }
                    else if ch == "\"" || ch == "'" { quote = ch }
                    else if ch == ">" { break }
                    end += 1
                }
                var body = string(i + 1, min(end, n))
                let closing = body.hasPrefix("/")
                if closing { body.removeFirst() }
                let selfClosing = body.hasSuffix("/")
                if selfClosing { body.removeLast() }
                let nameEnd = body.firstIndex(where: \.isWhitespace) ?? body.endIndex
                out.append(.tag(Tag(name: local(String(body[..<nameEnd])), closing: closing, selfClosing: selfClosing,
                                    attrs: attributes(String(body[nameEnd...])))))
                i = end + 1
            }
        }
        return out
    }

    private static func local(_ name: String) -> String {
        guard let colon = name.firstIndex(of: ":") else { return name }
        return String(name[name.index(after: colon)...])
    }

    private static func attributes(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        let s = Array(text)
        var i = 0
        while i < s.count {
            while i < s.count && s[i].isWhitespace { i += 1 }
            guard let eq = s[i...].firstIndex(of: "=") else { break }
            let name = String(s[i..<eq]).trimmingCharacters(in: .whitespaces)
            var j = eq + 1
            while j < s.count && s[j].isWhitespace { j += 1 }
            guard j < s.count, s[j] == "\"" || s[j] == "'" else { break }
            let q = s[j]
            let close = s[(j + 1)...].firstIndex(of: q) ?? s.count
            out[local(name)] = decode(String(s[(j + 1)..<close]))
            i = close + 1
        }
        return out
    }

    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let s = Array(text)
        var out = ""
        var i = 0
        while i < s.count {
            let ch = s[i]
            guard ch == "&", let semi = s[i...].prefix(12).firstIndex(of: ";") else { out.append(ch); i += 1; continue }
            let entity = String(s[(i + 1)..<semi])
            var decoded: String?
            switch entity {
            case "lt": decoded = "<"
            case "gt": decoded = ">"
            case "amp": decoded = "&"
            case "quot": decoded = "\""
            case "apos": decoded = "'"
            default:
                if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                    decoded = UInt32(entity.dropFirst(2), radix: 16).flatMap { Unicode.Scalar($0) }.map { String(Character($0)) }
                } else if entity.hasPrefix("#") {
                    decoded = UInt32(entity.dropFirst()).flatMap { Unicode.Scalar($0) }.map { String(Character($0)) }
                }
            }
            if let decoded { out += decoded; i = semi + 1 } else { out.append(ch); i += 1 }
        }
        return out
    }
}
