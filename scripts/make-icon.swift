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

struct Icon: View {
    // Orbit: ellipse around the book, tilted.
    let oc = CGPoint(x: 512, y: 585), orx: CGFloat = 345, ory: CGFloat = 108, tilt = Angle(degrees: -11)

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

    // Open book: two pages fanning from the spine.
    var leftPage: Path {
        var p = Path()
        p.move(to: CGPoint(x: 512, y: 455))
        p.addCurve(to: CGPoint(x: 268, y: 430), control1: CGPoint(x: 450, y: 410), control2: CGPoint(x: 350, y: 405))
        p.addLine(to: CGPoint(x: 268, y: 690))
        p.addCurve(to: CGPoint(x: 512, y: 720), control1: CGPoint(x: 350, y: 668), control2: CGPoint(x: 450, y: 675))
        p.closeSubpath()
        return p
    }
    var rightPage: Path { leftPage.applying(CGAffineTransform(translationX: 1024, y: 0).scaledBy(x: -1, y: 1)) }

    func pageLines(right: Bool) -> Path {
        var p = Path()
        for i in 0..<5 {
            let y0 = 478 + CGFloat(i) * 42
            p.move(to: CGPoint(x: 300, y: y0 - 6))
            p.addCurve(to: CGPoint(x: 482, y: y0 + 16), control1: CGPoint(x: 360, y: y0 - 22), control2: CGPoint(x: 440, y: y0 - 18))
        }
        return right ? p.applying(CGAffineTransform(translationX: 1024, y: 0).scaledBy(x: -1, y: 1)) : p
    }

    var body: some View {
        ZStack {
            // Paper tile
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(RadialGradient(colors: [hex(0xfffaf2), hex(0xf8efe2), hex(0xefe2cf)],
                                     center: UnitPoint(x: 0.42, y: 0.36), startRadius: 0, endRadius: 700))
                .frame(width: 824, height: 824)
                .shadow(color: hex(0x5c4630, 0.16), radius: 16, y: 12)

            // Halo behind the star
            Circle()
                .fill(RadialGradient(colors: [hex(0xf6c995, 0.55), hex(0xf3d2a8, 0.18), hex(0xf3d2a8, 0)],
                                     center: .center, startRadius: 0, endRadius: 250))
                .frame(width: 500, height: 500).position(x: 512, y: 400)

            // Back half of the orbit (behind the book)
            orbit(from: 180, to: 360)
                .stroke(LinearGradient(colors: [hex(0xe0b27c, 0.55), hex(0xd49a5e, 0.75)], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round))
            sphere(orbitPoint(215), 20, 0xd6dde8, 0x8193ad)

            // Book
            leftPage.fill(LinearGradient(colors: [hex(0xa7b9d0), hex(0x8098b6), hex(0x627b9c)],
                                         startPoint: UnitPoint(x: 0.25, y: 0.35), endPoint: UnitPoint(x: 0.5, y: 0.75)))
            rightPage.fill(LinearGradient(colors: [hex(0x93a8c3), hex(0x6e86a6)],
                                          startPoint: UnitPoint(x: 0.75, y: 0.35), endPoint: UnitPoint(x: 0.55, y: 0.75)))
            pageLines(right: false).stroke(hex(0xfdf6ea, 0.42), style: StrokeStyle(lineWidth: 7, lineCap: .round))
            pageLines(right: true).stroke(hex(0xfdf6ea, 0.32), style: StrokeStyle(lineWidth: 7, lineCap: .round))
            Path { p in p.move(to: CGPoint(x: 512, y: 452)); p.addLine(to: CGPoint(x: 512, y: 720)) }
                .stroke(hex(0x4d6383, 0.6), lineWidth: 4)

            // Front half of the orbit (over the book)
            orbit(from: 0, to: 180)
                .stroke(LinearGradient(colors: [hex(0xd49a5e), hex(0xf0c48c), hex(0xd49a5e)], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 11, lineCap: .round))
            sphere(orbitPoint(18), 24, 0xf6d2bb, 0xc98b6b)
            sphere(orbitPoint(128), 17, 0xe8ecf2, 0x9aa6b8)

            // The word rising from the book
            sparkle(CGPoint(x: 512, y: 330), 120, 0.16)
                .fill(LinearGradient(colors: [hex(0xf2c584), hex(0xc98a4b)], startPoint: .top, endPoint: .bottom))
                .shadow(color: hex(0xf6c995, 0.6), radius: 18)
            sparkle(CGPoint(x: 512, y: 330), 34, 0.2).fill(hex(0xfffaf0, 0.9))
            Circle().fill(hex(0xc98a4b)).frame(width: 18, height: 18).position(x: 512, y: 180)
            sparkle(CGPoint(x: 318, y: 300), 26).fill(hex(0xd9a76c, 0.85))
            sparkle(CGPoint(x: 720, y: 262), 18).fill(hex(0x8ea0bb, 0.85))
            sparkle(CGPoint(x: 760, y: 790), 14).fill(hex(0xd9a76c, 0.7))
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor func render() {
    let r = ImageRenderer(content: Icon())
    r.scale = 1
    guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { fatalError() }
    try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
MainActor.assumeIsolated { render() }
