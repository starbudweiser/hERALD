// hERALD — panneau Statistiques : tout ce qui a été diffusé pour la campagne, en un seul écran.
import Charts
import SwiftUI

extension StatPlatform {
    var color: Color {
        switch self {
        case .youtube: Color(red: 0.94, green: 0.27, blue: 0.27)
        case .reddit: Color(red: 0.98, green: 0.45, blue: 0.09)
        case .bluesky: Color(red: 0.22, green: 0.60, blue: 0.96)
        case .github: Socle.C.textMuted
        case .nexus: Color(red: 0.96, green: 0.62, blue: 0.04)
        case .site: Socle.C.success
        case .instagram: Color(red: 0.83, green: 0.33, blue: 0.49)
        case .facebook: Color(red: 0.26, green: 0.40, blue: 0.70)
        case .discord: Color(red: 0.51, green: 0.55, blue: 0.97)
        case .x, .other: Socle.C.textSubtle
        }
    }
}

struct StatsView: View {
    @EnvironmentObject var store: Store
    @Binding var selectedPost: UUID?
    @Binding var tab: Tab
    @State private var period: StatsPeriod = .campaign
    @State private var entry: UUID?
    @State private var pendingLinks: [UUID: String] = [:]

    var body: some View {
        let s = store.statsSummary(period)
        ScrollView {
            VStack(alignment: .leading, spacing: Socle.M.space4) {
                toolbar(s)
                notices(s)
                kpis(s)
                if let b = s.best {
                    Label(L.t("stats.best", b.post.title, L.number(b.growth24h)), systemImage: "flame")
                        .socle(Socle.T.label).foregroundStyle(Socle.C.warning)
                }
                if !s.curve.isEmpty { chart(s) }
                if !s.platforms.isEmpty { platformTotals(s) }
                table(s)
                Text(L.t("stats.note")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Socle.M.space4)
            .frame(maxWidth: 1180, alignment: .leading)
        }
        .sheet(item: Binding(get: { entry.map { EntryID(id: $0) } }, set: { entry = $0?.id })) { e in
            ManualStatsSheet(postID: e.id).environmentObject(store)
        }
    }

    // MARK: Barre d'outils

    private func toolbar(_ s: StatsSummary) -> some View {
        HStack(spacing: Socle.M.space2) {
            SocleSegmented(options: StatsPeriod.allCases, selection: period, label: \.label, onSelect: { period = $0 })
            Spacer()
            if store.statsChecking { ProgressView().controlSize(.small) }
            Text(store.data.statsChecked.map { L.t("stats.checked", L.date($0)) } ?? L.t("stats.never"))
                .socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
            Text(L.t(store.campaignActive ? "stats.freq.hour" : "stats.freq.day")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
            Button(L.t("stats.manual.add")) { entry = store.posts.first { !store.platform($0).automatic }?.id ?? store.posts.first?.id }
                .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                .disabled(store.posts.isEmpty)
            CopyButton(title: L.t("stats.copy")) { s.markdown(title: store.campaign.name) }
            Button(L.t("stats.refresh")) { Task { await store.refreshStats() } }
                .buttonStyle(SocleButtonStyle(.primary, height: Socle.M.sizeControl)).fixedSize()
                .disabled(store.statsChecking)
        }
    }

    // MARK: Avertissements utiles

    @ViewBuilder private func notices(_ s: StatsSummary) -> some View {
        let needsYouTube = store.campaign.posts.contains { store.platform($0) == .youtube && !$0.link.isEmpty } && Keychain.get("youtube").isEmpty
        if needsYouTube { Callout(kind: .warning, text: L.t("stats.notice.youtubekey")) }
        if store.data.goatcounter == nil { Callout(kind: .info, text: L.t("stats.notice.goatcounter")) }
        if let e = store.data.siteError { Callout(kind: .warning, text: L.t("stats.notice.siteerror", e)) }
        if !s.missingLinks.isEmpty {
            VStack(alignment: .leading, spacing: Socle.M.space2) {
                Text(L.t("stats.missing.title").uppercased()).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.warning)
                Text(L.t("stats.missing.text")).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted)
                ForEach(s.missingLinks) { p in
                    HStack(spacing: Socle.M.space2) {
                        Image(systemName: store.platform(p).symbol).foregroundStyle(store.platform(p).color).frame(width: 18)
                        Text("\(L.day(p.date)) · \(p.title)").socle(Socle.T.label).foregroundStyle(Socle.C.text).frame(width: 340, alignment: .leading).lineLimit(1)
                        TextField("https://…", text: Binding(get: { pendingLinks[p.id] ?? "" }, set: { pendingLinks[p.id] = $0 })).socleField()
                        Button(L.t("action.add")) {
                            if var q = store.post(p.id) { q.link = (pendingLinks[p.id] ?? "").trimmingCharacters(in: .whitespaces); store.update(q) }
                            pendingLinks[p.id] = nil
                            Task { await store.refreshStats() }
                        }
                        .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                        .disabled((pendingLinks[p.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .padding(Socle.M.space3).frame(maxWidth: .infinity, alignment: .leading)
            .background(Socle.C.surface, in: RoundedRectangle(cornerRadius: Socle.M.radiusMd))
            .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusMd).stroke(Socle.C.warningBorder, lineWidth: 1))
        }
        if !s.stale.isEmpty {
            Callout(kind: .info, text: L.t("stats.stale", s.stale.map(\.post.title).joined(separator: ", ")))
        }
    }

    // MARK: Chiffres clés

    private func kpis(_ s: StatsSummary) -> some View {
        HStack(spacing: Socle.M.space2) {
            kpi(L.t("stats.kpi.views"), s.views, sub: L.t("stats.kpi.views.sub"))
            kpi(L.t("stats.kpi.interactions"), s.interactions, sub: L.t("stats.kpi.interactions.sub"))
            kpi(L.t("stats.kpi.downloads"), s.downloads, sub: L.t("stats.kpi.downloads.sub"))
            kpi(L.t("stats.kpi.site"), period == .campaign ? s.siteVisits : s.siteDelta,
                sub: store.data.siteDomain ?? L.t("stats.kpi.site.none"))
        }
        .fixedSize(horizontal: false, vertical: true)   // cartes de même hauteur
    }

    private func kpi(_ label: String, _ v: Int?, sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textSubtle)
            Text(v.map(L.number) ?? "—").socle(Socle.T.stat).foregroundStyle(Socle.C.textStrong)
            if let sub { Text(sub).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).lineLimit(1) }
        }
        .padding(Socle.M.space3).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Socle.C.surface, in: RoundedRectangle(cornerRadius: Socle.M.radiusMd))
        .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusMd).stroke(Socle.C.border, lineWidth: 1))
    }

    // MARK: Courbe

    private func chart(_ s: StatsSummary) -> some View {
        let range = (s.curve.map(\.date).min() ?? Date())...(s.curve.map(\.date).max() ?? Date())
        let marks = store.campaign.milestones.filter { range.contains($0.date) }
        let pls = Array(Set(s.curve.map(\.platform))).sorted { $0.rawValue < $1.rawValue }
        return VStack(alignment: .leading, spacing: Socle.M.space2) {
            Text(L.t("stats.chart.title").uppercased()).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textSubtle)
            Chart {
                ForEach(s.curve) { pt in
                    LineMark(x: .value("date", pt.date), y: .value("vues", pt.views))
                        .foregroundStyle(by: .value("plateforme", pt.platform.label))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("date", pt.date), y: .value("vues", pt.views))
                        .foregroundStyle(by: .value("plateforme", pt.platform.label)).symbolSize(18)
                }
                ForEach(marks) { m in
                    RuleMark(x: .value("jalon", m.date))
                        .foregroundStyle(Socle.C.warning.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            Text(m.title).socle(Socle.T.caption).foregroundStyle(Socle.C.warning)
                        }
                }
            }
            .chartForegroundStyleScale(domain: pls.map(\.label), range: pls.map(\.color))
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.twoDigits)) } }
            .frame(height: 200)
        }
        .padding(Socle.M.space3)
        .background(Socle.C.surface, in: RoundedRectangle(cornerRadius: Socle.M.radiusMd))
        .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusMd).stroke(Socle.C.border, lineWidth: 1))
    }

    private func platformTotals(_ s: StatsSummary) -> some View {
        HStack(spacing: Socle.M.space2) {
            ForEach(s.platforms) { t in
                VStack(alignment: .leading, spacing: 2) {
                    Label(t.platform.label, systemImage: t.platform.symbol).socle(Socle.T.labelStrong).foregroundStyle(t.platform.color)
                    Text([t.views > 0 ? "\(L.number(t.views)) \(L.t("stats.col.views").lowercased())" : nil,
                          t.interactions > 0 ? "\(L.number(t.interactions)) \(L.t("stats.kpi.interactions").lowercased())" : nil,
                          t.downloads > 0 ? "\(L.number(t.downloads)) \(L.t("stats.col.downloads").lowercased())" : nil]
                        .compactMap { $0 }.joined(separator: " · ").ifEmpty("—"))
                        .socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted).lineLimit(2)
                }
                .padding(Socle.M.space2_5).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Socle.C.surface, in: RoundedRectangle(cornerRadius: Socle.M.radius))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Tableau des publications

    private static let widths: [CGFloat] = [86, 86, 86, 86, 96, 86]

    private func table(_ s: StatsSummary) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Socle.M.space2) {
                Text(L.t("stats.col.post")).frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(["stats.col.views", "stats.col.likes", "stats.col.comments", "stats.col.shares", "stats.col.downloads", "stats.col.day"].enumerated()), id: \.offset) { i, k in
                    Text(L.t(k)).frame(width: Self.widths[i], alignment: .trailing)
                }
                Text(L.t("stats.col.source")).frame(width: 150, alignment: .leading)
            }
            .socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textSubtle)
            .padding(.horizontal, Socle.M.space3).padding(.vertical, Socle.M.space2)
            Divider().overlay(Socle.C.border)
            if s.rows.isEmpty {
                EmptyState(text: L.t("stats.empty")).frame(height: 90)
            }
            ForEach(s.rows) { r in row(r) }
            // Publications avec un lien mais pas encore de relevé (ou plateforme à saisir à la main).
            let waiting = store.posts.filter { p in !p.link.isEmpty && (p.stats ?? []).isEmpty }
            ForEach(waiting) { p in waitingRow(p) }
        }
        .background(Socle.C.surface, in: RoundedRectangle(cornerRadius: Socle.M.radiusMd))
        .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusMd).stroke(Socle.C.border, lineWidth: 1))
    }

    private func num(_ v: Int?) -> String { v.map(L.number) ?? "—" }

    private func row(_ r: StatsSummary.Row) -> some View {
        let d = r.delta
        return HStack(spacing: Socle.M.space2) {
            HStack(spacing: Socle.M.space1_5) {
                Image(systemName: r.platform.symbol).foregroundStyle(r.platform.color).frame(width: 18)
                VStack(alignment: .leading, spacing: 0) {
                    Text(r.post.title).socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong).lineLimit(1)
                    Text("\(r.platform.label) · \(L.day(r.post.date))").socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                }
                if let e = r.post.statsError {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(Socle.C.warning).help(e)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                Text(num(d.views)).frame(width: Self.widths[0], alignment: .trailing)
                Text(num(d.likes)).frame(width: Self.widths[1], alignment: .trailing)
                Text(num(d.comments)).frame(width: Self.widths[2], alignment: .trailing)
                Text(num(d.shares)).frame(width: Self.widths[3], alignment: .trailing)
                Text(num(d.downloads)).frame(width: Self.widths[4], alignment: .trailing)
            }
            .socle(Socle.T.mono).foregroundStyle(Socle.C.text)
            Text(r.growth24h > 0 ? "+\(L.number(r.growth24h))" : r.growth24h == 0 ? "—" : L.number(r.growth24h))
                .socle(Socle.T.mono).foregroundStyle(r.growth24h > 0 ? Socle.C.success : Socle.C.textSubtle)
                .frame(width: Self.widths[5], alignment: .trailing)
            HStack(spacing: Socle.M.space1_5) {
                Badge(text: L.t(r.latest?.manual == true ? "stats.src.manual" : "stats.src.auto"),
                      kind: r.latest?.manual == true ? .warning : .success)
                Text(r.latest.map { L.date($0.date) } ?? "").socle(Socle.T.caption).foregroundStyle(Socle.C.textSubtle).lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)
        }
        .padding(.horizontal, Socle.M.space3).padding(.vertical, Socle.M.space2)
        .overlay(alignment: .bottom) { Divider().overlay(Socle.C.borderSubtle) }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { openURL(r.post.link) }
        .contextMenu { menu(r.post) }
        .help(r.post.link)
    }

    private func waitingRow(_ p: Post) -> some View {
        let pl = store.platform(p)
        return HStack(spacing: Socle.M.space2) {
            Image(systemName: pl.symbol).foregroundStyle(pl.color).frame(width: 18)
            Text(p.title).socle(Socle.T.label).foregroundStyle(Socle.C.textMuted).lineLimit(1)
            Text(p.statsError ?? L.t(pl.automatic ? "stats.waiting.auto" : "stats.waiting.manual"))
                .socle(Socle.T.meta).foregroundStyle(p.statsError == nil ? Socle.C.textSubtle : Socle.C.warning).lineLimit(1)
            Spacer()
            if !pl.automatic {
                Button(L.t("stats.manual.add")) { entry = p.id }
                    .buttonStyle(SocleButtonStyle(.tertiary, height: Socle.M.sizeControl)).fixedSize()
            }
        }
        .padding(.horizontal, Socle.M.space3).padding(.vertical, Socle.M.space2)
        .overlay(alignment: .bottom) { Divider().overlay(Socle.C.borderSubtle) }
        .contextMenu { menu(p) }
    }

    @ViewBuilder private func menu(_ p: Post) -> some View {
        Button(L.t("action.open")) { openURL(p.link) }.disabled(p.link.isEmpty)
        Button(L.t("stats.manual.add")) { entry = p.id }
        Button(L.t("stats.showpost")) { selectedPost = p.id; tab = .posts }
    }
}

private struct EntryID: Identifiable { let id: UUID }

private extension String {
    func ifEmpty(_ s: String) -> String { isEmpty ? s : self }
}

// MARK: Saisie manuelle

struct ManualStatsSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var postID: UUID
    @State private var date = Date()
    @State private var views = ""
    @State private var likes = ""
    @State private var comments = ""
    @State private var shares = ""
    @State private var downloads = ""

    init(postID: UUID) { _postID = State(initialValue: postID) }

    var body: some View {
        VStack(alignment: .leading, spacing: Socle.M.space4) {
            Text(L.t("stats.manual.title")).socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong)
            Field(label: L.t("stats.col.post")) {
                Picker("", selection: $postID) {
                    ForEach(store.posts) { p in Text("\(L.day(p.date)) · \(p.title)").tag(p.id) }
                }.labelsHidden()
            }
            if let last = store.post(postID)?.stats?.last {
                Text(L.t("stats.manual.last", L.date(last.date), [last.views, last.likes, last.comments, last.shares, last.downloads]
                    .map { $0.map(L.number) ?? "—" }.joined(separator: " / ")))
                    .socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
            }
            HStack(spacing: Socle.M.space2) {
                field("stats.col.views", $views); field("stats.col.likes", $likes); field("stats.col.comments", $comments)
                field("stats.col.shares", $shares); field("stats.col.downloads", $downloads)
            }
            Field(label: L.t("col.date")) {
                DatePicker("", selection: $date).labelsHidden()
            }.fixedSize()
            Text(L.t("stats.manual.note")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Socle.M.space2) {
                if let p = store.post(postID), !p.link.isEmpty {
                    Button(L.t("action.open")) { openURL(p.link) }
                        .buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
                }
                Spacer()
                Button(L.t("action.cancel")) { dismiss() }.buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
                Button(L.t("action.save")) {
                    let n: (String) -> Int? = { Int($0.filter(\.isNumber)) }
                    store.addManualStats(postID, StatSnapshot(date: date, views: n(views), likes: n(likes), comments: n(comments),
                                                              shares: n(shares), downloads: n(downloads)))
                    dismiss()
                }
                .buttonStyle(SocleButtonStyle(.primary)).fixedSize().keyboardShortcut(.defaultAction)
                .disabled([views, likes, comments, shares, downloads].allSatisfy { $0.filter(\.isNumber).isEmpty })
            }
        }
        .padding(Socle.M.space6)
        .frame(width: 640)
        .background(Socle.C.surface)
    }

    private func field(_ key: String, _ b: Binding<String>) -> some View {
        Field(label: L.t(key)) { TextField("", text: b).socleField() }
    }
}
