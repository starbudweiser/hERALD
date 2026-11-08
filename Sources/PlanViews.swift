// hERALD — le plan : calendrier du mois, tableau de suivi et fiche d'une publication.
import SwiftUI

// MARK: Calendrier

struct CalendarView: View {
    @EnvironmentObject var store: Store
    @Binding var selectedPost: UUID?
    @Binding var tab: Tab
    @State private var month = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()

    private var cal: Calendar { var c = Calendar.current; c.locale = L.locale; return c }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Socle.M.space2) {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                Text(month.formatted(.dateTime.month(.wide).year().locale(L.locale)).capitalized)
                    .socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong).frame(minWidth: 180)
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                Button(L.t("calendar.today")) { go(Date()) }
                    .buttonStyle(SocleButtonStyle(.tertiary, height: Socle.M.sizeControl)).fixedSize()
                Button(L.t("calendar.event")) { go(store.campaign.eventDate) }
                    .buttonStyle(SocleButtonStyle(.tertiary, height: Socle.M.sizeControl)).fixedSize()
                Spacer()
                ForEach(PostStatus.allCases) { StatusBadge(status: $0) }
            }
            .padding(Socle.M.space3)
            HStack(spacing: 1) {
                ForEach(weekdays, id: \.self) { d in
                    Text(d).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textSubtle).frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Socle.M.space3).padding(.bottom, Socle.M.space1)
            let days = grid
            let rows = days.count / 7
            GeometryReader { g in
                VStack(spacing: 1) {
                    ForEach(0..<rows, id: \.self) { r in
                        HStack(spacing: 1) {
                            ForEach(0..<7, id: \.self) { c in
                                DayCell(day: days[r * 7 + c], inMonth: cal.isDate(days[r * 7 + c], equalTo: month, toGranularity: .month),
                                        open: { selectedPost = $0; tab = .tracking })
                                    .frame(maxWidth: .infinity)
                                    .frame(height: (g.size.height - CGFloat(rows - 1)) / CGFloat(rows))
                            }
                        }
                    }
                }
                .background(Socle.C.border)
            }
            .padding(.horizontal, Socle.M.space3).padding(.bottom, Socle.M.space3)
        }
    }

    private var weekdays: [String] {
        let s = cal.shortWeekdaySymbols
        let f = cal.firstWeekday - 1
        return Array(s[f...] + s[..<f]).map { $0.uppercased() }
    }

    /// Semaines complètes couvrant le mois affiché.
    private var grid: [Date] {
        let first = month
        let offset = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        let start = cal.date(byAdding: .day, value: -offset, to: first) ?? first
        let count = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let cells = Int(ceil(Double(offset + count) / 7)) * 7
        return (0..<cells).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private func shift(_ n: Int) { month = cal.date(byAdding: .month, value: n, to: month) ?? month }
    private func go(_ d: Date) { month = cal.dateInterval(of: .month, for: d)?.start ?? month }
}

struct DayCell: View {
    @EnvironmentObject var store: Store
    let day: Date
    let inMonth: Bool
    let open: (UUID) -> Void

    var body: some View {
        let cal = Calendar.current
        let posts = store.posts.filter { cal.isDate($0.date, inSameDayAs: day) }
        let milestones = store.campaign.milestones.filter { cal.isDate($0.date, inSameDayAs: day) }
        let isEvent = cal.isDate(store.campaign.eventDate, inSameDayAs: day)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("\(cal.component(.day, from: day))").socle(Socle.T.labelStrong)
                    .foregroundStyle(cal.isDateInToday(day) ? Socle.C.accentText : inMonth ? Socle.C.textStrong : Socle.C.textDisabled)
                if isEvent { Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Socle.C.warning) }
                Spacer(minLength: 0)
            }
            ForEach(milestones) { m in
                Text(m.title).socle(Socle.T.caption).fontWeight(.semibold).foregroundStyle(Socle.C.warning).lineLimit(1)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(posts) { p in
                        Button { open(p.id) } label: { PostChip(post: p) }.buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Socle.M.space1_5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // jour courant : fond teinté et liseré de la couleur d'accent (les deux fonds dans un seul calque)
        .background(ZStack {
            Rectangle().fill(inMonth ? Socle.C.surface : Socle.C.bgSunken)
            if cal.isDateInToday(day) { Rectangle().fill(Socle.C.accent.opacity(0.28)) }
        })
        .overlay(Rectangle().stroke(Socle.C.accent.opacity(cal.isDateInToday(day) ? 0.7 : 0), lineWidth: 1.5))
        .contentShape(Rectangle())
        .contextMenu {
            Button(L.t("post.add.day")) { open(store.addPost(on: day)) }
        }
    }
}

struct PostChip: View {
    @EnvironmentObject var store: Store
    let post: Post
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Image(systemName: store.channel(post.channelID)?.kind.symbol ?? "megaphone").font(.system(size: 9))
                .foregroundStyle(Socle.C.textSubtle)
            Text(post.title).socle(Socle.T.caption).foregroundStyle(Socle.C.text).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4).padding(.vertical, 2)
        .background(Socle.C.control, in: RoundedRectangle(cornerRadius: Socle.M.radius))
        .help("\(store.channel(post.channelID)?.name ?? "") · \(post.title) · \(post.status.label)")
    }
    private var color: Color {
        switch post.status {
        case .idea: Socle.C.textSubtle
        case .draft: Socle.C.warning
        case .approved: Socle.C.accent
        case .published: Socle.C.success
        }
    }
}

// MARK: Tableau de suivi

struct TrackingView: View {
    @EnvironmentObject var store: Store
    @Binding var selected: UUID?
    @State private var filter: PostStatus?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: Socle.M.space2) {
                    SocleSegmented(options: [nil] + PostStatus.allCases.map { Optional($0) }, selection: filter,
                                   label: { s in s.map { "\($0.label) (\(count($0)))" } ?? L.t("filter.all", store.posts.count) },
                                   onSelect: { filter = $0 })
                    Spacer()
                    Button(L.t("post.add")) { selected = store.addPost() }
                        .buttonStyle(SocleButtonStyle(.primary, height: Socle.M.sizeControl)).fixedSize()
                }
                .padding(Socle.M.space3)
                header
                Divider().overlay(Socle.C.border)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, p in
                            TrackingRow(post: p, selected: p.id == selected, striped: i % 2 == 1) { selected = p.id }
                        }
                    }
                }
                .background(Socle.C.surface)
            }
            Divider().overlay(Socle.C.border)
            Group {
                if let id = selected, store.post(id) != nil { PostEditor(id: id, selected: $selected) }
                else { EmptyState(text: L.t("post.select")) }
            }
            .frame(width: 420)
            .background(Socle.C.bg)
        }
    }

    private var rows: [Post] { store.posts.filter { filter == nil || $0.status == filter } }
    private func count(_ s: PostStatus) -> Int { store.posts.filter { $0.status == s }.count }

    private var header: some View {
        HStack(spacing: Socle.M.space2) {
            Text(L.t("col.date")).frame(width: 90, alignment: .leading)
            Text(L.t("col.title")).frame(maxWidth: .infinity, alignment: .leading)
            Text(L.t("col.channel")).frame(width: 140, alignment: .leading)
            Text(L.t("col.status")).frame(width: 90, alignment: .leading)
            Text(L.t("col.feedback")).frame(width: 70, alignment: .trailing)
        }
        .socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textSubtle)
        .padding(.horizontal, Socle.M.space3).padding(.vertical, Socle.M.space1_5)
    }
}

struct TrackingRow: View {
    @EnvironmentObject var store: Store
    let post: Post
    let selected: Bool
    /// Une ligne sur deux a un fond légèrement différent pour suivre la ligne des yeux.
    var striped = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Socle.M.space2) {
                Text(L.day(post.date)).socle(Socle.T.meta).foregroundStyle(late ? Socle.C.danger : Socle.C.textMuted)
                    .frame(width: 90, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.title).socle(Socle.T.label).foregroundStyle(Socle.C.textStrong).lineLimit(1)
                    if let m = store.milestone(post.milestoneID) {
                        Text(m.title).socle(Socle.T.caption).foregroundStyle(Socle.C.warning).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    Image(systemName: store.channel(post.channelID)?.kind.symbol ?? "megaphone").foregroundStyle(Socle.C.textSubtle)
                    Text(store.channel(post.channelID)?.name ?? "—").lineLimit(1)
                }
                .socle(Socle.T.meta).foregroundStyle(Socle.C.text).frame(width: 140, alignment: .leading)
                HStack(spacing: 4) {
                    StatusBadge(status: post.status)
                    if !post.link.isEmpty { Image(systemName: "link").font(.system(size: 10)).foregroundStyle(Socle.C.textSubtle) }
                }
                .frame(width: 90, alignment: .leading)
                Text(post.feedback.isEmpty ? "—" : L.number(post.total(.comment)) + " 💬")
                    .socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted).frame(width: 70, alignment: .trailing)
            }
            // publication faite : texte estompé (le fond reste net pour garder l'alternance)
            .opacity(post.status == .published && !selected && !hover ? 0.5 : 1)
            .padding(.horizontal, Socle.M.space3).padding(.vertical, Socle.M.space2)
            .background(selected ? Socle.C.surfaceSelected : hover ? Socle.C.surfaceHover : striped ? Socle.C.textStrong.opacity(0.09) : .clear)
            .overlay(alignment: .leading) { Rectangle().fill(selected ? Socle.C.accent : .clear).frame(width: 2) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        Divider().overlay(Socle.C.borderSubtle)
    }

    /// Date passée et pas encore publiée.
    private var late: Bool { post.status != .published && Calendar.current.startOfDay(for: post.date) < Calendar.current.startOfDay(for: Date()) }
}

/// Fiche d'une publication : liaison directe avec le plan (chaque modification est enregistrée).
struct PostEditor: View {
    @EnvironmentObject var store: Store
    let id: UUID
    @Binding var selected: UUID?
    @State private var removing = false
    @AppStorage(AgentConfig.key) private var agentRaw = Data()

    private var post: Binding<Post> {
        Binding(get: { store.post(id) ?? Post() }, set: { store.update($0) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Socle.M.space4) {
                Field(label: L.t("col.title")) { TextField("", text: post.title).socleField() }
                HStack(alignment: .top, spacing: Socle.M.space3) {
                    Field(label: L.t("col.date")) {
                        DatePicker("", selection: post.date, displayedComponents: .date).labelsHidden()
                    }.fixedSize()
                    Field(label: L.t("col.channel")) {
                        Picker("", selection: post.channelID) {
                            Text("—").tag(UUID?.none)
                            ForEach(store.data.channels) { Text($0.name).tag(Optional($0.id)) }
                        }.labelsHidden()
                    }
                }
                Field(label: L.t("col.milestone")) {
                    Picker("", selection: post.milestoneID) {
                        Text("—").tag(UUID?.none)
                        ForEach(store.campaign.milestones) { Text("\(L.day($0.date)) · \($0.title)").tag(Optional($0.id)) }
                    }.labelsHidden()
                }
                Field(label: L.t("col.status")) {
                    SocleSegmented(options: PostStatus.allCases, selection: post.wrappedValue.status, label: \.label,
                                   onSelect: { post.wrappedValue.status = $0 })
                    Text(L.t("status.manual")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Field(label: L.t("col.link")) {
                    HStack(spacing: Socle.M.space2) {
                        TextField("https://…", text: post.link).socleField()
                        Button(L.t("action.open")) { openURL(post.wrappedValue.link) }
                            .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                            .disabled(post.wrappedValue.link.isEmpty)
                    }
                    if post.wrappedValue.status == .published && post.wrappedValue.link.isEmpty {
                        Text(L.t("post.link.missing")).socle(Socle.T.meta).foregroundStyle(Socle.C.warning)
                    }
                }
                Field(label: L.t("col.notes")) {
                    TextEditor(text: post.notes).socle(Socle.T.body).socleField(multiline: true).frame(height: 90)
                }
                if AgentConfig.isEnabled(agentRaw) {
                    Button(L.t("agent.chat")) { store.agentScopeTask = true; store.agentOpen = true }
                        .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                }
                HStack(spacing: Socle.M.space2) {
                    Text(L.t("post.drafts.count", Lang.allCases.filter { !post.wrappedValue.draft($0).isEmpty }.count))
                        .socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                    Spacer()
                    Button(L.t("post.remove")) { removing = true }
                        .buttonStyle(SocleButtonStyle(.tertiary, height: Socle.M.sizeControl)).fixedSize()
                }
            }
            .padding(Socle.M.space4)
        }
        .confirmationDialog(L.t("post.remove.confirm", post.wrappedValue.title), isPresented: $removing) {
            Button(L.t("post.remove"), role: .destructive) { store.removePost(id); selected = nil }
        }
    }
}
