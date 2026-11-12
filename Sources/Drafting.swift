// hERALD — assistant de rédaction : quand le texte d'une publication est vide, propose un premier jet écrit par l'agent IA
// (ou une traduction d'une autre langue déjà rédigée). Rien n'est publié : le texte est inséré dans l'éditeur, à relire.
import SwiftUI

extension AgentRunner {
    /// Un appel unique à l'agent configuré, quel que soit son type, qui rend le texte produit.
    static func oneShot(_ cfg: AgentConfig, name: String, system: String, prompt: String) async throws -> String {
        switch cfg.kind {
        case .claude:
            var c = cfg; c.sessionName = (cfg.sessionName.isEmpty ? "hERALD" : cfg.sessionName) + " › " + name
            return try await claude(c, session: "", system: system, prompt: prompt).text
        case .command:
            return try await command(cfg, prompt: system + "\n\n" + prompt)
        case .openai:
            return try await openai(cfg, system: system, history: [], user: prompt).text
        }
    }
}

struct WritingAssistant: View {
    @EnvironmentObject var store: Store
    @AppStorage(AgentConfig.key) private var agentRaw = Data()
    let postID: UUID
    let lang: Lang
    @Binding var text: String
    @State private var wish = ""
    @State private var busy = false
    @State private var failure: String?

    private var post: Post { store.post(postID) ?? Post() }
    /// Autre langue déjà rédigée, à traduire.
    private var source: Lang? { Lang.allCases.first { $0 != lang && !post.draft($0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }

    var body: some View {
        let ready = AgentConfig.isEnabled(agentRaw) && AgentConfig.current.isReady
        VStack(alignment: .leading, spacing: Socle.M.space3) {
            HStack(spacing: Socle.M.space2) {
                Image(systemName: "sparkles").foregroundStyle(Socle.C.accentText)
                Text(L.t("wr.title")).socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong)
            }
            Text(L.t("wr.sub")).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted).fixedSize(horizontal: false, vertical: true)
            TextField(L.t("wr.hint"), text: $wish).socleField()
            HStack(spacing: Socle.M.space2) {
                Button(L.t("wr.write")) { Task { await run(translate: false) } }
                    .buttonStyle(SocleButtonStyle(.primary)).fixedSize()
                if let s = source {
                    Button(L.t("wr.translate", s.label)) { Task { await run(translate: true) } }
                        .buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
                }
                if busy { ProgressView().controlSize(.small) }
            }
            .disabled(busy || !ready)
            if !ready { Callout(kind: .info, text: L.t("wr.needagent")) }
            if let failure { Callout(kind: .warning, text: failure) }
        }
        .padding(Socle.M.space4).frame(maxWidth: 460, alignment: .leading)
        .background(Socle.C.surface, in: RoundedRectangle(cornerRadius: Socle.M.radius))
        .overlay(RoundedRectangle(cornerRadius: Socle.M.radius).stroke(Socle.C.borderControl, lineWidth: 1))
    }

    private func run(translate: Bool) async {
        busy = true; failure = nil
        defer { busy = false }
        let names = ["fr": "français", "en": "English", "es": "español", "it": "italiano"]
        let target = names[lang.rawValue] ?? "English"
        let cfg = AgentConfig.current
        let system = "You help an independent developer write posts for community channels (Reddit, Discord, forums, press, directories). "
            + "Reply with the post text only, ready to paste: no preamble, no comment, no markdown fences. "
            + "Use ONLY the facts given; never invent numbers, features, quotes or links. If a needed fact is missing, write [à compléter]. "
            + "Respect the channel's culture and rules, and avoid promotional hype."
        let prompt: String
        if translate, let s = source {
            prompt = "Translate this post from \(names[s.rawValue] ?? s.rawValue) into \(target). Keep the structure, tone, links and formatting. Text only.\n\n\(post.draft(s))"
        } else {
            let c = store.campaign
            let ch = store.channel(post.channelID)
            var p = "Write the post in \(target).\n\nTitle / purpose: \(post.title)\n"
            if let ch { p += "Channel: \(ch.name) (\(ch.kind))" + (ch.url.isEmpty ? "" : " — \(ch.url)") + (ch.notes.isEmpty ? "" : "\nChannel rules and notes: \(ch.notes)") + "\n" }
            if !post.notes.isEmpty { p += "Notes on this post: \(post.notes)\n" }
            p += "Campaign: \(c.name)" + (c.notes.isEmpty ? "" : "\nCampaign notes: \(c.notes)") + (c.agentBrief.isEmpty ? "" : "\nStanding instructions: \(c.agentBrief)") + "\n"
            let examples = store.posts.filter { $0.id != postID && $0.status == .published && !$0.draft(lang).isEmpty }
                .sorted { ($0.channelID == post.channelID ? 0 : 1, -$0.date.timeIntervalSince1970) < ($1.channelID == post.channelID ? 0 : 1, -$1.date.timeIntervalSince1970) }
                .prefix(2)
            if !examples.isEmpty {
                p += "\nPosts already published in this campaign (same voice and facts; do not copy them):\n"
                for e in examples { p += "---\n\(e.title)\n\(String(e.draft(lang).prefix(900)))\n" }
            }
            if !wish.trimmingCharacters(in: .whitespaces).isEmpty { p += "\nExtra instruction from the author: \(wish)\n" }
            prompt = p
        }
        do {
            let out = try await AgentRunner.oneShot(cfg, name: L.t("wr.session"), system: system, prompt: prompt)
            let t = out.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { text = t }
        } catch let e as AgentFailure { failure = e.message }
        catch { failure = error.localizedDescription }
    }
}
