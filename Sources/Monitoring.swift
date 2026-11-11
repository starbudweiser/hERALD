// hERALD — panneau « Surveillances » : inventaire de tout ce que l'appli relève seule (calculé, instantané),
// et synthèse rédigée à la demande par l'agent IA à partir de cet inventaire.
import SwiftUI

struct MonitorLine: Identifiable {
    enum State { case ok, warn, off }
    let id = UUID()
    var symbol: String
    var title: String
    var detail: String
    var state: State
}

extension Store {
    func monitorLines() -> [MonitorLine] {
        var out: [MonitorLine] = []
        let now = Date()

        // Statistiques des publications
        let linked = hasCampaign ? posts.filter { !$0.link.isEmpty } : []
        let auto = linked.filter { platform($0).automatic }
        let errors = auto.filter { $0.statsError != nil }.count
        var d = L.t("mon.stats.detail", auto.count, linked.count - auto.count, L.t(campaignActive ? "mon.every.hour" : "mon.every.day"))
        d += " · " + (data.statsChecked.map { L.t("mon.last", L.date($0)) } ?? L.t("mon.never"))
        if errors > 0 { d += " · " + L.t("mon.errors", errors) }
        out.append(MonitorLine(symbol: "chart.bar", title: L.t("mon.stats"), detail: d, state: errors > 0 ? .warn : (auto.isEmpty ? .off : .ok)))

        // Visites du site
        let code = (data.goatcounter ?? "").trimmingCharacters(in: .whitespaces)
        if code.isEmpty {
            out.append(MonitorLine(symbol: "globe", title: L.t("mon.site"), detail: L.t("mon.off"), state: .off))
        } else if let e = data.siteError {
            out.append(MonitorLine(symbol: "globe", title: L.t("mon.site"), detail: e, state: .warn))
        } else {
            out.append(MonitorLine(symbol: "globe", title: L.t("mon.site"), detail: L.t("mon.site.detail", data.siteDomain ?? code), state: .ok))
        }

        // Réponses Reddit
        if !Keychain.get("reddit.id").isEmpty {
            out.append(MonitorLine(symbol: "bubble.left.and.bubble.right", title: L.t("mon.reddit"), detail: L.t("mon.reddit.api"), state: .ok))
        } else if Treg.available {
            out.append(MonitorLine(symbol: "bubble.left.and.bubble.right", title: L.t("mon.reddit"), detail: L.t("mon.reddit.treg"), state: .ok))
        } else {
            out.append(MonitorLine(symbol: "bubble.left.and.bubble.right", title: L.t("mon.reddit"), detail: L.t("mon.off"), state: .off))
        }

        // Veille (produits, mots-clés)
        if data.watch.isEmpty {
            out.append(MonitorLine(symbol: "binoculars", title: L.t("mon.watch"), detail: L.t("mon.off"), state: .off))
        }
        for w in data.watch {
            var s = w.kind.label + (w.ref.isEmpty ? "" : " · " + w.ref)
            s += " · " + (w.lastChecked.map { L.t("mon.last", L.date($0)) } ?? L.t("mon.never"))
            if w.unreadMentions > 0 { s += " · " + L.t("mon.unread", w.unreadMentions) }
            if let e = w.error { s += " · " + e }
            let late = !w.isKeyword && (w.lastChecked ?? .distantPast) < now.addingTimeInterval(-7 * 86400)
            out.append(MonitorLine(symbol: "binoculars", title: w.name.isEmpty ? w.ref : w.name, detail: s, state: (w.error != nil || late) ? .warn : .ok))
        }

        // OpenMacApps
        if let o = data.oma {
            var s = L.t("mon.oma.detail", o.apps.count)
            s += " · " + (o.checked.map { L.t("mon.last", L.date($0)) } ?? L.t("mon.never"))
            if let e = o.error { s += " · " + e }
            out.append(MonitorLine(symbol: "storefront", title: "OpenMacApps", detail: s, state: o.error == nil ? .ok : .warn))
        } else {
            out.append(MonitorLine(symbol: "storefront", title: "OpenMacApps", detail: L.t("mon.off"), state: .off))
        }

        // Boîte de dépôt
        out.append(MonitorLine(symbol: "tray.and.arrow.down", title: L.t("mon.inbox"), detail: L.t("mon.inbox.detail"), state: .ok))
        return out
    }

    /// Texte brut de l'inventaire, donné à l'IA.
    func monitorText() -> String {
        monitorLines().map { l in
            let st = l.state == .ok ? "OK" : (l.state == .warn ? "PROBLÈME" : "INACTIF")
            return "- [\(st)] \(l.title) : \(l.detail)"
        }.joined(separator: "\n")
    }
}

struct MonitorPanel: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AgentConfig.key) private var agentRaw = Data()
    @State private var summary = ""
    @State private var busy = false
    @State private var failure: String?
    @State private var usage: String?
    @State private var lines: [MonitorLine] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L.t("mon.title")).socle(Socle.T.title).foregroundStyle(Socle.C.textStrong)
                Spacer()
                Button(L.t("publish.close")) { dismiss() }.buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
                    .keyboardShortcut(.cancelAction)
            }
            .padding(Socle.M.space4)
            Divider().overlay(Socle.C.border)
            ScrollView {
                VStack(alignment: .leading, spacing: Socle.M.space4) {
                    VStack(spacing: 0) {
                        ForEach(lines) { l in
                            HStack(alignment: .top, spacing: Socle.M.space3) {
                                Image(systemName: l.symbol).frame(width: 18).foregroundStyle(Socle.C.textMuted)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(l.title).socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong)
                                    Text(l.detail).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 8)
                                Badge(text: L.t(l.state == .ok ? "mon.state.ok" : (l.state == .warn ? "mon.state.warn" : "mon.state.off")),
                                      kind: l.state == .ok ? .success : (l.state == .warn ? .warning : .neutral))
                            }
                            .padding(.vertical, Socle.M.space2)
                            Divider().overlay(Socle.C.borderSubtle)
                        }
                    }
                    summarySection
                }
                .padding(Socle.M.space4)
            }
        }
        .frame(width: 640, height: 640)
        .onAppear { lines = store.monitorLines() }
        .background(Socle.C.bg)
    }

    @ViewBuilder private var summarySection: some View {
        let cfg = AgentConfig.current
        let ready = AgentConfig.isEnabled(agentRaw) && cfg.isReady
        HStack {
            Text(L.t("mon.summary")).socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong)
            Spacer()
            if busy { ProgressView().controlSize(.small) }
            Button(L.t(summary.isEmpty ? "mon.write" : "mon.rewrite")) { Task { await write(cfg) } }
                .buttonStyle(SocleButtonStyle(.primary)).fixedSize().disabled(busy || !ready)
        }
        if !ready { Callout(kind: .info, text: L.t("mon.needagent")) }
        if let failure { Callout(kind: .warning, text: failure) }
        if !summary.isEmpty {
            MarkdownView(text: summary).frame(maxWidth: .infinity, alignment: .leading)
            if let usage { Text(usage).socle(Socle.T.meta).foregroundStyle(Socle.C.textDisabled) }
        }
    }

    private func write(_ cfg: AgentConfig) async {
        busy = true; failure = nil
        defer { busy = false }
        let lang = ["fr": "français", "en": "English", "es": "español", "it": "italiano"][L.lang] ?? "English"
        let system = "You write short, clear status summaries for a communication-plan tool. Use ONLY the data given; never invent anything. Do not run commands or use tools."
        let prompt = """
        Voici l'inventaire des surveillances automatiques de hERALD (état au \(L.date(Date()))) :

        \(store.monitorText())

        Rédige en \(lang) une synthèse point par point, facile à lire pour quelqu'un de non technique : \
        (1) ce qui est surveillé et à quel rythme, (2) ce qui fonctionne, (3) ce qui est en erreur, en retard ou inactif, \
        (4) les 1 à 3 actions concrètes à faire, s'il y en a. Une ligne par point, pas d'introduction ni de conclusion.
        """
        do {
            switch cfg.kind {
            case .claude:
                var c = cfg; c.sessionName = (cfg.sessionName.isEmpty ? "hERALD" : cfg.sessionName) + " › " + L.t("mon.session")
                let r = try await AgentRunner.claude(c, session: "", system: system, prompt: prompt)
                summary = r.text; usage = r.usage?.label(cfg)
            case .command:
                summary = try await AgentRunner.command(cfg, prompt: system + "\n\n" + prompt); usage = nil
            case .openai:
                let r = try await AgentRunner.openai(cfg, system: system, history: [], user: prompt)
                summary = r.text; usage = r.usage?.label(cfg)
            }
        } catch let e as AgentFailure { failure = e.message }
        catch { failure = error.localizedDescription }
    }
}
