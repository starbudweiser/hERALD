// hERALD — démarrage guidé : « Que voulez-vous annoncer ? » Crée la campagne de départ (jalons, publications, brouillons)
// d'après le ou les mods, la date de sortie et les canaux choisis. Rien n'est publié : tout est à relire et à compléter.
import SwiftUI

extension Sample {
    /// Publications d'un lancement : (clé du titre, décalage en jours par rapport à la sortie, canal, jalon, statut, brouillons, partagée entre mods).
    private typealias Spec = (key: String, day: Int, kind: ChannelKind, ms: Int, status: PostStatus, drafts: [String: String], shared: Bool)
    private static let specs: [Spec] = [
        ("sample.post.files", -12, .nexus, 0, .draft, [:], false),
        ("sample.post.visuals", -10, .instagram, 0, .idea, [:], false),
        ("sample.post.teaser", -7, .bluesky, 1, .draft, teaserDrafts, false),
        ("sample.post.teaser.ig", -7, .instagram, 1, .idea, [:], false),
        ("sample.post.preview", -3, .discord, 2, .idea, [:], false),
        ("sample.post.short", -2, .youtube, 2, .idea, [:], false),
        ("sample.post.reddit", 0, .reddit, 3, .draft, launchDrafts, false),
        ("sample.post.nexus", 0, .nexus, 3, .draft, nexusDrafts, false),
        ("sample.post.video", 0, .youtube, 3, .idea, [:], false),
        ("sample.post.discord", 0, .discord, 3, .draft, discordDrafts, false),
        ("sample.post.community", 7, .reddit, 4, .idea, [:], true),
        ("sample.post.review", 30, .github, 5, .idea, [:], true),
    ]

    /// Nombre de publications que créera `guided` (pour l'aperçu).
    static func guidedCount(mods: Int, kinds: Set<ChannelKind>) -> Int {
        specs.filter { kinds.contains($0.kind) }.reduce(0) { $0 + ($1.shared ? 1 : max(mods, 1)) }
    }

    static func guided(mods: [String], launch: Date, kinds: Set<ChannelKind>, using channels: inout [Channel]) -> Campaign {
        let cal = Calendar.current
        let day0 = cal.date(bySettingHour: 12, minute: 0, second: 0, of: launch) ?? launch
        func day(_ o: Int) -> Date { cal.date(byAdding: .day, value: o, to: day0) ?? day0 }
        func ch(_ kind: ChannelKind) -> Channel {
            if let c = channels.first(where: { $0.kind == kind }) { return c }
            let c = Sample.channels().first { $0.kind == kind } ?? Channel(name: kind.label, kind: kind)
            channels.append(c)
            return c
        }
        let ms = [
            Milestone(title: L.t("sample.ms.prep"), date: day(-14), kind: .other),
            Milestone(title: L.t("sample.ms.teaser"), date: day(-7), kind: .teaser),
            Milestone(title: L.t("sample.ms.preview"), date: day(-3), kind: .teaser),
            Milestone(title: L.t("sample.ms.launch"), date: day(0), kind: .announce),
            Milestone(title: L.t("sample.ms.followup"), date: day(3), kind: .followup),
            Milestone(title: L.t("sample.ms.review"), date: day(30), kind: .followup),
        ]
        let names = mods.isEmpty ? [""] : mods
        let placeholders = ["[Nom du mod]", "[Mod name]", "[Nombre del mod]", "[Nome della mod]"]
        var c = Campaign(name: L.t("wiz.campaign", names.joined(separator: ", ")), eventDate: day0, notes: L.t("sample.campaign.notes"))
        c.milestones = ms
        for sp in specs where kinds.contains(sp.kind) {
            for (i, name) in (sp.shared ? [""] : names).enumerated() {
                // plusieurs mods : leurs annonces sont décalées de deux jours pour ne pas s'empiler
                let offset = sp.shared || sp.day < 0 ? sp.day : sp.day + i * 2
                var drafts: [String: String] = [:]
                for (lang, text) in sp.drafts {
                    drafts[lang] = name.isEmpty ? text : placeholders.reduce(text) { $0.replacingOccurrences(of: $1, with: name) }
                }
                let title = L.t(sp.key) + (name.isEmpty || sp.shared ? "" : " — " + name)
                c.posts.append(Post(title: title, date: day(offset), channelID: ch(sp.kind).id, milestoneID: ms[sp.ms].id, status: sp.status, drafts: drafts))
            }
        }
        return c
    }
}

struct LaunchWizard: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    @Environment(\.dismiss) private var dismiss
    @State private var modsText = ""
    @State private var launch = Calendar.current.date(byAdding: .day, value: 21, to: Date()) ?? Date()
    @State private var kinds: Set<ChannelKind> = [.nexus, .reddit, .discord, .youtube]
    private let offered: [ChannelKind] = [.nexus, .reddit, .discord, .youtube, .instagram, .bluesky, .github]

    private var mods: [String] {
        modsText.split(whereSeparator: { ",;\n".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Socle.M.space4) {
            Text(L.t("wiz.title")).socle(Socle.T.title).foregroundStyle(Socle.C.textStrong)
            Text(L.t("wiz.sub")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted).fixedSize(horizontal: false, vertical: true)
            Field(label: L.t("wiz.mods")) {
                TextField(L.t("wiz.mods.hint"), text: $modsText).socleField()
            }
            Field(label: L.t("wiz.date")) {
                DatePicker("", selection: $launch, in: Date()..., displayedComponents: .date).labelsHidden().fixedSize()
            }
            Field(label: L.t("wiz.channels")) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: Socle.M.space2) {
                    ForEach(offered) { k in
                        Toggle(isOn: Binding(get: { kinds.contains(k) }, set: { if $0 { kinds.insert(k) } else { kinds.remove(k) } })) {
                            Label(k.label, systemImage: k.symbol)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            Text(L.t("wiz.preview", Sample.guidedCount(mods: mods.count, kinds: kinds))).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
            HStack(spacing: Socle.M.space2) {
                Button(L.t("wiz.blank")) { store.addCampaign(); dismiss() }.buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
                Spacer(minLength: 0)
                Button(L.t("wiz.cancel")) { dismiss() }.buttonStyle(SocleButtonStyle(.secondary)).fixedSize().keyboardShortcut(.cancelAction)
                Button(L.t("wiz.create")) {
                    store.addGuided(mods: mods, launch: launch, kinds: kinds)
                    ui.tab = .today
                    dismiss()
                }
                .buttonStyle(SocleButtonStyle(.primary)).fixedSize().disabled(mods.isEmpty || kinds.isEmpty)
            }
        }
        .padding(Socle.M.space5).frame(width: 560)
        .background(Socle.C.bg)
    }
}
