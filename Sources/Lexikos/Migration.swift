import Foundation

/// One-time move from the app's former name (Nombres): data folder and preferences.
enum Migration {
    static func run() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let old = support.appendingPathComponent("Nombres"), new = support.appendingPathComponent("Lexikos")
        if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) { try? fm.moveItem(at: old, to: new) }

        let d = UserDefaults.standard
        guard !d.bool(forKey: "migratedFromNombres") else { return }
        for (k, v) in UserDefaults.standard.persistentDomain(forName: "local.nombres") ?? [:]
        where d.object(forKey: k) == nil { d.set(v, forKey: k) }
        d.set(true, forKey: "migratedFromNombres")
    }
}
