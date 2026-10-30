import Foundation
import SQLite3
import ZIPFoundation

struct Card: Codable, Hashable { var front: String; var back: String; var hint: String = "" }

struct Deck: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var cards: [Card]

    /// First letter of the name, for the deck's tile ("1000 Essential…" → "E").
    var glyph: String { name.first(where: \.isLetter).map { String($0).uppercased() } ?? "#" }
}

enum ImportError: Error { case anki21b, empty, unreadable }

/// Imported decks, one JSON file each in Application Support.
@Observable final class DeckStore {
    private(set) var decks: [Deck] = []
    private let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Lexikos/decks", isDirectory: true)

    init() {
        Migration.run()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        decks = files.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(Deck.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func importFile(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let cards = url.pathExtension.lowercased() == "apkg" ? try Importer.anki(url) : try Importer.text(url)
        guard !cards.isEmpty else { throw ImportError.empty }
        let deck = Deck(name: url.deletingPathExtension().lastPathComponent, cards: cards)
        try JSONEncoder().encode(deck).write(to: file(deck))
        decks.append(deck)
    }

    /// Re-read a deck's source file, keeping its id so study progress stays attached.
    func reimport(_ id: UUID, from url: URL) throws {
        guard let i = decks.firstIndex(where: { $0.id == id }) else { throw ImportError.unreadable }
        let cards = url.pathExtension.lowercased() == "apkg" ? try Importer.anki(url) : try Importer.text(url)
        guard !cards.isEmpty else { throw ImportError.empty }
        decks[i].cards = cards
        try JSONEncoder().encode(decks[i]).write(to: file(decks[i]))
    }

    func delete(_ deck: Deck) {
        try? FileManager.default.removeItem(at: file(deck))
        decks.removeAll { $0.id == deck.id }
    }

    private func file(_ deck: Deck) -> URL { dir.appendingPathComponent("\(deck.id.uuidString).json") }
}

enum Importer {
    /// Anki package: a zip holding a SQLite collection; note fields are separated by 0x1F.
    static func anki(_ url: URL) throws -> [Card] {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let archive = try Archive(url: url, accessMode: .read)
        for name in ["collection.anki21", "collection.anki2", "collection.anki21b"] {
            if let entry = archive[name] { _ = try archive.extract(entry, to: tmp.appendingPathComponent(name)) }
        }

        let fm = FileManager.default
        let legacy = ["collection.anki21", "collection.anki2"].map { tmp.appendingPathComponent($0) }
            .first { fm.fileExists(atPath: $0.path) }
        guard let db = legacy else {
            throw fm.fileExists(atPath: tmp.appendingPathComponent("collection.anki21b").path) ? ImportError.anki21b : ImportError.unreadable
        }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(db.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw ImportError.unreadable }
        defer { sqlite3_close(handle) }
        if let typed = AnkiImport.cards(db: handle), typed.count > 1 { return typed }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT flds FROM notes ORDER BY id", -1, &stmt, nil) == SQLITE_OK else { throw ImportError.unreadable }
        defer { sqlite3_finalize(stmt) }
        var rows: [[String]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let c = sqlite3_column_text(stmt, 0) else { continue }
            rows.append(String(cString: c).components(separatedBy: "\u{1F}"))
        }
        // A stub collection that only says "please update Anki" means the real data is in anki21b.
        if rows.count <= 1, fm.fileExists(atPath: tmp.appendingPathComponent("collection.anki21b").path) { throw ImportError.anki21b }
        return cards(rows)
    }

    /// Anki text export, TSV or CSV: front, back, optional hint per line; "#" lines are headers.
    static func text(_ url: URL) throws -> [Card] {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { throw ImportError.unreadable }
        let lines = raw.components(separatedBy: .newlines).filter { !$0.isEmpty && !$0.hasPrefix("#") }
        let sep: Character = lines.first?.contains("\t") == true ? "\t" : lines.first?.contains(";") == true ? ";" : ","
        return cards(lines.map { splitCSV($0, sep) })
    }

    private static func cards(_ rows: [[String]]) -> [Card] {
        rows.compactMap { f in
            let f = f.map(clean)
            guard f.count >= 2, !f[0].isEmpty, !f[1].isEmpty else { return nil }
            return Card(front: f[0], back: f[1], hint: f.count > 2 ? f[2] : "")
        }
    }

    static func clean(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "<br\\s*/?>|<div[^>]*>|</div>|</p>", with: "\n", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: "<[^>]+>|\\[sound:[^\\]]*\\]", with: "", options: .regularExpression)
        for (k, v) in ["&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&amp;": "&"] {
            t = t.replacingOccurrences(of: k, with: v)
        }
        return t.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static func splitCSV(_ line: String, _ sep: Character) -> [String] {
        var out: [String] = [], cur = "", quoted = false
        var it = Array(line).makeIterator(), pending: Character? = nil
        while let ch = pending ?? it.next() {
            pending = nil
            if ch == "\"" {
                if quoted, let n = it.next() { if n == "\"" { cur.append("\"") } else { quoted = false; pending = n } }
                else { quoted.toggle() }
            } else if ch == sep && !quoted { out.append(cur); cur = "" }
            else { cur.append(ch) }
        }
        out.append(cur)
        return out
    }
}
