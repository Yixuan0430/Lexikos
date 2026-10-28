import Foundation

/// French cardinal numbers 0–9999 with spelling and broad IPA (syllables split by ".").
enum FrenchNumbers {
    struct Entry { let word: String; let ipa: String }

    private static let base: [(String, String)] = [
        ("zéro", "ze.ʁo"), ("un", "œ̃"), ("deux", "dø"), ("trois", "tʁwa"), ("quatre", "katʁ"),
        ("cinq", "sɛ̃k"), ("six", "sis"), ("sept", "sɛt"), ("huit", "ɥit"), ("neuf", "nœf"),
        ("dix", "dis"), ("onze", "ɔ̃z"), ("douze", "duz"), ("treize", "tʁɛz"), ("quatorze", "ka.tɔʁz"),
        ("quinze", "kɛ̃z"), ("seize", "sɛz"), ("dix-sept", "di.sɛt"), ("dix-huit", "di.zɥit"),
        ("dix-neuf", "diz.nœf"),
    ]

    // tens 20…60: word, alone, before "et", before a hyphenated unit
    private static let tens: [Int: (String, String, String, String)] = [
        20: ("vingt", "vɛ̃", "vɛ̃.te", "vɛ̃t"),
        30: ("trente", "tʁɑ̃t", "tʁɑ̃.te", "tʁɑ̃t"),
        40: ("quarante", "ka.ʁɑ̃t", "ka.ʁɑ̃.te", "ka.ʁɑ̃t"),
        50: ("cinquante", "sɛ̃.kɑ̃t", "sɛ̃.kɑ̃.te", "sɛ̃.kɑ̃t"),
        60: ("soixante", "swa.sɑ̃t", "swa.sɑ̃.te", "swa.sɑ̃t"),
    ]

    // multiplier before "cent" / "mille" (pre-consonant forms)
    private static let multiplier = ["", "", "dø", "tʁwa", "katʁ", "sɛ̃k", "si", "sɛt", "ɥi", "nœf"]

    static func entry(_ n: Int) -> Entry {
        precondition((0...9999).contains(n))
        if n < 1000 { return below1000(n) }
        let th = n / 1000, r = n % 1000
        var word = th == 1 ? "mille" : "\(base[th].0) mille"
        var ipa = th == 1 ? "mil" : "\(multiplier[th]).mil"
        if r > 0 {
            let tail = below1000(r)
            word += " " + tail.word
            ipa += "." + tail.ipa
        }
        return Entry(word: word, ipa: ipa)
    }

    private static func below1000(_ n: Int) -> Entry {
        if n < 100 { return below100(n, final: true) }
        let h = n / 100, r = n % 100
        var word = h == 1 ? "cent" : "\(base[h].0) cent"
        var ipa = h == 1 ? "sɑ̃" : "\(multiplier[h]).sɑ̃"
        if r == 0 {
            if h > 1 { word += "s" }
        } else {
            let tail = below100(r, final: true)
            word += " " + tail.word
            ipa += "." + tail.ipa
        }
        return Entry(word: word, ipa: ipa)
    }

    private static func below100(_ n: Int, final: Bool) -> Entry {
        if n < 20 { return Entry(word: base[n].0, ipa: base[n].1) }
        let t = n / 10 * 10, u = n % 10
        if t <= 60 {
            let (w, alone, beforeEt, beforeUnit) = tens[t]!
            if u == 0 { return Entry(word: w, ipa: alone) }
            if u == 1 { return Entry(word: "\(w) et un", ipa: "\(beforeEt).œ̃") }
            return Entry(word: "\(w)-\(base[u].0)", ipa: "\(beforeUnit).\(base[u].1)")
        }
        if t == 70 {
            let teen = base[n - 60]
            if n == 71 { return Entry(word: "soixante et onze", ipa: "swa.sɑ̃.te.ɔ̃z") }
            return Entry(word: "soixante-\(teen.0)", ipa: "swa.sɑ̃t.\(teen.1)")
        }
        // 80–99
        if n == 80 { return Entry(word: "quatre-vingts", ipa: "ka.tʁə.vɛ̃") }
        let rest = base[n - 80]
        return Entry(word: "quatre-vingt-\(rest.0)", ipa: "ka.tʁə.vɛ̃.\(rest.1)")
    }
}
