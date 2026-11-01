// Icône de hERALD redessinée en vectoriel (mêmes cotes que Resources/make_icon.swift) pour le splash :
// le fanion flotte, les ondes d'annonce partent deux fois après l'arrivée de l'icône, puis tout se pose sur le logo exact.
import AppKit
import SwiftUI

struct AnimatedHeraldIcon: View {
    @State private var start = Date()

    var body: some View {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            HeraldIconFrame(t: HeraldIconFrame.settled)
        } else {
            TimelineView(.animation) { context in
                HeraldIconFrame(t: context.date.timeIntervalSince(start))
            }
        }
    }
}

/// Image de l'icône à l'instant `t` (secondes depuis l'apparition du splash).
struct HeraldIconFrame: View {
    var t: Double

    /// À partir de cet instant, l'icône est identique au logo.
    static let settled = 4.0
    /// Fin de l'arrivée en tourbillon du splash : les ondes partent à ce moment-là.
    private static let wavesStart = 1.2
    private static let wavesPeriod = 1.0

    private static let ink = Color(red: 0.13, green: 0.13, blue: 0.13)
    private static let amber = Color(red: 0xf5 / 255, green: 0x9e / 255, blue: 0x0b / 255)
    private static let accent = Color(red: 0x0e / 255, green: 0xa5 / 255, blue: 0xe9 / 255)

    private func smooth(_ x: Double) -> Double {
        let v = min(1, max(0, x))
        return v * v * (3 - 2 * v)
    }

    /// Amplitude du flottement : monte en 0,5 s, retombe à zéro avant la sortie du splash.
    private var amplitude: Double { 24 * smooth(t / 0.5) * (1 - smooth((t - 3.2) / 0.7)) }

    /// Décalage vertical du fanion à l'abscisse `x` : nul à la hampe, maximal à la pointe, vague qui s'éloigne de la hampe.
    private func lift(_ x: Double) -> Double {
        let d = x - 296
        return amplitude * (d / 344) * sin(2 * .pi * (d / 300 - 1.4 * t))
    }

    /// Opacité de l'onde `i` : allumée de la plus proche à la plus lointaine, deux fois, et reste à sa valeur du logo.
    private func waveOpacity(_ i: Int) -> Double {
        let base = 1 - Double(i) * 0.25
        let u = (t - Self.wavesStart) / Self.wavesPeriod
        if u < 0 { return base * 0.12 }
        if u >= 2 { return base }
        let phase = u - floor(u)
        let on = min(1, max(0, (phase - Double(i) * 0.22) / 0.12))
        let off = u >= 1 ? 0 : min(1, max(0, (phase - 0.72) / 0.24))
        return base * (0.12 + 0.88 * on * (1 - off))
    }

    var body: some View {
        Canvas { ctx, size in
            ctx.scaleBy(x: size.width / 1024, y: size.height / 1024)
            // repère de make_icon.swift (origine en bas) retourné : y → 1024 − y
            ctx.fill(Path(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerRadius: 185), with: .color(Self.ink))
            ctx.fill(Path(roundedRect: CGRect(x: 262, y: 204, width: 34, height: 600), cornerRadius: 17), with: .color(Color(white: 0.85)))

            // fanion à queue fendue, découpé finement pour suivre la vague
            let corners: [(Double, Double)] = [(296, 224), (640, 224), (560, 374), (640, 524), (296, 524)]
            var flag = Path()
            flag.move(to: CGPoint(x: 296, y: 224 + lift(296)))
            for k in 1..<corners.count {
                let (ax, ay) = corners[k - 1], (bx, by) = corners[k]
                for s in 1...24 {
                    let f = Double(s) / 24, x = ax + (bx - ax) * f
                    flag.addLine(to: CGPoint(x: x, y: ay + (by - ay) * f + lift(x)))
                }
            }
            flag.closeSubpath()
            ctx.fill(flag, with: .color(Self.amber))

            // le « H » suit la pente du tissu
            var letter = ctx
            letter.translateBy(x: 420, y: 368 + lift(420))
            letter.rotate(by: .radians(atan2(lift(421) - lift(419), 2)))
            letter.draw(Text("H").font(.system(size: 210, weight: .heavy)).foregroundColor(Self.ink), at: .zero)

            for (i, r) in [120.0, 200.0, 280.0].enumerated() {
                var arc = Path()
                arc.addArc(center: CGPoint(x: 600, y: 664), radius: r, startAngle: .degrees(-40), endAngle: .degrees(40), clockwise: false)
                ctx.stroke(arc, with: .color(Self.accent.opacity(waveOpacity(i))),
                           style: StrokeStyle(lineWidth: 40 - Double(i) * 6, lineCap: .round))
            }
        }
    }
}
