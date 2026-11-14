// hERALD — mode guidé : l'écran « Ma campagne » (préparer, publier, écouter) et la fiche d'une publication en trois gestes
// (texte, publication, lien). Une seule étape est ouverte à la fois ; chaque ligne n'a qu'un bouton.
import SwiftUI
import AppKit

struct GuideTarget: Identifiable { let id: UUID; var step: Int }

struct GuideView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    @State private var openStep: Int?
    @State private var target: GuideTarget?

    private func hasText(_ p: Post) -> Bool { Lang.allCases.contains { !p.draft($0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    private var open: [Post] { store.posts.filter { $0.status != .published && $0.archived != true } }
    private var noText: [Post] { open.filter { !hasText($0) } }
    private var published: [Post] { store.posts.filter { $0.status == .published && $0.archived != true } }
    private var noLink: [Post] { published.filter { $0.link.isEmpty && $0.noLink != true && $0.feedback.isEmpty } }
    private var unread: Int { published.reduce(0) { $0 + $1.unreadFeedback } }
    /// Étape à ouvrir d'office : la première qui n'est pas terminée.
    private var current: Int { !noText.isEmpty ? 1 : (!open.isEmpty ? 2 : 3) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Socle.M.space3) {
                header
                step(1, L.t("guide.s1"), L.t("guide.s1.sub", open.count - noText.count, open.count), done: noText.isEmpty) { s1 }
                step(2, L.t("guide.s2"), L.t("guide.s2.sub", published.count, published.count + open.count), done: open.isEmpty) { s2 }
                step(3, L.t("guide.s3"), published.isEmpty ? L.t("guide.s3.off") : L.t("guide.s3.sub", published.count), done: false, off: published.isEmpty) { s3 }
            }
            .padding(Socle.M.space4).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .soclePanel()
        .sheet(item: $target) { t in GuidedPostSheet(id: t.id, step: t.step).environmentObject(store).environmentObject(ui) }
    }

    private var header: some View {
        let d = store.daysLeft(store.campaign)
        let when = d == 0 ? L.t("countdown.today") : (d > 0 ? L.t("countdown.left", d) : L.t("countdown.past", -d))
        let total = max(store.posts.count, 1)
        return VStack(alignment: .leading, spacing: Socle.M.space2) {
            HStack(alignment: .firstTextBaseline) {
                Text(store.campaign.name).socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong).lineLimit(1)
                Spacer(minLength: 8)
                Text(L.t("guide.release", when, L.day(store.campaign.eventDate))).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted)
            }
            ProgressBar(value: Double(store.posts.filter { $0.status == .published }.count) / Double(total))
        }
    }

    @ViewBuilder private func step<C: View>(_ n: Int, _ title: String, _ sub: String, done: Bool, off: Bool = false, @ViewBuilder content: () -> C) -> some View {
        let isOpen = (openStep ?? current) == n
        VStack(alignment: .leading, spacing: Socle.M.space2) {
            Button { withAnimation(.easeOut(duration: 0.2)) { openStep = isOpen ? 0 : n } } label: {
                HStack(spacing: Socle.M.space3) {
                    ZStack {
                        Circle().fill(done ? Socle.C.success.opacity(0.25) : Socle.C.accentFill.opacity(off ? 0.4 : 1)).frame(width: 24, height: 24)
                        if done { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Socle.C.success) }
                        else { Text("\(n)").socle(Socle.T.labelStrong).foregroundStyle(Socle.C.onAccentFill) }
                    }
                    Text(title).socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong)
                    Spacer(minLength: 8)
                    Text(sub).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted).lineLimit(1)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down").font(.system(size: 10)).foregroundStyle(Socle.C.textSubtle)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen { content() }
        }
        .padding(Socle.M.space3).frame(maxWidth: .infinity, alignment: .leading).soclePanel()
        .overlay(RoundedRectangle(cornerRadius: Socle.M.radius).stroke(isOpen && !done ? Socle.C.accent : Color.clear, lineWidth: 1.5))
        .opacity(off && !isOpen ? 0.6 : 1)
    }

    private func line(_ p: Post, _ button: String, _ step: Int, primary: Bool = false) -> some View {
        HStack(spacing: Socle.M.space3) {
            Image(systemName: store.channel(p.channelID)?.kind.symbol ?? "megaphone").frame(width: 20).foregroundStyle(Socle.C.textMuted)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.title).socle(Socle.T.body).foregroundStyle(Socle.C.textStrong).lineLimit(1)
                Text(L.day(p.date)).socle(Socle.T.meta).foregroundStyle(Calendar.current.startOfDay(for: p.date) < Calendar.current.startOfDay(for: Date()) && p.status != .published ? Socle.C.danger : Socle.C.textSubtle)
            }
            Spacer(minLength: 8)
            Button(button) { target = GuideTarget(id: p.id, step: step) }
                .buttonStyle(SocleButtonStyle(primary ? .primary : .secondary, height: Socle.M.sizeControl)).fixedSize()
        }
        .padding(.vertical, 6)
        .overlay(alignment: .top) { Divider().overlay(Socle.C.borderSubtle) }
    }

    @ViewBuilder private var s1: some View {
        if noText.isEmpty { Text(L.t("guide.done1")).socle(Socle.T.body).foregroundStyle(Socle.C.textSubtle) }
        ForEach(noText.prefix(5)) { line($0, L.t("guide.write"), 1, primary: $0.id == noText.first?.id) }
        more(noText.count)
    }
    @ViewBuilder private var s2: some View {
        if open.isEmpty { Text(L.t("guide.done2")).socle(Socle.T.body).foregroundStyle(Socle.C.textSubtle) }
        ForEach(open.prefix(5)) { p in
            hasText(p) ? line(p, L.t("guide.review"), 2, primary: p.id == open.first?.id) : line(p, L.t("guide.write"), 1)
        }
        more(open.count)
    }
    @ViewBuilder private var s3: some View {
        if unread > 0 {
            HStack {
                Text(L.t("guide.unread", unread)).socle(Socle.T.body).foregroundStyle(Socle.C.textStrong)
                Spacer(minLength: 8)
                Button(L.t("guide.feedback")) { ui.tab = .feedback }
                    .buttonStyle(SocleButtonStyle(.primary, height: Socle.M.sizeControl)).fixedSize()
            }
        } else if noLink.isEmpty {
            Text(L.t("guide.quiet")).socle(Socle.T.body).foregroundStyle(Socle.C.textSubtle)
        }
        if !noLink.isEmpty {
            Text(L.t("guide.nolink")).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted)
            ForEach(noLink.prefix(5)) { line($0, L.t("guide.link"), 3) }
        }
    }
    @ViewBuilder private func more(_ n: Int) -> some View {
        if n > 5 {
            Button(L.t("guide.all")) { ui.tab = .posts; ui.guided = false }
                .buttonStyle(.plain).socle(Socle.T.meta).foregroundStyle(Socle.C.accentText).padding(.top, 4)
        }
    }
}

/// Une publication en trois gestes : texte, publication, lien.
struct GuidedPostSheet: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @State var step: Int
    @State private var lang: Lang = Lang(rawValue: L.lang) ?? .en

    init(id: UUID, step: Int) { self.id = id; _step = State(initialValue: step) }

    private var post: Binding<Post> { Binding(get: { store.post(id) ?? Post() }, set: { store.update($0) }) }
    private var text: Binding<String> {
        Binding(get: { post.wrappedValue.draft(lang) },
                set: { v in var q = post.wrappedValue; q.drafts[lang.rawValue] = v; post.wrappedValue = q })
    }
    private var channel: Channel? { store.channel(post.wrappedValue.channelID) }

    var body: some View {
        VStack(alignment: .leading, spacing: Socle.M.space3) {
            HStack {
                Text(post.wrappedValue.title).socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong).lineLimit(1)
                Spacer()
                Button(L.t("publish.close")) { dismiss() }.buttonStyle(SocleButtonStyle(.secondary)).fixedSize().keyboardShortcut(.cancelAction)
            }
            stepper
            Group {
                switch step {
                case 1: textStep
                case 2: publishStep
                default: linkStep
                }
            }
            .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        }
        .padding(Socle.M.space5).frame(width: 660)
        .background(Socle.C.bg)
    }

    private var stepper: some View {
        HStack(spacing: Socle.M.space2) {
            ForEach(1...3, id: \.self) { n in
                HStack(spacing: 6) {
                    Text("\(n)").socle(Socle.T.labelStrong).foregroundStyle(n == step ? Socle.C.onAccentFill : Socle.C.textMuted)
                        .frame(width: 22, height: 22).background(n == step ? Socle.C.accentFill : Socle.C.bgSunken, in: Circle())
                    Text(L.t("gp.step\(n)")).socle(n == step ? Socle.T.labelStrong : Socle.T.label).foregroundStyle(n == step ? Socle.C.textStrong : Socle.C.textMuted)
                }
                if n < 3 { Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Socle.C.textDisabled) }
            }
        }
    }

    private var textStep: some View {
        VStack(alignment: .leading, spacing: Socle.M.space2) {
            HStack {
                SocleSegmented(options: Lang.allCases, selection: lang, label: { $0.label }, onSelect: { lang = $0 })
                Spacer(minLength: 0)
                Text(L.t("draft.chars", text.wrappedValue.count)).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
            }
            TextEditor(text: text).socle(Socle.T.reading).socleField(multiline: true).frame(height: 280)
                .overlay {
                    if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        WritingAssistant(postID: id, lang: lang, text: text)
                    }
                }
            HStack {
                Spacer()
                Button(L.t("gp.next")) { step = 2 }
                    .buttonStyle(SocleButtonStyle(.primary, height: Socle.M.sizeControlLg)).fixedSize()
                    .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var publishStep: some View {
        VStack(alignment: .leading, spacing: Socle.M.space3) {
            if text.wrappedValue.isEmpty { Callout(kind: .info, text: L.t("gp.empty")) }
            Text(L.t("gp.how")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted).fixedSize(horizontal: false, vertical: true)
            ScrollView { Text(text.wrappedValue).socle(Socle.T.reading).foregroundStyle(Socle.C.text).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                .frame(height: 150).padding(Socle.M.space3).background(Socle.C.bgSunken, in: RoundedRectangle(cornerRadius: Socle.M.radius))
            HStack(spacing: Socle.M.space2) {
                Button(L.t("gp.back")) { step = 1 }.buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
                CopyButton(title: L.t("action.copy")) { text.wrappedValue }.disabled(text.wrappedValue.isEmpty)
                Button(L.t("gp.open", channel?.name ?? L.t("col.channel"))) { dismiss(); ui.openWorkspace(.post(id), store) }
                    .buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
                Spacer(minLength: 0)
                Button(L.t("gp.done")) { post.wrappedValue.status = .published; step = 3 }
                    .buttonStyle(SocleButtonStyle(.primary, height: Socle.M.sizeControlLg)).fixedSize()
            }
        }
    }

    private var linkStep: some View {
        VStack(alignment: .leading, spacing: Socle.M.space3) {
            TextField(L.t("gp.link.hint"), text: post.link).socleField()
            let auto = !post.wrappedValue.link.isEmpty && store.platform(post.wrappedValue).automatic
            Callout(kind: .info, text: L.t(auto ? "gp.link.auto" : "gp.link.manual"))
            Toggle(L.t("gp.nolink"), isOn: Binding(get: { post.wrappedValue.noLink == true }, set: { post.wrappedValue.noLink = $0 ? true : nil }))
                .toggleStyle(.checkbox)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(L.t("gp.finish")) { dismiss() }.buttonStyle(SocleButtonStyle(.primary, height: Socle.M.sizeControlLg)).fixedSize()
            }
        }
    }
}
