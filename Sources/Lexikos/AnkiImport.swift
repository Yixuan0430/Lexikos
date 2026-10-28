import Foundation
import SQLite3

/// Maps Anki notes to cards by what each field *means* (its name and the card template),
/// not by position: decks put ranks, audio, part of speech and examples in any order.
enum AnkiImport {
    struct NoteType { var fields: [String]; var qfmt: String; var afmt: String }

    /// Role of each field index for one note type.
    struct FieldMap {
        var front: [Int] = []
        var answer: [Int] = []
        var tag: Int?
        var hint: Int?
        var examples: [(fr: Int, en: Int?)] = []
        var extras: [Int] = []
    }

    static func cards(db: OpaquePointer?) -> [Card]? {
        let types = noteTypes(db)
        guard !types.isEmpty else { return nil }
        var maps: [Int64: FieldMap] = [:]
        var out: [Card] = []
        for (mid, flds) in rows(db, "SELECT mid, flds FROM notes ORDER BY id") {
            let mid = Int64(mid) ?? 0
            let values = flds.components(separatedBy: "\u{1F}").map(Importer.clean)
            guard let type = types[mid] else { continue }
            let map = maps[mid] ?? fieldMap(type)
            maps[mid] = map
            if let card = card(values, type, map) { out.append(card) }
        }
        return out
    }

    // MARK: Building a card

    private static func usable(_ v: String) -> Bool { !v.isEmpty && v.range(of: #"^[\d\s.,#-]+$"#, options: .regularExpression) == nil }

    private static func card(_ v: [String], _ t: NoteType, _ m: FieldMap) -> Card? {
        func val(_ i: Int) -> String? { i < v.count && usable(v[i]) ? v[i] : nil }
        var front = m.front.compactMap(val).joined(separator: " ")
        if front.isEmpty { front = v.first(where: usable) ?? "" }
        guard !front.isEmpty else { return nil }
        if let tag = m.tag.flatMap(val) { front += " (\(tag))" }

        var lines: [String] = []
        let answer = m.answer.compactMap(val)
        lines.append(answer.first ?? "")
        lines += answer.dropFirst()
        let examples = m.examples.compactMap { ex -> String? in
            guard let fr = val(ex.fr) else { return nil }
            return ex.en.flatMap(val).map { "\(fr) (\($0))" } ?? fr
        }
        if !examples.isEmpty { lines.append("Example:"); lines += examples }
        for i in m.extras { if let x = val(i) { lines.append("\(t.fields[i]):"); lines.append(x) } }
        if lines[0].isEmpty { lines.removeFirst() } // no meaning field: first note becomes the answer
        guard !lines.isEmpty else { return nil }
        return Card(front: front, back: lines.joined(separator: "\n"), hint: m.hint.flatMap(val) ?? "")
    }

    // MARK: Field roles

    private static func has(_ name: String, _ words: [String]) -> Bool { words.contains { name.contains($0) } }
    private static let skipWords = ["audio", "sound", "image", "picture", "img", "photo", "rank", "freq", "index", "s.l", "sl no", "id"]
    private static let tagWords = ["part of speech", "pos", "gender", "word type", "wordtype", "class", "genre", "nature"]
    private static let hintWords = ["ipa", "phonetic", "pronunciation", "prononciation", "transcription"]
    private static let sentenceWords = ["sentence", "example", "exemple", "phrase", "usage example", "context"]
    private static let meaningWords = ["meaning", "definition", "english", "translation", "traduction", "sens", "signification",
                                       "back", "answer", "verso", "释义", "中文", "翻译", "意思"]

    static func fieldMap(_ t: NoteType) -> FieldMap {
        let names = t.fields.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        func refs(_ tmpl: String) -> [Int] {
            tmpl.matches(of: #/\{\{([^}]+)\}\}/#).compactMap { m in
                let raw = String(m.1).split(separator: ":").last.map(String.init) ?? ""
                let name = raw.trimmingCharacters(in: CharacterSet(charactersIn: "#/^ ")).lowercased()
                return names.firstIndex(of: name)
            }
        }
        let skip = Set(names.indices.filter { names[$0] == "no" || names[$0] == "#" || has(names[$0], skipWords) && !has(names[$0], sentenceWords) })
        var m = FieldMap()
        let q = refs(t.qfmt).filter { !skip.contains($0) }
        m.front = q.isEmpty ? [0] : Array(NSOrderedSet(array: q)) as! [Int]

        var rest = refs(t.afmt).filter { !m.front.contains($0) && !skip.contains($0) }
        if rest.isEmpty { rest = names.indices.filter { !m.front.contains($0) && !skip.contains($0) } }
        rest = Array(NSOrderedSet(array: rest)) as! [Int]
        rest.sort() // field order reflects the author's grouping (sentence then its translation)

        var used = Set<Int>()
        for i in rest where has(names[i], tagWords) && m.tag == nil { m.tag = i; used.insert(i) }
        for i in rest where has(names[i], hintWords) && m.hint == nil { m.hint = i; used.insert(i) }
        // Example sentence followed by its translation.
        for i in rest where !used.contains(i) && has(names[i], sentenceWords) {
            used.insert(i)
            let next = rest.first { $0 > i && !used.contains($0) && has(names[$0], ["translation", "english", "traduction", "meaning"]) }
            if let n = next, !has(names[n], sentenceWords) || has(names[n], ["translation", "english"]) { used.insert(n); m.examples.append((i, n)) }
            else { m.examples.append((i, nil)) }
        }
        let meanings = rest.filter { !used.contains($0) && has(names[$0], meaningWords) }
        m.answer = meanings.isEmpty ? Array(rest.filter { !used.contains($0) }.prefix(1)) : meanings
        used.formUnion(m.answer)
        m.extras = rest.filter { !used.contains($0) }
        return m
    }

    // MARK: Reading note types (legacy JSON in col.models, or the newer notetypes tables)

    static func noteTypes(_ db: OpaquePointer?) -> [Int64: NoteType] {
        var out: [Int64: NoteType] = [:]
        if let json = rows(db, "SELECT models FROM col").first?.0, let data = json.data(using: .utf8),
           let models = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
            for (id, m) in models {
                let flds = (m["flds"] as? [[String: Any]] ?? []).sorted { ($0["ord"] as? Int ?? 0) < ($1["ord"] as? Int ?? 0) }
                let tmpl = (m["tmpls"] as? [[String: Any]])?.first
                out[Int64(id) ?? 0] = NoteType(fields: flds.compactMap { $0["name"] as? String },
                                              qfmt: tmpl?["qfmt"] as? String ?? "", afmt: tmpl?["afmt"] as? String ?? "")
            }
        }
        if out.isEmpty {
            for (ntid, _) in rows(db, "SELECT id, name FROM notetypes") {
                let fields = rows(db, "SELECT name, ord FROM fields WHERE ntid = \(ntid) ORDER BY ord").map(\.0)
                let (q, a) = templateFormats(db, ntid)
                out[Int64(ntid) ?? 0] = NoteType(fields: fields, qfmt: q, afmt: a)
            }
        }
        return out
    }

    /// Template config is a protobuf: field 1 = question format, field 2 = answer format.
    private static func templateFormats(_ db: OpaquePointer?, _ ntid: String) -> (String, String) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT config FROM templates WHERE ntid = \(ntid) ORDER BY ord LIMIT 1", -1, &stmt, nil) == SQLITE_OK else { return ("", "") }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, let p = sqlite3_column_blob(stmt, 0) else { return ("", "") }
        let bytes = Array(UnsafeBufferPointer(start: p.assumingMemoryBound(to: UInt8.self), count: Int(sqlite3_column_bytes(stmt, 0))))
        var i = 0, strings: [Int: String] = [:]
        func varint() -> Int { var r = 0, s = 0; while i < bytes.count { let b = bytes[i]; i += 1; r |= Int(b & 0x7F) << s; if b < 0x80 { break }; s += 7 }; return r }
        while i < bytes.count {
            let key = varint(), field = key >> 3
            switch key & 7 {
            case 0: _ = varint()
            case 2: let n = varint(); if i + n <= bytes.count { strings[field] = String(decoding: bytes[i..<i + n], as: UTF8.self) }; i += n
            case 1: i += 8
            case 5: i += 4
            default: i = bytes.count
            }
        }
        return (strings[1] ?? "", strings[2] ?? "")
    }

    private static func rows(_ db: OpaquePointer?, _ sql: String) -> [(String, String)] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [(String, String)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let a = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let b = sqlite3_column_count(stmt) > 1 ? sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "" : ""
            out.append((a, b))
        }
        return out
    }
}
