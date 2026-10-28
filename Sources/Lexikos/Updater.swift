import AppKit
import Security

/// Self-update from GitHub Releases: finds a newer release's .dmg, checks that the app inside is
/// signed by the same Developer ID team, then swaps it in place and relaunches.
@MainActor @Observable final class Updater {
    static let repo = "Yixuan0430/Lexikos"
    static let teamID = "BGM8P5U985"

    struct Release { var version: String; var notes: String; var dmg: URL; var page: URL }
    enum State: Equatable { case idle, checking, upToDate, downloading(Double), installing, failed(String) }

    private(set) var available: Release?
    private(set) var state = State.idle
    var dismissed = false
    let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    private var lastCheck: Date? {
        get { UserDefaults.standard.object(forKey: "updateLastCheck") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "updateLastCheck") }
    }

    /// Background check at launch, at most every 12 hours.
    func checkIfDue() async {
        guard UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true else { return }
        if let last = lastCheck, Date.now.timeIntervalSince(last) < 12 * 3600 { return }
        await check()
    }

    func check() async {
        state = .checking
        do {
            var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
                  let dmg = (json["assets"] as? [[String: Any]])?
                    .compactMap({ $0["browser_download_url"] as? String }).first(where: { $0.hasSuffix(".dmg") })
                    .flatMap(URL.init(string:)) else { throw UpdateError.noRelease }
            lastCheck = .now
            let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            if Self.isNewer(version, than: current) {
                available = Release(version: version, notes: json["body"] as? String ?? "", dmg: dmg, page: page)
                dismissed = false
                state = .idle
            } else {
                available = nil
                state = .upToDate
            }
        } catch {
            state = .failed("check")
        }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    // MARK: Install

    enum UpdateError: Error { case noRelease, notWritable, badSignature, mount }

    func install() async {
        guard let release = available else { return }
        let target = Bundle.main.bundleURL
        let parent = target.deletingLastPathComponent()
        // Running from the disk image or a translocated copy: nowhere permanent to update.
        guard !target.path.contains("/AppTranslocation/"), !target.path.hasPrefix("/Volumes/"),
              FileManager.default.isWritableFile(atPath: parent.path) else {
            state = .failed("location")
            return
        }
        do {
            state = .downloading(0)
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("lexikos-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let dmg = work.appendingPathComponent("update.dmg")
            try await download(release.dmg, to: dmg)

            state = .installing
            let mount = work.appendingPathComponent("mnt"), staged = work.appendingPathComponent("Lexikos.app")
            guard run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-mountpoint", mount.path]) else { throw UpdateError.mount }
            let copied = run("/usr/bin/ditto", [mount.appendingPathComponent("Lexikos.app").path, staged.path])
            _ = run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
            guard copied else { throw UpdateError.mount }
            guard Self.signedByUs(staged) else { throw UpdateError.badSignature }

            // Swap after we quit, then relaunch the new copy.
            let script = """
            while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
            rm -rf "\(target.path)" && mv "\(staged.path)" "\(target.path)" && open "\(target.path)"
            rm -rf "\(work.path)"
            """
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", script]
            try p.run()
            NSApp.terminate(nil)
        } catch UpdateError.badSignature {
            state = .failed("signature")
        } catch {
            state = .failed("download")
        }
    }

    /// The new app must be valid and signed with our Developer ID team.
    static func signedByUs(_ app: URL) -> Bool {
        var code: SecStaticCode?, req: SecRequirement?
        let r = "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(r as CFString, [], &req) == errSecSuccess else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate), req) == errSecSuccess
    }

    private func download(_ url: URL, to dest: URL) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        let total = Double(response.expectedContentLength)
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        let h = try FileHandle(forWritingTo: dest)
        defer { try? h.close() }
        var buf = Data(), got = 0.0
        for try await b in bytes {
            buf.append(b)
            if buf.count >= 1 << 16 {
                try h.write(contentsOf: buf); got += Double(buf.count); buf.removeAll(keepingCapacity: true)
                if total > 0 { state = .downloading(got / total) }
            }
        }
        try h.write(contentsOf: buf)
    }

    @discardableResult private func run(_ tool: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}

import SwiftUI

/// Home-page notice: a newer version, download progress, or what went wrong.
struct UpdateBanner: View {
    let l: L, accent: Accent
    @Environment(Updater.self) private var updater

    var body: some View {
        switch updater.state {
        case .downloading(let f): bar { ProgressView(value: f).frame(width: 160); Text(l["update.downloading"]) }
        case .installing: bar { ProgressView().controlSize(.small); Text(l["update.installing"]) }
        case .failed(let why) where why != "check":
            bar {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(gradeColor(.forgot))
                Text(l["update.err.\(why)"]).lineLimit(2)
                Spacer()
                if let r = updater.available { Button(l["update.page"]) { NSWorkspace.shared.open(r.page) }.buttonStyle(.link) }
            }
        default:
            if let r = updater.available, !updater.dismissed {
                bar {
                    Image(systemName: "sparkles").foregroundStyle(accent.color)
                    Text("\(l["update.available"]) \(r.version)").fontWeight(.medium)
                    Text("(\(l["update.current"]) \(updater.current))").foregroundStyle(Color.muted)
                    Spacer()
                    Button(l["update.later"]) { updater.dismissed = true }.buttonStyle(.plain).foregroundStyle(Color.muted)
                    Button { Task { await updater.install() } } label: {
                        Text(l["update.install"]).font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Capsule().fill(accent.color)).foregroundStyle(Color.bg)
                    }
                    .buttonStyle(.plain).focusable(false)
                }
            }
        }
    }

    private func bar<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 10) { c() }
            .font(.system(size: 13)).foregroundStyle(Color.ink)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.panel))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.line))
    }
}

struct UpdateSettings: View {
    let l: L
    @Environment(Updater.self) private var updater
    @AppStorage("autoUpdate") private var autoUpdate = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Toggle(l["update.auto"], isOn: $autoUpdate).toggleStyle(.checkbox)
                Spacer()
                Button(l["update.check"]) { Task { await updater.check() } }.disabled(updater.state == .checking)
            }
            Text(status).font(.system(size: 11)).foregroundStyle(Color.muted)
        }
    }

    private var status: String {
        let v = "\(l["update.current"]) \(updater.current)"
        switch updater.state {
        case .checking: return "\(v) · \(l["update.checking"])"
        case .upToDate: return "\(v) · \(l["update.latest"])"
        case .failed("check"): return "\(v) · \(l["update.err.check"])"
        default: return updater.available.map { "\(v) · \(l["update.available"]) \($0.version)" } ?? v
        }
    }
}
