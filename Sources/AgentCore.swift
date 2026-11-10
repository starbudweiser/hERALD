// hERALD — dialogue avec un agent IA : réglages, fils de discussion, contexte envoyé, propositions de modifications.
// Logique pure (sans interface). Règle d'or : l'agent ne publie rien ; ses propositions ne touchent le plan
// qu'après un clic de l'utilisateur, et seulement sur les notes, les brouillons et le statut (jamais « Publié »).
import Foundation

// MARK: Réglages

enum AgentKind: String, Codable, CaseIterable, Identifiable {
    case claude      // Claude Code (ligne de commande `claude`) : sessions retrouvables dans Claude Code
    case openai      // API compatible OpenAI (ChatGPT, ou tout service/serveur local du même format)
    case command     // n'importe quelle commande qui lit la question sur l'entrée standard (Codex, etc.)
    var id: String { rawValue }
    var label: String { L.t("agent.kind.\(rawValue)") }
    /// Les sessions sont conservées par l'agent lui-même (sinon hERALD renvoie l'historique à chaque question).
    var hasSessions: Bool { self == .claude }
}

struct AgentConfig: Codable, Equatable {
    /// Option désactivée par défaut : sans agent, hERALD s'affiche et fonctionne comme avant.
    var enabled = false
    var kind: AgentKind = .claude
    var claudePath = ""
    /// Mode léger (recommandé) : Claude Code démarre sans vos serveurs MCP, skills, hooks ni CLAUDE.md. Une demande coûte
    /// environ cent fois moins de jetons qu'avec un environnement chargé ; décochez pour que l'agent y ait accès.
    var lightMode = true
    /// Session Claude Code où atterrissent toutes les demandes : nom affiché dans Claude Code, et identifiant
    /// (créée au premier message si l'identifiant est vide ; on peut aussi y coller celui d'une session existante).
    var sessionName = "hERALD"
    var sessionID = ""
    var command = ""
    var model = ""
    var apiURL = "https://api.openai.com/v1/chat/completions"
    /// Tarifs de l'API en dollars par million de jetons (0 = inconnu : on affiche seulement les jetons).
    var priceIn = 0.0
    var priceOut = 0.0
    /// Taux de change fixé à la main (devise du système pour 1 dollar) ; 0 = taux du jour automatique.
    var fxRate = 0.0
    var workdir = ""
    /// Ce que hERALD joint à la question (la fiche de la tâche est toujours jointe).
    var shareDrafts = true
    var shareStats = true
    var shareCampaignNotes = true
    /// Actions rapides : une par ligne, « Titre | consigne ». Vide = actions par défaut.
    var quickPrompts = ""

    init() {}
    /// Relecture tolérante : un champ absent (réglages d'une version précédente) garde sa valeur par défaut.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self), d = AgentConfig()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        kind = try c.decodeIfPresent(AgentKind.self, forKey: .kind) ?? d.kind
        claudePath = try c.decodeIfPresent(String.self, forKey: .claudePath) ?? d.claudePath
        lightMode = try c.decodeIfPresent(Bool.self, forKey: .lightMode) ?? d.lightMode
        sessionName = try c.decodeIfPresent(String.self, forKey: .sessionName) ?? d.sessionName
        sessionID = try c.decodeIfPresent(String.self, forKey: .sessionID) ?? d.sessionID
        command = try c.decodeIfPresent(String.self, forKey: .command) ?? d.command
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        apiURL = try c.decodeIfPresent(String.self, forKey: .apiURL) ?? d.apiURL
        priceIn = try c.decodeIfPresent(Double.self, forKey: .priceIn) ?? d.priceIn
        priceOut = try c.decodeIfPresent(Double.self, forKey: .priceOut) ?? d.priceOut
        fxRate = try c.decodeIfPresent(Double.self, forKey: .fxRate) ?? d.fxRate
        workdir = try c.decodeIfPresent(String.self, forKey: .workdir) ?? d.workdir
        shareDrafts = try c.decodeIfPresent(Bool.self, forKey: .shareDrafts) ?? d.shareDrafts
        shareStats = try c.decodeIfPresent(Bool.self, forKey: .shareStats) ?? d.shareStats
        shareCampaignNotes = try c.decodeIfPresent(Bool.self, forKey: .shareCampaignNotes) ?? d.shareCampaignNotes
        quickPrompts = try c.decodeIfPresent(String.self, forKey: .quickPrompts) ?? d.quickPrompts
    }

    static let key = "agentConfig"
    /// Lecture de l'interrupteur depuis la valeur brute (pour que les vues se mettent à jour quand elle change).
    static func isEnabled(_ raw: Data) -> Bool { (try? JSONDecoder().decode(AgentConfig.self, from: raw))?.enabled ?? false }
    static var current: AgentConfig {
        get {
            guard let d = UserDefaults.standard.data(forKey: key), let c = try? JSONDecoder().decode(AgentConfig.self, from: d) else { return AgentConfig() }
            return c
        }
        set { if let d = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(d, forKey: key) } }
    }

    var workURL: URL { URL(fileURLWithPath: workdir.isEmpty ? NSHomeDirectory() : (workdir as NSString).expandingTildeInPath) }

    /// Actions rapides utilisables dans la discussion.
    var quick: [(title: String, prompt: String)] {
        let lines = quickPrompts.split(whereSeparator: \.isNewline).compactMap { l -> (String, String)? in
            let parts = l.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            return parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty ? (parts[0], parts[1]) : nil
        }
        if !lines.isEmpty { return lines }
        return (1...5).map { (L.t("agent.quick.\($0).title"), L.t("agent.quick.\($0).prompt")) }
    }
}

// MARK: Fils de discussion (une session de campagne, des sous-sessions par publication)

struct AgentUndo: Codable, Hashable {
    var postID: UUID?
    var field: String          // « notes », « status », « draft.fr », « campaign.notes »
    var old: String?
}

/// Devise du système (la région du Mac : euro en France) et taux de change depuis le dollar, unité des tarifs des fournisseurs.
/// Taux du jour de la Banque centrale européenne via frankfurter.dev (gratuit, sans clé, aucune donnée personnelle envoyée),
/// gardé 24 h ; un taux fixé à la main dans les réglages l'emporte.
enum AgentCurrency {
    static var code: String { Locale.current.currency?.identifier ?? "USD" }

    private static let keyRate = "agentFxRate", keyDate = "agentFxDate", keyCode = "agentFxCode"

    /// Taux connu pour passer des dollars à la devise du système (nil si inconnu).
    static func rate(_ cfg: AgentConfig = AgentConfig.current) -> Double? {
        if code == "USD" { return 1 }
        if cfg.fxRate > 0 { return cfg.fxRate }
        let d = UserDefaults.standard
        guard d.string(forKey: keyCode) == code, d.double(forKey: keyRate) > 0 else { return nil }
        return d.double(forKey: keyRate)
    }

    /// Met le taux à jour s'il a plus de 24 h. Renvoie vrai si une valeur nouvelle a été enregistrée.
    @discardableResult
    static func refreshIfNeeded() async -> Bool {
        let d = UserDefaults.standard, c = code
        if c == "USD" { return false }
        if d.string(forKey: keyCode) == c, let t = d.object(forKey: keyDate) as? Date, Date().timeIntervalSince(t) < 86400 { return false }
        guard let url = URL(string: "https://api.frankfurter.dev/v1/latest?base=USD&symbols=\(c)") else { return false }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("hERALD/\(Watcher.version)", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let r = (obj["rates"] as? [String: Any])?[c] as? Double, r > 0 else { return false }
        d.set(r, forKey: keyRate); d.set(Date(), forKey: keyDate); d.set(c, forKey: keyCode)
        return true
    }

    /// Montant en dollars → texte dans la devise donnée (ou en dollars si le taux est inconnu).
    static func format(dollars: Double, code: String, rate: Double?, locale: Locale) -> String {
        let useLocal = rate != nil && code != "USD"
        let amount = useLocal ? dollars * (rate ?? 1) : dollars
        let digits = amount < 0.1 ? 4 : 2
        return amount.formatted(.currency(code: useLocal ? code : "USD").precision(.fractionLength(digits)).locale(locale))
    }
}

/// Consommation d'une réponse : jetons et, si l'agent la donne ou si des tarifs sont réglés, son coût en dollars.
struct AgentUsage: Codable, Hashable {
    var input = 0
    var output = 0
    /// Coût annoncé par l'agent (Claude Code : équivalent API, non facturé avec un abonnement).
    var cost: Double?

    var tokens: Int { input + output }

    /// Coût affiché : celui de l'agent, sinon calculé avec les tarifs réglés (dollars par million de jetons).
    func dollars(_ cfg: AgentConfig) -> Double? {
        if let cost { return cost }
        guard cfg.priceIn > 0 || cfg.priceOut > 0 else { return nil }
        return (Double(input) * cfg.priceIn + Double(output) * cfg.priceOut) / 1_000_000
    }

    static func + (a: AgentUsage, b: AgentUsage) -> AgentUsage {
        AgentUsage(input: a.input + b.input, output: a.output + b.output, cost: (a.cost == nil && b.cost == nil) ? nil : (a.cost ?? 0) + (b.cost ?? 0))
    }

    /// Phrase courte : « 1 234 jetons · ≈ 0,0042 $ ».
    func label(_ cfg: AgentConfig) -> String {
        var s = L.t("agent.usage.tokens", L.number(tokens))
        if let d = dollars(cfg) { s += " · ≈ " + AgentUsage.money(d) }
        return s
    }

    /// Montant en dollars affiché dans la devise du système (euro en France), au taux du jour.
    static func money(_ d: Double) -> String {
        AgentCurrency.format(dollars: d, code: AgentCurrency.code, rate: AgentCurrency.rate(), locale: Locale.current)
    }
}

struct AgentMessage: Codable, Identifiable, Hashable {
    enum Role: String, Codable { case user, assistant }
    var id = UUID()
    var role: Role
    var text: String
    var date = Date()
    /// Proposition appliquée (avec de quoi l'annuler) ou ignorée.
    var applied: Date?
    var undo: [AgentUndo]?
    var dismissed: Bool?
    var usage: AgentUsage?
    /// Message envoyé par hERALD lui-même (résultats des actions du mode assistance).
    var auto: Bool?
}

extension Campaign {
    /// Consommation de toute la campagne (sa discussion et celles de ses tâches).
    var agentUsage: AgentUsage {
        let all = (agent?.messages ?? []) + posts.flatMap { $0.agent?.messages ?? [] }
        return all.compactMap(\.usage).reduce(AgentUsage(), +)
    }
}

extension AgentThread {
    var usage: AgentUsage { messages.compactMap(\.usage).reduce(AgentUsage(), +) }
}

/// Sous-session ouverte par l'agent pour traiter une demande (il l'annonce dans un bloc herald-session).
struct AgentSubSession: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var date = Date()
}

/// Discussion affichée pour une campagne ou une publication. Toutes les demandes partent dans la même session de
/// l'agent ; hERALD garde ici l'historique de ce qui concerne cette tâche, et les sous-sessions que l'agent y a ouvertes.
struct AgentThread: Codable, Hashable {
    var messages: [AgentMessage] = []
    var subSessions: [AgentSubSession] = []
    /// Empreinte du dernier contexte envoyé : on ne le renvoie que s'il a changé.
    var contextHash: String?
}

enum AgentTarget: Hashable {
    case campaign
    case post(UUID)
}

// MARK: Propositions de modifications

struct AgentProposal: Hashable {
    struct Change: Hashable {
        var post: String?                 // identifiant ou titre de la publication
        var notes: String?
        var status: PostStatus?
        var drafts: [String: String] = [:]
        var why: String?
    }
    var summary: String
    var changes: [Change]
    var campaignNotesAppend: String?
}

/// Un champ proposé, avec sa valeur actuelle : l'utilisateur voit l'avant et l'après et coche ce qu'il applique.
struct AgentItem: Identifiable, Hashable {
    let id: String          // « 0.notes », « 0.status », « 0.draft.fr », « campaign »
    let post: String?       // titre de la publication (nil pour la campagne)
    let label: String
    let old: String
    let new: String
}

extension AgentProposal {
    func items(in c: Campaign, current: UUID?) -> [AgentItem] {
        var out: [AgentItem] = []
        for (n, ch) in changes.enumerated() {
            guard let i = AgentParse.find(ch.post, in: c, current: current) else { continue }
            let p = c.posts[i]
            if let v = ch.notes { out.append(AgentItem(id: "\(n).notes", post: p.title, label: L.t("col.notes"), old: p.notes, new: v)) }
            if let s = ch.status, s != .published { out.append(AgentItem(id: "\(n).status", post: p.title, label: L.t("col.status"), old: p.status.label, new: s.label)) }
            for (k, v) in ch.drafts.sorted(by: { $0.key < $1.key }) {
                out.append(AgentItem(id: "\(n).draft.\(k)", post: p.title, label: "\(L.t("tab.drafts")) \(k.uppercased())", old: p.drafts[k] ?? "", new: v))
            }
        }
        if let add = campaignNotesAppend { out.append(AgentItem(id: "campaign", post: nil, label: L.t("agent.campaignnotes.add"), old: "", new: add)) }
        return out
    }
}

enum AgentParse {
    /// Sépare le texte de la réponse du bloc ```herald-proposal … ``` qui peut la terminer.
    static func split(_ reply: String) -> (text: String, proposal: AgentProposal?) {
        guard let re = try? NSRegularExpression(pattern: "```herald-proposal[ \\t]*\\n(.*?)\\n?```", options: [.dotMatchesLineSeparators]),
              let m = re.firstMatch(in: reply, range: NSRange(reply.startIndex..., in: reply)),
              let whole = Range(m.range, in: reply), let body = Range(m.range(at: 1), in: reply) else {
            return (reply.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }
        var text = reply; text.removeSubrange(whole)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(reply[body].utf8))) as? [String: Any] else { return (text, nil) }
        var changes: [AgentProposal.Change] = []
        for c in obj["changes"] as? [[String: Any]] ?? [] {
            var ch = AgentProposal.Change()
            ch.post = (c["post"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ch.notes = c["notes"] as? String
            ch.status = (c["status"] as? String).flatMap { PostStatus(rawValue: $0.lowercased()) }
            for (k, v) in c["drafts"] as? [String: Any] ?? [:] { if Lang(rawValue: k.lowercased()) != nil, let s = v as? String { ch.drafts[k.lowercased()] = s } }
            ch.why = c["why"] as? String
            if ch.notes != nil || ch.status != nil || !ch.drafts.isEmpty { changes.append(ch) }
        }
        let append = (obj["campaign_notes_append"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        guard !changes.isEmpty || append != nil else { return (text, nil) }
        return (text, AgentProposal(summary: obj["summary"] as? String ?? "", changes: changes, campaignNotesAppend: append))
    }

    /// Sous-sessions annoncées par l'agent : ```herald-session {"id": "<uuid>", "name": "…", "task": "<id de tâche>"}```.
    static func sessions(_ reply: String) -> (clean: String, items: [(id: String, name: String, task: String?)]) {
        guard let re = try? NSRegularExpression(pattern: "```herald-session[ \\t]*\\n(.*?)\\n?```", options: [.dotMatchesLineSeparators]) else { return (reply, []) }
        var items: [(String, String, String?)] = [], clean = reply
        for m in re.matches(in: reply, range: NSRange(reply.startIndex..., in: reply)).reversed() {
            guard let whole = Range(m.range, in: clean), let body = Range(m.range(at: 1), in: reply) else { continue }
            if let o = (try? JSONSerialization.jsonObject(with: Data(reply[body].utf8))) as? [String: Any],
               let id = o["id"] as? String, UUID(uuidString: id) != nil {
                items.insert((id, (o["name"] as? String) ?? id, o["task"] as? String), at: 0)
            }
            clean.removeSubrange(whole)
        }
        return (clean.trimmingCharacters(in: .whitespacesAndNewlines), items)
    }

    /// Publication visée par une modification : identifiant, sinon titre exact, sinon titre contenant le texte.
    static func find(_ ref: String?, in c: Campaign, current: UUID?) -> Int? {
        guard let ref, !ref.isEmpty else { return current.flatMap { id in c.posts.firstIndex { $0.id == id } } }
        if let id = UUID(uuidString: ref), let i = c.posts.firstIndex(where: { $0.id == id }) { return i }
        if let i = c.posts.firstIndex(where: { $0.title.localizedCaseInsensitiveCompare(ref) == .orderedSame }) { return i }
        return c.posts.firstIndex { $0.title.localizedCaseInsensitiveContains(ref) }
    }

    /// Applique une proposition (jamais « Publié », jamais d'autre champ que notes, brouillons, statut) ; renvoie de quoi l'annuler.
    /// `only` : identifiants des éléments cochés (voir `AgentProposal.items`) ; nil = tout.
    static func apply(_ p: AgentProposal, to c: inout Campaign, current: UUID?, only: Set<String>? = nil) -> (lines: [String], undo: [AgentUndo]) {
        var lines: [String] = [], undo: [AgentUndo] = []
        func want(_ k: String) -> Bool { only?.contains(k) ?? true }
        for (n, ch) in p.changes.enumerated() {
            guard let i = find(ch.post, in: c, current: current) else { lines.append(L.t("agent.apply.notfound", ch.post ?? "—")); continue }
            let id = c.posts[i].id, title = c.posts[i].title
            if let v = ch.notes, want("\(n).notes") {
                undo.append(AgentUndo(postID: id, field: "notes", old: c.posts[i].notes)); c.posts[i].notes = v
                lines.append("\(title) · \(L.t("col.notes"))")
            }
            if let s = ch.status, s != .published, want("\(n).status") {
                undo.append(AgentUndo(postID: id, field: "status", old: c.posts[i].status.rawValue)); c.posts[i].status = s
                lines.append("\(title) · \(L.t("col.status")) : \(s.label)")
            } else if ch.status == .published {
                lines.append(L.t("agent.apply.nopublished", title))
            }
            for (k, v) in ch.drafts.sorted(by: { $0.key < $1.key }) where want("\(n).draft.\(k)") {
                undo.append(AgentUndo(postID: id, field: "draft.\(k)", old: c.posts[i].drafts[k])); c.posts[i].drafts[k] = v
                lines.append("\(title) · \(L.t("tab.drafts")) \(k.uppercased())")
            }
        }
        if let add = p.campaignNotesAppend, want("campaign") {
            undo.append(AgentUndo(postID: nil, field: "campaign.notes", old: c.notes))
            c.notes = c.notes.isEmpty ? add : c.notes + "\n\n" + add
            lines.append(L.t("campaign.notes"))
        }
        return (lines, undo)
    }

    static func revert(_ undo: [AgentUndo], in c: inout Campaign) {
        for u in undo.reversed() {
            if u.field == "campaign.notes" { c.notes = u.old ?? ""; continue }
            guard let id = u.postID, let i = c.posts.firstIndex(where: { $0.id == id }) else { continue }
            switch u.field {
            case "notes": c.posts[i].notes = u.old ?? ""
            case "status": if let s = u.old.flatMap(PostStatus.init(rawValue:)) { c.posts[i].status = s }
            default:
                if u.field.hasPrefix("draft.") {
                    let k = String(u.field.dropFirst(6))
                    if let o = u.old, !o.isEmpty { c.posts[i].drafts[k] = o } else { c.posts[i].drafts[k] = nil }
                }
            }
        }
    }
}

// MARK: Contexte et consignes envoyés à l'agent

enum AgentContext {
    /// Empreinte stable (le hachage de Swift change à chaque lancement).
    static func hash(_ s: String) -> String {
        var h: UInt64 = 5381
        for b in s.utf8 { h = (h &* 33) &+ UInt64(b) }
        return String(h, radix: 16)
    }

    static func system(config: AgentConfig, campaign: Campaign, assist: Bool = false) -> String {
        let lang = Locale(identifier: "en").localizedString(forLanguageCode: L.lang) ?? L.lang
        let rule = assist
            ? "- Assist mode is ON for this request: you may publish, post or send ONLY through the confirmed herald-act actions described below."
            : "- You never publish, post or send anything anywhere. The user publishes by hand. If the user asks you to do it for them (publish, post, send an email, fill a form on a site, take control of something in the app), end your answer with this block and nothing else is needed: ```herald-assist\n{}\n```. hERALD then hands you control of the app automatically (the user's request is their authorization; they still confirm each irreversible action) and asks you to proceed. Never answer with a list of manual steps instead."
        var s = """
        You are the assistant of the app hERALD, which manages communication campaigns. This session ("\(config.sessionName)") receives every request made from hERALD, for any campaign or task. The current campaign is "\(campaign.name)".
        Rules:
        \(rule)
        - You may read files in the working directory to find facts (videos, texts, notes); never modify any file.
        - Answer in \(lang), concisely, unless the user writes in another language.
        - Messages may start with a "[hERALD context]" block describing the campaign or one task of the plan: treat it as the current state of the plan.
        - You can work in this session, or open a sub-session for a request that deserves its own thread (a long job, a different topic) by running through Bash: claude -p --resume <this session id> --fork-session --session-id <new uuid> --name "\(config.sessionName) › <short name>" "<instruction>" (you may also start a fresh one with --session-id and --name only). When you open one, announce it with ONE block per sub-session so hERALD can link it to the task: ```herald-session
        {"id": "<new uuid>", "name": "<name>", "task": "<task id or empty>"}
        ```
        Sub-sessions are read-only too and must never publish anything either.
        - To propose changes to the plan, end your answer with ONE fenced block, exactly in this format (the user reviews it and applies it with one click):
        ```herald-proposal
        {"summary": "short description",
         "changes": [{"post": "<task id or exact title>", "notes": "new notes", "status": "idea|draft|approved", "drafts": {"fr": "text", "en": "text", "es": "text", "it": "text"}, "why": "reason"}],
         "campaign_notes_append": "text added at the end of the campaign notes"}
        ```
        Only these fields exist: notes, status (never "published"), drafts per language (fr, en, es, it), campaign_notes_append. Omit what you do not change. Replace whole texts, do not send diffs.
        """
        if config.kind == .claude, !config.sessionID.isEmpty {
            s += "\n\nThis session's id is \(config.sessionID); the user resumes it with: cd \"\(config.workURL.path)\" && claude --resume \(config.sessionID)"
        }
        if !campaign.agentBrief.isEmpty { s += "\n\nCampaign instructions from the user:\n\(campaign.agentBrief)" }
        if assist { s += "\n\n" + AssistPrompt.text }
        return s
    }

    static func campaignBlock(_ c: Campaign, config: AgentConfig, channel: (UUID?) -> String) -> String {
        var s = "[hERALD context · campaign]\nName: \(c.name)\nEvent date: \(L.day(c.eventDate))\n"
        if config.shareCampaignNotes, !c.notes.isEmpty { s += "Campaign notes and decisions:\n\(c.notes)\n" }
        s += "Milestones: " + (c.milestones.sorted { $0.date < $1.date }.map { "\(L.day($0.date)) \($0.title)" }.joined(separator: " · ")) + "\n"
        s += "Plan (id | date | channel | status | title | link):\n"
        for p in c.posts.sorted(by: { $0.date < $1.date }) {
            s += "\(p.id.uuidString) | \(L.day(p.date)) | \(channel(p.channelID)) | \(p.status.rawValue) | \(p.title) | \(p.link.isEmpty ? "-" : p.link)\n"
        }
        return s
    }

    static func postBlock(_ p: Post, in c: Campaign, config: AgentConfig, channel: (UUID?) -> String) -> String {
        var s = "[hERALD context · task]\nId: \(p.id.uuidString)\nTitle: \(p.title)\nDate: \(L.day(p.date))\nChannel: \(channel(p.channelID))\nStatus: \(p.status.rawValue)\nLink: \(p.link.isEmpty ? "-" : p.link)\n"
        if let m = c.milestones.first(where: { $0.id == p.milestoneID }) { s += "Milestone: \(m.title)\n" }
        s += "Notes: \(p.notes.isEmpty ? "-" : p.notes)\n"
        if config.shareDrafts {
            for l in Lang.allCases where !p.draft(l).isEmpty { s += "Draft \(l.rawValue):\n\(p.draft(l))\n" }
        }
        if config.shareStats, let st = p.stats?.last {
            s += "Latest statistics (\(L.date(st.date))): views \(st.views.map(String.init) ?? "-"), likes \(st.likes.map(String.init) ?? "-"), comments \(st.comments.map(String.init) ?? "-"), shares \(st.shares.map(String.init) ?? "-"), downloads \(st.downloads.map(String.init) ?? "-")\n"
        }
        return s
    }

    /// Message envoyé : contexte (si nouveau ou modifié) puis question.
    static func message(question: String, context: String?) -> String {
        guard let context else { return question }
        return context + "\n[Question]\n" + question
    }

    /// Pour les agents sans session : tout l'historique est renvoyé avec la question.
    static func transcript(system: String, context: String, history: [AgentMessage], question: String) -> String {
        var s = system + "\n\n" + context + "\n[Conversation so far]\n"
        for m in history.suffix(24) { s += (m.role == .user ? "User: " : "Assistant: ") + m.text + "\n" }
        return s + "\n[Question]\n" + question
    }
}
