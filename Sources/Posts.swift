// hERALD — Publications (suivi + brouillons) : liste filtrable et inspecteur à onglets.
import SwiftUI

struct PostsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    @State private var filter: PostStatus?
    @State private var channel: UUID?

    private var rows: [Post] {
        store.posts.filter { (filter == nil || $0.status == filter) && (channel == nil || $0.channelID == channel) && ui.matches($0, store) }
    }

    var body: some View {
        SplitLayout(width: 480) {
            HStack(spacing: Socle.M.space2) {
                SocleSegmented(options: [nil] + PostStatus.allCases.map { Optional($0) }, selection: filter,
                               label: { s in s?.label ?? L.t("filter.all", store.posts.count) }, onSelect: { filter = $0 })
                Spacer(minLength: 0)
                Menu {
                    Button { channel = nil } label: { if channel == nil { Label(L.t("filter.channels"), systemImage: "checkmark") } else { Text(L.t("filter.channels")) } }
                    Divider()
                    ForEach(store.data.channels) { c in
                        Button { channel = c.id } label: { if channel == c.id { Label(c.name, systemImage: "checkmark") } else { Text(c.name) } }
                    }
                } label: {
                    Image(systemName: channel == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .foregroundStyle(channel == nil ? Socle.C.textMuted : Socle.C.brand)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel(L.t("col.channel")).help(L.t("col.channel"))
            }
            .padding(Socle.M.space3)
            Divider().overlay(Socle.C.borderSubtle)
            ForEach(rows) { p in
                ItemRow(selected: p.id == ui.selectedPost, symbol: store.channel(p.channelID)?.kind.symbol ?? "megaphone",
                        title: p.title, meta: L.day(p.date), metaColor: late(p) ? Socle.C.danger : Socle.C.textSubtle,
                        action: { ui.selectedPost = p.id }) { StatusBadge(status: p.status) }
                    .opacity(p.status == .published && p.id != ui.selectedPost ? 0.6 : 1)
                    .postDeleteMenu(p)
            }
        } detail: {
            if let id = ui.selectedPost, store.post(id) != nil { PostInspector(id: id, selected: $ui.selectedPost) }
            else { EmptyState(text: L.t("post.select")) }
        }
    }

    private func late(_ p: Post) -> Bool { p.status != .published && Calendar.current.startOfDay(for: p.date) < Calendar.current.startOfDay(for: Date()) }
}

enum InspectorTab: String, CaseIterable, Identifiable {
    case text, numbers, feedback, notes
    var id: String { rawValue }
    var label: String { L.t("insp.\(rawValue)") }
}

/// Fiche d'une publication : en-tête (titre, date, canal, statut), quatre onglets, pied d'actions.
struct PostInspector: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    let id: UUID
    @Binding var selected: UUID?
    @State private var tab: InspectorTab = .text
    @State private var lang: Lang = Lang(rawValue: L.lang) ?? .en
    @State private var removing = false
    @State private var manual: UUID?
    @AppStorage(AgentConfig.key) private var agentRaw = Data()

    private var post: Binding<Post> { Binding(get: { store.post(id) ?? Post() }, set: { store.update($0) }) }
    private var text: Binding<String> {
        Binding(get: { post.wrappedValue.draft(lang) },
                set: { v in var q = post.wrappedValue; q.drafts[lang.rawValue] = v; post.wrappedValue = q })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Socle.M.space3) {
            header
            SocleSegmented(options: InspectorTab.allCases, selection: tab, label: \.label, onSelect: { tab = $0 })
            Group {
                switch tab {
                case .text: textTab
                case .numbers: numbersTab
                case .feedback: feedbackTab
                case .notes: notesTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .padding(Socle.M.space4)
        .sheet(item: Binding(get: { manual.map { EntryID(id: $0) } }, set: { manual = $0?.id })) { e in
            ManualStatsSheet(postID: e.id).environmentObject(store)
        }
        .confirmationDialog(L.t("post.remove.confirm", post.wrappedValue.title), isPresented: $removing) {
            Button(L.t("post.remove"), role: .destructive) { store.removePost(id); selected = nil }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Socle.M.space2) {
            TextField("", text: post.title).socleField().socle(Socle.T.heading)
            HStack(spacing: Socle.M.space2) {
                DatePicker("", selection: post.date, displayedComponents: .date).labelsHidden().fixedSize()
                Picker("", selection: post.channelID) {
                    Text("—").tag(UUID?.none)
                    ForEach(store.data.channels) { Text($0.name).tag(Optional($0.id)) }
                }
                .labelsHidden().frame(maxWidth: 170)
                Spacer(minLength: 0)
                Menu {
                    ForEach(PostStatus.allCases) { s in Button(s.label) { post.wrappedValue.status = s } }
                } label: { StatusBadge(status: post.wrappedValue.status) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(L.t("status.manual"))
            }
        }
    }

    // MARK: Texte

    private var textTab: some View {
        VStack(alignment: .leading, spacing: Socle.M.space2) {
            HStack(spacing: Socle.M.space2) {
                SocleSegmented(options: Lang.allCases, selection: lang, label: { $0.label }, onSelect: { lang = $0 })
                Spacer(minLength: 0)
                Text(L.t("draft.chars", text.wrappedValue.count)).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).lineLimit(1)
            }
            if let n = store.channel(post.wrappedValue.channelID)?.notes, !n.isEmpty {
                Text(n).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted).lineLimit(2)
            }
            TextEditor(text: text).socle(Socle.T.reading).socleField(multiline: true).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Chiffres

    private var numbersTab: some View {
        let p = post.wrappedValue
        let last = p.stats?.last
        return VStack(alignment: .leading, spacing: Socle.M.space3) {
            if let e = p.statsError { Callout(kind: .warning, text: e) }
            if let last {
                HStack(spacing: Socle.M.space2) {
                    tile(L.t("stats.kpi.views"), last.views)
                    tile(L.t("stats.kpi.interactions"), last.interactions)
                    tile(L.t("stats.kpi.downloads"), last.downloads)
                }
                Text(L.t("stats.checked", L.date(last.date))).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
            } else {
                Text(L.t("insp.numbers.none")).socle(Socle.T.body).foregroundStyle(Socle.C.textSubtle)
            }
            Button(L.t("stats.manual.add")) { manual = id }
                .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
            Spacer(minLength: 0)
        }
    }

    private func tile(_ label: String, _ v: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted).lineLimit(1).minimumScaleFactor(0.8)
            Text(v.map(L.number) ?? "—").socle(Socle.T.stat).socleValue().lineLimit(1)
        }
        .padding(Socle.M.space3).frame(maxWidth: .infinity, alignment: .leading)
        .background(Socle.C.bgSunken, in: RoundedRectangle(cornerRadius: Socle.M.radius))
    }

    // MARK: Retours

    private var feedbackTab: some View {
        let items = post.wrappedValue.feedback.sorted { $0.date > $1.date }
        return VStack(alignment: .leading, spacing: Socle.M.space2) {
            HStack {
                Text(items.isEmpty ? L.t("feedback.none") : "\(items.count)")
                    .socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                Spacer()
                Button(L.t("insp.feedback.open")) { ui.selectedPost = id; ui.tab = .feedback }
                    .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { f in
                        HStack(alignment: .firstTextBaseline, spacing: Socle.M.space2) {
                            Text(L.day(f.date)).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).frame(width: 84, alignment: .leading)
                            Text(f.author.map { "u/\($0)" } ?? "\(f.kind.label) \(L.number(f.value))")
                                .socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong).lineLimit(1).fixedSize()
                            Text(f.text).socle(Socle.T.body).foregroundStyle(Socle.C.text).lineLimit(2)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, Socle.M.space1_5)
                        Divider().overlay(Socle.C.borderSubtle)
                    }
                }
            }
        }
    }

    // MARK: Notes

    private var notesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Socle.M.space3) {
                Field(label: L.t("col.milestone")) {
                    Picker("", selection: post.milestoneID) {
                        Text("—").tag(UUID?.none)
                        ForEach(store.campaign.milestones) { Text("\(L.day($0.date)) · \($0.title)").tag(Optional($0.id)) }
                    }.labelsHidden()
                }
                Field(label: L.t("col.notes")) {
                    TextEditor(text: post.notes).socle(Socle.T.body).socleField(multiline: true).frame(height: 140)
                }
                HStack(spacing: Socle.M.space2) {
                    if AgentConfig.isEnabled(agentRaw) {
                        Button(L.t("agent.chat")) { ui.selectedPost = id; store.agentScopeTask = true; store.agentOpen = true }
                            .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                    }
                    Spacer()
                    Button(L.t("post.remove")) { removing = true }
                        .buttonStyle(SocleButtonStyle(.tertiary, height: Socle.M.sizeControl)).fixedSize()
                }
            }
        }
    }

    // MARK: Pied

    private var footer: some View {
        VStack(spacing: Socle.M.space2) {
            TextField(L.t("post.linkafter"), text: post.link).socleField()
            HStack(spacing: Socle.M.space2) {
                CopyButton(title: L.t("action.copy")) { text.wrappedValue }.disabled(text.wrappedValue.isEmpty)
                Button(L.t("publish.open")) { ui.openWorkspace(.post(id), store) }
                    .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                Spacer(minLength: 0)
                Button(post.wrappedValue.status == .published ? L.t("post.published.done") : L.t("post.markpublished")) {
                    post.wrappedValue.status = .published
                }
                .buttonStyle(SocleButtonStyle(.primary, height: Socle.M.sizeControlLg)).fixedSize()
                .disabled(post.wrappedValue.status == .published)
            }
        }
    }
}

/// Clic droit « Supprimer la publication » (avec confirmation) sur une ligne de liste ou une pastille du calendrier.
private struct PostDeleteMenu: ViewModifier {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    let post: Post
    @State private var asking = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button(L.t("post.remove"), role: .destructive) { asking = true }
            }
            .confirmationDialog(L.t("post.remove.confirm", post.title), isPresented: $asking) {
                Button(L.t("post.remove"), role: .destructive) {
                    if ui.selectedPost == post.id { ui.selectedPost = nil }
                    store.removePost(post.id)
                }
            }
    }
}

extension View {
    func postDeleteMenu(_ post: Post) -> some View { modifier(PostDeleteMenu(post: post)) }
}
