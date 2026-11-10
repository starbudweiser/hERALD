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
                                        open: { selectedPost = $0; tab = .posts })
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
    @EnvironmentObject var ui: UIState
    let day: Date
    let inMonth: Bool
    let open: (UUID) -> Void

    var body: some View {
        let cal = Calendar.current
        let posts = store.posts.filter { cal.isDate($0.date, inSameDayAs: day) && ui.matches($0, store) }
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
            if cal.isDateInToday(day) { Rectangle().fill(Socle.C.accent.opacity(0.14)) }
        })
        .overlay(Rectangle().stroke(Socle.C.accent.opacity(cal.isDateInToday(day) ? 0.45 : 0), lineWidth: 1.5))
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
