// hERALD — démarrage guidé : « Que voulez-vous annoncer ? » Crée la campagne de départ (jalons, publications, brouillons)
// d'après le ou les mods, la date de sortie et les canaux choisis. Rien n'est publié : tout est à relire et à compléter.
import SwiftUI

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
            Text(L.n("wiz.preview", Sample.guidedCount(mods: mods.count, kinds: kinds))).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
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
