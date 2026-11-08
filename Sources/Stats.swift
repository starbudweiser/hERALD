// hERALD — statistiques des publications : relevés automatiques (YouTube, Reddit, Bluesky, GitHub, Nexus, site via
// GoatCounter) ou saisis à la main (Instagram, Facebook, Discord, X…), cumul par période et rapport.
// Lecture seule : rien n'est jamais publié ni envoyé, on ne fait que lire des compteurs publics.
import Foundation

/// Un relevé des compteurs d'une publication (ou du site) à une date. Les champs absents ne sont pas connus.
struct StatSnapshot: Codable, Hashable {
    var date = Date()
    var views: Int?
    var likes: Int?
    var comments: Int?
    var shares: Int?
    var downloads: Int?
    var manual = false

    var interactions: Int { (likes ?? 0) + (comments ?? 0) + (shares ?? 0) }
    func sameCounts(_ o: StatSnapshot) -> Bool {
        views == o.views && likes == o.likes && comments == o.comments && shares == o.shares && downloads == o.downloads
    }
}

/// Plateforme déduite du lien de la publication (sinon du type de canal).
enum StatPlatform: String, CaseIterable, Identifiable, Codable {
    case youtube, reddit, bluesky, github, nexus, site, instagram, facebook, discord, x, other
    var id: String { rawValue }
    var label: String { L.t("stats.platform.\(rawValue)") }
    /// Relevé automatique possible (les autres se saisissent à la main).
    var automatic: Bool { [.youtube, .reddit, .bluesky, .github, .nexus, .site].contains(self) }
    var symbol: String {
        switch self {
        case .youtube: "play.rectangle"
        case .reddit: "bubble.left.and.bubble.right"
        case .bluesky, .x: "at"
        case .github: "chevron.left.forwardslash.chevron.right"
        case .nexus: "shippingbox"
        case .site: "globe"
        case .instagram: "camera"
        case .facebook: "person.2"
        case .discord: "message"
        case .other: "megaphone"
        }
    }

    static func detect(link: String, channel: ChannelKind?, site: String) -> StatPlatform {
        let t = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if let host = URL(string: t.contains("://") ? t : "https://\(t)")?.host?.lowercased(), !t.isEmpty {
            let h = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            if h.hasSuffix("youtube.com") || h == "youtu.be" { return .youtube }
            if h.hasSuffix("reddit.com") || h == "redd.it" { return .reddit }
            if h == "bsky.app" { return .bluesky }
            if h == "github.com" { return .github }
            if h.hasSuffix("nexusmods.com") { return .nexus }
            if h.hasSuffix("instagram.com") { return .instagram }
            if h.hasSuffix("facebook.com") || h == "fb.watch" { return .facebook }
            if h.hasSuffix("discord.com") || h.hasSuffix("discord.gg") { return .discord }
            if h == "x.com" || h.hasSuffix("twitter.com") { return .x }
            if !site.isEmpty, h == site.lowercased() || h.hasSuffix("." + site.lowercased()) { return .site }
            return .other   // lien vers un site inconnu : chiffres à saisir à la main
        }
        switch channel {
        case .youtube: return .youtube
        case .reddit: return .reddit
        case .bluesky: return .bluesky
        case .github: return .github
        case .nexus: return .nexus
        case .instagram: return .instagram
        case .discord: return .discord
        case .x: return .x
        default: return .other
        }
    }
}

/// Références extraites des liens (identifiant de vidéo, de post, de dépôt…).
enum StatLink {
    static func url(_ s: String) -> URL? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : URL(string: t.contains("://") ? t : "https://\(t)")
    }

    static func youtubeID(_ s: String) -> String? {
        guard let u = url(s), let host = u.host?.lowercased() else { return nil }
        let parts = u.path.split(separator: "/").map(String.init)
        if host.hasSuffix("youtu.be") { return parts.first }
        if let v = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value { return v }
        if parts.count >= 2, ["shorts", "live", "embed"].contains(parts[0]) { return parts[1] }
        return nil
    }

    static func redditID(_ s: String) -> String? {
        guard let u = url(s), let host = u.host?.lowercased() else { return nil }
        let parts = u.path.split(separator: "/").map(String.init)
        if host.hasSuffix("redd.it") { return parts.first }
        if let i = parts.firstIndex(of: "comments"), i + 1 < parts.count { return parts[i + 1] }
        return nil
    }

    /// (identifiant ou handle, clé du post) pour bsky.app/profile/<handle>/post/<clé>.
    static func bluesky(_ s: String) -> (String, String)? {
        guard let u = url(s) else { return nil }
        let p = u.path.split(separator: "/").map(String.init)
        guard p.count >= 4, p[0] == "profile", p[2] == "post" else { return nil }
        return (p[1], p[3])
    }

    /// (propriétaire/dépôt, tag de release éventuel).
    static func github(_ s: String) -> (String, String?)? {
        guard let u = url(s) else { return nil }
        let p = u.path.split(separator: "/").map(String.init)
        guard p.count >= 2 else { return nil }
        let tag = p.count >= 5 && p[2] == "releases" && p[3] == "tag" ? p[4] : nil
        return ("\(p[0])/\(p[1])", tag)
    }

    static func nexus(_ s: String) -> String? { WatchItem.parse(s).flatMap { $0.0 == .nexus ? $0.1 : nil } }

    /// Chemin de la page pour le compteur GoatCounter (« TOTAL » pour tout le site).
    static func sitePath(_ s: String) -> String {
        guard let u = url(s) else { return "TOTAL" }
        let p = u.path.isEmpty ? "/" : u.path
        return p
    }
}

/// Nettoyage des réglages saisis : « https://www.monsite.com/ » → « monsite.com » ; « https://code.goatcounter.com » → « code ».
enum SiteInput {
    static func domain(_ s: String) -> String? {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let h = URL(string: t.contains("://") ? t : "https://\(t)")?.host { t = h }
        if t.hasPrefix("www.") { t.removeFirst(4) }
        return t.isEmpty ? nil : t
    }
    static func goatcounter(_ s: String) -> String? {
        guard var t = domain(s) else { return nil }
        if t.hasSuffix(".goatcounter.com") { t = String(t.dropLast(".goatcounter.com".count)) }
        return t.isEmpty ? nil : t
    }
}

// MARK: Lecture des compteurs

struct StatKeys {
    var youtube = ""
    var nexus = ""
    var goatcounter = ""   // code du site GoatCounter (sous-domaine), pas un secret
}

enum StatsFetcher {
    static func fetch(_ link: String, platform: StatPlatform, keys: StatKeys) async -> Result<StatSnapshot, WatchError> {
        switch platform {
        case .youtube:
            guard let id = StatLink.youtubeID(link) else { return .failure(WatchError(message: L.t("stats.err.link"))) }
            return await youtube([id], key: keys.youtube).flatMap { r in r[id].map { .success($0) } ?? .failure(WatchError(message: L.t("stats.err.notfound"))) }
        case .reddit:
            guard let id = StatLink.redditID(link) else { return .failure(WatchError(message: L.t("stats.err.link"))) }
            return await reddit(id)
        case .bluesky:
            guard let (who, key) = StatLink.bluesky(link) else { return .failure(WatchError(message: L.t("stats.err.link"))) }
            return await bluesky(who, key)
        case .github:
            guard let (repo, tag) = StatLink.github(link) else { return .failure(WatchError(message: L.t("stats.err.link"))) }
            return await github(repo, tag: tag)
        case .nexus:
            guard let ref = StatLink.nexus(link) else { return .failure(WatchError(message: L.t("stats.err.link"))) }
            return await nexus(ref, key: keys.nexus)
        case .site:
            return await site(keys.goatcounter, path: StatLink.sitePath(link))
        default:
            return .failure(WatchError(message: L.t("stats.err.manual")))
        }
    }

    private static func get(_ url: URL, headers: [String: String] = [:]) async -> Result<Any, WatchError> {
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.setValue("hERALD/\(Watcher.version) (statistiques en lecture seule)", forHTTPHeaderField: "User-Agent")
        headers.forEach { r.setValue($1, forHTTPHeaderField: $0) }
        do {
            let (d, resp) = try await URLSession.shared.data(for: r)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else { return .failure(WatchError(message: L.t("watch.http", code))) }
            guard let j = try? JSONSerialization.jsonObject(with: d) else { return .failure(WatchError(message: L.t("watch.parse"))) }
            return .success(j)
        } catch {
            return .failure(WatchError(message: error.localizedDescription))
        }
    }

    static func int(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s.filter(\.isNumber)) }
        return nil
    }

    /// Jusqu'à 50 vidéos par appel (1 unité de quota YouTube par appel).
    static func youtube(_ ids: [String], key: String) async -> Result<[String: StatSnapshot], WatchError> {
        guard !key.isEmpty else { return .failure(WatchError(message: L.t("stats.err.youtubekey"))) }
        var c = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
        c.queryItems = [.init(name: "part", value: "statistics"), .init(name: "id", value: ids.joined(separator: ",")), .init(name: "key", value: key)]
        return await get(c.url!).flatMap { j in
            guard let items = (j as? [String: Any])?["items"] as? [[String: Any]] else { return .failure(WatchError(message: L.t("watch.parse"))) }
            var out: [String: StatSnapshot] = [:]
            for it in items {
                guard let id = it["id"] as? String, let s = it["statistics"] as? [String: Any] else { continue }
                out[id] = StatSnapshot(views: int(s["viewCount"]), likes: int(s["likeCount"]), comments: int(s["commentCount"]))
            }
            return .success(out)
        }
    }

    static func reddit(_ id: String) async -> Result<StatSnapshot, WatchError> {
        guard let url = URL(string: "https://www.reddit.com/comments/\(id).json?limit=1&raw_json=1") else { return .failure(WatchError(message: L.t("stats.err.link"))) }
        return await get(url).flatMap { j in
            guard let arr = j as? [[String: Any]], let listing = arr.first?["data"] as? [String: Any],
                  let child = (listing["children"] as? [[String: Any]])?.first?["data"] as? [String: Any] else {
                return .failure(WatchError(message: L.t("watch.parse")))
            }
            return .success(StatSnapshot(likes: int(child["score"]), comments: int(child["num_comments"]),
                                         shares: int(child["num_crossposts"])))
        }
    }

    static func bluesky(_ who: String, _ key: String) async -> Result<StatSnapshot, WatchError> {
        var did = who
        if !who.hasPrefix("did:") {
            var c = URLComponents(string: "https://public.api.bsky.app/xrpc/com.atproto.identity.resolveHandle")!
            c.queryItems = [.init(name: "handle", value: who)]
            switch await get(c.url!) {
            case .failure(let e): return .failure(e)
            case .success(let j):
                guard let d = (j as? [String: Any])?["did"] as? String else { return .failure(WatchError(message: L.t("watch.parse"))) }
                did = d
            }
        }
        var c = URLComponents(string: "https://public.api.bsky.app/xrpc/app.bsky.feed.getPosts")!
        c.queryItems = [.init(name: "uris", value: "at://\(did)/app.bsky.feed.post/\(key)")]
        return await get(c.url!).flatMap { j in
            guard let p = ((j as? [String: Any])?["posts"] as? [[String: Any]])?.first else { return .failure(WatchError(message: L.t("stats.err.notfound"))) }
            let shares = (int(p["repostCount"]) ?? 0) + (int(p["quoteCount"]) ?? 0)
            return .success(StatSnapshot(likes: int(p["likeCount"]), comments: int(p["replyCount"]), shares: shares))
        }
    }

    static func github(_ repo: String, tag: String?) async -> Result<StatSnapshot, WatchError> {
        let h = ["Accept": "application/vnd.github+json"]
        guard let repoURL = URL(string: "https://api.github.com/repos/\(repo)") else { return .failure(WatchError(message: L.t("stats.err.link"))) }
        var stars: Int?
        if case .success(let j) = await get(repoURL, headers: h) { stars = int((j as? [String: Any])?["stargazers_count"]) }
        let path = tag.map { "releases/tags/\($0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0)" } ?? "releases?per_page=100"
        guard let relURL = URL(string: "https://api.github.com/repos/\(repo)/\(path)") else { return .failure(WatchError(message: L.t("stats.err.link"))) }
        return await get(relURL, headers: h).flatMap { j in
            let rels: [[String: Any]] = (j as? [[String: Any]]) ?? ((j as? [String: Any]).map { [$0] } ?? [])
            let dl = rels.flatMap { ($0["assets"] as? [[String: Any]]) ?? [] }.reduce(0) { $0 + (int($1["download_count"]) ?? 0) }
            return .success(StatSnapshot(likes: stars, downloads: dl))
        }
    }

    static func nexus(_ ref: String, key: String) async -> Result<StatSnapshot, WatchError> {
        guard !key.isEmpty else { return .failure(WatchError(message: L.t("watch.nokey"))) }
        let p = ref.split(separator: "/")
        guard p.count == 2, let url = URL(string: "https://api.nexusmods.com/v1/games/\(p[0])/mods/\(p[1]).json") else {
            return .failure(WatchError(message: L.t("stats.err.link")))
        }
        let h = ["apikey": key, "Application-Name": "hERALD", "Application-Version": Watcher.version, "Accept": "application/json"]
        return await get(url, headers: h).flatMap { j in
            guard let m = j as? [String: Any] else { return .failure(WatchError(message: L.t("watch.parse"))) }
            return .success(StatSnapshot(likes: int(m["endorsement_count"]), downloads: int(m["mod_downloads"])))
        }
    }

    /// Compteur public GoatCounter (option « Allow adding visitor counts on your website » activée côté GoatCounter).
    static func site(_ code: String, path: String) async -> Result<StatSnapshot, WatchError> {
        guard !code.isEmpty else { return .failure(WatchError(message: L.t("stats.err.goatcounter"))) }
        let p = path == "TOTAL" ? "TOTAL" : (path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? path)
        guard let url = URL(string: "https://\(code).goatcounter.com/counter/\(p).json") else { return .failure(WatchError(message: L.t("stats.err.link"))) }
        return await get(url).flatMap { j in
            guard let n = int((j as? [String: Any])?["count"]) else { return .failure(WatchError(message: L.t("watch.parse"))) }
            return .success(StatSnapshot(views: n))
        }
    }
}

// MARK: Historique

enum StatHistory {
    /// Ajoute un relevé ; un relevé identique au précédent et récent (< 23 h) ne fait que rafraîchir la date.
    static func append(_ s: StatSnapshot, to h: inout [StatSnapshot], limit: Int = 600) {
        if let last = h.last, !s.manual, !last.manual, last.sameCounts(s), s.date.timeIntervalSince(last.date) < 23 * 3600,
           h.count >= 2, h[h.count - 2].sameCounts(s) {
            h[h.count - 1].date = s.date
        } else {
            h.append(s)
        }
        h.sort { $0.date < $1.date }
        if h.count > limit { h.removeFirst(h.count - limit) }
    }

    /// Dernier relevé connu à une date (nil s'il n'y en a pas encore).
    static func at(_ d: Date, _ h: [StatSnapshot]) -> StatSnapshot? { h.last { $0.date <= d } }
}

// MARK: Cumul et rapport

enum StatsPeriod: String, CaseIterable, Identifiable {
    case campaign, day, week
    var id: String { rawValue }
    var label: String { L.t("stats.period.\(rawValue)") }
    func start(_ now: Date) -> Date? {
        switch self {
        case .campaign: nil
        case .day: now.addingTimeInterval(-86400)
        case .week: now.addingTimeInterval(-7 * 86400)
        }
    }
}

struct StatsSummary {
    struct Row: Identifiable {
        let post: Post
        let platform: StatPlatform
        let latest: StatSnapshot?
        let delta: StatSnapshot     // évolution sur la période choisie
        let growth24h: Int          // vues (ou interactions) gagnées en 24 h
        var id: UUID { post.id }
        /// Valeur de tri : vues si connues, sinon interactions, sinon téléchargements.
        var weight: Int { latest?.views ?? latest.map { $0.interactions } ?? latest?.downloads ?? 0 }
    }
    struct PlatformTotal: Identifiable { let platform: StatPlatform; let views: Int; let interactions: Int; let downloads: Int; var id: String { platform.rawValue } }
    struct Point: Identifiable { let date: Date; let platform: StatPlatform; let views: Int; var id: String { "\(platform.rawValue)-\(date.timeIntervalSince1970)" } }

    let period: StatsPeriod
    let rows: [Row]
    let views: Int
    let interactions: Int
    let downloads: Int
    let siteVisits: Int?
    let siteDelta: Int?
    let platforms: [PlatformTotal]
    let curve: [Point]
    let missingLinks: [Post]       // publiés mais sans lien : aucun relevé possible
    let stale: [Row]               // relevé manuel vieux de plus de 24 h

    init(campaign: Campaign, data: AppData, platform: (Post) -> StatPlatform, period: StatsPeriod, now: Date = Date()) {
        self.period = period
        let start = period.start(now)
        func diff(_ a: Int?, _ b: Int?) -> Int? { a.map { $0 - (b ?? 0) } }
        var rows: [Row] = []
        for p in campaign.posts {
            let h = p.stats ?? []
            guard !h.isEmpty else { continue }
            let last = h.last
            let base = start.flatMap { StatHistory.at($0, h) }
            var d = last ?? StatSnapshot()
            if start != nil {
                d = StatSnapshot(date: now, views: diff(last?.views, base?.views), likes: diff(last?.likes, base?.likes),
                                 comments: diff(last?.comments, base?.comments), shares: diff(last?.shares, base?.shares),
                                 downloads: diff(last?.downloads, base?.downloads))
            }
            let day = StatHistory.at(now.addingTimeInterval(-86400), h)
            let g = last?.views != nil ? (last!.views! - (day?.views ?? 0)) : ((last?.interactions ?? 0) - (day?.interactions ?? 0))
            rows.append(Row(post: p, platform: platform(p), latest: last, delta: d, growth24h: g))
        }
        self.rows = rows.sorted { $0.weight > $1.weight }
        views = rows.reduce(0) { $0 + ($1.delta.views ?? 0) }
        interactions = rows.reduce(0) { $0 + $1.delta.interactions }
        downloads = rows.reduce(0) { $0 + ($1.delta.downloads ?? 0) }
        let site = data.siteStats ?? []
        siteVisits = site.last?.views
        siteDelta = start.flatMap { s in site.last?.views.map { $0 - (StatHistory.at(s, site)?.views ?? 0) } }
        platforms = StatPlatform.allCases.compactMap { pl in
            let r = rows.filter { $0.platform == pl }
            guard !r.isEmpty else { return nil }
            return PlatformTotal(platform: pl, views: r.reduce(0) { $0 + ($1.delta.views ?? 0) },
                                 interactions: r.reduce(0) { $0 + $1.delta.interactions },
                                 downloads: r.reduce(0) { $0 + ($1.delta.downloads ?? 0) })
        }
        // Courbe : vues cumulées par plateforme, un point par jour (fin de journée), du premier relevé à maintenant.
        var pts: [Point] = []
        let cal = Calendar.current
        let first = rows.compactMap { $0.post.stats?.first?.date }.min()
        if let first {
            var day = cal.startOfDay(for: max(first, start ?? first))
            let viewed = Set(rows.filter { $0.latest?.views != nil }.map(\.platform))
            while day <= now {
                let end = min(now, cal.date(byAdding: .day, value: 1, to: day)!.addingTimeInterval(-1))
                for pl in StatPlatform.allCases where viewed.contains(pl) {
                    let v = rows.filter { $0.platform == pl }.reduce(0) { $0 + (StatHistory.at(end, $1.post.stats ?? [])?.views ?? 0) }
                    pts.append(Point(date: end, platform: pl, views: v))
                }
                if !site.isEmpty, let v = StatHistory.at(end, site)?.views { pts.append(Point(date: end, platform: .site, views: v)) }
                day = cal.date(byAdding: .day, value: 1, to: day)!
            }
        }
        curve = pts
        missingLinks = campaign.posts.filter { $0.status == .published && $0.link.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.date < $1.date }
        stale = rows.filter { !$0.platform.automatic && ($0.latest?.date ?? .distantPast) < now.addingTimeInterval(-86400) }
    }

    var best: Row? { rows.max { $0.growth24h < $1.growth24h }.flatMap { $0.growth24h > 0 ? $0 : nil } }

    func markdown(title: String, now: Date = Date()) -> String {
        func n(_ v: Int?) -> String { v.map(L.number) ?? "—" }
        var s = "# \(L.t("stats.report.title", title))\n\(L.t("stats.report.when", L.date(now), period.label))\n\n"
        s += "- \(L.t("stats.kpi.views")) : \(L.number(views))\n- \(L.t("stats.kpi.interactions")) : \(L.number(interactions))\n"
        s += "- \(L.t("stats.kpi.downloads")) : \(L.number(downloads))\n- \(L.t("stats.kpi.site")) : \(n(siteVisits))\n\n"
        s += "## \(L.t("stats.report.platforms"))\n"
        s += platforms.map { "- \($0.platform.label) : \(L.number($0.views)) \(L.t("stats.col.views").lowercased()), \(L.number($0.interactions)) \(L.t("stats.kpi.interactions").lowercased()), \(L.number($0.downloads)) \(L.t("stats.kpi.downloads").lowercased())" }
            .joined(separator: "\n") + "\n\n"
        s += "## \(L.t("stats.report.posts"))\n"
        s += "| \(L.t("stats.col.post")) | \(L.t("stats.col.views")) | \(L.t("stats.col.likes")) | \(L.t("stats.col.comments")) | \(L.t("stats.col.shares")) | \(L.t("stats.col.downloads")) | 24 h |\n|---|---:|---:|---:|---:|---:|---:|\n"
        for r in rows {
            s += "| \(r.platform.label) · \(r.post.title) | \(n(r.delta.views)) | \(n(r.delta.likes)) | \(n(r.delta.comments)) | \(n(r.delta.shares)) | \(n(r.delta.downloads)) | \(r.growth24h >= 0 ? "+" : "")\(L.number(r.growth24h)) |\n"
        }
        if let b = best { s += "\n\(L.t("stats.best", b.post.title, L.number(b.growth24h)))\n" }
        if !missingLinks.isEmpty { s += "\n\(L.t("stats.missing.title")) : " + missingLinks.map(\.title).joined(separator: ", ") + "\n" }
        return s
    }
}
