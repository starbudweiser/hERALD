// hERALD — vue « Aujourd'hui » : chiffres du moment, liste « À faire » et prochains jalons.
import SwiftUI

struct TodoItem: Identifiable {
    enum Kind { case postToday, postLate, noLink, feedback, followUp, tracking }
    let kind: Kind
    var postID: UUID?
    var contactID: UUID?
    var title: String
    var meta: String
    var id: String { "\(kind)-\(postID?.uuidString ?? "")\(contactID?.uuidString ?? "")" }

    var symbol: String {
        switch kind {
        case .postToday: "paperplane"
        case .postLate: "exclamationmark.circle"
        case .noLink: "link.badge.plus"
        case .feedback: "bubble.left"
        case .followUp: "envelope.badge"
        case .tracking: "hourglass"
        }
    }
    /// Ce qui demande une action aujourd'hui (le suivi en cours n'est qu'une information).
    var urgent: Bool { kind != .tracking }
}

extension Store {
    func todoItems(now: Date = Date()) -> [TodoItem] {
        guard hasCampaign else { return [] }
        let cal = Calendar.current
        var out: [TodoItem] = []
        for p in posts where p.status != .published {
            if cal.isDate(p.date, inSameDayAs: now) {
                out.append(TodoItem(kind: .postToday, postID: p.id, title: p.title, meta: p.status.label))
            } else if p.date < now {
                out.append(TodoItem(kind: .postLate, postID: p.id, title: p.title, meta: L.t("today.late")))
            }
        }
        for p in posts where p.status == .published && p.link.trimmingCharacters(in: .whitespaces).isEmpty {
            out.append(TodoItem(kind: .noLink, postID: p.id, title: p.title, meta: L.t("today.nolink")))
        }
        for p in posts where p.unreadFeedback > 0 {
            out.append(TodoItem(kind: .feedback, postID: p.id, title: p.title, meta: L.t("feedback.unread", p.unreadFeedback)))
        }
        out += contactTodos(now: now)
        return out
    }


    func contactTodos(now: Date) -> [TodoItem] {
        var out: [TodoItem] = []
        for c in contacts {
            if c.followUpDue(now) {
                out.append(TodoItem(kind: .followUp, contactID: c.id, title: c.name,
                                    meta: c.nextFollowUp.map { L.t("contact.followup.on", L.shortDay($0)) } ?? ""))
            } else if c.status.waiting {
                out.append(TodoItem(kind: .tracking, contactID: c.id, title: c.name,
                                    meta: c.nextFollowUp.map { L.t("contact.followup.on", L.shortDay($0)) } ?? c.status.label))
            }
        }
        return out
    }

    var todoCount: Int { todoItems().filter(\.urgent).count }
}

struct TodayView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    @State private var selected: TodoItem.ID?

    var body: some View {
        let items = store.todoItems().filter { ui.matches($0.title, $0.meta) }
        let s = store.statsSummary(.day)
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                kpi(L.t("today.kpi.views"), L.number(s.views))
                kpi(L.t("stats.kpi.interactions"), L.number(s.interactions))
                kpi(L.t("stats.kpi.downloads"), L.number(s.downloads))
                kpi(L.t("today.kpi.step"), nextStep.0, sub: nextStep.1)
            }
            .fixedSize(horizontal: false, vertical: true)
            SplitLayout(width: 520) {
                SectionBar(title: L.t("today.todo")) { Text("\(items.count)").socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle) }
                if items.isEmpty { Text(L.t("today.none")).socle(Socle.T.body).foregroundStyle(Socle.C.textSubtle).padding(Socle.M.space4) }
                ForEach(items) { it in
                    ItemRow(selected: it.id == selected, symbol: it.symbol,
                            tint: it.urgent ? Socle.C.brand : Socle.C.textMuted, title: it.title, meta: it.meta,
                            metaColor: it.kind == .postLate ? Socle.C.danger : Socle.C.textSubtle) { open(it) }
                }
            } detail: {
                if let it = items.first(where: { $0.id == selected }) {
                    if let c = it.contactID { ContactDetail(id: c) }
                    else if let p = it.postID { PostInspector(id: p, selected: $ui.selectedPost) }
                } else { upcoming }
            }
        }
    }

    private func open(_ it: TodoItem) {
        selected = it.id
        if let p = it.postID { ui.selectedPost = p }
        if let c = it.contactID { ui.selectedContact = c }
    }

    /// Prochain jalon : titre et « J-x · date ».
    private var nextStep: (String, String) {
        guard let m = upcomingMilestones.first else { return ("—", L.t("today.nomilestone")) }
        let d = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: m.date)).day ?? 0
        return (d == 0 ? L.t("countdown.today") : L.t("countdown.left", d), m.title)
    }
    private var upcomingMilestones: [Milestone] {
        let t = Calendar.current.startOfDay(for: Date())
        return store.campaign.milestones.filter { $0.date >= t }.sorted { $0.date < $1.date }
    }

    private func kpi(_ label: String, _ value: String, sub: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textSubtle).lineLimit(1)
            Text(value).socle(Socle.T.stat).foregroundStyle(Socle.C.textStrong).lineLimit(1).minimumScaleFactor(0.7)
            Text(sub ?? " ").socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).lineLimit(1)
        }
        .padding(Socle.M.space3).frame(maxWidth: .infinity, alignment: .leading).soclePanel()
    }

    private var upcoming: some View {
        VStack(alignment: .leading, spacing: Socle.M.space3) {
            Text(L.t("today.next").uppercased()).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textSubtle)
            ForEach(Array(upcomingMilestones.prefix(3))) { m in
                HStack(spacing: Socle.M.space3) {
                    Text(L.day(m.date)).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted).frame(width: 90, alignment: .leading)
                    Text(m.title).socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong).lineLimit(1)
                    Spacer(minLength: 0)
                    Badge(text: m.kind.label)
                }
                .padding(.vertical, 4)
                Divider().overlay(Socle.C.borderSubtle)
            }
            if upcomingMilestones.isEmpty { Text(L.t("today.nomilestone")).socle(Socle.T.body).foregroundStyle(Socle.C.textSubtle) }
            Spacer(minLength: 0)
            Text(L.t("today.select")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
        }
        .padding(Socle.M.space4)
    }
}
