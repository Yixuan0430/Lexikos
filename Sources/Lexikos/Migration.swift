import Foundation

/// One-time moves from the app's former name (Nombres) and former bundle id (local.lexikos):
/// data folder and preferences.
enum Migration {
    static func run() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let old = support.appendingPathComponent("Nombres"), new = support.appendingPathComponent("Lexikos")
        if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) { try? fm.moveItem(at: old, to: new) }

        adoptDefaults(from: "local.nombres", flag: "migratedFromNombres")
        adoptDefaults(from: "local.lexikos", flag: "migratedFromLocalId")
    }

    /// Copies an old preferences domain into the current one, without overwriting and skipping AppKit's own keys.
    private static func adoptDefaults(from domain: String, flag: String) {
        let d = UserDefaults.standard
        guard !d.bool(forKey: flag) else { return }
        for (k, v) in d.persistentDomain(forName: domain) ?? [:]
        where !k.hasPrefix("NS") && d.object(forKey: k) == nil { d.set(v, forKey: k) }
        d.set(true, forKey: flag)
    }
}
