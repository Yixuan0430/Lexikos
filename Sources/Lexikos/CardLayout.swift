import Foundation
import NaturalLanguage

/// Splits a raw card into what the learner needs first (answer) and categorised notes.
struct CardParts {
    enum Category: String, CaseIterable { case examples, usage, expressions, related, grammar, other }
    /// What a header announces: the meaning (answer) block, or a notes category.
    enum Kind: Equatable { case meaning, notes(Category) }

    /// A French phrase with its translation, or a plain explanatory note.
    struct Item: Hashable { var fr: String?; var gloss: String?; var text: String }

    struct Section: Identifiable {
        var category: Category
        var title: String // only used for .other
        var items: [Item]
        var id: String { category == .other ? "other-\(title)" : category.rawValue }
    }

    var front: String
    var tag: String?
    var answer: String
    var answerNote: String?
    var hint: String
    var sections: [Section]

    init(_ card: Card) {
        // Each front line may carry its own "(feminine noun)" gloss.
        let fronts = card.front.split(separator: "\n").map { CardParts.splitGloss(String($0)) }
        front = fronts.map(\.0).joined(separator: "\n")
        let tags = fronts.compactMap(\.1)
        tag = tags.isEmpty ? nil : tags.joined(separator: " / ")
        hint = card.hint

        // Community decks often glue items together ("…later!)À tout…", "expensiveJe plie", "StripedExample:").
        let text = card.back
            .replacingOccurrences(of: "([.?!)…])(?=[A-ZÀ-ÖØ-Þ«])", with: "$1\n", options: .regularExpression)
            .replacingOccurrences(of: "([.?!][”\"»])(?=\\s*[A-ZÀ-ÖØ-Þ])", with: "$1\n", options: .regularExpression)
            .replacingOccurrences(of: "(?<=[^\\d\\s])(?=\\d+\\.\\s)", with: "\n", options: .regularExpression) // "dressed.2. Je…"
            .replacingOccurrences(of: "(?<=[a-zà-ÿ])(?=[A-ZÀ-ÖØ-Þ][a-zà-ÿ])", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "(?<=[^\\s(])(?=(\(CardParts.headerPattern))\\s*:)", with: "\n",
                                  options: [.regularExpression, .caseInsensitive])

        // Raw blocks: (header title or nil, lines)
        var blocks: [(String?, [String])] = []
        for line in text.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) })
        where line.contains(where: { $0.isLetter || $0.isNumber }) {
            if line.hasSuffix(":"), line.count <= 40 {
                blocks.append((line.dropLast().trimmingCharacters(in: .whitespaces), []))
            } else if let m = line.firstMatch(of: #/^([^:]{2,30}?)\s*:\s+(.+)$/#), CardParts.category(m.1) != nil {
                blocks.append((String(m.1), [String(m.2)])) // inline header: "Meaning: to put"
            } else {
                if blocks.isEmpty { blocks.append((nil, [])) }
                blocks[blocks.count - 1].1.append(line)
            }
        }

        // The answer is the first line of the Meaning block, or of the untitled opening block.
        answer = ""
        func kind(_ t: String?) -> Kind? { t.map { CardParts.category($0) } ?? .meaning }
        if let i = blocks.firstIndex(where: { kind($0.0) == .meaning })
            ?? blocks.firstIndex(where: { !$0.1.isEmpty }), !blocks[i].1.isEmpty {
            answer = blocks[i].1.removeFirst()
        }
        // Move a long trailing explanation under the answer; keep short ones like "(feminine)".
        if case let (head, note?) = CardParts.splitGloss(answer), note.count > 20 { (answer, answerNote) = (head, note) }

        var merged: [String: Section] = [:]
        func add(_ cat: Category, _ title: String, _ item: Item) {
            let key = cat == .other ? "other-\(title)" : cat.rawValue
            merged[key, default: Section(category: cat, title: title, items: [])].items.append(item)
        }
        for (title, lines) in blocks {
            for item in CardParts.items(lines) {
                switch kind(title) {
                case .notes(let cat): add(cat, "", item)
                case .meaning: add(item.fr != nil ? .examples : .usage, "", item) // untitled / Meaning: by content
                case .none: add(.other, title ?? "", item)
                }
            }
        }
        sections = merged.values.sorted {
            (Category.allCases.firstIndex(of: $0.category)!, $0.title) < (Category.allCases.firstIndex(of: $1.category)!, $1.title)
        }
    }

    // MARK: Header vocabulary

    private static let headers: [String: Kind] = [
        "meaning": .meaning, "translation": .meaning, "sens": .meaning, "signification": .meaning, "traduction": .meaning,
        "simple sentences": .notes(.examples), "example sentences": .notes(.examples), "example": .notes(.examples), "examples": .notes(.examples),
        "exemple": .notes(.examples), "exemples": .notes(.examples), "sentence": .notes(.examples), "sentences": .notes(.examples),
        "learning notes": .notes(.usage), "note and usage": .notes(.usage), "note et utilisation": .notes(.usage), "note": .notes(.usage),
        "notes": .notes(.usage), "usage": .notes(.usage),
        "common expressions": .notes(.expressions), "expressions": .notes(.expressions),
        "related vocabulary": .notes(.related), "vocabulary": .notes(.related), "synonyms": .notes(.related),
        "gender": .notes(.grammar), "plural": .notes(.grammar), "plural forms": .notes(.grammar), "masculine": .notes(.grammar),
        "feminine": .notes(.grammar), "feminine form": .notes(.grammar), "conjugation": .notes(.grammar), "grammar": .notes(.grammar),
    ]
    private static let headerPattern = headers.keys.sorted { $0.count > $1.count }
        .map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")

    /// nil for an unknown header.
    static func category<S: StringProtocol>(_ title: S) -> Kind? {
        headers[title.trimmingCharacters(in: .whitespaces).lowercased()]
    }

    // MARK: French / translation pairing

    static func lang(_ s: String) -> NLLanguage? {
        let r = NLLanguageRecognizer()
        r.languageConstraints = [.french, .english]
        r.processString(s)
        return r.dominantLanguage
    }

    /// English notes often quote French words; only call a whole line French when the model is sure.
    static func frenchConfidence(_ s: String) -> Double {
        let r = NLLanguageRecognizer()
        r.languageConstraints = [.french, .english]
        r.processString(s)
        return r.languageHypotheses(withMaximum: 2)[.french] ?? 0
    }

    static func items(_ lines: [String]) -> [Item] {
        // Rejoin lines where a parenthetical translation/note was split across a newline.
        var merged: [String] = []
        for line in lines {
            if let last = merged.last,
               last.filter({ $0 == "(" }).count > last.filter({ $0 == ")" }).count,
               line.filter({ $0 == ")" }).count > line.filter({ $0 == "(" }).count {
                merged[merged.count - 1] = "\(last) \(line)"
            } else {
                merged.append(line)
            }
        }
        var out: [Item] = [], i = 0
        while i < merged.count {
            var item = pair(merged[i])
            // French line followed by its English translation on the next line.
            if item.fr != nil, item.gloss == nil, i + 1 < merged.count,
               pair(merged[i + 1]).fr == nil, lang(merged[i + 1]) == .english {
                item.gloss = merged[i + 1]; i += 1
            }
            out.append(item); i += 1
        }
        return out
    }

    static func pair(_ line: String) -> Item {
        let line = line.replacingOccurrences(of: "^\\d+\\.\\s+", with: "", options: .regularExpression)
        // "Ce n'est pas possible ! – It's not possible!"
        for sep in [" – ", " — ", " - "] {
            if let r = line.range(of: sep) {
                let l = String(line[..<r.lowerBound]), rr = String(line[r.upperBound...])
                if l.filter({ $0 == "(" }).count != l.filter({ $0 == ")" }).count { continue } // dash inside "( … )"
                if lang(l) == .french, lang(rr) == .english { return Item(fr: l, gloss: rr, text: line) }
            }
        }
        // "Je mets mon chapeau. (I put on my hat.)"
        let (head, gloss) = splitGloss(line)
        if let gloss, lang(head) != .english { return Item(fr: head, gloss: gloss, text: line) }
        // "Je lave les vêtements.  I wash the clothes."
        let tok = NLTokenizer(unit: .sentence)
        tok.string = line
        let sentences = tok.tokens(for: line.startIndex..<line.endIndex).map { String(line[$0]).trimmingCharacters(in: .whitespaces) }
        if sentences.count >= 2, let cut = sentences.firstIndex(where: { lang($0) == .english }), cut > 0,
           sentences[..<cut].allSatisfy({ lang($0) == .french }) {
            return Item(fr: sentences[..<cut].joined(separator: " "), gloss: sentences[cut...].joined(separator: " "), text: line)
        }
        return frenchConfidence(line) > 0.8 ? Item(fr: line, gloss: nil, text: line) : Item(fr: nil, gloss: nil, text: line)
    }

    /// "date de naissance (feminine noun)" → ("date de naissance", "feminine noun"); handles nested parentheses.
    static func splitGloss(_ s: String) -> (String, String?) {
        var t = s.trimmingCharacters(in: .whitespaces)
        if let last = t.last, ".!?".contains(last), t.dropLast().hasSuffix(")") { t.removeLast() }
        guard t.hasSuffix(")") else { return (s, nil) }
        var depth = 0, open: String.Index?
        for i in t.indices.reversed() {
            if t[i] == ")" { depth += 1 } else if t[i] == "(" { depth -= 1; if depth == 0 { open = i; break } }
        }
        guard let open else { return (s, nil) }
        let head = t[..<open].trimmingCharacters(in: .whitespaces)
        let gloss = t[t.index(after: open)..<t.index(before: t.endIndex)].trimmingCharacters(in: .whitespaces)
        return head.isEmpty || gloss.isEmpty ? (s, nil) : (head, gloss)
    }
}
