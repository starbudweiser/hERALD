// hERALD — vue « OpenMacApps » : une ligne par appli du compte suivi, triée par visites venues d'openmacapps.com.
import SwiftUI

struct OMAView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState

    private static let w: [CGFloat] = [110, 96, 96, 140, 70]

    var body: some View {
        let st = store.oma
        let apps = OMA.sorted(st.apps).filter { ui.matches($0.name, $0.category ?? "") }
        VStack(alignment: .leading, spacing: Socle.M.space3) {
            toolbar(st)
            notices(st)
            kpis(st.apps)
            VStack(spacing: 0) {
                header
                Divider().overlay(Socle.C.border)
                if apps.isEmpty {
                    EmptyState(text: L.t(st.apps.isEmpty ? "oma.empty" : "oma.empty.search")).frame(height: 90)
                } else {
                    ScrollView { LazyVStack(spacing: 0) { ForEach(apps) { row($0) } } }
                }
            }
            .soclePanel()
            Text(L.t("oma.note")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).lineLimit(1).truncationMode(.tail)
        }
        .padding(Socle.M.space4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .soclePanel()
    }

    private func toolbar(_ st: OMAState) -> some View {
        HStack(spacing: Socle.M.space2) {
            Text(st.checked.map { L.t("oma.checked", L.date($0)) } ?? L.t("oma.never"))
                .socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted).lineLimit(1)
            if let o = st.owner, !o.isEmpty {
                Badge(text: "github.com/\(o)")
            }
            Spacer(minLength: Socle.M.space2)
            if store.omaChecking { ProgressView().controlSize(.small) }
            Button(L.t("oma.site")) { if let u = URL(string: "https://openmacapps.com") { Browser.openURL(u) } }
                .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
            Button(L.t("stats.refresh")) { Task { await store.refreshOMA() } }
                .buttonStyle(SocleButtonStyle(.primary, height: Socle.M.sizeControl)).fixedSize()
                .disabled(store.omaChecking)
        }
    }

    @ViewBuilder private func notices(_ st: OMAState) -> some View {
        if Keychain.get("github").isEmpty {
            HStack(spacing: Socle.M.space2) {
                Callout(kind: .info, text: L.t("oma.notice.token"))
                Button(L.t("settings.title")) { ui.showSettings = true }
                    .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
            }
        }
        if let e = st.error { Callout(kind: .warning, text: e) }
    }

    private func kpis(_ apps: [OMAApp]) -> some View {
        let listed = apps.filter(\.listed)
        return HStack(spacing: Socle.M.space2) {
            kpi(L.t("oma.kpi.window"), listed.reduce(0) { $0 + $1.window },
                sub: L.t("oma.kpi.uniques", L.number(listed.reduce(0) { $0 + $1.windowUniques })))
            kpi(L.t("oma.kpi.total"), apps.reduce(0) { $0 + $1.cumulative },
                sub: L.t("oma.kpi.uniques", L.number(apps.reduce(0) { $0 + $1.cumulativeUniques })))
            kpi(L.t("stats.kpi.downloads"), apps.reduce(0) { $0 + ($1.downloads ?? 0) }, sub: L.t("oma.kpi.downloads.sub"))
            kpi(L.t("oma.kpi.listed"), listed.count, sub: L.t("oma.kpi.featured", listed.filter(\.featured).count))
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func kpi(_ label: String, _ v: Int, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textSubtle).lineLimit(1)
            Text(L.number(v)).socle(Socle.T.stat).foregroundStyle(Socle.C.textStrong).lineLimit(1)
            Text(sub).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).lineLimit(1)
        }
        .padding(Socle.M.space3).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Socle.C.surface, in: RoundedRectangle(cornerRadius: Socle.M.radiusMd))
        .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusMd).stroke(Socle.C.border, lineWidth: 1))
    }

    private var header: some View {
        HStack(spacing: Socle.M.space2_5) {
            Text(L.t("oma.col.app")).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 26 + Socle.M.space2_5)
            Text(L.t("oma.col.status")).frame(width: Self.w[0], alignment: .leading)
            Text(L.t("oma.col.window")).frame(width: Self.w[1], alignment: .trailing)
            Text(L.t("oma.col.total")).frame(width: Self.w[2], alignment: .trailing)
            Text(L.t("stats.col.downloads")).frame(width: Self.w[3], alignment: .trailing)
            Text("").frame(width: Self.w[4])
        }
        .socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textSubtle).lineLimit(1)
        .padding(.horizontal, Socle.M.space3).frame(height: Socle.M.sizeBar)
    }

    private func row(_ a: OMAApp) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Socle.M.space2_5) {
                AsyncImage(url: a.iconURL) { img in img.resizable().scaledToFit() } placeholder: {
                    Image(systemName: "app.dashed").foregroundStyle(Socle.C.textSubtle)
                }
                .frame(width: 26, height: 26).clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityHidden(true)
                HStack(spacing: Socle.M.space2) {
                    Text(a.name).socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong).lineLimit(1).fixedSize()
                    Text(a.category ?? "").socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).lineLimit(1).truncationMode(.tail)
                    if let e = a.error {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(Socle.C.warning)
                            .help(e).accessibilityLabel(e)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    if !a.listed { Badge(text: L.t("oma.badge.removed"), kind: .danger) }
                    else if a.featured { Badge(text: L.t("oma.badge.featured"), kind: .success) }
                    else { Badge(text: L.t("oma.badge.listed")) }
                }
                .frame(width: Self.w[0], alignment: .leading)
                number(a.window, sub: a.windowUniques, width: Self.w[1], strong: a.window > 0)
                number(a.cumulative, sub: a.cumulativeUniques, width: Self.w[2], strong: false)
                Text(a.downloads.map(L.number) ?? "—").socle(Socle.T.label).foregroundStyle(Socle.C.text).lineLimit(1)
                    .frame(width: Self.w[3], alignment: .trailing)
                Button { if let u = a.page { Browser.openURL(u) } } label: {
                    Text(L.t("oma.open")).lineLimit(1)
                }
                .buttonStyle(SocleButtonStyle(.tertiary, height: Socle.M.sizeControl)).fixedSize()
                .frame(width: Self.w[4], alignment: .trailing)
                .accessibilityLabel(L.t("oma.open.a11y", a.name))
            }
            .padding(.horizontal, Socle.M.space3).frame(height: 46)
            Divider().overlay(Socle.C.borderSubtle)
        }
    }

    private func number(_ v: Int, sub: Int, width: CGFloat, strong: Bool) -> some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            Text(L.number(v)).socle(Socle.T.labelStrong).foregroundStyle(strong ? Socle.C.textStrong : Socle.C.text)
            Text("(\(L.number(sub)))").socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
        }
        .lineLimit(1).frame(width: width)
        .help(L.t("oma.uniques.help"))
    }
}
