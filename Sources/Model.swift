// hERALD — modèle de données : campagnes, jalons, publications, canaux, veille et retours.
import Foundation

/// Langues des brouillons (les mêmes que l'interface).
enum Lang: String, Codable, CaseIterable, Identifiable {
    case fr, en, es, it
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

enum PostStatus: String, Codable, CaseIterable, Identifiable {
    case idea, draft, approved, published
    var id: String { rawValue }
    var label: String { L.t("status.\(rawValue)") }
}

enum MilestoneKind: String, Codable, CaseIterable, Identifiable {
    case teaser, announce, followup, other
    var id: String { rawValue }
    var label: String { L.t("milestone.\(rawValue)") }
}

enum ChannelKind: String, Codable, CaseIterable, Identifiable {
    case nexus, reddit, discord, youtube, github, x, bluesky, instagram, forum, other
    var id: String { rawValue }
    var label: String { L.t("channel.kind.\(rawValue)") }
    var symbol: String {
        switch self {
        case .nexus: "shippingbox"
        case .reddit: "bubble.left.and.bubble.right"
        case .discord: "message"
        case .youtube: "play.rectangle"
        case .github: "chevron.left.forwardslash.chevron.right"
        case .x, .bluesky: "at"
        case .instagram: "camera"
        case .forum: "text.bubble"
        case .other: "megaphone"
        }
    }
}

enum FeedbackKind: String, Codable, CaseIterable, Identifiable {
    case comment, downloads, endorsements, stars, views, other
    var id: String { rawValue }
    var label: String { L.t("feedback.kind.\(rawValue)") }
    /// Compteur relevé à une date (on garde la dernière valeur) ou événements qui s'additionnent.
    var isMetric: Bool { self != .comment && self != .other }
}

struct Channel: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = ""
    var kind: ChannelKind = .other
    var url = ""
    var notes = ""
}

struct Milestone: Codable, Identifiable, Hashable {
    var id = UUID()
    var title = ""
    var date = Date()
    var kind: MilestoneKind = .other
}

struct Feedback: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var kind: FeedbackKind = .comment
    var value = 1
    var text = ""
    /// Réponses relevées automatiquement (Reddit) : auteur, lien, identifiant source (pour ne pas les doubler), non lue.
    var author: String?
    var url: String?
    var source: String?
    var unread: Bool?
}

struct Post: Codable, Identifiable, Hashable {
    var id = UUID()
    var title = ""
    var date = Date()
    var channelID: UUID?
    var milestoneID: UUID?
    var status: PostStatus = .idea
    var link = ""
    var notes = ""
    var drafts: [String: String] = [:]
    var feedback: [Feedback] = []
    /// Relevés de statistiques (facultatifs : absents des anciens plans).
    var stats: [StatSnapshot]?
    var statsError: String?
    var agent: AgentThread?

    func draft(_ l: Lang) -> String { drafts[l.rawValue] ?? "" }
    var unreadFeedback: Int { feedback.filter { $0.unread == true }.count }

    /// Total d'un type de retour : somme des commentaires, dernière valeur relevée pour les compteurs.
    func total(_ k: FeedbackKind) -> Int {
        let items = feedback.filter { $0.kind == k }
        if k.isMetric { return items.max { $0.date < $1.date }?.value ?? 0 }
        return items.reduce(0) { $0 + $1.value }
    }
}

struct Campaign: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = ""
    var eventDate = Date()
    var notes = ""
    var milestones: [Milestone] = []
    var posts: [Post] = []
    /// Consignes permanentes pour l'agent IA (ton, public, contraintes propres à la campagne).
    var brief: String?
    var agent: AgentThread?
    /// Lecture simple du brief (le champ enregistré est facultatif pour relire les anciens plans).
    var agentBrief: String {
        get { brief ?? "" }
        set { brief = newValue.isEmpty ? nil : newValue }
    }
}

enum WatchKind: String, Codable, CaseIterable, Identifiable {
    case github, nexus
    var id: String { rawValue }
    var label: String { L.t("watch.kind.\(rawValue)") }
}

/// Relevé d'un produit surveillé à une date.
struct WatchSnapshot: Codable, Hashable {
    var date = Date()
    var version = ""
    var published: Date?
    var title = ""
    var downloads: Int?
    var endorsements: Int?
}

struct WatchItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = ""
    var kind: WatchKind = .github
    /// « propriétaire/dépôt » pour GitHub, « jeu/identifiant » pour Nexus.
    var ref = ""
    var notes = ""
    var lastChecked: Date?
    var error: String?
    var history: [WatchSnapshot] = []

    var latest: WatchSnapshot? { history.last }

    var pageURL: URL? {
        switch kind {
        case .github: URL(string: "https://github.com/\(ref)/releases")
        case .nexus:
            ref.split(separator: "/").count == 2
                ? URL(string: "https://www.nexusmods.com/\(ref.split(separator: "/")[0])/mods/\(ref.split(separator: "/")[1])") : nil
        }
    }

    /// Lit une URL GitHub ou Nexus (ou « a/b ») et en déduit le type et la référence.
    static func parse(_ input: String) -> (WatchKind, String)? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let u = URL(string: s), let host = u.host?.lowercased() {
            let parts = u.path.split(separator: "/").map(String.init)
            if host.hasSuffix("github.com"), parts.count >= 2 { return (.github, "\(parts[0])/\(parts[1])") }
            if host.hasSuffix("nexusmods.com"), parts.count >= 3, parts[1] == "mods", Int(parts[2]) != nil {
                return (.nexus, "\(parts[0])/\(parts[2])")
            }
            return nil
        }
        let parts = s.split(separator: "/").map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return Int(parts[1]) != nil ? (.nexus, s) : (.github, s)
    }
}

struct AppData: Codable {
    var format = 1
    var campaigns: [Campaign] = []
    var selected: UUID?
    var channels: [Channel] = []
    var watch: [WatchItem] = []
    /// Statistiques : visites du site (GoatCounter), domaine du site, code GoatCounter, dernier relevé.
    var siteStats: [StatSnapshot]?
    var siteDomain: String?
    var goatcounter: String?
    var siteError: String?
    var statsChecked: Date?
}

enum Storage {
    static let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("hERALD", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    static let url = dir.appendingPathComponent("plan.json")

    static func decode(_ data: Data) throws -> AppData {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try d.decode(AppData.self, from: data)
    }

    static func encode(_ p: AppData) throws -> Data {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(p)
    }

    /// Premier lancement : aucun plan, seulement les canaux par défaut (l'exemple est proposé à part).
    static func load() -> AppData {
        guard let data = try? Data(contentsOf: url), let p = try? decode(data) else { return AppData(channels: Sample.channels()) }
        return p
    }

    static func save(_ p: AppData) {
        if let data = try? encode(p) { try? data.write(to: url, options: .atomic) }
    }
}
