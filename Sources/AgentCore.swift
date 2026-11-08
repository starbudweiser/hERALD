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
    static func apply(_ p: AgentProposal, to c: inout Campaign, current: UUID?) -> (lines: [String], undo: [AgentUndo]) {
        var lines: [String] = [], undo: [AgentUndo] = []
        for ch in p.changes {
            guard let i = find(ch.post, in: c, current: current) else { lines.append(L.t("agent.apply.notfound", ch.post ?? "—")); continue }
            let id = c.posts[i].id, title = c.posts[i].title
            if let n = ch.notes {
                undo.append(AgentUndo(postID: id, field: "notes", old: c.posts[i].notes)); c.posts[i].notes = n
                lines.append("\(title) · \(L.t("col.notes"))")
            }
            if let s = ch.status, s != .published {
                undo.append(AgentUndo(postID: id, field: "status", old: c.posts[i].status.rawValue)); c.posts[i].status = s
                lines.append("\(title) · \(L.t("col.status")) : \(s.label)")
            } else if ch.status == .published {
                lines.append(L.t("agent.apply.nopublished", title))
            }
            for (k, v) in ch.drafts.sorted(by: { $0.key < $1.key }) {
                undo.append(AgentUndo(postID: id, field: "draft.\(k)", old: c.posts[i].drafts[k])); c.posts[i].drafts[k] = v
                lines.append("\(title) · \(L.t("tab.drafts")) \(k.uppercased())")
            }
        }
        if let add = p.campaignNotesAppend {
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

    static func system(config: AgentConfig, campaign: Campaign) -> String {
        let lang = Locale(identifier: "en").localizedString(forLanguageCode: L.lang) ?? L.lang
        var s = """
        You are the assistant of the app hERALD, which manages communication campaigns. This session ("\(config.sessionName)") receives every request made from hERALD, for any campaign or task. The current campaign is "\(campaign.name)".
        Rules:
        - You never publish, post or send anything anywhere. The user publishes by hand.
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
        if !campaign.agentBrief.isEmpty { s += "\n\nCampaign instructions from the user:\n\(campaign.agentBrief)" }
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
