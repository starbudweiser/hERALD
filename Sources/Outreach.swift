// hERALD — démarchage : reprise des anciennes publications de contact, modèles de mails, envoi par l'app Mail.
// L'envoi n'a lieu que sur un clic de l'utilisateur, après confirmation ; aucun mot de passe n'est manipulé
// (c'est l'app Mail de l'utilisateur, déjà connectée à ses comptes, qui envoie).
import Foundation

extension Store {
    var contacts: [Contact] { campaign.outreach ?? [] }
    func contact(_ id: UUID?) -> Contact? { contacts.first { $0.id == id } }

    func updateContact(_ c: Contact) {
        var list = campaign.outreach ?? []
        if let i = list.firstIndex(where: { $0.id == c.id }) { list[i] = c; campaign.outreach = list }
    }

    @discardableResult
    func addContact() -> UUID? {
        guard hasCampaign else { return nil }
        let c = Contact(name: L.t("contact.new"))
        campaign.outreach = (campaign.outreach ?? []) + [c]
        return c.id
    }

    func removeContact(_ id: UUID) { campaign.outreach?.removeAll { $0.id == id } }

    /// Relances dues (toutes campagnes de la campagne affichée).
    var followUpsDue: Int { contacts.filter { $0.followUpDue() }.count }

    /// Lit dans l'app Mail les réponses des contacts (adresses enregistrées) et les ajoute au fil.
    /// Renvoie le nombre de nouvelles réponses, ou un message d'erreur.
    func scanReplies() -> (count: Int, error: String?, names: [String]) {
        var total = 0
        var names: [String] = []
        var list = campaign.outreach ?? []
        for i in list.indices {
            let addr = list[i].email.trimmingCharacters(in: .whitespaces)
            guard !addr.isEmpty else { continue }
            switch MailSender.scan(address: addr) {
            case .failure(.script(let e)): return (total, e, names)
            case .success(let mails):
                let known = Set(list[i].messages.compactMap(\.mailID))
                for m in mails where !known.contains(m.id) {
                    list[i].messages.append(OutreachMessage(date: m.date, kind: .reply, direction: .received, subject: m.subject,
                                                            body: m.body, to: m.sender, mailID: m.id))
                    if list[i].status.waiting { list[i].status = .replied; list[i].nextFollowUp = nil }
                    total += 1
                    if !names.contains(list[i].name) { names.append(list[i].name) }
                }
            }
        }
        if total > 0 { campaign.outreach = list }
        return (total, nil, names)
    }

    /// Met à la corbeille de Mail une réponse lue ; le texte reste dans le fil.
    func trashReply(contact id: UUID, message mid: UUID) -> String? {
        guard var c = contact(id), let i = c.messages.firstIndex(where: { $0.id == mid }), let mailID = c.messages[i].mailID else { return nil }
        if case .failure(.script(let e)) = MailSender.trash(mailID: mailID) { return e }
        c.messages[i].mailID = nil
        updateContact(c)
        return nil
    }

    var publishedCount: (Int, Int) { (campaign.posts.filter { $0.status == .published }.count, campaign.posts.count) }
}

extension L {
    /// « 10 nov., 02:42 » : date courte avec l'heure, sans l'année.
    static func stamp(_ d: Date) -> String { d.formatted(Date.FormatStyle().day().month(.abbreviated).hour().minute().locale(locale)) }
    static func shortDay(_ d: Date) -> String { d.formatted(Date.FormatStyle().day().month(.twoDigits).locale(locale)) }

    /// Texte dans une langue précise (modèles de mails écrits dans la langue du contact).
    static func t(_ key: String, in code: String, _ args: CVarArg...) -> String {
        let s = tables[code]?[key] ?? tables["en"]?[key] ?? key
        return args.isEmpty ? s : String(format: s, locale: Locale(identifier: code), arguments: args)
    }
}

enum Outreach {
    // MARK: Modèles de mails

    static func template(_ kind: MessageKind, for c: Contact, campaign: Campaign, sender: String = NSFullUserName()) -> (subject: String, body: String) {
        let code = c.lang.rawValue
        let date = campaign.eventDate.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: code)))
        let key = kind == .followUp ? "follow" : "first"
        let name = c.name.isEmpty ? "" : c.name
        return (L.t("mail.\(key).subject", in: code, campaign.name),
                L.t("mail.\(key).body", in: code, name, sender, campaign.name, date, campaign.notes))
    }

    // MARK: AppleScript

    /// Texte sûr dans un littéral AppleScript : guillemets et barres échappés, sauts de ligne en `linefeed`.
    static func appleScriptString(_ s: String) -> String {
        let lines = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        let quoted = lines.map { l in "\"" + l.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        return quoted.joined(separator: " & linefeed & ")
    }

    static func mailScript(to: String, subject: String, body: String) -> String {
        """
        tell application "Mail"
            set m to make new outgoing message with properties {visible:false, subject:\(appleScriptString(subject)), content:\(appleScriptString(body))}
            tell m to make new to recipient at end of to recipients with properties {address:\(appleScriptString(to))}
            send m
        end tell
        """
    }

    static func scanScript(address: String) -> String {
        """
        tell application "Mail"
            set out to {}
            set ms to (messages of inbox whose sender contains \(appleScriptString(address)))
            repeat with m in ms
                set c to content of m
                if (length of c) > 8000 then set c to text 1 thru 8000 of c
                set end of out to {message id of m, date received of m, sender of m, subject of m, c}
            end repeat
            return out
        end tell
        """
    }

    static func trashScript(mailID: String) -> String {
        """
        tell application "Mail"
            delete (first message of inbox whose message id is \(appleScriptString(mailID)))
        end tell
        """
    }

    /// « mailto: » avec objet et corps, pour ouvrir le brouillon dans Mail si l'envoi direct échoue.
    static func mailtoURL(to: String, subject: String, body: String) -> URL? {
        var c = URLComponents(); c.scheme = "mailto"; c.path = to
        c.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
        return c.url
    }

    // MARK: Reprise des publications de démarchage

    /// Adresse e-mail trouvée dans un lien « mailto: » ou dans un texte.
    static func firstEmail(_ texts: String...) -> String {
        for t in texts {
            if t.lowercased().hasPrefix("mailto:") { return String(t.dropFirst(7)).components(separatedBy: "?")[0].trimmingCharacters(in: .whitespaces) }
            if let r = t.range(of: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", options: .regularExpression) { return String(t[r]) }
        }
        return ""
    }

    /// Nom du contact d'après un titre « E-mail à X (…) », « MP Discord à X (…) » ou « Relance X (…) ».
    static func contactName(_ title: String) -> (name: String, followUp: Bool)? {
        func cut(_ s: Substring) -> String { String(s.components(separatedBy: " (")[0]).trimmingCharacters(in: .whitespaces) }
        if title.hasPrefix("Relance ") { return (cut(title.dropFirst(8)), true) }
        if let r = title.range(of: " à ") { return (cut(title[r.upperBound...]), false) }
        return nil
    }

    /// Sépare le texte d'un mail de ses consignes : objet (ligne « **Objet :** … ») et corps.
    static func splitMail(_ notes: String) -> (intro: String, subject: String, body: String) {
        let lines = notes.components(separatedBy: "\n")
        guard let i = lines.firstIndex(where: { $0.hasPrefix("**Objet :**") || $0.hasPrefix("**Sujet") }) else { return (notes, "", "") }
        let subject = lines[i].components(separatedBy: ":**").dropFirst().joined(separator: ":**").trimmingCharacters(in: .whitespaces)
        let intro = lines[..<i].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = lines[(i + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (intro, subject, body)
    }

    /// Les publications des canaux « YouTubeurs (démarchage) » et « Discord MacProTips » deviennent des contacts.
    /// Une seule fois : les publications reprises sont retirées. Renvoie le nombre de contacts créés.
    @discardableResult
    static func migrate(_ data: inout AppData) -> Int {
        let wanted: [(String, ContactKind)] = [("YouTubeurs (démarchage)", .youtuber), ("Discord MacProTips", .discord)]
        var created = 0
        for ci in data.campaigns.indices {
            var contacts = data.campaigns[ci].outreach ?? []
            var moved = Set<UUID>()
            for (channelName, kind) in wanted {
                guard let ch = data.channels.first(where: { $0.name.localizedCaseInsensitiveCompare(channelName) == .orderedSame }) else { continue }
                let posts = data.campaigns[ci].posts.filter { $0.channelID == ch.id }
                var order: [String] = []
                var groups: [String: [Post]] = [:]
                for p in posts {
                    guard let n = contactName(p.title) else { continue }
                    if groups[n.name] == nil { order.append(n.name) }
                    groups[n.name, default: []].append(p)
                }
                for name in order {
                    let ps = groups[name]!
                    guard !contacts.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else { continue }
                    var c = Contact(name: name, kind: kind, url: kind == .discord ? ch.url : "")
                    c.lang = .en
                    let first = ps.first { contactName($0.title)?.followUp == false }
                    let follow = ps.first { contactName($0.title)?.followUp == true }
                    if let f = first {
                        let m = splitMail(f.notes)
                        c.email = firstEmail(f.link, f.notes)
                        if !f.link.lowercased().hasPrefix("mailto:"), !f.link.isEmpty, c.url.isEmpty { c.url = f.link }
                        c.notes = m.intro
                        let sent = f.status == .published
                        c.messages.append(OutreachMessage(date: f.date, kind: .first, direction: sent ? .sent : .draft,
                                                          subject: m.subject, body: m.body.isEmpty ? m.intro : m.body, to: c.email))
                        c.status = sent ? .contacted : .toContact
                    }
                    if let r = follow {
                        c.nextFollowUp = r.date
                        if r.status == .published { c.status = .followedUp }
                    }
                    contacts.append(c); created += 1
                    ps.forEach { moved.insert($0.id) }
                }
            }
            if !moved.isEmpty {
                data.campaigns[ci].outreach = contacts
                data.campaigns[ci].posts.removeAll { moved.contains($0.id) }
            }
        }
        return created
    }
}

// MARK: Envoi par Mail

#if canImport(AppKit)
import AppKit

/// Client de messagerie choisi dans les Réglages : l'app Mail (envoi, lecture des réponses, corbeille) ou un autre client
/// (ouvre un message prêt à envoyer). Aucun mot de passe n'est jamais demandé.
enum MailClient: String, CaseIterable, Identifiable {
    case mail, other
    var id: String { rawValue }
    var label: String { L.t("mail.client.\(rawValue)") }
    static var current: MailClient {
        get { MailClient(rawValue: UserDefaults.standard.string(forKey: "mailClient") ?? "") ?? .mail }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "mailClient") }
    }
}

struct IncomingMail { let id: String; let date: Date; let sender: String; let subject: String; let body: String }

@MainActor
enum MailSender {
    enum Failure: Error { case script(String) }

    private static func run(_ source: String) -> Result<NSAppleEventDescriptor, Failure> {
        var err: NSDictionary?
        let r = NSAppleScript(source: source)?.executeAndReturnError(&err)
        if let err { return .failure(.script(err[NSAppleScript.errorMessage] as? String ?? L.t("mail.err.unknown"))) }
        return .success(r ?? NSAppleEventDescriptor())
    }

    /// Envoie par l'app Mail (AppleScript). Premier envoi : macOS demande l'autorisation de piloter Mail.
    static func send(to: String, subject: String, body: String) -> Result<Void, Failure> {
        run(Outreach.mailScript(to: to, subject: subject, body: body)).map { _ in () }
    }

    /// Messages de la boîte de réception venant de cette adresse (corps tronqué à 8000 caractères).
    static func scan(address: String) -> Result<[IncomingMail], Failure> {
        run(Outreach.scanScript(address: address)).map { d in
            guard d.numberOfItems > 0 else { return [] }
            return (1...d.numberOfItems).compactMap { i in
                guard let m = d.atIndex(i), m.numberOfItems >= 5, let id = m.atIndex(1)?.stringValue else { return nil }
                return IncomingMail(id: id, date: m.atIndex(2)?.dateValue ?? Date(), sender: m.atIndex(3)?.stringValue ?? "",
                                    subject: m.atIndex(4)?.stringValue ?? "", body: m.atIndex(5)?.stringValue ?? "")
            }
        }
    }

    /// Déplace un message de la boîte de réception vers la corbeille de Mail.
    static func trash(mailID: String) -> Result<Void, Failure> {
        run(Outreach.trashScript(mailID: mailID)).map { _ in () }
    }

    /// Ouvre le brouillon dans le client par défaut (l'utilisateur envoie lui-même).
    static func openDraft(to: String, subject: String, body: String) {
        if let u = Outreach.mailtoURL(to: to, subject: subject, body: body) { NSWorkspace.shared.open(u) }
    }
}
#endif

#if canImport(AppKit)
import AppKit
import UserNotifications

extension Store {
    /// Relève automatique des réponses des contacts (toutes les 30 minutes), seulement si l'app Mail est déjà ouverte
    /// (jamais lancée par hERALD) et s'il y a un contact avec une adresse ; notification à chaque nouvelle réponse.
    func autoScanRepliesIfDue() {
        guard MailClient.current == .mail,
              Date().timeIntervalSince(UserDefaults.standard.object(forKey: "replyScanAt") as? Date ?? .distantPast) >= 1800,
              contacts.contains(where: { !$0.email.trimmingCharacters(in: .whitespaces).isEmpty }),
              NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").isEmpty == false
        else { return }
        UserDefaults.standard.set(Date(), forKey: "replyScanAt")
        let r = scanReplies()
        guard r.error == nil, r.count > 0, Bundle.main.bundleIdentifier != nil else { return }
        let body = r.names.count == 1 ? L.t("notif.reply.body", r.names[0]) : L.t("notif.reply.many", r.names.count)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            let c = UNMutableNotificationContent()
            c.title = L.t("notif.reply.title"); c.body = body; c.sound = .default
            center.add(UNNotificationRequest(identifier: "reply-\(UUID().uuidString)", content: c, trigger: nil))
        }
    }
}
#endif
