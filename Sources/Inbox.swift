// hERALD — boîte de dépôt : les fichiers JSON déposés dans un dossier sont fusionnés dans le plan.
// Sert à alimenter hERALD depuis un script (herald_add) ou un assistant, sans passer par l'import manuel.
// Fusion prudente : on ajoute ce qui manque et on complète les champs vides, sans écraser ce que
// l'utilisateur a saisi, sauf « overwrite: true » (pour tout le fichier ou pour un élément).
// Comme le reste de l'appli, rien ici ne publie quoi que ce soit.
import Foundation

struct InboxError: Error { let message: String }

struct InboxResult {
    var added = 0
    var updated = 0
    var log: [String] = []
}

enum Inbox {
    static let dir = Storage.dir.appendingPathComponent("Inbox", isDirectory: true)
    static let processedName = "processed"
    static let errorsName = "errors"
    static let logName = "journal.log"

    static func prepare(_ dir: URL = dir) {
        for d in [dir, dir.appendingPathComponent(processedName), dir.appendingPathComponent(errorsName)] {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
    }

    /// Fichiers en attente (.json ou .herald, hors fichiers cachés), du plus ancien au plus récent.
    static func pending(_ dir: URL = dir, minAge: TimeInterval = 0, now: Date = Date()) -> [URL] {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
                                                 options: [.skipsHiddenFiles])) ?? []
        func date(_ u: URL) -> Date { (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
        // Un fichier trop récent est peut-être encore en cours d'écriture : il attend le passage suivant.
        return urls.filter { ["json", "herald"].contains($0.pathExtension.lowercased()) && now.timeIntervalSince(date($0)) >= minAge }
            .sorted { date($0) < date($1) }
    }

    /// Traite tous les fichiers en attente : fusion dans `data`, fichier rangé dans processed/ ou errors/,
    /// une ligne par changement dans journal.log. Renvoie les lignes ajoutées au journal.
    @discardableResult
    static func process(_ dir: URL = dir, into data: inout AppData, minAge: TimeInterval = 0, now: Date = Date()) -> [String] {
        prepare(dir)
        var lines: [String] = []
        for url in pending(dir, minAge: minAge, now: now) {
            let name = url.lastPathComponent
            let stamp = ISO8601DateFormatter().string(from: now)
            let target: String
            do {
                let raw = try Data(contentsOf: url)
                let r = try merge(raw, into: &data)
                lines.append("\(stamp) \(L.t("inbox.log.file", name, r.added, r.updated))")
                lines += r.log.map { "\(stamp)   \($0)" }
                target = processedName
            } catch {
                let msg = (error as? InboxError)?.message ?? error.localizedDescription
                lines.append("\(stamp) \(L.t("inbox.log.error", name, msg))")
                target = errorsName
            }
            move(url, to: dir.appendingPathComponent(target))
        }
        if !lines.isEmpty { appendLog(lines, dir) }
        return lines
    }

    static func readLog(_ dir: URL = dir, last n: Int = 30) -> [String] {
        let text = (try? String(contentsOf: dir.appendingPathComponent(logName), encoding: .utf8)) ?? ""
        return Array(text.split(whereSeparator: \.isNewline).map(String.init).suffix(n))
    }

    private static func appendLog(_ lines: [String], _ dir: URL) {
        let url = dir.appendingPathComponent(logName)
        let text = lines.joined(separator: "\n") + "\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Déplace sans écraser : « nom 2.json » si le nom est déjà pris.
    private static func move(_ url: URL, to folder: URL) {
        let fm = FileManager.default
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        var dest = folder.appendingPathComponent(url.lastPathComponent)
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = folder.appendingPathComponent("\(base) \(n).\(ext)"); n += 1
        }
        if (try? fm.moveItem(at: url, to: dest)) == nil { try? fm.removeItem(at: url) }
    }

    /// Fusionne un fichier (changements « herald-changes » ou plan .herald complet). Tout ou rien :
    /// à la moindre erreur, le plan reste inchangé.
    static func merge(_ raw: Data, into data: inout AppData) throws -> InboxResult {
        guard let root = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            throw InboxError(message: L.t("inbox.err.json"))
        }
        var m = Merger(data: data, overwriteAll: root["overwrite"] as? Bool ?? false)
        if root["campaigns"] is [Any] {
            guard let plan = try? Storage.decode(raw) else { throw InboxError(message: L.t("inbox.err.format")) }
            try m.mergePlan(plan)
        } else if let f = root["format"] as? String, f != "herald-changes" {
            throw InboxError(message: L.t("inbox.err.format"))
        } else {
            try m.mergeChanges(root)
        }
        data = m.data
        return m.result
    }
}

// MARK: Lecture des valeurs JSON

private enum J {
    static func str(_ d: [String: Any], _ k: String) -> String? {
        (d[k] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func uuid(_ d: [String: Any], _ k: String) -> UUID? { str(d, k).flatMap(UUID.init(uuidString:)) }

    /// « 2026-11-11 » (midi, heure locale), « 2026-11-11 18:30 » ou ISO 8601 complet.
    static func date(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        for (fmt, noon) in [("yyyy-MM-dd HH:mm", false), ("yyyy-MM-dd'T'HH:mm", false), ("yyyy-MM-dd", true)] {
            f.dateFormat = fmt
            if let d = f.date(from: s) {
                return noon ? Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: d) : d
            }
        }
        return nil
    }

    static func same(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespaces).localizedCaseInsensitiveCompare(b.trimmingCharacters(in: .whitespaces)) == .orderedSame
    }
}

// MARK: Fusion

private struct Merger {
    var data: AppData
    var result = InboxResult()
    let overwriteAll: Bool

    private func kind(_ k: String) -> String { L.t("inbox.kind.\(k)") }
    private mutating func added(_ k: String, _ title: String) { result.added += 1; result.log.append(L.t("inbox.log.added", kind(k), title)) }
    private mutating func updated(_ k: String, _ title: String) { result.updated += 1; result.log.append(L.t("inbox.log.updated", kind(k), title)) }
    private func fail(_ k: String, _ field: String) -> InboxError { InboxError(message: L.t("inbox.err.field", kind(k), field)) }

    /// Applique `value` si le champ est vide (ou si l'écrasement est demandé). Renvoie vrai si quelque chose a changé.
    private func fill<T: Equatable>(_ field: inout T, _ value: T?, empty: T, _ force: Bool) -> Bool {
        guard let value, value != field, force || field == empty else { return false }
        field = value
        return true
    }

    // MARK: Fichier de changements

    mutating func mergeChanges(_ root: [String: Any]) throws {
        for c in root["channels"] as? [[String: Any]] ?? [] { try channel(c) }
        for w in root["watch"] as? [[String: Any]] ?? [] { try watch(w) }
        let hasCampaignItems = ["milestones", "posts", "feedback", "contacts"].contains { !((root[$0] as? [Any]) ?? []).isEmpty }
        guard hasCampaignItems || root["campaign"] != nil else { return }
        let ci = try campaignIndex(root["campaign"])
        for m in root["milestones"] as? [[String: Any]] ?? [] { try milestone(m, in: ci) }
        for p in root["posts"] as? [[String: Any]] ?? [] { try post(p, in: ci) }
        for c in root["contacts"] as? [[String: Any]] ?? [] { try contact(c, in: ci) }
        for f in root["feedback"] as? [[String: Any]] ?? [] {
            guard let ref = J.str(f, "post"), let pi = findPost(ref, date: nil, in: ci) else { throw fail("feedback", "post") }
            let title = data.campaigns[ci].posts[pi].title
            if try addFeedback([f], to: &data.campaigns[ci].posts[pi]) > 0 { updated("feedback", title) }
        }
    }

    /// Campagne visée : id ou nom (créée si absente), objet {id, name, date, notes}, ou à défaut la campagne affichée.
    private mutating func campaignIndex(_ spec: Any?) throws -> Int {
        var d: [String: Any] = [:]
        if let s = spec as? String { d = UUID(uuidString: s) != nil ? ["id": s] : ["name": s] }
        else if let o = spec as? [String: Any] { d = o }
        else if spec == nil {
            if let i = data.campaigns.firstIndex(where: { $0.id == data.selected }) ?? (data.campaigns.isEmpty ? nil : 0) { return i }
            d = ["name": L.t("campaign.new.name")]
        }
        let force = overwriteAll || (d["overwrite"] as? Bool ?? false)
        let id = J.uuid(d, "id"), name = J.str(d, "name")
        if let i = data.campaigns.firstIndex(where: { $0.id == id || (name != nil && J.same($0.name, name!)) }) {
            var c = data.campaigns[i], changed = false
            if force, let name, name != c.name { c.name = name; changed = true }
            if force, let date = J.date(J.str(d, "date")) { c.eventDate = date; changed = true }
            changed = fill(&c.notes, J.str(d, "notes"), empty: "", force) || changed
            if changed { data.campaigns[i] = c; updated("campaign", c.name) }
            return i
        }
        guard let name, !name.isEmpty else { throw fail("campaign", "name") }
        var c = Campaign(id: id ?? UUID(), name: name)
        c.eventDate = J.date(J.str(d, "date")) ?? Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
        c.notes = J.str(d, "notes") ?? ""
        data.campaigns.append(c)
        if data.selected == nil { data.selected = c.id }
        added("campaign", name)
        return data.campaigns.count - 1
    }

    private mutating func channel(_ d: [String: Any]) throws {
        let force = overwriteAll || (d["overwrite"] as? Bool ?? false)
        let id = J.uuid(d, "id"), name = J.str(d, "name")
        let kindValue = J.str(d, "kind").flatMap { ChannelKind(rawValue: $0.lowercased()) }
        if let i = data.channels.firstIndex(where: { $0.id == id || (name != nil && J.same($0.name, name!)) }) {
            var c = data.channels[i]
            var changed = force && name != nil && name != c.name
            if changed { c.name = name! }
            changed = fill(&c.kind, kindValue, empty: .other, force) || changed
            changed = fill(&c.url, J.str(d, "url"), empty: "", force) || changed
            changed = fill(&c.notes, J.str(d, "notes"), empty: "", force) || changed
            if changed { data.channels[i] = c; updated("channel", c.name) }
            return
        }
        guard let name, !name.isEmpty else { throw fail("channel", "name") }
        data.channels.append(Channel(id: id ?? UUID(), name: name, kind: kindValue ?? .other,
                                     url: J.str(d, "url") ?? "", notes: J.str(d, "notes") ?? ""))
        added("channel", name)
    }

    private mutating func watch(_ d: [String: Any]) throws {
        let force = overwriteAll || (d["overwrite"] as? Bool ?? false)
        let id = J.uuid(d, "id")
        var parsed: (WatchKind, String)?
        if let k = J.str(d, "kind").flatMap({ WatchKind(rawValue: $0.lowercased()) }), let ref = J.str(d, "ref") { parsed = (k, ref) }
        else if let s = J.str(d, "url") ?? J.str(d, "ref") { parsed = WatchItem.parse(s) }
        guard id != nil || parsed != nil else { throw fail("watch", "url") }
        if let i = data.watch.firstIndex(where: { $0.id == id || (parsed != nil && $0.kind == parsed!.0 && J.same($0.ref, parsed!.1)) }) {
            var w = data.watch[i], changed = false
            if force, let name = J.str(d, "name"), !name.isEmpty, name != w.name { w.name = name; changed = true }
            changed = fill(&w.notes, J.str(d, "notes"), empty: "", force) || changed
            if changed { data.watch[i] = w; updated("watch", w.name) }
            return
        }
        guard let (kind, ref) = parsed else { throw fail("watch", "url") }
        let name = J.str(d, "name").flatMap { $0.isEmpty ? nil : $0 } ?? ref
        var w = WatchItem(id: id ?? UUID(), name: name, kind: kind, ref: ref, notes: J.str(d, "notes") ?? "")
        if let h = d["history"], let raw = try? JSONSerialization.data(withJSONObject: h) {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            w.history = (try? dec.decode([WatchSnapshot].self, from: raw)) ?? []
            w.lastChecked = w.history.last?.date
        }
        data.watch.append(w)
        added("watch", name)
    }

    private mutating func milestone(_ d: [String: Any], in ci: Int) throws {
        let force = overwriteAll || (d["overwrite"] as? Bool ?? false)
        let id = J.uuid(d, "id"), title = J.str(d, "title"), date = J.date(J.str(d, "date"))
        let kindValue = J.str(d, "kind").flatMap { MilestoneKind(rawValue: $0.lowercased()) }
        let cal = Calendar.current
        if let i = data.campaigns[ci].milestones.firstIndex(where: { m in
            m.id == id || (title != nil && J.same(m.title, title!) && (date == nil || cal.isDate(m.date, inSameDayAs: date!)))
        }) {
            var m = data.campaigns[ci].milestones[i], changed = false
            if force, let title, title != m.title { m.title = title; changed = true }
            if force, let date, date != m.date { m.date = date; changed = true }
            changed = fill(&m.kind, kindValue, empty: .other, force) || changed
            if changed { data.campaigns[ci].milestones[i] = m; updated("milestone", m.title) }
            return
        }
        guard let title, !title.isEmpty else { throw fail("milestone", "title") }
        guard let date else { throw fail("milestone", "date") }
        data.campaigns[ci].milestones.append(Milestone(id: id ?? UUID(), title: title, date: date, kind: kindValue ?? .other))
        added("milestone", title)
    }

    /// Publication par id, sinon titre + jour (ou titre seul s'il n'y en a qu'une).
    private func findPost(_ ref: String, date: Date?, in ci: Int) -> Int? {
        let posts = data.campaigns[ci].posts
        if let id = UUID(uuidString: ref) { return posts.firstIndex { $0.id == id } }
        let same = posts.indices.filter { J.same(posts[$0].title, ref) }
        if let date { return same.first { Calendar.current.isDate(posts[$0].date, inSameDayAs: date) } }
        return same.count == 1 ? same[0] : nil
    }

    private func channelID(_ d: [String: Any]) -> UUID? {
        if let id = J.uuid(d, "channelID"), data.channels.contains(where: { $0.id == id }) { return id }
        guard let s = J.str(d, "channel"), !s.isEmpty else { return nil }
        return data.channels.first { $0.id.uuidString == s.uppercased() || J.same($0.name, s) }?.id
            ?? ChannelKind(rawValue: s.lowercased()).flatMap { k in data.channels.first { $0.kind == k }?.id }
    }

    private func milestoneID(_ d: [String: Any], in ci: Int) -> UUID? {
        let ms = data.campaigns[ci].milestones
        if let id = J.uuid(d, "milestoneID"), ms.contains(where: { $0.id == id }) { return id }
        guard let s = J.str(d, "milestone"), !s.isEmpty else { return nil }
        return ms.first { $0.id.uuidString == s.uppercased() || J.same($0.title, s) }?.id
    }

    private mutating func post(_ d: [String: Any], in ci: Int) throws {
        let force = overwriteAll || (d["overwrite"] as? Bool ?? false)
        let title = J.str(d, "title"), date = J.date(J.str(d, "date"))
        if J.str(d, "channel") != nil, channelID(d) == nil { throw fail("post", "channel") }
        if J.str(d, "milestone") != nil, milestoneID(d, in: ci) == nil { throw fail("post", "milestone") }
        let status = try J.str(d, "status").map { s -> PostStatus in
            guard let v = PostStatus(rawValue: s.lowercased()) else { throw fail("post", "status") }
            return v
        }
        var drafts: [String: String] = [:]
        for (k, v) in d["drafts"] as? [String: Any] ?? [:] {
            guard let lang = Lang(rawValue: k.lowercased()) else { throw fail("post", "drafts.\(k)") }
            if let s = v as? String, !s.isEmpty { drafts[lang.rawValue] = s }
        }
        let feedback = d["feedback"] as? [[String: Any]] ?? []

        let index = J.uuid(d, "id").flatMap { id in data.campaigns[ci].posts.firstIndex { $0.id == id } }
            ?? title.flatMap { findPost($0, date: date, in: ci) }
        if let i = index {
            var p = data.campaigns[ci].posts[i], changed = false
            if force, let title, title != p.title { p.title = title; changed = true }
            if force, let date, date != p.date { p.date = date; changed = true }
            changed = fill(&p.channelID, channelID(d), empty: nil, force) || changed
            changed = fill(&p.milestoneID, milestoneID(d, in: ci), empty: nil, force) || changed
            changed = fill(&p.status, status, empty: .idea, force) || changed
            changed = fill(&p.link, J.str(d, "link"), empty: "", force) || changed
            changed = fill(&p.notes, J.str(d, "notes"), empty: "", force) || changed
            for (lang, text) in drafts.sorted(by: { $0.key < $1.key }) {
                var cur = p.drafts[lang] ?? ""
                if fill(&cur, text, empty: "", force) { p.drafts[lang] = cur; changed = true }
            }
            changed = try addFeedback(feedback, to: &p) > 0 || changed
            if changed { data.campaigns[ci].posts[i] = p; updated("post", p.title) }
            return
        }
        guard let title, !title.isEmpty else { throw fail("post", "title") }
        guard let date else { throw fail("post", "date") }
        var p = Post(id: J.uuid(d, "id") ?? UUID(), title: title, date: date, channelID: channelID(d),
                     milestoneID: milestoneID(d, in: ci), status: status ?? .idea,
                     link: J.str(d, "link") ?? "", notes: J.str(d, "notes") ?? "", drafts: drafts)
        _ = try addFeedback(feedback, to: &p)
        data.campaigns[ci].posts.append(p)
        added("post", title)
    }

    /// Ajoute les retours absents (même date, type, valeur et texte = doublon). Renvoie le nombre ajouté.
    private func addFeedback(_ items: [[String: Any]], to p: inout Post) throws -> Int {
        var n = 0
        for f in items {
            guard let date = J.date(J.str(f, "date")) else { throw fail("feedback", "date") }
            let kind = J.str(f, "kind").flatMap { FeedbackKind(rawValue: $0.lowercased()) } ?? .comment
            let value = (f["value"] as? Int) ?? Int(J.str(f, "value") ?? "") ?? 1
            // Réponse relevée sur une plateforme (Reddit…) : auteur, lien, identifiant source ; arrive non lue.
            let source = J.str(f, "source")
            let fb = Feedback(id: J.uuid(f, "id") ?? UUID(), date: date, kind: kind, value: value, text: J.str(f, "text") ?? "",
                              author: J.str(f, "author"), url: J.str(f, "url"), source: source, unread: source != nil ? true : nil)
            let dup = p.feedback.contains { $0.id == fb.id || (source != nil && $0.source == source)
                || ($0.kind == kind && $0.value == value && $0.text == fb.text && abs($0.date.timeIntervalSince(date)) < 1) }
            if !dup { p.feedback.append(fb); n += 1 }
        }
        return n
    }

    // MARK: Plan complet (.herald)

    /// Un plan entier est traité comme une suite de changements : canaux, veille, puis chaque campagne.
    mutating func mergePlan(_ plan: AppData) throws {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        func dicts<T: Encodable>(_ v: [T]) throws -> [[String: Any]] {
            try JSONSerialization.jsonObject(with: enc.encode(v)) as? [[String: Any]] ?? []
        }
        // Canaux : correspondance par id ou par nom, pour rattacher les publications au bon canal local.
        var channelMap: [UUID: UUID] = [:]
        for (c, d) in zip(plan.channels, try dicts(plan.channels)) {
            try channel(d)
            channelMap[c.id] = data.channels.first { $0.id == c.id || J.same($0.name, c.name) }?.id
        }
        for d in try dicts(plan.watch) { try watch(d) }
        for c in plan.campaigns {
            let ci = try campaignIndex(["id": c.id.uuidString, "name": c.name, "date": ISO8601DateFormatter().string(from: c.eventDate),
                                        "notes": c.notes])
            var msMap: [UUID: UUID] = [:]
            for (m, d) in zip(c.milestones, try dicts(c.milestones)) {
                try milestone(d, in: ci)
                let cal = Calendar.current
                msMap[m.id] = data.campaigns[ci].milestones.first {
                    $0.id == m.id || (J.same($0.title, m.title) && cal.isDate($0.date, inSameDayAs: m.date))
                }?.id
            }
            for (p, var d) in zip(c.posts, try dicts(c.posts)) {
                d["channelID"] = p.channelID.flatMap { channelMap[$0] }?.uuidString
                d["milestoneID"] = p.milestoneID.flatMap { msMap[$0] }?.uuidString
                try post(d, in: ci)
            }
            for d in try dicts(c.outreach ?? []) { try contact(d, in: ci) }
        }
    }

    // MARK: Contacts de démarchage

    private func messages(_ d: [String: Any]) throws -> [OutreachMessage] {
        try (d["messages"] as? [[String: Any]] ?? []).map { m in
            guard let date = J.date(J.str(m, "date")) else { throw fail("contact", "messages.date") }
            return OutreachMessage(id: J.uuid(m, "id") ?? UUID(), date: date,
                                   kind: J.str(m, "kind").flatMap { MessageKind(rawValue: $0) } ?? .note,
                                   direction: J.str(m, "direction").flatMap { MessageDirection(rawValue: $0) } ?? .draft,
                                   subject: J.str(m, "subject") ?? "", body: J.str(m, "body") ?? "", to: J.str(m, "to") ?? "",
                                   mailID: J.str(m, "mailID"))
        }
    }

    private mutating func contact(_ d: [String: Any], in ci: Int) throws {
        let force = overwriteAll || (d["overwrite"] as? Bool ?? false)
        let id = J.uuid(d, "id"), name = J.str(d, "name")
        let kind = J.str(d, "kind").flatMap { ContactKind(rawValue: $0.lowercased()) }
        let lang = J.str(d, "lang").flatMap { Lang(rawValue: $0.lowercased()) }
        let status = J.str(d, "status").flatMap { ContactStatus(rawValue: $0) }
        let follow = J.date(J.str(d, "nextFollowUp"))
        let msgs = try messages(d)
        var list = data.campaigns[ci].outreach ?? []
        if let i = list.firstIndex(where: { $0.id == id || (name != nil && J.same($0.name, name!)) }) {
            var c = list[i], changed = false
            if force, let name, name != c.name { c.name = name; changed = true }
            changed = fill(&c.kind, kind, empty: .other, force) || changed
            changed = fill(&c.lang, lang, empty: .fr, force) || changed
            changed = fill(&c.status, status, empty: .toContact, force) || changed
            changed = fill(&c.url, J.str(d, "url"), empty: "", force) || changed
            changed = fill(&c.email, J.str(d, "email"), empty: "", force) || changed
            changed = fill(&c.coverage, J.str(d, "coverage"), empty: "", force) || changed
            changed = fill(&c.notes, J.str(d, "notes"), empty: "", force) || changed
            if let follow, force || c.nextFollowUp == nil { if c.nextFollowUp != follow { c.nextFollowUp = follow; changed = true } }
            for m in msgs where !c.messages.contains(where: { $0.id == m.id || ($0.direction == m.direction && $0.subject == m.subject
                && abs($0.date.timeIntervalSince(m.date)) < 1) }) { c.messages.append(m); changed = true }
            if changed { list[i] = c; data.campaigns[ci].outreach = list; updated("contact", c.name) }
            return
        }
        guard let name, !name.isEmpty else { throw fail("contact", "name") }
        var c = Contact(id: id ?? UUID(), name: name, kind: kind ?? .other, url: J.str(d, "url") ?? "", email: J.str(d, "email") ?? "",
                        lang: lang ?? .en, status: status ?? .toContact, nextFollowUp: follow, coverage: J.str(d, "coverage") ?? "",
                        notes: J.str(d, "notes") ?? "")
        c.messages = msgs
        list.append(c)
        data.campaigns[ci].outreach = list
        added("contact", name)
    }
}
