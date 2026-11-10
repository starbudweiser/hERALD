// hERALD — espace de publication : navigateur intégré à gauche, panneau de publication à droite.
// hERALD ne publie jamais : l'utilisateur copie, colle et publie lui-même.
import SwiftUI

enum Workspace: Equatable { case post(UUID), contact(UUID) }

enum Publish {
    /// Limites de caractères connues par canal.
    static func limit(_ k: ChannelKind?) -> Int? { k == .bluesky ? 300 : k == .x ? 280 : nil }

    /// Page à ouvrir : rédaction du canal quand on la connaît, sinon adresse du canal, sinon lien de la publication.
    static func url(post p: Post, channel c: Channel?) -> URL? {
        let base = (c?.url ?? "").trimmingCharacters(in: .whitespaces)
        switch c?.kind {
        case .bluesky: return URL(string: "https://bsky.app")
        case .x: return URL(string: "https://x.com/compose/post")
        case .youtube: return URL(string: "https://studio.youtube.com")
        case .discord: if base.isEmpty { return URL(string: "https://discord.com/app") }
        case .reddit:
            if base.lowercased().contains("reddit.com") {
                let b = base.hasSuffix("/") ? String(base.dropLast()) : base
                return Browser.url(from: b.hasSuffix("/submit") ? b : b + "/submit")
            }
        default: break
        }
        if !base.isEmpty { return Browser.url(from: base) }
        return Browser.url(from: p.link)
    }

    /// Langue habituelle du canal en premier (anglais pour les canaux internationaux, sinon la langue de l'interface).
    static func order(_ k: ChannelKind?) -> [Lang] {
        let intl: [ChannelKind] = [.nexus, .reddit, .x, .bluesky, .youtube, .github, .instagram]
        let first = k.map { intl.contains($0) } == true ? Lang.en : (Lang(rawValue: L.lang) ?? .en)
        return [first] + Lang.allCases.filter { $0 != first }
    }

    static func matches(_ pattern: String, in texts: [String]) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        var out: [String] = []
        for t in texts {
            for m in re.matches(in: t, range: NSRange(t.startIndex..., in: t)) {
                if let r = Range(m.range, in: t) {
                    var s = String(t[r])
                    while let l = s.last, ".,;:!?".contains(l) { s.removeLast() }
                    if !out.contains(s) { out.append(s) }
                }
            }
        }
        return out
    }
    static func links(in texts: [String]) -> [String] { matches(#"https?://[^\s)\]»”"]+"#, in: texts) }
    static func hashtags(in texts: [String]) -> [String] { matches(#"(?<![\w/&#])#[\p{L}\p{N}_]{2,}"#, in: texts) }
}

extension UIState {
    func openWorkspace(_ w: Workspace, _ store: Store) {
        workspace = w
        switch w {
        case .post(let id):
            selectedPost = id
            if let p = store.post(id), let u = Publish.url(post: p, channel: store.channel(p.channelID)) {
                BrowserModel.shared.open(u, reveal: false)
            }
        case .contact(let id):
            selectedContact = id
            if let c = store.contact(id), let u = Browser.url(from: c.url) { BrowserModel.shared.open(u, reveal: false) }
        }
    }

    /// ⌘⇧B : ferme l'espace s'il est ouvert, sinon l'ouvre sur la ligne choisie.
    func toggleWorkspace(_ store: Store) {
        if workspace != nil { workspace = nil; return }
        if tab == .contacts, let c = selectedContact { openWorkspace(.contact(c), store) }
        else if let p = selectedPost, store.post(p) != nil { openWorkspace(.post(p), store) }
        else if let c = selectedContact, store.contact(c) != nil { openWorkspace(.contact(c), store) }
    }
}

extension Store {
    /// Publications du jour encore à publier, dans l'ordre.
    func publishQueue(now: Date = Date()) -> [UUID] {
        posts.filter { $0.status != .published && Calendar.current.isDate($0.date, inSameDayAs: now) }
            .sorted { $0.date < $1.date }.map(\.id)
    }
    func nextToPublish(after id: UUID) -> UUID? {
        let q = publishQueue()
        if let i = q.firstIndex(of: id) { return i + 1 < q.count ? q[i + 1] : nil }
        return q.first { $0 != id }
    }
}

struct PublishWorkspace: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    let target: Workspace

    var body: some View {
        HStack(spacing: 12) {
            BrowserView().soclePanel()
            Group {
                switch target {
                case .post(let id):
                    if store.post(id) != nil { PublishPanel(id: id) } else { EmptyState(text: L.t("post.select")) }
                case .contact(let id):
                    if store.contact(id) != nil {
                        VStack(spacing: 0) {
                            PanelHeader(title: store.contact(id)?.name ?? "", sub: L.t("tab.contacts"))
                            Divider().overlay(Socle.C.borderSubtle)
                            ContactDetail(id: id)
                        }
                    } else { EmptyState(text: L.t("contact.select")) }
                }
            }
            .frame(width: { if case .contact = target { return 420 } else { return 360 } }())
            .soclePanel()
        }
        .background(Button("") { ui.workspace = nil }.keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0))
    }
}

/// En-tête du panneau : titre et sous-titre sur une ligne chacun, bouton Fermer à droite.
struct PanelHeader: View {
    @EnvironmentObject var ui: UIState
    let title: String
    let sub: String

    var body: some View {
        HStack(spacing: Socle.M.space2) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong).lineLimit(1).truncationMode(.tail)
                Text(sub).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 0)
            Button(L.t("publish.close")) { ui.workspace = nil }
                .buttonStyle(SocleButtonStyle(.tertiary, height: Socle.M.sizeControl)).fixedSize()
        }
        .padding(Socle.M.space3)
    }
}

struct PublishPanel: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    let id: UUID

    private var post: Post { store.post(id) ?? Post() }
    private var channel: Channel? { store.channel(post.channelID) }

    private func binding(_ l: Lang) -> Binding<String> {
        Binding(get: { store.post(id)?.draft(l) ?? "" },
                set: { v in guard var q = store.post(id) else { return }; q.drafts[l.rawValue] = v; store.update(q) })
    }

    var body: some View {
        let order = Publish.order(channel?.kind)
        let texts = order.map { post.draft($0) }
        let links = Publish.links(in: texts), tags = Publish.hashtags(in: texts)
        VStack(spacing: 0) {
            PanelHeader(title: post.title, sub: channel?.name ?? "—")
            Divider().overlay(Socle.C.borderSubtle)
            ScrollView {
                VStack(alignment: .leading, spacing: Socle.M.space3) {
                    ForEach(order) { l in textBlock(l) }
                    if !links.isEmpty || !tags.isEmpty {
                        Text(L.t("publish.links").uppercased()).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textSubtle).lineLimit(1)
                        ForEach(Array(links.prefix(4)), id: \.self) { copyRow($0, $0) }
                        if !tags.isEmpty { copyRow(tags.joined(separator: " "), tags.joined(separator: " ")) }
                    }
                }
                .padding(Socle.M.space3)
            }
            Divider().overlay(Socle.C.borderSubtle)
            footer.padding(Socle.M.space3)
        }
    }

    private func textBlock(_ l: Lang) -> some View {
        let t = binding(l).wrappedValue
        let lim = Publish.limit(channel?.kind)
        let over = lim.map { t.count > $0 } ?? false
        return VStack(alignment: .leading, spacing: Socle.M.space1_5) {
            HStack(spacing: Socle.M.space2) {
                Text(l.label).socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong)
                Text(lim.map { "\(t.count) / \($0)" } ?? L.t("draft.chars", t.count))
                    .socle(Socle.T.meta).foregroundStyle(over ? Socle.C.danger : Socle.C.textSubtle).lineLimit(1)
                if over, let lim {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(Socle.C.danger)
                        .accessibilityLabel(L.t("publish.toolong", lim)).help(L.t("publish.toolong", lim))
                }
                Spacer(minLength: 0)
                CopyButton(title: L.t("action.copy")) { t }.disabled(t.isEmpty)
            }
            TextEditor(text: binding(l)).socle(Socle.T.body).socleField(multiline: true).frame(height: 84)
        }
    }

    private func copyRow(_ shown: String, _ copied: String) -> some View {
        HStack(spacing: Socle.M.space2) {
            Text(shown).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            CopyButton(title: L.t("action.copy")) { copied }
        }
    }

    private var footer: some View {
        VStack(spacing: Socle.M.space2) {
            Text(L.t("post.linkafter")).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField("https://…", text: Binding(get: { store.post(id)?.link ?? "" },
                                                set: { v in guard var q = store.post(id) else { return }; q.link = v; store.update(q) })).socleField()
            HStack(spacing: Socle.M.space2) {
                Button(L.t("publish.takeurl")) {
                    if let u = BrowserModel.shared.current?.url, var q = store.post(id) { q.link = u.absoluteString; store.update(q) }
                }
                .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                Spacer(minLength: 0)
            }
            HStack(spacing: Socle.M.space2) {
                if let n = store.nextToPublish(after: id) {
                    Button(L.t("publish.next")) { ui.openWorkspace(.post(n), store) }
                        .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControlLg)).fixedSize()
                }
                Spacer(minLength: 0)
                Button(post.status == .published ? L.t("post.published.done") : L.t("post.markpublished")) {
                    if var q = store.post(id) { q.status = .published; store.update(q) }
                }
                .buttonStyle(SocleButtonStyle(.primary, height: Socle.M.sizeControlLg)).fixedSize()
                .disabled(post.status == .published)
            }
        }
    }
}
