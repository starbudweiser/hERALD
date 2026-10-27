// hERALD — état de l'appli : plan en cours, enregistrement, export/import, veille.
// Règle d'or : rien ici n'envoie de contenu nulle part. La seule activité réseau est la lecture
// de pages publiques (versions GitHub, fiche Nexus) pour la veille.
import AppKit
import UniformTypeIdentifiers

@MainActor
final class Store: ObservableObject {
    @Published var data = Storage.load() { didSet { Storage.save(data) } }
    @Published var checking = false
    /// Premier lancement : propose (sans l'imposer) la campagne d'exemple.
    @Published var welcome = !FileManager.default.fileExists(atPath: Storage.url.path)

    /// Dernières lignes du journal de la boîte de dépôt, et résumé du dernier passage (effacé à la lecture).
    @Published var inboxLog = Inbox.readLog()
    @Published var inboxNotice: String?
    private var inboxSource: DispatchSourceFileSystemObject?

    init() {
        if welcome { Storage.save(data) }
    }

    // MARK: Boîte de dépôt

    /// Traite les fichiers déjà présents puis surveille le dossier Inbox tant que l'appli tourne.
    func startInbox() {
        guard inboxSource == nil else { return }
        Inbox.prepare()
        processInbox()
        let fd = open(Inbox.dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        src.setEventHandler { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { Task { @MainActor in self?.processInbox() } }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        inboxSource = src
    }

    func processInbox() {
        var d = data
        let lines = Inbox.process(into: &d, minAge: 1)
        if !lines.isEmpty {
            data = d
            inboxLog = Inbox.readLog()
            let files = lines.filter { !$0.contains("   ") }.count
            inboxNotice = L.t("inbox.notice", files)
        }
        // Fichiers encore en cours d'écriture : nouvel essai un peu plus tard.
        if !Inbox.pending().isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { Task { @MainActor in self.processInbox() } }
        }
    }

    func revealInbox() {
        Inbox.prepare()
        NSWorkspace.shared.open(Inbox.dir)
    }

    // MARK: Campagne affichée

    private var index: Int? {
        data.campaigns.firstIndex { $0.id == data.selected } ?? (data.campaigns.isEmpty ? nil : 0)
    }
    var hasCampaign: Bool { index != nil }

    var campaign: Campaign {
        get { index.map { data.campaigns[$0] } ?? Campaign() }
        set { if let i = index { data.campaigns[i] = newValue } }
    }

    func select(_ id: UUID) { data.selected = id }

    func addCampaign() {
        var c = Campaign()
        c.name = L.t("campaign.new.name")
        c.eventDate = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
        data.campaigns.append(c)
        data.selected = c.id
    }

    func removeCampaign(_ id: UUID) {
        data.campaigns.removeAll { $0.id == id }
        if data.selected == id { data.selected = data.campaigns.first?.id }
    }

    /// Jours restants avant l'événement (négatif une fois passé).
    func daysLeft(_ c: Campaign) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: c.eventDate)).day ?? 0
    }

    // MARK: Publications

    var posts: [Post] { campaign.posts.sorted { $0.date < $1.date } }

    func post(_ id: UUID?) -> Post? { campaign.posts.first { $0.id == id } }

    func update(_ p: Post) {
        if let i = campaign.posts.firstIndex(where: { $0.id == p.id }) { campaign.posts[i] = p }
    }

    @discardableResult
    func addPost(on day: Date? = nil) -> UUID {
        var p = Post()
        p.title = L.t("post.new.title")
        p.date = day ?? Date()
        p.channelID = data.channels.first?.id
        campaign.posts.append(p)
        return p.id
    }

    func removePost(_ id: UUID) { campaign.posts.removeAll { $0.id == id } }

    func channel(_ id: UUID?) -> Channel? { data.channels.first { $0.id == id } }
    func milestone(_ id: UUID?) -> Milestone? { campaign.milestones.first { $0.id == id } }

    // MARK: Export / import (fichier JSON du plan complet, sans aucune clé)

    /// Fichier « .herald » : le plan en JSON.
    static let planType = UTType(filenameExtension: "herald", conformingTo: .json) ?? .json

    func exportPlan() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.planType]
        panel.nameFieldStringValue = "plan.herald"
        guard panel.runModal() == .OK, let url = panel.url, let d = try? Storage.encode(data) else { return }
        try? d.write(to: url, options: .atomic)
    }

    /// Renvoie un message d'erreur si le fichier n'est pas un plan hERALD.
    func importPlan() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.planType, .json]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let d = try? Data(contentsOf: url), let p = try? Storage.decode(d) else { return L.t("import.invalid") }
        data = p
        return nil
    }

    /// Ajoute la campagne d'exemple (en réutilisant les canaux existants) ; elle se supprime comme les autres.
    func addSample() {
        var chans = data.channels
        let c = Sample.campaign(using: &chans)
        data.channels = chans
        data.campaigns.append(c)
        data.selected = c.id
    }

    // MARK: Retours

    /// Importe des retours depuis un CSV « date;type;valeur;texte » (virgule ou point-virgule). Renvoie le nombre de lignes lues.
    func importFeedback(into id: UUID) -> Int? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        guard panel.runModal() == .OK, let url = panel.url, let text = try? String(contentsOf: url, encoding: .utf8),
              var p = post(id) else { return nil }
        let items = FeedbackCSV.parse(text)
        p.feedback.append(contentsOf: items)
        update(p)
        return items.count
    }

    // MARK: Veille

    var weekReport: WeekReport { WeekReport(data: data, campaign: hasCampaign ? campaign : nil) }

    /// Vérifie tout au lancement si le dernier relevé date de plus d'une semaine.
    func checkIfStale() async {
        let week: TimeInterval = 7 * 86400
        if data.watch.contains(where: { ($0.lastChecked ?? .distantPast) < Date().addingTimeInterval(-week) }) {
            await checkAll()
        }
    }

    func checkAll() async {
        guard !checking else { return }
        checking = true
        let key = Keychain.get("nexus")
        for item in data.watch {
            let result = await Watcher.fetch(item, nexusKey: key)
            guard let i = data.watch.firstIndex(where: { $0.id == item.id }) else { continue }
            data.watch[i].lastChecked = Date()
            switch result {
            case .success(let snap):
                data.watch[i].error = nil
                data.watch[i].history.append(snap)
                if data.watch[i].history.count > 200 { data.watch[i].history.removeFirst() }
            case .failure(let e):
                data.watch[i].error = e.message
            }
        }
        checking = false
    }

    func addWatch(_ input: String, name: String) -> String? {
        guard let (kind, ref) = WatchItem.parse(input) else { return L.t("watch.invalid") }
        guard !data.watch.contains(where: { $0.kind == kind && $0.ref.lowercased() == ref.lowercased() }) else {
            return L.t("watch.duplicate")
        }
        let n = name.trimmingCharacters(in: .whitespaces)
        data.watch.append(WatchItem(name: n.isEmpty ? ref : n, kind: kind, ref: ref))
        return nil
    }
}

// MARK: Rapport hebdomadaire

struct WeekReport {
    struct Release { let name: String; let version: String; let date: Date?; let url: URL? }
    let start: Date
    let end: Date
    let releases: [Release]        // nouvelles versions repérées dans la semaine
    let watched: [WatchItem]       // tout ce qui est suivi, avec sa dernière version
    let published: [Post]          // nos publications de la semaine
    let upcoming: [Post]           // à publier dans les 7 prochains jours
    let feedback: [(Post, Feedback)]

    init(data: AppData, campaign: Campaign?, now: Date = Date()) {
        end = now
        start = now.addingTimeInterval(-7 * 86400)
        let week = start...now
        var rel: [Release] = []
        for w in data.watch {
            // Une version compte si elle diffère de la précédente et a été vue (ou publiée) dans la semaine.
            var previous: String?
            for s in w.history {
                if let p = previous, p != s.version, week.contains(s.published ?? s.date) {
                    rel.append(Release(name: w.name, version: s.version, date: s.published ?? s.date, url: w.pageURL))
                } else if previous == nil, let pub = s.published, week.contains(pub) {
                    rel.append(Release(name: w.name, version: s.version, date: pub, url: w.pageURL))
                }
                previous = s.version
            }
        }
        releases = rel.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        watched = data.watch.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let posts = campaign?.posts ?? []
        published = posts.filter { $0.status == .published && week.contains($0.date) }.sorted { $0.date < $1.date }
        let next = now...now.addingTimeInterval(7 * 86400)
        upcoming = posts.filter { $0.status != .published && next.contains($0.date) }.sorted { $0.date < $1.date }
        feedback = posts.flatMap { p in p.feedback.filter { week.contains($0.date) }.map { (p, $0) } }
            .sorted { $0.1.date > $1.1.date }
    }

    func markdown(channel: (UUID?) -> Channel?) -> String {
        var s = "# \(L.t("report.title"))\n\(L.t("report.period", L.day(start), L.day(end)))\n\n"
        s += "## \(L.t("report.releases"))\n"
        s += releases.isEmpty ? "- \(L.t("report.releases.none"))\n"
            : releases.map { "- **\($0.name)** \($0.version) (\($0.date.map(L.day) ?? "—"))" }.joined(separator: "\n") + "\n"
        s += "\n## \(L.t("report.watched"))\n"
        s += watched.map { w in
            "- \(w.name) : \(w.latest?.version ?? "—")" + (w.error.map { " ⚠︎ \($0)" } ?? "")
        }.joined(separator: "\n") + "\n"
        s += "\n## \(L.t("report.published"))\n"
        s += published.isEmpty ? "- \(L.t("report.none"))\n"
            : published.map { "- \(L.day($0.date)) · \(channel($0.channelID)?.name ?? "—") · \($0.title) \($0.link)" }.joined(separator: "\n") + "\n"
        s += "\n## \(L.t("report.feedback"))\n"
        s += feedback.isEmpty ? "- \(L.t("report.none"))\n"
            : feedback.map { "- \($0.0.title) · \($0.1.kind.label) \($0.1.value)" + ($0.1.text.isEmpty ? "" : " — \($0.1.text)") }.joined(separator: "\n") + "\n"
        s += "\n## \(L.t("report.upcoming"))\n"
        s += upcoming.isEmpty ? "- \(L.t("report.none"))\n"
            : upcoming.map { "- \(L.day($0.date)) · \(channel($0.channelID)?.name ?? "—") · \($0.title) (\($0.status.label))" }.joined(separator: "\n") + "\n"
        return s
    }
}

// MARK: Import CSV des retours

enum FeedbackCSV {
    static func parse(_ text: String) -> [Feedback] {
        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"; iso.locale = Locale(identifier: "en_US_POSIX")
        var out: [Feedback] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            let sep: Character = line.contains(";") ? ";" : ","
            let cols = line.split(separator: sep, maxSplits: 3, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\""))) }
            guard cols.count >= 2, let date = iso.date(from: cols[0]) else { continue }  // en-tête ignoré
            var f = Feedback(date: date)
            f.kind = FeedbackKind(rawValue: cols[1].lowercased()) ?? .other
            f.value = cols.count > 2 ? Int(cols[2]) ?? 1 : 1
            f.text = cols.count > 3 ? cols[3] : ""
            out.append(f)
        }
        return out
    }
}

// MARK: Lecture des pages publiques (lecture seule)

struct WatchError: Error { let message: String }

enum Watcher {
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    static func fetch(_ item: WatchItem, nexusKey: String) async -> Result<WatchSnapshot, WatchError> {
        switch item.kind {
        case .github: return await github(item.ref)
        case .nexus: return await nexus(item.ref, key: nexusKey)
        }
    }

    private static func get(_ url: URL, headers: [String: String]) async -> Result<Data, WatchError> {
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.setValue("hERALD/\(version)", forHTTPHeaderField: "User-Agent")
        headers.forEach { r.setValue($1, forHTTPHeaderField: $0) }
        do {
            let (d, resp) = try await URLSession.shared.data(for: r)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else { return .failure(WatchError(message: L.t("watch.http", code))) }
            return .success(d)
        } catch {
            return .failure(WatchError(message: error.localizedDescription))
        }
    }

    private static func github(_ ref: String) async -> Result<WatchSnapshot, WatchError> {
        guard let url = URL(string: "https://api.github.com/repos/\(ref)/releases?per_page=1") else {
            return .failure(WatchError(message: L.t("watch.invalid")))
        }
        switch await get(url, headers: ["Accept": "application/vnd.github+json"]) {
        case .failure(let e): return .failure(e)
        case .success(let d):
            struct Rel: Decodable { let tag_name: String; let name: String?; let published_at: String? }
            guard let rels = try? JSONDecoder().decode([Rel].self, from: d) else { return .failure(WatchError(message: L.t("watch.parse"))) }
            guard let r = rels.first else { return .success(WatchSnapshot(version: L.t("watch.norelease"))) }
            return .success(WatchSnapshot(version: r.tag_name, published: r.published_at.flatMap { ISO8601DateFormatter().date(from: $0) },
                                          title: r.name ?? ""))
        }
    }

    private static func nexus(_ ref: String, key: String) async -> Result<WatchSnapshot, WatchError> {
        guard !key.isEmpty else { return .failure(WatchError(message: L.t("watch.nokey"))) }
        let parts = ref.split(separator: "/")
        guard parts.count == 2, let url = URL(string: "https://api.nexusmods.com/v1/games/\(parts[0])/mods/\(parts[1]).json") else {
            return .failure(WatchError(message: L.t("watch.invalid")))
        }
        let headers = ["apikey": key, "Application-Name": "hERALD", "Application-Version": version, "Accept": "application/json"]
        switch await get(url, headers: headers) {
        case .failure(let e): return .failure(e)
        case .success(let d):
            struct Mod: Decodable {
                let name: String?; let version: String?; let updated_timestamp: Double?
                let endorsement_count: Int?; let mod_downloads: Int?
            }
            guard let m = try? JSONDecoder().decode(Mod.self, from: d) else { return .failure(WatchError(message: L.t("watch.parse"))) }
            return .success(WatchSnapshot(version: m.version ?? "—", published: m.updated_timestamp.map { Date(timeIntervalSince1970: $0) },
                                          title: m.name ?? "", downloads: m.mod_downloads, endorsements: m.endorsement_count))
        }
    }
}

/// Clé API Nexus rangée dans le trousseau macOS, jamais dans plan.json ni dans l'export.
enum Keychain {
    private static let service = Bundle.main.bundleIdentifier ?? "herald"
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func get(_ account: String) -> String {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return "" }
        return String(decoding: d, as: UTF8.self)
    }

    static func set(_ value: String, _ account: String) {
        guard value != get(account) else { return }
        SecItemDelete(query(account) as CFDictionary)
        guard !value.isEmpty else { return }
        var q = query(account)
        q[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }
}
