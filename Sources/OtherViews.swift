// hERALD — brouillons par langue, retours, veille (rapport hebdomadaire) et canaux.
import SwiftUI

// MARK: Brouillons

struct DraftsView: View {
    @EnvironmentObject var store: Store
    @Binding var selected: UUID?
    @State private var lang: Lang = Lang(rawValue: L.lang) ?? .en

    var body: some View {
        SplitLayout {
            ForEach(store.posts) { p in
                ListRow(selected: p.id == selected) { selected = p.id } content: {
                    HStack(spacing: Socle.M.space1_5) {
                        Text(p.title).socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong).lineLimit(1)
                        Spacer(minLength: 0)
                        StatusBadge(status: p.status)
                    }
                    HStack(spacing: Socle.M.space1_5) {
                        Text("\(L.day(p.date)) · \(store.channel(p.channelID)?.name ?? "—")")
                            .socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).lineLimit(1)
                        Spacer(minLength: 0)
                        ForEach(Lang.allCases) { l in
                            Text(l.label).socle(Socle.T.caption)
                                .foregroundStyle(p.draft(l).isEmpty ? Socle.C.textDisabled : Socle.C.accentText)
                        }
                    }
                }
            }
        } detail: {
            if let id = selected, let p = store.post(id) { editor(p) } else { EmptyState(text: L.t("post.select")) }
        }
    }

    private func editor(_ p: Post) -> some View {
        let text = Binding<String>(
            get: { store.post(p.id)?.draft(lang) ?? "" },
            set: { v in if var q = store.post(p.id) { q.drafts[lang.rawValue] = v; store.update(q) } })
        let channel = store.channel(p.channelID)
        return VStack(alignment: .leading, spacing: Socle.M.space3) {
            HStack(spacing: Socle.M.space2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.title).socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong)
                    Text("\(L.day(p.date)) · \(channel?.name ?? "—")").socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                }
                Spacer()
                StatusBadge(status: p.status)
            }
            if let notes = channel?.notes, !notes.isEmpty {
                Text(notes).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Socle.M.space2) {
                SocleSegmented(options: Lang.allCases, selection: lang, label: { L.t("lang.\($0.rawValue)") },
                               onSelect: { lang = $0 })
                Spacer()
                Text(L.t("draft.chars", text.wrappedValue.count)).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
            }
            TextEditor(text: text).socle(Socle.T.reading).socleField(multiline: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: Socle.M.space2) {
                Text(L.t("draft.hint")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if let url = channel?.url, !url.isEmpty {
                    Button(L.t("draft.openchannel")) { openURL(url) }
                        .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                }
                if p.status == .idea || p.status == .draft {
                    Button(L.t("draft.approve")) { if var q = store.post(p.id) { q.status = .approved; store.update(q) } }
                        .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                        .disabled(text.wrappedValue.isEmpty)
                }
                CopyButton(title: L.t("action.copy"), variant: .primary) { text.wrappedValue }
                    .disabled(text.wrappedValue.isEmpty)
            }
        }
        .padding(Socle.M.space4)
    }
}

// MARK: Retours

struct FeedbackView: View {
    @EnvironmentObject var store: Store
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
            ForEach(store.posts.sorted { ($0.status == .published ? 0 : 1, $0.date) < ($1.status == .published ? 0 : 1, $1.date) }) { p in
                ListRow(selected: p.id == selected) { open(p.id) } content: {
                    HStack(spacing: Socle.M.space1_5) {
                        Text(p.title).socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong).lineLimit(1)
                        Spacer(minLength: 0)
                        if p.unreadFeedback > 0 { Badge(text: L.t("feedback.unread", p.unreadFeedback), kind: .accent) }
                        StatusBadge(status: p.status)
                    }
                    Text(summary(p)).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).lineLimit(1)
                }
            }
        } detail: {
            if let id = selected, let p = store.post(id) { detail(p) } else { EmptyState(text: L.t("feedback.select")) }
        }
    }

    private func summary(_ p: Post) -> String {
        guard !p.feedback.isEmpty else { return L.t("feedback.none") }
        return FeedbackKind.allCases.filter { k in p.feedback.contains { $0.kind == k } }
            .map { "\($0.label) \(L.number(p.total($0)))" }.joined(separator: " · ")
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
    @State private var selected: UUID?
    @State private var input = ""
    @State private var name = ""
    @State private var problem: String?

    var body: some View {
        SplitLayout(width: 340) {
            ListRow(selected: selected == nil) { selected = nil } content: {
                Label(L.t("report.title"), systemImage: "doc.text").socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong)
                Text(L.t("report.period", L.day(store.weekReport.start), L.day(store.weekReport.end)))
                    .socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
            }
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
            ForEach(store.data.watch) { w in
                ListRow(selected: w.id == selected) { selected = w.id } content: {
                    HStack(spacing: Socle.M.space1_5) {
                        Text(w.name).socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong).lineLimit(1)
                        Spacer(minLength: 0)
                        Badge(text: w.kind.label)
                    }
                    HStack(spacing: Socle.M.space1_5) {
                        Text(w.latest?.version ?? L.t("watch.unchecked")).socle(Socle.T.mono).foregroundStyle(Socle.C.accentText).lineLimit(1)
                        Spacer(minLength: 0)
                        if w.error != nil { Image(systemName: "exclamationmark.triangle").foregroundStyle(Socle.C.warning) }
                    }
                }
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
                    Button(L.t("action.open")) { NSWorkspace.shared.open(u) }
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
    @State private var selected: UUID?

    var body: some View {
        SplitLayout(width: 320) {
            SectionBar(title: L.t("channels.title")) {
                Button(L.t("action.add")) {
                    let c = Channel(name: L.t("channel.new"))
                    store.data.channels.append(c); selected = c.id
                }
                .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
            }
            ForEach(store.data.channels) { c in
                ListRow(selected: c.id == selected) { selected = c.id } content: {
                    Label(c.name, systemImage: c.kind.symbol).socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong)
                    Text(L.t("channel.uses", usage(c.id))).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                }
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
