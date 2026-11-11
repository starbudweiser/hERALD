// hERALD — accès à treg (treg.to), catalogue d'outils payés à l'appel : lecture de Reddit sans clé d'API Reddit
// (chiffres et réponses de nos posts, veille par mots-clés). Le jeton d'équipe reste dans le trousseau.
import Foundation

enum Treg {
    static var token: String { Keychain.get("treg.token").trimmingCharacters(in: .whitespacesAndNewlines) }
    static var available: Bool { !token.isEmpty }

    /// Appel GET d'un outil du catalogue ; renvoie le JSON du fournisseur et le coût en dollars.
    static func call(_ id: String, _ query: [String: String]) async -> Result<(Any, Double), WatchError> {
        let t = token
        guard !t.isEmpty else { return .failure(WatchError(message: L.t("treg.err.notoken"))) }
        var c = URLComponents(string: "https://treg.to/call/\(id)")!
        c.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = c.url else { return .failure(WatchError(message: L.t("watch.invalid"))) }
        var r = URLRequest(url: url, timeoutInterval: 45)
        r.setValue(t, forHTTPHeaderField: "X-Treg-Token")
        r.setValue("hERALD/\(Watcher.version)", forHTTPHeaderField: "User-Agent")
        do {
            let (d, resp) = try await URLSession.shared.data(for: r)
            let h = resp as? HTTPURLResponse
            let code = h?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                return .failure(WatchError(message: code == 401 || code == 403 ? L.t("treg.err.token") : code == 402 ? L.t("treg.err.balance") : L.t("watch.http", code)))
            }
            guard let j = try? JSONSerialization.jsonObject(with: d) else { return .failure(WatchError(message: L.t("watch.parse"))) }
            let cost = Double(h?.value(forHTTPHeaderField: "X-Treg-Cost-Micro") ?? "").map { $0 / 1_000_000 } ?? 0
            Treg.addSpent(cost)
            return .success((j, cost))
        } catch {
            return .failure(WatchError(message: error.localizedDescription))
        }
    }

    /// Total dépensé par cette appli (affiché dans les Réglages).
    static var spent: Double { UserDefaults.standard.double(forKey: "treg.spent") }
    private static func addSpent(_ v: Double) { UserDefaults.standard.set(spent + v, forKey: "treg.spent") }

    // MARK: Reddit

    /// Un post Reddit (le nôtre) : compteurs et réponses, en un seul appel.
    static func redditPost(_ link: String) async -> Result<(StatSnapshot, [Feedback]), WatchError> {
        let url = link.trimmingCharacters(in: .whitespacesAndNewlines)
        return await call("scrapecreators.x.v1-reddit-post-comments", ["url": url]).flatMap { j, _ in
            guard let o = j as? [String: Any], let post = o["post"] as? [String: Any] else { return .failure(WatchError(message: L.t("watch.parse"))) }
            let op = post["author"] as? String ?? ""
            let snap = StatSnapshot(likes: StatsFetcher.int(post["score"]), comments: StatsFetcher.int(post["num_comments"]),
                                    shares: StatsFetcher.int(post["num_crossposts"]))
            var out: [Feedback] = []
            func walk(_ v: Any?) {
                let list = (v as? [[String: Any]]) ?? ((v as? [String: Any])?["items"] as? [[String: Any]]) ?? []
                for d in list {
                    let author = d["author"] as? String ?? ""
                    let body = (d["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let name = (d["name"] as? String) ?? (d["id"] as? String).map { "t1_\($0)" } ?? ""
                    if !name.isEmpty, author != op, author != "[deleted]", !body.isEmpty, body != "[deleted]", body != "[removed]" {
                        let created = StatsFetcher.int(d["created_utc"]).map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
                        let link = (d["url"] as? String) ?? (d["permalink"] as? String).map { "https://www.reddit.com\($0)" }
                        out.append(Feedback(date: created, kind: .comment, value: 1, text: body,
                                            author: author, url: link, source: "reddit:\(name)", unread: true))
                    }
                    walk(d["replies"])
                }
            }
            walk(o["comments"])
            return .success((snap, out))
        }
    }

    /// Recherche Reddit par mots-clés (posts du dernier mois, par pertinence).
    static func redditSearch(_ query: String) async -> Result<[Mention], WatchError> {
        await call("scrapecreators.reddit.search.posts", ["query": query, "sort": "relevance", "timeframe": "month", "trim": "true"]).flatMap { j, _ in
            guard let posts = (j as? [String: Any])?["posts"] as? [[String: Any]] else { return .failure(WatchError(message: L.t("watch.parse"))) }
            let out: [Mention] = posts.compactMap { p in
                guard let id = p["id"] as? String, let title = p["title"] as? String else { return nil }
                let url = (p["url"] as? String) ?? (p["permalink"] as? String).map { "https://www.reddit.com\($0)" } ?? ""
                let date = StatsFetcher.int(p["created_utc"]).map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
                return Mention(id: "reddit:\(id)", date: date, title: title, place: p["subreddit"] as? String ?? "",
                               author: p["author"] as? String ?? "", url: url,
                               score: StatsFetcher.int(p["score"]), comments: StatsFetcher.int(p["num_comments"]))
            }
            return .success(out)
        }
    }
}

// MARK: Veille par mots-clés (Reddit, YouTube)

#if canImport(AppKit)
import UserNotifications

@MainActor
extension Store {
    /// Une fois par jour, relève les veilles par mots-clés : Reddit par treg (~0,002 $ le mot-clé),
    /// YouTube par l'API officielle avec la clé des Réglages (gratuit, ~100 unités de quota par recherche).
    func refreshKeywordWatchIfDue() async {
        guard !checking else { return }
        let ytKey = !Keychain.get("youtube").isEmpty
        let due = data.watch.filter { w in
            w.isKeyword && (w.kind == .reddit ? Treg.available : ytKey)
                && (w.lastChecked ?? .distantPast) < Date().addingTimeInterval(-86400 + 60)
        }
        guard !due.isEmpty else { return }
        var fresh: [(WatchKind, Mention)] = []
        for w in due { fresh += await checkKeywordWatch(w.id).map { (w.kind, $0) } }
        notifyMentions(fresh)
    }

    /// Relève une veille par mots-clés ; renvoie les mentions nouvelles (marquées non lues). La première relève ne marque
    /// rien comme nouveau : elle constitue l'état de départ.
    @discardableResult
    func checkKeywordWatch(_ id: UUID) async -> [Mention] {
        guard let item = data.watch.first(where: { $0.id == id }) else { return [] }
        let result = item.kind == .youtube ? await StatsFetcher.youtubeSearch(item.ref, key: Keychain.get("youtube"))
                                           : await Treg.redditSearch(item.ref)
        guard let i = data.watch.firstIndex(where: { $0.id == id }) else { return [] }
        let first = data.watch[i].mentions == nil
        data.watch[i].lastChecked = Date()
        switch result {
        case .failure(let e):
            data.watch[i].error = e.message
            return []
        case .success(let found):
            data.watch[i].error = nil
            var list = data.watch[i].mentions ?? []
            let known = Set(list.map(\.id))
            var fresh: [Mention] = []
            for var m in found {
                if let k = list.firstIndex(where: { $0.id == m.id }) {
                    list[k].score = m.score; list[k].comments = m.comments; list[k].views = m.views   // compteurs à jour
                } else if !known.contains(m.id) {
                    m.unread = !first
                    list.append(m)
                    if !first { fresh.append(m) }
                }
            }
            list.sort { $0.date > $1.date }
            if list.count > 300 { list.removeLast(list.count - 300) }
            data.watch[i].mentions = list
            data.watch[i].history.append(WatchSnapshot(version: L.t(item.kind == .youtube ? "watch.youtube.count" : "watch.reddit.count", list.count),
                                                       title: list.first?.title ?? ""))
            if data.watch[i].history.count > 200 { data.watch[i].history.removeFirst() }
            return fresh
        }
    }

    func markMentionsRead(_ id: UUID) {
        guard let i = data.watch.firstIndex(where: { $0.id == id }), data.watch[i].unreadMentions > 0 else { return }
        for k in data.watch[i].mentions!.indices { data.watch[i].mentions![k].unread = false }
    }

    private func notifyMentions(_ fresh: [(WatchKind, Mention)]) {
        guard !fresh.isEmpty, Bundle.main.bundleIdentifier != nil else { return }
        let yt = fresh.allSatisfy { $0.0 == .youtube }, rd = fresh.allSatisfy { $0.0 == .reddit }
        let body = fresh.count == 1
            ? L.t(yt ? "notif.mention.yt.body" : "notif.mention.body", fresh[0].1.place, fresh[0].1.title)
            : L.t(yt ? "notif.mention.yt.many" : rd ? "notif.mention.many" : "notif.mention.mixed", fresh.count)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            let c = UNMutableNotificationContent()
            c.title = L.t(yt ? "notif.mention.yt.title" : "notif.mention.title"); c.body = body; c.sound = .default
            center.add(UNNotificationRequest(identifier: "mention-\(UUID().uuidString)", content: c, trigger: nil))
        }
    }
}
#endif
