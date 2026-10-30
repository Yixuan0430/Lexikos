import SwiftUI
import AppKit

func hex(_ h: UInt32, _ a: Double = 1) -> Color {
    Color(red: Double(h >> 16 & 255) / 255, green: Double(h >> 8 & 255) / 255, blue: Double(h & 255) / 255, opacity: a)
}

/// Four-point sparkle with concave sides.
func sparkle(_ c: CGPoint, _ r: CGFloat, _ waist: CGFloat = 0.18) -> Path {
    var p = Path()
    let pts = [CGPoint(x: c.x, y: c.y - r), CGPoint(x: c.x + r, y: c.y), CGPoint(x: c.x, y: c.y + r), CGPoint(x: c.x - r, y: c.y)]
    p.move(to: pts[0])
    for i in 0..<4 {
        let a = pts[i], b = pts[(i + 1) % 4]
        p.addQuadCurve(to: b, control: CGPoint(x: c.x + (a.x + b.x - 2 * c.x) * waist, y: c.y + (a.y + b.y - 2 * c.y) * waist))
    }
    p.closeSubpath()
    return p
}

/// Two word cards — the one in front shows a word's first letter — circled by the review orbit.
/// The fine orbit and its three planets follow Synaxos: words coming round again. The star is the word that stuck.
struct Icon: View {
    /// iOS masks its own corners, so its icon is full-bleed with no tile or shadow.
    let fullBleed: Bool
    let oc = CGPoint(x: 512, y: 600), orx: CGFloat = 352, ory: CGFloat = 112, tilt = Angle(degrees: -12)

    func orbitPoint(_ deg: Double) -> CGPoint {
        let t = deg * .pi / 180, x = orx * cos(t), y = ory * sin(t), a = tilt.radians
        return CGPoint(x: oc.x + x * cos(a) - y * sin(a), y: oc.y + x * sin(a) + y * cos(a))
    }

    func orbit(from: Double, to: Double) -> Path {
        var p = Path()
        p.move(to: orbitPoint(from))
        for d in stride(from: from, through: to, by: 2) { p.addLine(to: orbitPoint(d)) }
        return p
    }

    func sphere(_ c: CGPoint, _ r: CGFloat, _ light: UInt32, _ dark: UInt32) -> some View {
        Circle()
            .fill(RadialGradient(colors: [hex(light), hex(dark)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: r * 1.4))
            .frame(width: r * 2, height: r * 2)
            .shadow(color: hex(0x5c4630, 0.18), radius: 4, y: 2)
            .position(c)
    }

    var backCard: some View {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
            .fill(LinearGradient(colors: [hex(0xa7b9d0), hex(0x7e96b5), hex(0x627b9c)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 290, height: 370)
            .rotationEffect(.degrees(-11))
            .position(x: 445, y: 585)
            .shadow(color: hex(0x3d4f6a, 0.18), radius: 10, y: 6)
    }

    var frontCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(LinearGradient(colors: [hex(0xfffdf8), hex(0xf6ecdd)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .strokeBorder(hex(0xd9c7ad, 0.7), lineWidth: 3)
            Text("é").font(.custom("Didot", size: 250)).foregroundStyle(
                LinearGradient(colors: [hex(0x6f88a9), hex(0x4d6383)], startPoint: .top, endPoint: .bottom))
                .offset(y: -18)
        }
        .frame(width: 290, height: 370)
        .rotationEffect(.degrees(7))
        .position(x: 565, y: 600)
        .shadow(color: hex(0x5c4630, 0.22), radius: 18, y: 10)
    }

    var art: some View {
        ZStack {
            // Halo behind the star
            Circle()
                .fill(RadialGradient(colors: [hex(0xf6c995, 0.5), hex(0xf3d2a8, 0.16), hex(0xf3d2a8, 0)],
                                     center: .center, startRadius: 0, endRadius: 240))
                .frame(width: 480, height: 480).position(x: 690, y: 330)

            // Back half of the orbit (behind the cards): a fine line, as in Synaxos
            orbit(from: 180, to: 360)
                .stroke(hex(0xe0b27c, 0.6), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            sphere(orbitPoint(195), 15, 0xd6dde8, 0x8193ad)

            backCard
            frontCard

            // Front half of the orbit, plus a fainter outer trace (one planet rides it)
            orbit(from: 0, to: 180)
                .stroke(LinearGradient(colors: [hex(0xd49a5e, 0.9), hex(0xf0c48c), hex(0xd49a5e, 0.9)], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
            Ellipse().trim(from: 0.02, to: 0.2)
                .stroke(hex(0xe0b27c, 0.45), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: orx * 2 + 40, height: ory * 2 + 40)
                .rotationEffect(tilt).position(oc)
            sphere(orbitPoint(335), 17, 0xf6d2bb, 0xc98b6b)
            sphere(orbitPoint(28).applying(.init(translationX: 22, y: 30)), 11, 0xe8ecf2, 0x9aa6b8)

            // The word that stuck
            sparkle(CGPoint(x: 712, y: 318), 96, 0.16)
                .fill(LinearGradient(colors: [hex(0xf2c584), hex(0xc98a4b)], startPoint: .top, endPoint: .bottom))
                .shadow(color: hex(0xf6c995, 0.6), radius: 18)
            sparkle(CGPoint(x: 712, y: 318), 26, 0.2).fill(hex(0xfffaf0, 0.9))
            Circle().fill(hex(0xc98a4b)).frame(width: 16, height: 16).position(x: 712, y: 182)
            sparkle(CGPoint(x: 300, y: 285), 24).fill(hex(0xd9a76c, 0.85))
            sparkle(CGPoint(x: 236, y: 445), 15).fill(hex(0x8ea0bb, 0.85))
            sparkle(CGPoint(x: 250, y: 780), 13).fill(hex(0xd9a76c, 0.7))
        }
        .frame(width: 1024, height: 1024)
    }

    var paper: RadialGradient {
        RadialGradient(colors: [hex(0xfffaf2), hex(0xf8efe2), hex(0xefe2cf)], center: UnitPoint(x: 0.42, y: 0.36), startRadius: 0, endRadius: 700)
    }

    var body: some View {
        ZStack {
            if fullBleed {
                Rectangle().fill(paper)
                art.scaleEffect(1.12).offset(y: -14)
            } else {
                RoundedRectangle(cornerRadius: 185, style: .continuous)
                    .fill(paper)
                    .frame(width: 824, height: 824)
                    .shadow(color: hex(0x5c4630, 0.16), radius: 16, y: 12)
                art.scaleEffect(0.92).offset(y: -6)
            }
        }
        .frame(width: 1024, height: 1024)
        .clipped()
    }
}

@MainActor func render() {
    let r = ImageRenderer(content: Icon(fullBleed: CommandLine.arguments.contains("--ios")))
    r.scale = 1
    guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { fatalError() }
    try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
MainActor.assumeIsolated { render() }
