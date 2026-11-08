// hERALD — gestion d'un plan de communication pour moddeurs : prépare et suit, ne publie jamais.
import SwiftUI

@main
struct HeraldApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = Store()
    @AppStorage("zoom") private var zoom = 1.0

    var body: some Scene {
        Window("hERALD", id: "main") {
            ZoomedRoot(zoom: zoom)
                .splashGated()
                .environmentObject(store)
                .task { store.startInbox(); store.startStats(); await store.checkIfStale() }
        }
        .defaultSize(width: 1320, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L.t("campaign.add")) { store.addCampaign() }.keyboardShortcut("n")
                Button(L.t("post.add")) { _ = store.addPost() }.keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(!store.hasCampaign)
            }
            CommandGroup(after: .toolbar) {
                Button(L.t("view.zoomin")) { setZoom(zoom + 0.1) }.keyboardShortcut("+", modifiers: .option)
                Button(L.t("view.zoomout")) { setZoom(zoom - 0.1) }.keyboardShortcut("-", modifiers: .option)
                Button(L.t("view.zoomreset")) { setZoom(1) }.keyboardShortcut("0", modifiers: .option)
            }
            CommandGroup(after: .windowArrangement) {
                Button(L.t("menubar.hide")) { Presence.shared.hideToMenuBar() }
                    .keyboardShortcut("m", modifiers: [.command, .option])
            }
            CommandGroup(replacing: .importExport) {
                Button(L.t("menu.export")) { store.exportPlan() }.keyboardShortcut("e")
                Button(L.t("menu.import")) { _ = store.importPlan() }
                Button(L.t("menu.inbox")) { store.revealInbox() }
            }
        }
    }
}

extension HeraldApp {
    private func setZoom(_ z: Double) { Zoom.set(z) }
}

enum Zoom {
    /// Zoom de l'interface entre 70 % et 200 %, par pas de 10 % (préférence « zoom », lue par @AppStorage).
    static func set(_ z: Double) { UserDefaults.standard.set(min(2, max(0.7, (z * 10).rounded() / 10)), forKey: "zoom") }
}

/// Toute l'interface mise à l'échelle : la mise en page se fait à la taille divisée par le zoom, puis s'agrandit.
struct ZoomedRoot: View {
    let zoom: Double
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var store: Store
    @AppStorage("agentPanelWidth") private var panelWidth = 440.0
    @AppStorage(AgentConfig.key) private var agentRaw = Data()
    var body: some View {
        GeometryReader { g in
            RootView()
                .frame(width: g.size.width / zoom, height: g.size.height / zoom)
                .scaleEffect(zoom, anchor: .topLeading)
        }
        .onAppear {
            Presence.shared.openMain = { openWindow(id: "main") }
            Presence.shared.refreshStats = { Task { await store.refreshStats() } }
        }
        // volet de l'agent ouvert : la fenêtre s'élargit d'autant plutôt que de rogner le contenu
        .frame(minWidth: (store.agentOpen && AgentConfig.isEnabled(agentRaw) ? 1090 + panelWidth + 7 : 1120) * zoom, minHeight: 680 * zoom)
        .background(Socle.C.bg)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        let orange = Color(red: 0xf3 / 255, green: 0x92 / 255, blue: 0)
        Socle.brand("hERALD", color: orange)  // « h » dans l'orange du fanion du logo
        // Le splash part avant que SwiftUI ouvre la fenêtre principale, pour pouvoir la retenir jusqu'à t = 2 s.
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        Splash.shared.start(Splash.Config(title: "hERALD", subtitle: L.t("splash.subtitle"),
                                          footer: version.isEmpty ? "" : "v" + version,
                                          iconView: AnyView(AnimatedHeraldIcon()), accent: orange))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Socle.apply()
        Presence.shared.apply()
        // ⌥+ / ⌥− / ⌥0 quelle que soit la disposition du clavier (sur AZERTY, « + » demande Maj) et au pavé numérique.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let mods = e.modifierFlags.intersection([.command, .option, .control])
            guard mods == .option, let c = e.charactersIgnoringModifiers else { return e }
            let z = UserDefaults.standard.object(forKey: "zoom") as? Double ?? 1
            switch c {
            case "+", "=": Zoom.set(z + 0.1)
            case "-", "_": Zoom.set(z - 0.1)
            case "0", "à": Zoom.set(1)
            default: return e
            }
            return nil
        }
    }
    /// Avec la barre de menus, fermer la fenêtre ne quitte pas l'appli (elle continue ses relevés).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !IconMode.current.showsMenuBar }

    /// Clic sur l'icône du Dock quand la fenêtre est fermée.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Presence.shared.showMain(); return false }
        return true
    }
}

enum Tab: String, CaseIterable { case calendar, tracking, drafts, stats, feedback, watch, channels }

struct RootView: View {
    @EnvironmentObject var store: Store
    @State private var tab: Tab = .calendar
    @State private var editingCampaign = false
    @State private var settings = false
    @State private var selectedPost: UUID?
    @AppStorage(AgentConfig.key) private var agentRaw = Data()

    var body: some View {
        HStack(spacing: 0) {
            // volet de l'agent ouvert : la liste des campagnes s'efface (le nom reste dans l'en-tête) pour laisser la place
            if !(store.agentOpen && AgentConfig.isEnabled(agentRaw)) {
                CampaignSidebar(editing: $editingCampaign)
                Divider().overlay(Socle.C.border)
            }
            VStack(spacing: 0) {
                HeaderBar(editing: $editingCampaign, settings: $settings)
                Divider().overlay(Socle.C.border)
                GoldenRule()
                TabsBar(tab: $tab)
                Divider().overlay(Socle.C.border)
                Group {
                    if !store.hasCampaign && [.calendar, .tracking, .drafts, .stats, .feedback].contains(tab) {
                        VStack(spacing: Socle.M.space3) {
                            EmptyState(text: L.t("campaign.empty")).frame(maxHeight: 120)
                            Button(L.t("campaign.add")) { store.addCampaign() }
                                .buttonStyle(SocleButtonStyle(.primary)).fixedSize()
                        }
                    } else {
                        switch tab {
                        case .calendar: CalendarView(selectedPost: $selectedPost, tab: $tab)
                        case .tracking: TrackingView(selected: $selectedPost)
                        case .drafts: DraftsView(selected: $selectedPost)
                        case .stats: StatsView(selectedPost: $selectedPost, tab: $tab)
                        case .feedback: FeedbackView(selected: $selectedPost)
                        case .watch: WatchView()
                        case .channels: ChannelsView()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if store.agentOpen && AgentConfig.isEnabled(agentRaw) {
                Divider().overlay(Socle.C.border)
                AgentPanel(selectedPost: $selectedPost)
            }
        }
        .background(Socle.C.bg)
        .sheet(isPresented: $editingCampaign) { CampaignSheet().environmentObject(store) }
        .sheet(isPresented: $settings) { SettingsView().environmentObject(store) }
        .sheet(isPresented: $store.welcome) { WelcomeView().environmentObject(store) }
    }
}

/// Premier lancement : exemple facultatif.
struct WelcomeView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: Socle.M.space4) {
            Text(branded: L.t("welcome.title")).socle(Socle.T.display).foregroundStyle(Socle.C.textStrong)
            Text(branded: L.t("welcome.text")).socle(Socle.T.bodyLg).foregroundStyle(Socle.C.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Socle.M.space2) {
                Spacer()
                Button(L.t("welcome.empty")) { store.welcome = false }
                    .buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
                Button(L.t("welcome.sample")) { store.addSample(); store.welcome = false }
                    .buttonStyle(SocleButtonStyle(.primary)).fixedSize().keyboardShortcut(.defaultAction)
            }
        }
        .padding(Socle.M.space6)
        .frame(width: 640)
        .background(Socle.C.surface)
    }
}

/// Rappel permanent de la règle d'or.
struct GoldenRule: View {
    var body: some View {
        Callout(kind: .info, text: L.t("rule.banner"))
            .padding(.horizontal, Socle.M.space3).padding(.vertical, Socle.M.space2)
    }
}

// MARK: Campagnes

struct CampaignSidebar: View {
    @EnvironmentObject var store: Store
    @Binding var editing: Bool
    @State private var removing: Campaign?

    var body: some View {
        VStack(spacing: 0) {
            SectionBar(title: L.t("campaigns.title")) {
                Button { store.addCampaign() } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).foregroundStyle(Socle.C.textMuted).help(L.t("campaign.add"))
            }
            .frame(minHeight: Socle.M.sizeBar + 8)
            Divider().overlay(Socle.C.border)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.data.campaigns) { c in
                        let current = c.id == store.campaign.id
                        ListRow(selected: current) { store.select(c.id) } content: {
                            Text(c.name).socle(Socle.T.labelStrong).lineLimit(2)
                                .foregroundStyle(current ? Socle.C.warning : Socle.C.textStrong)
                            HStack(spacing: Socle.M.space1_5) {
                                Text(L.day(c.eventDate)).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                                Spacer(minLength: 0)
                                Countdown(days: store.daysLeft(c))
                            }
                            ProgressBar(value: progress(c))
                        }
                        .contextMenu {
                            Button(L.t("campaign.edit")) { store.select(c.id); editing = true }
                            Button(L.t("campaign.remove")) { removing = c }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 240)
        .background(Socle.C.surface)
        .confirmationDialog(L.t("campaign.remove.confirm", removing?.name ?? ""),
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button(L.t("campaign.remove"), role: .destructive) { if let c = removing { store.removeCampaign(c.id) } }
        }
    }

    private func progress(_ c: Campaign) -> Double {
        c.posts.isEmpty ? 0 : Double(c.posts.filter { $0.status == .published }.count) / Double(c.posts.count)
    }
}

struct Countdown: View {
    let days: Int
    var body: some View {
        if days > 0 { Badge(text: L.t("countdown.left", days), kind: days <= 7 ? .warning : .accent) }
        else if days == 0 { Badge(text: L.t("countdown.today"), kind: .success) }
        else { Badge(text: L.t("countdown.past", -days)) }
    }
}

struct ProgressBar: View {
    let value: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Socle.C.control)
                Capsule().fill(Socle.C.accent).frame(width: g.size.width * max(0, min(1, value)))
            }
        }
        .frame(height: 4)
    }
}

// MARK: En-tête

struct HeaderBar: View {
    @EnvironmentObject var store: Store
    @Binding var editing: Bool
    @Binding var settings: Bool
    @State private var problem: String?
    @AppStorage(AgentConfig.key) private var agentRaw = Data()

    var body: some View {
        HStack(spacing: Socle.M.space2) {
            Text(branded: "hERALD").socle(Socle.T.title).foregroundStyle(Socle.C.textStrong)
            Text(L.t("app.subtitle")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted).lineLimit(1)
            if store.hasCampaign {
                Text("·  \(store.campaign.name)").socle(Socle.T.body).foregroundStyle(Socle.C.textStrong).lineLimit(1)
                Countdown(days: store.daysLeft(store.campaign))
            }
            Spacer(minLength: Socle.M.space4)
            if let problem { Text(branded: problem).socle(Socle.T.meta).foregroundStyle(Socle.C.danger) }
            if let notice = store.inboxNotice {
                Button { store.inboxNotice = nil; settings = true } label: { Badge(text: notice, kind: .accent) }
                    .buttonStyle(.plain).help(L.t("inbox.title"))
            }
            Menu {
                Button(L.t("menu.export")) { store.exportPlan() }
                Button(L.t("menu.import")) { problem = store.importPlan() }
                Button(L.t("menu.inbox")) { store.revealInbox() }
                Divider()
                Button(L.t("menu.sample")) { store.addSample() }
            } label: { Text(L.t("menu.plan")) }
                .menuStyle(.borderlessButton).fixedSize()
            if AgentConfig.isEnabled(agentRaw) {
                Button(L.t("agent.button")) {
                    store.agentOpen.toggle()
                    if store.agentOpen { store.agentScopeTask = false }
                }
                .buttonStyle(SocleButtonStyle(store.agentOpen ? .primary : .secondary, height: Socle.M.sizeControl)).fixedSize()
                .disabled(!store.hasCampaign)
            }
            Button(L.t("campaign.edit")) { editing = true }
                .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                .disabled(!store.hasCampaign)
            Button { settings = true } label: { Image(systemName: "gearshape") }
                .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                .help(L.t("settings.title"))
        }
        .padding(.horizontal, Socle.M.space3)
        .frame(minHeight: Socle.M.sizeBar + 8)
        .background(Socle.C.surfaceRaised)
    }
}

struct TabsBar: View {
    @EnvironmentObject var store: Store
    @Binding var tab: Tab

    var body: some View {
        HStack(spacing: Socle.M.space4) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button { tab = t } label: {
                    Text(L.t("tab.\(t.rawValue)")).socle(Socle.T.label)
                        .foregroundStyle(tab == t ? Socle.C.textStrong : Socle.C.textMuted)
                        .padding(.vertical, Socle.M.space2_5)
                        .overlay(alignment: .bottom) { Rectangle().fill(tab == t ? Socle.C.accent : .clear).frame(height: 2) }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, Socle.M.space3)
        .background(Socle.C.bg)
    }
}

// MARK: Campagne (nom, date, jalons)

struct CampaignSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Socle.M.space4) {
            Text(L.t("campaign.edit")).socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong)
            HStack(alignment: .top, spacing: Socle.M.space4) {
                Field(label: L.t("campaign.name")) { TextField("", text: $store.campaign.name).socleField() }
                Field(label: L.t("campaign.date")) {
                    DatePicker("", selection: $store.campaign.eventDate, displayedComponents: .date).labelsHidden()
                }.fixedSize()
            }
            Field(label: L.t("campaign.notes")) {
                TextEditor(text: $store.campaign.notes).socle(Socle.T.body).socleField(multiline: true).frame(height: 80)
            }
            if AgentConfig.current.enabled {
                Field(label: L.t("agent.brief")) {
                    TextEditor(text: Binding(get: { store.campaign.agentBrief }, set: { store.campaign.agentBrief = $0 }))
                        .socle(Socle.T.body).socleField(multiline: true).frame(height: 70)
                    Text(L.t("agent.brief.note")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Text(L.t("milestones.title").uppercased()).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textSubtle)
                Spacer()
                Button(L.t("milestone.add")) {
                    store.campaign.milestones.append(Milestone(title: L.t("milestone.new"), date: store.campaign.eventDate))
                }
                .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
            }
            ScrollView {
                VStack(spacing: Socle.M.space2) {
                    ForEach($store.campaign.milestones) { $m in
                        HStack(spacing: Socle.M.space2) {
                            DatePicker("", selection: $m.date, displayedComponents: .date).labelsHidden().fixedSize()
                            Picker("", selection: $m.kind) {
                                ForEach(MilestoneKind.allCases) { Text($0.label).tag($0) }
                            }.labelsHidden().frame(width: 130)
                            TextField("", text: $m.title).socleField()
                            Button { store.campaign.milestones.removeAll { $0.id == m.id } } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain).foregroundStyle(Socle.C.textMuted).help(L.t("action.remove"))
                        }
                    }
                }
            }
            .frame(minHeight: 160, maxHeight: 280)
            HStack {
                Spacer()
                Button(L.t("action.done")) {
                    store.campaign.milestones.sort { $0.date < $1.date }
                    dismiss()
                }
                .buttonStyle(SocleButtonStyle(.primary)).fixedSize().keyboardShortcut(.defaultAction)
            }
        }
        .padding(Socle.M.space6)
        .frame(width: 680)
        .background(Socle.C.surface)
    }
}

// MARK: Réglages

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var key = Keychain.get("nexus")
    @State private var youtubeKey = Keychain.get("youtube")
    @State private var iconMode = IconMode.current
    @State private var agentOn = AgentConfig.current.enabled
    @State private var agentSettings = false
    @State private var domain = ""
    @State private var goat = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Socle.M.space4) {
            Text(L.t("settings.title")).socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong)
            Field(label: L.t("settings.nexuskey")) {
                SecureField("", text: $key).socleField()
                Text(L.t("settings.nexuskey.note")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Field(label: L.t("settings.youtubekey")) {
                SecureField("", text: $youtubeKey).socleField()
                HStack(spacing: Socle.M.space2) {
                    Text(L.t("settings.youtubekey.note")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(L.t("settings.youtubekey.open")) { openURL("https://console.cloud.google.com/apis/library/youtube.googleapis.com") }
                        .buttonStyle(SocleButtonStyle(.tertiary, height: Socle.M.sizeControl)).fixedSize()
                }
            }
            HStack(alignment: .top, spacing: Socle.M.space3) {
                Field(label: L.t("settings.site")) { TextField("monsite.com", text: $domain).socleField() }
                Field(label: L.t("settings.goatcounter")) { TextField("code", text: $goat).socleField() }
            }
            Text(L.t("settings.goatcounter.note")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                .fixedSize(horizontal: false, vertical: true)
            Field(label: L.t("settings.icon")) {
                SocleSegmented(options: IconMode.allCases, selection: iconMode, label: \.label, onSelect: { iconMode = $0 })
                Text(L.t("settings.icon.note")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Field(label: L.t("agent.option.title")) {
                HStack(spacing: Socle.M.space3) {
                    Toggle(L.t("agent.option.enable"), isOn: $agentOn)
                    Spacer(minLength: 0)
                    Button(L.t("agent.configure")) { agentSettings = true }
                        .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                }
                Text(L.t("agent.option.note")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Field(label: L.t("settings.data")) {
                HStack {
                    Text(Storage.url.path).socle(Socle.T.monoSm).foregroundStyle(Socle.C.textMuted).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button(L.t("settings.reveal")) { NSWorkspace.shared.activateFileViewerSelecting([Storage.url]) }
                        .buttonStyle(SocleButtonStyle(.tertiary, height: Socle.M.sizeControl)).fixedSize()
                }
            }
            Field(label: L.t("inbox.title")) {
                HStack {
                    Text(Inbox.dir.path).socle(Socle.T.monoSm).foregroundStyle(Socle.C.textMuted).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button(L.t("settings.reveal")) { store.revealInbox() }
                        .buttonStyle(SocleButtonStyle(.tertiary, height: Socle.M.sizeControl)).fixedSize()
                }
                Text(L.t("inbox.note")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    Text(store.inboxLog.isEmpty ? L.t("inbox.log.empty") : store.inboxLog.reversed().joined(separator: "\n"))
                        .socle(Socle.T.monoSm).foregroundStyle(Socle.C.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
                .frame(height: 120)
                .padding(Socle.M.space2)
                .background(Socle.C.control, in: RoundedRectangle(cornerRadius: Socle.M.radius))
            }
            Callout(kind: .info, text: L.t("rule.long"))
            HStack(spacing: Socle.M.space2) {
                Spacer()
                Button(L.t("action.cancel")) { dismiss() }
                    .buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
                Button(L.t("action.save")) {
                    Keychain.set(key.trimmingCharacters(in: .whitespacesAndNewlines), "nexus")
                    Keychain.set(youtubeKey.trimmingCharacters(in: .whitespacesAndNewlines), "youtube")
                    store.data.siteDomain = SiteInput.domain(domain)
                    store.data.goatcounter = SiteInput.goatcounter(goat)
                    var ac = AgentConfig.current; ac.enabled = agentOn; AgentConfig.current = ac
                    IconMode.current = iconMode
                    Presence.shared.apply()
                    dismiss()
                }
                    .buttonStyle(SocleButtonStyle(.primary)).fixedSize().keyboardShortcut(.defaultAction)
            }
        }
        .padding(Socle.M.space6)
        .frame(width: 640)
        .onAppear { domain = store.data.siteDomain ?? ""; goat = store.data.goatcounter ?? "" }
        .sheet(isPresented: $agentSettings) { AgentSettingsView() }
        .background(Socle.C.surface)
    }
}
