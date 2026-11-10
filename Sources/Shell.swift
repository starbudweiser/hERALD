// hERALD — cadre de la fenêtre : barre latérale en panneau, en-tête de vue, barre d'état, À propos.
import SwiftUI

/// Entrées de la barre latérale qui ouvrent une vue.
enum Tab: String, CaseIterable {
    case today, calendar, posts, contacts, stats, feedback, watch, channels, browser

    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .calendar: "calendar"
        case .posts: "doc.text"
        case .contacts: "person.2"
        case .stats: "chart.bar"
        case .feedback: "bubble.left.and.bubble.right"
        case .watch: "binoculars"
        case .channels: "megaphone"
        case .browser: "globe"
        }
    }
    var title: String { L.t("tab.\(rawValue)") }
    /// Vues qui montrent la campagne choisie (les autres fonctionnent sans campagne).
    var needsCampaign: Bool { [.today, .calendar, .posts, .contacts, .stats, .feedback].contains(self) }
}

/// État de l'interface (vue affichée, sélections, recherche, fenêtres) ; rien ici n'est enregistré dans le plan.
@MainActor
final class UIState: ObservableObject {
    @Published var tab: Tab = .today { didSet { if tab != oldValue { query = "" } } }
    @Published var selectedPost: UUID?
    @Published var selectedContact: UUID?
    @Published var query = ""
    @Published var focusSearch = 0
    @Published var showSettings = false
    @Published var editingCampaign = false
    @Published var showAbout = false
    @Published var problem: String?

    /// La publication correspond-elle à la recherche en cours (titre, canal, notes) ?
    func matches(_ p: Post, _ store: Store) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || [p.title, store.channel(p.channelID)?.name ?? "", p.notes]
            .contains { $0.localizedCaseInsensitiveContains(q) }
    }
    func matches(_ text: String...) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || text.contains { $0.localizedCaseInsensitiveContains(q) }
    }
}

extension Socle.C {
    /// Orange du fanion du logo (le « h » de hERALD).
    static let brand = Color(red: 0xf3 / 255, green: 0x92 / 255, blue: 0)
}

/// Panneau arrondi du contenu : fond `surface`, filet 1 px.
extension View {
    func soclePanel() -> some View {
        background(Socle.C.surface, in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Socle.C.border, lineWidth: 1))
    }
}

// MARK: Racine

struct RootView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    @AppStorage(AgentConfig.key) private var agentRaw = Data()

    var body: some View {
        HStack(spacing: 0) {
            Sidebar().padding(.leading, 12).padding(.vertical, 12)
            VStack(spacing: 12) {
                ViewHeader(spec: spec(ui.tab))
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
                StatusBar()
            }
            .padding(12)
            if store.agentOpen && AgentConfig.isEnabled(agentRaw) {
                Divider().overlay(Socle.C.border)
                AgentPanel(selectedPost: $ui.selectedPost)
            }
        }
        .background(Socle.C.bg)
        .onAppear { BrowserModel.shared.reveal = { [weak ui] in ui?.tab = .browser; ui?.showSettings = false } }
        .sheet(isPresented: $ui.editingCampaign) { CampaignSheet().environmentObject(store) }
        .sheet(isPresented: $ui.showSettings) { SettingsView().environmentObject(store) }
        .sheet(isPresented: $store.welcome) { WelcomeView().environmentObject(store) }
        .sheet(isPresented: $ui.showAbout) { AboutView() }
        .alert(L.t("import.invalid.title"), isPresented: Binding(get: { ui.problem != nil }, set: { if !$0 { ui.problem = nil } })) {
            Button("OK") { ui.problem = nil }
        } message: { Text(ui.problem ?? "") }
    }

    @ViewBuilder private var content: some View {
        if !store.hasCampaign && ui.tab.needsCampaign {
            VStack(spacing: Socle.M.space3) {
                EmptyState(text: L.t("campaign.empty")).frame(maxHeight: 120)
                Button(L.t("campaign.add")) { store.addCampaign() }
                    .buttonStyle(SocleButtonStyle(.primary)).fixedSize()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).soclePanel()
        } else {
            switch ui.tab {
            case .today: TodayView()
            case .calendar: CalendarView(selectedPost: $ui.selectedPost, tab: $ui.tab).soclePanel()
            case .posts: PostsView()
            case .contacts: ContactsView()
            case .stats: StatsView(selectedPost: $ui.selectedPost, tab: $ui.tab).soclePanel()
            case .feedback: FeedbackView(selected: $ui.selectedPost)
            case .watch: WatchView()
            case .channels: ChannelsView()
            case .browser: BrowserView().soclePanel()
            }
        }
    }

    private func spec(_ t: Tab) -> HeaderSpec {
        let title = t.title, sub = L.t("head.\(t.rawValue)")
        switch t {
        case .today, .calendar, .posts:
            return HeaderSpec(title: title, subtitle: sub, searchable: true,
                              primary: store.hasCampaign ? (L.t("post.add"), { ui.selectedPost = store.addPost(); ui.tab = .posts }) : nil)
        case .contacts:
            return HeaderSpec(title: title, subtitle: sub, searchable: true,
                              primary: store.hasCampaign ? (L.t("contact.add"), { ui.selectedContact = store.addContact() }) : nil)
        case .feedback, .watch, .channels:
            return HeaderSpec(title: title, subtitle: sub, searchable: true, primary: nil)
        case .stats, .browser:
            return HeaderSpec(title: title, subtitle: sub, searchable: false, primary: nil)
        }
    }
}

// MARK: En-tête de vue

struct HeaderSpec {
    var title: String
    var subtitle: String
    var searchable: Bool
    var primary: (String, () -> Void)?
}

struct ViewHeader: View {
    let spec: HeaderSpec
    @EnvironmentObject var ui: UIState
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: Socle.M.space3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(spec.title).font(.system(size: 22, weight: .bold)).foregroundStyle(Socle.C.textStrong).lineLimit(1)
                Text(spec.subtitle).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted).lineLimit(1)
            }
            Spacer(minLength: Socle.M.space3)
            if spec.searchable {
                HStack(spacing: Socle.M.space1_5) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Socle.C.textSubtle).accessibilityHidden(true)
                    TextField(L.t("search.placeholder"), text: $ui.query).textFieldStyle(.plain)
                        .socle(Socle.T.body).focused($searchFocused)
                    if !ui.query.isEmpty {
                        Button { ui.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(Socle.C.textSubtle).accessibilityLabel(L.t("search.clear"))
                    }
                }
                .padding(.horizontal, Socle.M.space2_5)
                .frame(width: 220, height: Socle.M.sizeControlLg)
                .background(Socle.C.bgSunken, in: RoundedRectangle(cornerRadius: Socle.M.radius))
                .overlay(RoundedRectangle(cornerRadius: Socle.M.radius).stroke(searchFocused ? Socle.C.focusRing : .clear, lineWidth: 1))
                .onChange(of: ui.focusSearch) { _, _ in searchFocused = true }
            }
            if let (label, action) = spec.primary {
                Button(label, action: action)
                    .buttonStyle(SocleButtonStyle(.primary)).fixedSize()
            }
        }
        .frame(minHeight: 44)
    }
}

// MARK: Barre latérale

struct Sidebar: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    @AppStorage(AgentConfig.key) private var agentRaw = Data()
    @State private var removing: Campaign?

    private var agentOn: Bool { AgentConfig.isEnabled(agentRaw) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(branded: "hERALD").font(.system(size: 19, weight: .bold)).foregroundStyle(Socle.C.textStrong)
                .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 10)
            CampaignPicker(removing: $removing).padding(.horizontal, 8).padding(.bottom, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    group("side.group.campaign", [.today, .calendar, .posts])
                    group("side.group.outreach", [.contacts])
                    group("side.group.results", [.stats, .feedback, .watch])
                    groupTools
                }
                .padding(.horizontal, 8)
            }
            footer
        }
        .frame(width: 228)
        .background(Socle.C.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Socle.C.border, lineWidth: 1))
        .confirmationDialog(L.t("campaign.remove.confirm", removing?.name ?? ""),
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button(L.t("campaign.remove"), role: .destructive) { if let c = removing { store.removeCampaign(c.id) } }
        }
    }

    /// Ordre des entrées, repris par les raccourcis ⌘1 à ⌘9.
    private var order: [String] {
        ["today", "calendar", "posts", "contacts", "stats", "feedback", "watch", "channels"] + (agentOn ? ["agent"] : []) + ["browser"]
    }
    private func shortcut(_ id: String) -> KeyEquivalent? {
        guard let i = order.firstIndex(of: id), i < 9 else { return nil }
        return KeyEquivalent(Character("\(i + 1)"))
    }

    private func title(_ key: String) -> some View {
        Text(L.t(key)).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).lineLimit(1)
            .padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 4)
    }

    private func group(_ key: String, _ tabs: [Tab]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            title(key)
            ForEach(tabs, id: \.self) { t in
                SidebarRow(symbol: t.symbol, title: t.title, count: count(t), selected: ui.tab == t && !(store.agentOpen && agentOn),
                           key: shortcut(t.rawValue)) { ui.tab = t }
            }
        }
    }

    private var groupTools: some View {
        VStack(alignment: .leading, spacing: 2) {
            title("side.group.tools")
            SidebarRow(symbol: Tab.channels.symbol, title: Tab.channels.title, count: 0, selected: ui.tab == .channels,
                       key: shortcut("channels")) { ui.tab = .channels }
            if agentOn {
                SidebarRow(symbol: "sparkles", title: L.t("agent.button"), count: 0, selected: store.agentOpen, key: shortcut("agent")) {
                    store.agentOpen.toggle()
                    if store.agentOpen { store.agentScopeTask = false }
                }
                .disabled(!store.hasCampaign)
            }
            SidebarRow(symbol: Tab.browser.symbol, title: Tab.browser.title, count: 0, selected: ui.tab == .browser,
                       key: shortcut("browser")) { ui.tab = .browser }
        }
    }

    private func count(_ t: Tab) -> Int {
        switch t {
        case .today: store.todoCount
        case .feedback: store.unreadFeedback
        case .contacts: store.followUpsDue
        default: 0
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                SidebarRow(symbol: "gearshape", title: L.t("settings.title"), count: 0, selected: false) { ui.showSettings = true }
                SidebarRow(symbol: "info.circle", title: L.t("side.about", "hERALD"), count: 0, selected: false) { ui.showAbout = true }
            }
            Divider().overlay(Socle.C.border)
            let (done, total) = store.publishedCount
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L.t("side.published", done, total)).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(total == 0 ? "—" : "\(Int((Double(done) / Double(total) * 100).rounded())) %")
                        .socle(Socle.T.meta).foregroundStyle(Socle.C.textStrong).lineLimit(1)
                }
                ProgressBar(value: total == 0 ? 0 : Double(done) / Double(total))
                Button {
                    if store.inboxFiles > 0 { store.inboxFiles = 0; ui.showSettings = true } else { store.revealInbox() }
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(store.inboxFiles > 0 ? Socle.C.warning : Socle.C.success).frame(width: 8, height: 8)
                        Text(store.inboxFiles > 0 ? L.t("side.inbox.n", store.inboxFiles) : L.t("side.inbox.ok"))
                            .socle(Socle.T.meta).foregroundStyle(store.inboxFiles > 0 ? Socle.C.warning : Socle.C.textMuted).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L.t("inbox.title"))
            }
            .padding(.horizontal, 4)
        }
        .padding(8).padding(.bottom, 2)
    }
}

struct SidebarRow: View {
    let symbol: String
    let title: String
    let count: Int
    let selected: Bool
    var key: KeyEquivalent?
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 13)).frame(width: 18)
                    .foregroundStyle(selected ? Color.white : Socle.C.textMuted).accessibilityHidden(true)
                Text(title).socle(Socle.T.label).lineLimit(1)
                    .foregroundStyle(selected ? Color.white : Socle.C.text)
                Spacer(minLength: 4)
                if count > 0 {
                    Text(L.number(count)).socle(Socle.T.caption).fontWeight(.semibold).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Socle.C.brand, in: Capsule()).lineLimit(1).fixedSize()
                }
            }
            .padding(.horizontal, 8).frame(height: 32)
            .background(selected ? Socle.C.control : hover ? Socle.C.surfaceHover : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .background { if let key { Button("", action: action).keyboardShortcut(key, modifiers: .command).opacity(0).accessibilityHidden(true) } }
        .accessibilityLabel(title)
    }
}

/// Sélecteur de campagne : une ligne (pastille, nom tronqué, J-x, chevron) ; menu des campagnes et du plan.
struct CampaignPicker: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    @Binding var removing: Campaign?

    var body: some View {
        Menu {
            ForEach(store.data.campaigns) { c in
                Button { store.select(c.id) } label: {
                    if c.id == store.campaign.id && store.hasCampaign { Label(c.name, systemImage: "checkmark") } else { Text(c.name) }
                }
            }
            Divider()
            Button(L.t("campaign.add")) { store.addCampaign() }
            Button(L.t("campaign.edit")) { ui.editingCampaign = true }.disabled(!store.hasCampaign)
            Button(L.t("campaign.remove")) { removing = store.campaign }.disabled(!store.hasCampaign)
            Divider()
            Menu(L.t("menu.plan")) {
                Button(L.t("menu.export")) { store.exportPlan() }
                Button(L.t("menu.import")) { ui.problem = store.importPlan() }
                Button(L.t("menu.inbox")) { store.revealInbox() }
                Divider()
                Button(L.t("menu.sample")) { store.addSample() }
            }
        } label: {
            HStack(spacing: 8) {
                Circle().fill(Socle.C.brand).frame(width: 8, height: 8)
                Text(store.hasCampaign ? store.campaign.name : L.t("campaign.none")).socle(Socle.T.labelStrong)
                    .foregroundStyle(Socle.C.textStrong).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                if store.hasCampaign { Countdown(days: store.daysLeft(store.campaign)) }
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Socle.C.textSubtle)
            }
            .padding(.horizontal, 10).frame(height: 34)
            .background(Socle.C.control, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .accessibilityLabel(L.t("campaigns.title"))
    }
}

// MARK: Barre d'état

struct StatusBar: View {
    @EnvironmentObject var store: Store

    var body: some View {
        HStack(spacing: Socle.M.space4) {
            HStack(spacing: 6) {
                if store.statsChecking || store.checking { ProgressView().controlSize(.mini) }
                Text(stats).lineLimit(1)
            }
            Text("·").foregroundStyle(Socle.C.textDisabled)
            Text(L.t("status.watch", store.data.watch.count)).lineLimit(1)
            Spacer(minLength: Socle.M.space3)
            Text(L.t("rule.short")).lineLimit(1).truncationMode(.tail).foregroundStyle(Socle.C.textMuted)
        }
        .socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
        .padding(.horizontal, Socle.M.space3)
        .frame(height: 36)
        .soclePanel()
    }

    private var stats: String {
        guard let last = store.data.statsChecked else { return L.t("status.stats.none") }
        let next = last.addingTimeInterval(store.campaignActive ? 3600 : 86400)
        return L.t("status.stats", L.stamp(last), L.stamp(max(next, Date())))
    }
}

// MARK: À propos

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        VStack(spacing: Socle.M.space3) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84).accessibilityHidden(true)
            Text(branded: "hERALD").font(.system(size: 17, weight: .bold)).foregroundStyle(Socle.C.textStrong)
            Text(L.t("about.version", version)).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted)
            Text(branded: L.t("about.tagline")).socle(Socle.T.body).foregroundStyle(Socle.C.text).multilineTextAlignment(.center)
            Text("starbudweiser").socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong)
            Text(L.t("about.license")).socle(Socle.T.body).foregroundStyle(Socle.C.text)
            Text(branded: L.t("rule.long")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(L.t("action.done")) { dismiss() }.buttonStyle(SocleButtonStyle(.primary)).fixedSize().keyboardShortcut(.defaultAction)
        }
        .padding(Socle.M.space6)
        .frame(width: 400)
        .background(Socle.C.surface)
    }
}
