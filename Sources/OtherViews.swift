// hERALD — brouillons par langue, retours, veille (rapport hebdomadaire) et canaux.
import SwiftUI

// MARK: Retours

struct FeedbackView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    @Binding var selected: UUID?
    @State private var kind: FeedbackKind = .comment
    @State private var value = 1
    @State private var date = Date()
    @State private var text = ""
    @State private var message: String?
    /// Réponses non lues au moment où la publication a été ouverte (restent signalées « nouveau » pendant la lecture).
    @State private var fresh: Set<UUID> = []

    private func open(_ id: UUID) {
        selected = id; message = nil
        fresh = Set(store.post(id)?.feedback.filter { $0.unread == true }.map(\.id) ?? [])
        store.markFeedbackRead(id)
    }

    var body: some View {
        SplitLayout {
            ForEach(feedbackPosts) { p in
                ItemRow(selected: p.id == selected, symbol: p.unreadFeedback > 0 ? "bubble.left.fill" : "bubble.left",
                        tint: p.unreadFeedback > 0 ? Socle.C.brand : Socle.C.textMuted, title: p.title,
                        meta: summary(p), action: { open(p.id) }) {
                    if p.unreadFeedback > 0 { Badge(text: L.t("feedback.unread", p.unreadFeedback), kind: .accent) }
                    else { StatusBadge(status: p.status) }
                }
            }
        } detail: {
            if let id = selected, let p = store.post(id) { detail(p) } else { EmptyState(text: L.t("feedback.select")) }
        }
    }

    private var feedbackPosts: [Post] {
        store.posts.filter { ui.matches($0, store) }
            .sorted { ($0.status == .published ? 0 : 1, $0.date) < ($1.status == .published ? 0 : 1, $1.date) }
    }

    /// Une seule ligne : nombre de commentaires ou « aucun retour ».
    private func summary(_ p: Post) -> String {
        p.feedback.isEmpty ? L.t("feedback.none") : "\(FeedbackKind.comment.label) \(L.number(p.total(.comment)))"
    }

    private func detail(_ p: Post) -> some View {
        VStack(alignment: .leading, spacing: Socle.M.space3) {
            HStack {
                Text(p.title).socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong)
                Spacer()
                if !p.link.isEmpty {
                    Button(L.t("action.open")) { openURL(p.link) }
                        .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                }
            }
            HStack(spacing: Socle.M.space2) {
                ForEach(FeedbackKind.allCases.filter { $0 != .other }) { k in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(k.label).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted)
                        Text(L.number(p.total(k))).socle(Socle.T.stat).socleValue()
                    }
                    .padding(Socle.M.space3).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Socle.C.surface, in: RoundedRectangle(cornerRadius: Socle.M.radius))
                }
            }
            // Saisie d'un retour
            HStack(alignment: .bottom, spacing: Socle.M.space2) {
                Field(label: L.t("feedback.kind")) {
                    Picker("", selection: $kind) { ForEach(FeedbackKind.allCases) { Text($0.label).tag($0) } }
                        .labelsHidden().frame(width: 150)
                }
                Field(label: L.t("feedback.value")) {
                    TextField("", value: $value, format: .number).socleField().frame(width: 90)
                }
                Field(label: L.t("col.date")) {
                    DatePicker("", selection: $date, displayedComponents: .date).labelsHidden()
                }.fixedSize()
                Spacer(minLength: 0)
            }
            HStack(alignment: .bottom, spacing: Socle.M.space2) {
                Field(label: L.t("feedback.text")) { TextField("", text: $text).socleField() }
                Button(L.t("action.add")) {
                    var q = p
                    q.feedback.append(Feedback(date: date, kind: kind, value: value, text: text.trimmingCharacters(in: .whitespaces)))
                    store.update(q); text = ""; value = 1
                }
                .buttonStyle(SocleButtonStyle(.primary, height: Socle.M.sizeControlLg)).fixedSize()
            }
            HStack(spacing: Socle.M.space2) {
                Text(message ?? L.t("feedback.csv.help")).socle(Socle.T.meta)
                    .foregroundStyle(message == nil ? Socle.C.textSubtle : Socle.C.success)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(L.t("feedback.import")) {
                    if let n = store.importFeedback(into: p.id) { message = L.t("feedback.imported", n) }
                }
                .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
            }
            Divider().overlay(Socle.C.border)
            if p.feedback.isEmpty { EmptyState(text: L.t("feedback.none")) }
            else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(p.feedback.sorted { $0.date > $1.date }) { f in
                            HStack(alignment: .firstTextBaseline, spacing: Socle.M.space2) {
                                Text(L.day(f.date)).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).frame(width: 90, alignment: .leading)
                                Badge(text: f.kind.label, kind: f.kind == .comment ? .accent : .neutral)
                                if let a = f.author {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: Socle.M.space1_5) {
                                            Text("u/\(a)").socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong)
                                            if fresh.contains(f.id) || f.unread == true { Badge(text: L.t("feedback.new"), kind: .success) }
                                        }
                                        Text(f.text).socle(Socle.T.body).foregroundStyle(Socle.C.text)
                                            .lineLimit(8).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                                    }
                                } else {
                                    Text(L.number(f.value)).socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong)
                                    Text(f.text).socle(Socle.T.body).foregroundStyle(Socle.C.text).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                if let u = f.url {
                                    Button { openURL(u) } label: { Image(systemName: "arrow.up.right.square") }
                                        .buttonStyle(.plain).foregroundStyle(Socle.C.textMuted).help(L.t("feedback.reply.open"))
                                }
                                Button {
                                    var q = p; q.feedback.removeAll { $0.id == f.id }; store.update(q)
                                } label: { Image(systemName: "trash") }
                                    .buttonStyle(.plain).foregroundStyle(Socle.C.textMuted).help(L.t("action.remove"))
                            }
                            .padding(.vertical, Socle.M.space1_5)
                            Divider().overlay(Socle.C.borderSubtle)
                        }
                    }
                }
            }
        }
        .padding(Socle.M.space4)
    }
}

// MARK: Veille

struct WatchView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    @State private var selected: UUID?
    @State private var input = ""
    @State private var name = ""
    @State private var problem: String?

    var body: some View {
        SplitLayout {
            ItemRow(selected: selected == nil, symbol: "doc.text", title: L.t("report.title"),
                    meta: L.t("report.period", L.day(store.weekReport.start), L.day(store.weekReport.end))) { selected = nil }
            SectionBar(title: L.t("watch.title")) {
                if store.checking { ProgressView().controlSize(.small) }
                Button(L.t("watch.check")) { Task { await store.checkAll() } }
                    .buttonStyle(SocleButtonStyle(.primary, height: Socle.M.sizeControl)).fixedSize()
                    .disabled(store.checking || store.data.watch.isEmpty)
            }
            VStack(alignment: .leading, spacing: Socle.M.space1_5) {
                TextField(L.t("watch.add.placeholder"), text: $input).socleField()
                HStack(spacing: Socle.M.space1_5) {
                    TextField(L.t("watch.add.name"), text: $name).socleField()
                    Button(L.t("action.add")) {
                        problem = store.addWatch(input, name: name)
                        if problem == nil { input = ""; name = "" }
                    }
                    .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControlLg)).fixedSize()
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let problem { Text(problem).socle(Socle.T.meta).foregroundStyle(Socle.C.danger) }
            }
            .padding(.horizontal, Socle.M.space3).padding(.bottom, Socle.M.space2)
            Divider().overlay(Socle.C.borderSubtle)
            ForEach(store.data.watch.filter { ui.matches($0.name, $0.ref, $0.notes) }) { w in
                ItemRow(selected: w.id == selected, symbol: w.error != nil ? "exclamationmark.triangle" : "shippingbox",
                        tint: w.error != nil ? Socle.C.warning : Socle.C.textMuted, title: w.name,
                        meta: w.latest?.version ?? L.t("watch.unchecked"), metaColor: Socle.C.accentText,
                        action: { selected = w.id }) { Badge(text: w.kind.label) }
            }
        } detail: {
            if let id = selected, let w = store.data.watch.first(where: { $0.id == id }) { WatchDetail(item: w, selected: $selected) }
            else { ReportView() }
        }
    }
}

struct WatchDetail: View {
    @EnvironmentObject var store: Store
    let item: WatchItem
    @Binding var selected: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: Socle.M.space3) {
            HStack(spacing: Socle.M.space2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong)
                    Text("\(item.kind.label) · \(item.ref)").socle(Socle.T.monoSm).foregroundStyle(Socle.C.textSubtle)
                }
                Spacer()
                if let u = item.pageURL {
                    Button(L.t("action.open")) { Browser.openURL(u) }
                        .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                }
                Button(L.t("action.remove")) { store.data.watch.removeAll { $0.id == item.id }; selected = nil }
                    .buttonStyle(SocleButtonStyle(.tertiary, height: Socle.M.sizeControl)).fixedSize()
            }
            if let e = item.error { Callout(kind: .warning, text: e) }
            Text(item.lastChecked.map { L.t("watch.checked", L.date($0)) } ?? L.t("watch.unchecked"))
                .socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
            Field(label: L.t("col.notes")) {
                TextField("", text: Binding(
                    get: { store.data.watch.first { $0.id == item.id }?.notes ?? "" },
                    set: { v in if let i = store.data.watch.firstIndex(where: { $0.id == item.id }) { store.data.watch[i].notes = v } }))
                .socleField()
            }
            Text(L.t("watch.history").uppercased()).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textSubtle)
            if item.history.isEmpty { EmptyState(text: L.t("watch.history.empty")) }
            else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(item.history.enumerated().reversed()), id: \.offset) { _, s in
                            HStack(spacing: Socle.M.space3) {
                                Text(L.date(s.date)).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).frame(width: 150, alignment: .leading)
                                Text(s.version).socle(Socle.T.mono).foregroundStyle(Socle.C.accentText).frame(width: 140, alignment: .leading)
                                Text(s.published.map { L.t("watch.published", L.day($0)) } ?? "")
                                    .socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted)
                                if let d = s.downloads {
                                    Text("⬇︎ \(L.number(d))").socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted)
                                }
                                if let e = s.endorsements {
                                    Text("👍 \(L.number(e))").socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, Socle.M.space1_5)
                            Divider().overlay(Socle.C.borderSubtle)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Socle.M.space4)
    }
}

/// Rapport de la semaine, lisible dans l'appli et copiable en Markdown.
struct ReportView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let r = store.weekReport
        ScrollView {
            VStack(alignment: .leading, spacing: Socle.M.space4) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.t("report.title")).socle(Socle.T.display).foregroundStyle(Socle.C.textStrong)
                        Text(L.t("report.period", L.day(r.start), L.day(r.end))).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                    }
                    Spacer()
                    CopyButton(title: L.t("report.copy")) { r.markdown(channel: store.channel) }
                }
                section(L.t("report.releases"), r.releases.isEmpty ? [L.t("report.releases.none")]
                        : r.releases.map { "\($0.name) — \($0.version) (\($0.date.map(L.day) ?? "—"))" })
                section(L.t("report.watched"), r.watched.isEmpty ? [L.t("report.none")]
                        : r.watched.map { w in "\(w.name) — \(w.latest?.version ?? L.t("watch.unchecked"))" + (w.error.map { " ⚠︎ \($0)" } ?? "") })
                section(L.t("report.published"), r.published.isEmpty ? [L.t("report.none")]
                        : r.published.map { "\(L.day($0.date)) · \(store.channel($0.channelID)?.name ?? "—") · \($0.title)" })
                section(L.t("report.feedback"), r.feedback.isEmpty ? [L.t("report.none")]
                        : r.feedback.map { "\($0.0.title) · \($0.1.kind.label) \(L.number($0.1.value))" + ($0.1.text.isEmpty ? "" : " — \($0.1.text)") })
                section(L.t("report.upcoming"), r.upcoming.isEmpty ? [L.t("report.none")]
                        : r.upcoming.map { "\(L.day($0.date)) · \(store.channel($0.channelID)?.name ?? "—") · \($0.title) (\($0.status.label))" })
                Text(L.t("report.note")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
            }
            .padding(Socle.M.space6)
            .frame(maxWidth: 860, alignment: .leading)
        }
    }

    private func section(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: Socle.M.space1_5) {
            Text(title.uppercased()).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.warning)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                HStack(alignment: .firstTextBaseline, spacing: Socle.M.space2) {
                    Text("•").foregroundStyle(Socle.C.textSubtle)
                    Text(l).socle(Socle.T.bodyLg).foregroundStyle(Socle.C.text).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Socle.M.space4).frame(maxWidth: .infinity, alignment: .leading)
        .background(Socle.C.surface, in: RoundedRectangle(cornerRadius: Socle.M.radiusMd))
        .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusMd).stroke(Socle.C.border, lineWidth: 1))
    }
}

// MARK: Canaux

struct ChannelsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    @State private var selected: UUID?

    var body: some View {
        SplitLayout {
            SectionBar(title: L.t("channels.title")) {
                Button(L.t("action.add")) {
                    let c = Channel(name: L.t("channel.new"))
                    store.data.channels.append(c); selected = c.id
                }
                .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
            }
            ForEach(store.data.channels.filter { ui.matches($0.name, $0.url, $0.notes) }) { c in
                ItemRow(selected: c.id == selected, symbol: c.kind.symbol, title: c.name,
                        meta: L.t("channel.uses", usage(c.id)), action: { selected = c.id })
            }
        } detail: {
            if let id = selected, let i = store.data.channels.firstIndex(where: { $0.id == id }) { editor(i) }
            else { EmptyState(text: L.t("channel.select")) }
        }
    }

    private func usage(_ id: UUID) -> Int { store.data.campaigns.flatMap(\.posts).filter { $0.channelID == id }.count }

    private func editor(_ i: Int) -> some View {
        let c = $store.data.channels[i]
        return VStack(alignment: .leading, spacing: Socle.M.space4) {
            HStack(alignment: .top, spacing: Socle.M.space3) {
                Field(label: L.t("channel.name")) { TextField("", text: c.name).socleField() }
                Field(label: L.t("channel.kind")) {
                    Picker("", selection: c.kind) { ForEach(ChannelKind.allCases) { Text($0.label).tag($0) } }
                        .labelsHidden().frame(width: 160)
                }
            }
            Field(label: L.t("channel.url")) {
                HStack(spacing: Socle.M.space2) {
                    TextField("https://…", text: c.url).socleField()
                    Button(L.t("action.open")) { openURL(c.wrappedValue.url) }
                        .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                        .disabled(c.wrappedValue.url.isEmpty)
                }
            }
            Field(label: L.t("channel.notes")) {
                TextEditor(text: c.notes).socle(Socle.T.body).socleField(multiline: true).frame(height: 120)
            }
            HStack {
                Spacer()
                Button(L.t("action.remove")) {
                    let id = c.wrappedValue.id
                    selected = nil
                    store.data.channels.removeAll { $0.id == id }
                }
                .buttonStyle(SocleButtonStyle(.tertiary, height: Socle.M.sizeControl)).fixedSize()
            }
            Spacer()
        }
        .padding(Socle.M.space4)
    }
}
