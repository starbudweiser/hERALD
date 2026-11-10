// hERALD — suivi des applis d'un compte GitHub listées sur OpenMacApps (https://openmacapps.com) : présence de la
// fiche, mise en avant, visites venues d'openmacapps.com (trafic GitHub, fenêtre de 14 jours cumulée jour après jour)
// et téléchargements des releases. Lecture seule, une fois par jour, en arrière-plan.
import Foundation

/// Fenêtre « 14 derniers jours » des visites venues d'OpenMacApps, telle que relevée un jour donné.
struct OMAVisit: Codable, Hashable {
    var date: Date
    var count: Int
    var uniques: Int
}

/// Une appli du compte suivi, telle que connue d'après le catalogue et GitHub.
struct OMAApp: Codable, Hashable, Identifiable {
    var slug: String
    var name: String
    var repo: String               // propriétaire/dépôt
    var category: String?
    var featured = false
    var verified: String?
    var added: String?
    var icon: String?              // chemin de l'icône sur openmacapps.com
    var listed = true              // false : la fiche a disparu du catalogue
    var visits: [OMAVisit] = []
    var downloads: Int?
    var peakNotified = false
    var error: String?
    var id: String { slug }

    var page: URL? { URL(string: "https://openmacapps.com/apps/\(slug)/") }
    var iconURL: URL? { icon.flatMap { $0.hasPrefix("http") ? URL(string: $0) : URL(string: "https://openmacapps.com" + ($0.hasPrefix("/") ? $0 : "/" + $0)) } }
    var window: Int { visits.last?.count ?? 0 }
    var windowUniques: Int { visits.last?.uniques ?? 0 }
    var cumulative: Int { OMA.cumulative(visits, \.count) }
    var cumulativeUniques: Int { OMA.cumulative(visits, \.uniques) }
}

struct OMAState: Codable {
    var owner: String?             // compte GitHub suivi (sinon celui du jeton)
    var apps: [OMAApp] = []
    var checked: Date?
    var error: String?
}

/// Entrée du catalogue public (seuls les champs utiles ; les autres sont ignorés).
struct OMACatalogEntry: Decodable {
    var name: String
    var slug: String?
    var id: String?
    var repository: String?
    var category: String?
    var featured: Bool?
    var verified: String?
    var added: String?
    var iconUrl: String?
}

enum OMAEvent: Equatable {
    case listed(String), featured(String), removed(String), peak(String, Int)

    var text: String {
        switch self {
        case .listed(let n): L.t("oma.notif.listed", n)
        case .featured(let n): L.t("oma.notif.featured", n)
        case .removed(let n): L.t("oma.notif.removed", n)
        case .peak(let n, let c): L.t("oma.notif.peak", n, c)
        }
    }
}

enum OMA {
    static let catalogURL = URL(string: "https://openmacapps.com/catalog.json")!
    /// Premier « pic » : la fenêtre de 14 jours atteint ce nombre de visites pour la première fois.
    static let peakThreshold = 10

    static func decodeCatalog(_ d: Data) throws -> [OMACatalogEntry] {
        try JSONDecoder().decode([OMACatalogEntry].self, from: d)
    }

    /// « https://github.com/Owner/Repo(.git)(/…) » → « Owner/Repo » si le propriétaire est celui demandé.
    static func repo(_ s: String?, owner: String) -> String? {
        guard let s, let u = URL(string: s), let h = u.host?.lowercased(), h == "github.com" || h == "www.github.com" else { return nil }
        let p = u.path.split(separator: "/").map(String.init)
        guard p.count >= 2, p[0].lowercased() == owner.lowercased() else { return nil }
        var r = p[1]
        if r.hasSuffix(".git") { r.removeLast(4) }
        return "\(p[0])/\(r)"
    }

    /// Cumul estimé d'une suite de fenêtres glissantes de 14 jours : la première fenêtre, puis chaque hausse d'un relevé
    /// au suivant (ou toute la fenêtre si 14 jours ou plus se sont écoulés : elle ne recoupe plus la précédente).
    static func cumulative(_ v: [OMAVisit], _ k: KeyPath<OMAVisit, Int>) -> Int {
        guard let first = v.first else { return 0 }
        var total = first[keyPath: k]
        for i in v.indices.dropFirst() {
            let gap = v[i].date.timeIntervalSince(v[i - 1].date)
            total += gap >= 14 * 86400 ? v[i][keyPath: k] : max(0, v[i][keyPath: k] - v[i - 1][keyPath: k])
        }
        return total
    }

    /// Ajoute le relevé du jour (remplace celui du même jour), historique limité à ~2 ans.
    static func record(_ s: OMAVisit, into v: inout [OMAVisit], calendar: Calendar = .current) {
        if let last = v.last, calendar.isDate(last.date, inSameDayAs: s.date) { v[v.count - 1] = s } else { v.append(s) }
        v.sort { $0.date < $1.date }
        if v.count > 800 { v.removeFirst(v.count - 800) }
    }

    /// Visites venues d'openmacapps.com dans la réponse de traffic/popular/referrers.
    static func referrer(_ json: Any) -> (Int, Int) {
        let rows = json as? [[String: Any]] ?? []
        let r = rows.filter { (($0["referrer"] as? String) ?? "").lowercased().hasSuffix("openmacapps.com") }
        return (r.reduce(0) { $0 + (StatsFetcher.int($1["count"]) ?? 0) }, r.reduce(0) { $0 + (StatsFetcher.int($1["uniques"]) ?? 0) })
    }

    /// Somme des téléchargements de tous les fichiers de toutes les releases.
    static func downloads(_ json: Any) -> Int {
        (json as? [[String: Any]] ?? []).flatMap { ($0["assets"] as? [[String: Any]]) ?? [] }
            .reduce(0) { $0 + (StatsFetcher.int($1["download_count"]) ?? 0) }
    }

    /// Fusionne le catalogue du jour avec les applis connues ; renvoie les événements notables.
    static func merge(_ old: [OMAApp], catalog: [OMACatalogEntry], owner: String) -> ([OMAApp], [OMAEvent]) {
        var apps = old
        var events: [OMAEvent] = []
        var seen = Set<String>()
        for e in catalog {
            guard let repo = repo(e.repository, owner: owner), let slug = e.slug ?? e.id else { continue }
            seen.insert(slug)
            if let i = apps.firstIndex(where: { $0.slug == slug }) {
                if !apps[i].listed { events.append(.listed(e.name)) }
                if e.featured == true && !apps[i].featured { events.append(.featured(e.name)) }
                apps[i].name = e.name; apps[i].repo = repo; apps[i].category = e.category
                apps[i].featured = e.featured ?? false; apps[i].verified = e.verified; apps[i].added = e.added
                apps[i].icon = e.iconUrl; apps[i].listed = true
            } else {
                // Première fois : pas d'événement pour les fiches déjà là au premier relevé (sauf mise en avant).
                if !old.isEmpty { events.append(.listed(e.name)) }
                if e.featured == true { events.append(.featured(e.name)) }
                apps.append(OMAApp(slug: slug, name: e.name, repo: repo, category: e.category, featured: e.featured ?? false,
                                   verified: e.verified, added: e.added, icon: e.iconUrl))
            }
        }
        for i in apps.indices where !seen.contains(apps[i].slug) && apps[i].listed {
            apps[i].listed = false; apps[i].featured = false
            events.append(.removed(apps[i].name))
        }
        return (apps, events)
    }

    /// Premier pic de visites (une seule fois par appli).
    static func peak(_ app: inout OMAApp) -> OMAEvent? {
        guard !app.peakNotified, app.window >= peakThreshold else { return nil }
        app.peakNotified = true
        return .peak(app.name, app.window)
    }

    /// Tri : visites des 14 jours, puis cumul, puis téléchargements, puis nom.
    static func sorted(_ a: [OMAApp]) -> [OMAApp] {
        a.sorted {
            ($0.window, $0.cumulative, $0.downloads ?? 0) != ($1.window, $1.cumulative, $1.downloads ?? 0)
                ? ($0.window, $0.cumulative, $0.downloads ?? 0) > ($1.window, $1.cumulative, $1.downloads ?? 0)
                : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    // MARK: Réseau

    static func get(_ url: URL, token: String) async -> Result<Any, WatchError> {
        var r = URLRequest(url: url, timeoutInterval: 30)
        r.setValue("hERALD/\(Watcher.version) (read-only stats)", forHTTPHeaderField: "User-Agent")
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        r.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if !token.isEmpty { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            let (d, resp) = try await URLSession.shared.data(for: r)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                return .failure(WatchError(message: code == 401 ? L.t("oma.err.token") : code == 403 ? L.t("oma.err.forbidden") : L.t("watch.http", code)))
            }
            guard let j = try? JSONSerialization.jsonObject(with: d) else { return .failure(WatchError(message: L.t("watch.parse"))) }
            return .success(j)
        } catch {
            return .failure(WatchError(message: error.localizedDescription))
        }
    }

    static func catalog() async -> Result<[OMACatalogEntry], WatchError> {
        var r = URLRequest(url: catalogURL, timeoutInterval: 60)
        r.setValue("hERALD/\(Watcher.version) (read-only stats)", forHTTPHeaderField: "User-Agent")
        do {
            let (d, resp) = try await URLSession.shared.data(for: r)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else { return .failure(WatchError(message: L.t("watch.http", code))) }
            let c = try decodeCatalog(d)
            // Garde-fou : un catalogue presque vide est une panne du site, pas un retrait de toutes les fiches.
            guard c.count >= 100 else { return .failure(WatchError(message: L.t("watch.parse"))) }
            return .success(c)
        } catch {
            return .failure(WatchError(message: error.localizedDescription))
        }
    }

    /// Compte du jeton (pour suivre ses propres applis sans rien saisir).
    static func login(token: String) async -> String? {
        guard !token.isEmpty, case .success(let j) = await get(URL(string: "https://api.github.com/user")!, token: token) else { return nil }
        return (j as? [String: Any])?["login"] as? String
    }

    /// Jeton de l'outil gh (proposé dans les Réglages) ; jamais affiché.
    static func ghToken() -> String? {
        let paths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        guard let gh = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: gh)
        p.arguments = ["auth", "token"]
        let out = Pipe()
        p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        let t = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return p.terminationStatus == 0 && !t.isEmpty ? t : nil
    }
}

#if canImport(AppKit)
import AppKit
import UserNotifications

extension Store {
    var oma: OMAState { data.oma ?? OMAState() }

    /// Un relevé par jour, depuis la minuterie des statistiques.
    func refreshOMAIfDue() async {
        guard (data.oma?.checked ?? .distantPast) < Date().addingTimeInterval(-86400 + 60) else { return }
        await refreshOMA()
    }

    func refreshOMA() async {
        guard !omaChecking else { return }
        omaChecking = true
        defer { omaChecking = false }
        let token = Keychain.get("github")
        var st = oma
        var owner = (st.owner ?? "").trimmingCharacters(in: .whitespaces)
        if owner.isEmpty, let l = await OMA.login(token: token) { owner = l; st.owner = l }
        guard !owner.isEmpty else { st.error = L.t("oma.err.owner"); data.oma = st; return }
        let now = Date()
        var events: [OMAEvent] = []
        switch await OMA.catalog() {
        case .failure(let e):
            st.error = L.t("oma.err.catalog", e.message)
            data.oma = st
            return
        case .success(let c):
            let (apps, ev) = OMA.merge(st.apps, catalog: c, owner: owner)
            st.apps = apps; events += ev; st.error = nil
        }
        for i in st.apps.indices where st.apps[i].listed {
            let repo = st.apps[i].repo
            var err: String?
            if token.isEmpty {
                // Pas de jeton : signalé une seule fois en tête de la vue, pas sur chaque ligne.
            } else if let u = URL(string: "https://api.github.com/repos/\(repo)/traffic/popular/referrers") {
                switch await OMA.get(u, token: token) {
                case .success(let j):
                    let (c, uq) = OMA.referrer(j)
                    OMA.record(OMAVisit(date: now, count: c, uniques: uq), into: &st.apps[i].visits)
                    if let e = OMA.peak(&st.apps[i]) { events.append(e) }
                case .failure(let e): err = e.message
                }
            }
            if let u = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=100") {
                switch await OMA.get(u, token: token) {
                case .success(let j): st.apps[i].downloads = OMA.downloads(j)
                case .failure(let e): err = err ?? e.message
                }
            }
            st.apps[i].error = err
        }
        st.checked = now
        data.oma = st
        notifyOMA(events)
    }

    private func notifyOMA(_ events: [OMAEvent]) {
        guard !events.isEmpty, Bundle.main.bundleIdentifier != nil else { return }
        let body = events.count == 1 ? events[0].text : events.prefix(4).map(\.text).joined(separator: "\n")
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            let c = UNMutableNotificationContent()
            c.title = L.t("oma.notif.title"); c.body = body; c.sound = .default
            center.add(UNNotificationRequest(identifier: "oma-\(UUID().uuidString)", content: c, trigger: nil))
        }
    }
}
#endif
