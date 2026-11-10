import SwiftUI

/// Tiroir « Navigateur » : glisse depuis le bas par-dessus la zone de contenu, ne recouvre jamais le panneau IA.
enum DrawerMotion {
    /// Arrivée : rapide, amortie en fin de course.
    static let open = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.46)
    /// Départ : un peu plus court.
    static let close = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.34)
    /// Agrandir / réduire, suivi du panneau IA.
    static let resize = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.42)
}

struct BrowserDrawer: View {
    @EnvironmentObject var ui: UIState
    @State private var dragY: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            grip
            BrowserView()
        }
        .background(Socle.C.surface)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: Socle.M.radiusXl, topTrailingRadius: Socle.M.radiusXl))
        .overlay(UnevenRoundedRectangle(topLeadingRadius: Socle.M.radiusXl, topTrailingRadius: Socle.M.radiusXl)
            .stroke(Socle.C.borderControl, lineWidth: 1))
        .offset(y: max(0, dragY))
    }

    private var grip: some View {
        ZStack {
            Capsule().fill(Socle.C.borderControl).frame(width: 40, height: 4)
            HStack {
                Button { ui.setBrowser(false) } label: { Image(systemName: "chevron.down") }
                    .help(L.t("drawer.close"))
                Spacer()
                Button { withAnimation(DrawerMotion.resize) { ui.browserFull.toggle() } } label: {
                    Image(systemName: ui.browserFull ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .help(ui.browserFull ? L.t("drawer.shrink") : L.t("drawer.expand"))
            }
            .buttonStyle(.plain).foregroundStyle(Socle.C.textMuted).padding(.horizontal, Socle.M.space3)
        }
        .frame(height: 24).frame(maxWidth: .infinity).contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 8)
            .onChanged { dragY = $0.translation.height }
            .onEnded { v in
                if v.translation.height > 70 { ui.setBrowser(false) }
                withAnimation(DrawerMotion.resize) { dragY = 0 }
            })
    }
}

/// Languette affichée en bas de la zone de contenu quand le tiroir est rabattu.
struct BrowserDrawerTab: View {
    @EnvironmentObject var ui: UIState
    var body: some View {
        Button { ui.setBrowser(true) } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.up").font(.system(size: 9, weight: .bold))
                Text(L.t("drawer.tab")).font(.system(size: 11))
            }
            .foregroundStyle(Socle.C.onAccentFill)
            .padding(.horizontal, 14).frame(height: 18)
            .background(Socle.C.accentFill)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: Socle.M.radiusLg, topTrailingRadius: Socle.M.radiusLg))
            .overlay(UnevenRoundedRectangle(topLeadingRadius: Socle.M.radiusLg, topTrailingRadius: Socle.M.radiusLg)
                .stroke(Socle.C.accent, lineWidth: 1))
        }
        .buttonStyle(.plain).help(L.t("drawer.open"))
    }
}

private struct SidebarWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

extension View {
    /// Mesure la largeur du bloc (barre latérale + marge) pour caler le tiroir contre elle.
    func reportWidth(_ w: Binding<CGFloat>) -> some View {
        background(GeometryReader { g in Color.clear.preference(key: SidebarWidthKey.self, value: g.size.width) })
            .onPreferenceChange(SidebarWidthKey.self) { w.wrappedValue = $0 }
    }
}
