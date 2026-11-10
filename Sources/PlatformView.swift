// hERALD — une vue par plateforme (YouTube, GitHub, Reddit…) : chiffres, publications et retours de cette plateforme seule.
import SwiftUI

extension Store {
    /// Plateformes à montrer dans la barre latérale : celles des canaux réglés et celles des publications saisies.
    /// Plateformes ajoutées à la main (assistant ou Réglages) ; au départ la liste est vide.
    var pinnedPlatforms: [StatPlatform] {
        (data.platforms ?? []).compactMap(StatPlatform.init(rawValue:))
    }
    /// Barre latérale : plateformes choisies, plus celles qui ont déjà des publications dans le plan.
    var activePlatforms: [StatPlatform] {
        var count: [StatPlatform: Int] = [:]
        for p in pinnedPlatforms { count[p, default: 0] += 0 }
        for post in posts where platform(post).group != .other { count[platform(post).group, default: 0] += 1 }
        return count.keys.sorted { (count[$0]!, $1.label) > (count[$1]!, $0.label) }
    }
    func posts(on p: StatPlatform) -> [Post] { posts.filter { platform($0).group == p } }
}

struct PlatformView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    let platform: StatPlatform

    var body: some View {
        let all = store.posts(on: platform).sorted { $0.date > $1.date }
        let rows = all.filter { ui.matches($0, store) }
        let views = all.compactMap { $0.stats?.last?.views }.reduce(0, +)
        let inter = all.map { $0.stats?.last?.interactions ?? 0 }.reduce(0, +)
        let published = all.filter { $0.status == .published }.count
        VStack(spacing: Socle.M.space3) {
            HStack(spacing: Socle.M.space3) {
                kpi(L.t("platform.kpi.posts"), "\(all.count)", sub: L.t("platform.kpi.published", published))
                kpi(L.t("stats.kpi.views"), L.number(views))
                kpi(L.t("stats.kpi.interactions"), L.number(inter))
                kpi(L.t("platform.kpi.feedback"), "\(all.reduce(0) { $0 + $1.feedback.count })",
                    sub: L.t("feedback.unread", all.reduce(0) { $0 + $1.unreadFeedback }))
            }
            .fixedSize(horizontal: false, vertical: true)
            SplitLayout(width: 480) {
                if rows.isEmpty {
                    VStack(spacing: Socle.M.space3) {
                        EmptyState(text: L.t(all.isEmpty ? "platform.empty.help" : "platform.empty", platform.label))
                        if all.isEmpty {
                            Button(L.t("platform.empty.btn")) { ui.selectedPost = store.addPlatformPost(platform) }
                                .buttonStyle(SocleButtonStyle(.primary, height: Socle.M.sizeControlLg)).fixedSize().disabled(!store.hasCampaign)
                        }
                    }.padding(.bottom, Socle.M.space4)
                }
                ForEach(rows) { p in
                    ItemRow(selected: p.id == ui.selectedPost, symbol: platform.symbol,
                            title: p.title, meta: meta(p), metaColor: p.unreadFeedback > 0 ? Socle.C.warning : Socle.C.textSubtle,
                            highlight: p.unreadFeedback > 0, action: { ui.selectedPost = p.id }) { StatusBadge(status: p.status) }
                        .opacity(p.status == .published && p.id != ui.selectedPost ? 0.6 : 1)
                        .postDeleteMenu(p)
                }
            } detail: {
                if let id = ui.selectedPost, let p = store.post(id), store.platform(p).group == platform {
                    PostInspector(id: id, selected: $ui.selectedPost)
                } else { EmptyState(text: L.t("post.select")) }
            }
        }
        .onChange(of: platform) { _, _ in ui.selectedPost = nil }
    }

    private func meta(_ p: Post) -> String {
        var parts = [L.day(p.date)]
        if let s = p.stats?.last {
            if let v = s.views { parts.append("👁 \(L.number(v))") }
            if s.interactions > 0 { parts.append("♥ \(L.number(s.interactions))") }
        }
        if p.unreadFeedback > 0 { parts.append(L.t("feedback.unread", p.unreadFeedback)) }
        return parts.joined(separator: " · ")
    }

    private func kpi(_ label: String, _ value: String, sub: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textSubtle).lineLimit(1)
            Text(value).socle(Socle.T.stat).foregroundStyle(Socle.C.textStrong).lineLimit(1).minimumScaleFactor(0.7)
            Text(sub ?? " ").socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).lineLimit(1)
        }
        .padding(Socle.M.space3).frame(maxWidth: .infinity, alignment: .leading).soclePanel()
    }
}

extension Store {
    /// Crée une première publication sur la plateforme, épingle la plateforme et renvoie la publication.
    func addPlatformPost(_ p: StatPlatform) -> UUID {
        let id = addPost()
        if let i = campaign.posts.firstIndex(where: { $0.id == id }) {
            if let c = data.channels.first(where: { StatPlatform.detect(link: "", channel: $0.kind, site: siteDomain).group == p }) {
                campaign.posts[i].channelID = c.id
            } else if let root = StatPlatform.rootURL[p] {
                campaign.posts[i].link = root        // pas de canal de ce type : le lien suffit à reconnaître la plateforme
            }
        }
        var l = pinnedPlatforms.filter { $0 != p }; l.append(p)
        data.platforms = l.map(\.rawValue)
        return id
    }
}

extension StatPlatform {
    /// Les pages Nexus (article, forum) se regroupent avec Nexus Mods dans la barre latérale.
    var group: StatPlatform { self == .nexusPage ? .nexus : self }
    static let rootURL: [StatPlatform: String] = [.vimeo: "https://vimeo.com/", .facebook: "https://www.facebook.com/"]
    static var choosable: [StatPlatform] { allCases.filter { $0 != .other && $0 != .nexusPage } }
}

/// Assistant guidé : on choisit une plateforme, on lit ce qui sera suivi, et une première publication est créée.
struct AddPlatformSheet: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: StatPlatform?

    var body: some View {
        VStack(alignment: .leading, spacing: Socle.M.space3) {
            Text(L.t("platform.add.title")).socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong)
            Text(L.t("platform.add.step1")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: Socle.M.space2)], spacing: Socle.M.space2) {
                ForEach(StatPlatform.choosable) { p in
                    Button { chosen = p } label: {
                        VStack(spacing: 6) {
                            Image(systemName: p.symbol).font(.system(size: 20)).foregroundStyle(p.color)
                            Text(p.label).socle(Socle.T.label).foregroundStyle(Socle.C.text).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(chosen == p ? Socle.C.surfaceSelected : Socle.C.control, in: RoundedRectangle(cornerRadius: Socle.M.radius))
                        .overlay(RoundedRectangle(cornerRadius: Socle.M.radius).stroke(chosen == p ? Socle.C.accent : Color.clear, lineWidth: 1.5))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if let p = chosen {
                VStack(alignment: .leading, spacing: Socle.M.space1_5) {
                    Text(L.t("platform.add.step2", p.label)).socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong)
                    Text(L.t("platform.add.how")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted)
                    Text(L.t(p.automatic ? "platform.add.auto" : "platform.add.manual")).socle(Socle.T.body)
                        .foregroundStyle(p.automatic ? Socle.C.success : Socle.C.warning)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(Socle.M.space3).frame(maxWidth: .infinity, alignment: .leading).soclePanel()
            }
            HStack {
                Spacer()
                Button(L.t("action.cancel")) { dismiss() }.buttonStyle(SocleButtonStyle(.tertiary, height: Socle.M.sizeControlLg)).fixedSize()
                Button(chosen.map { L.t("platform.add.go", $0.label) } ?? L.t("platform.add.pick")) {
                    guard let p = chosen else { return }
                    let id = store.addPlatformPost(p)
                    ui.platform = p; ui.selectedPost = id; ui.tab = .platform
                    dismiss()
                }
                .buttonStyle(SocleButtonStyle(.primary, height: Socle.M.sizeControlLg)).fixedSize().disabled(chosen == nil || !store.hasCampaign)
            }
        }
        .padding(Socle.M.space5).frame(width: 520)
        .background(Socle.C.bg)
    }
}
