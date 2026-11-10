// hERALD — gestion d'un plan de communication pour moddeurs : prépare et suit, ne publie jamais.
import SwiftUI

@main
struct HeraldApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = Store()
    @StateObject private var ui = UIState()
    @AppStorage("zoom") private var zoom = 1.0

    var body: some Scene {
        Window("hERALD", id: "main") {
            ZoomedRoot(zoom: zoom)
                .splashGated()
                .environmentObject(store)
                .environmentObject(ui)
                .task {
                    store.startInbox(); store.startStats()
                    Updater.shared.start(busy: { store.statsChecking || store.checking || !store.agentBusy.isEmpty })
                    await store.checkIfStale()
                }
        }
        .defaultSize(width: 1724, height: 953)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L.t("side.about", "hERALD")) { About.show() }
            }
            CommandGroup(replacing: .appSettings) {
                Button(L.t("settings.title") + "…") { ui.showSettings = true }.keyboardShortcut(",")
            }
            CommandGroup(replacing: .newItem) {
                Button(L.t("campaign.add")) { store.addCampaign() }.keyboardShortcut("n")
                Button(L.t("post.add")) { ui.selectedPost = store.addPost(); ui.tab = .posts }
                    .keyboardShortcut("n", modifiers: [.command, .shift]).disabled(!store.hasCampaign)
            }
            CommandGroup(after: .textEditing) {
                Button(L.t("search.placeholder")) { ui.focusSearch += 1 }.keyboardShortcut("f")
                Button(L.t("drawer.toggle")) { ui.toggleBrowser() }.keyboardShortcut("b")
                Button(L.t("publish.open")) { ui.toggleWorkspace(store) }
                    .keyboardShortcut("b", modifiers: [.command, .shift]).disabled(!store.hasCampaign)
            }
            CommandGroup(after: .toolbar) {
                Button(L.t("view.zoomin")) { setZoom(zoom + 0.1) }.keyboardShortcut("+", modifiers: .option)
                Button(L.t("view.zoomout")) { setZoom(zoom - 0.1) }.keyboardShortcut("-", modifiers: .option)
                Button(L.t("view.zoomreset")) { setZoom(1) }.keyboardShortcut("0", modifiers: .option)
            }
            CommandGroup(after: .windowArrangement) {
                Button(L.t("menubar.hide")) { Presence.shared.hideToMenuBar() }
                    .keyboardShortcut("m", modifiers: [.command, .option])
                Button(L.t("window.close.remember")) { WindowMemory.closeRemembering() }
            }
            CommandGroup(replacing: .importExport) {
                Button(L.t("menu.export")) { store.exportPlan() }.keyboardShortcut("e")
                Button(L.t("menu.import")) { ui.problem = store.importPlan() }
                Button(L.t("menu.inbox")) { store.revealInbox() }
                Divider()
                Button(L.t("menu.sample")) { store.addSample() }
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
        .frame(minWidth: (store.agentOpen && AgentConfig.isEnabled(agentRaw) ? 1180 + panelWidth + 7 : 1180) * zoom, minHeight: 720 * zoom)
        .background(Socle.C.bg)
        .background(TitleBarCleaner())
    }
}

/// Barre de titre système sans titre ni filet : la fenêtre garde ses boutons, le contenu commence dessous.
struct TitleBarCleaner: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.backgroundColor = NSColor(Socle.C.bg)
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
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
        WindowMemory.install()
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
    @State private var redditID = Keychain.get("reddit.id")
    @State private var redditSecret = Keychain.get("reddit.secret")
    @State private var githubToken = Keychain.get("github")
    @State private var omaOwner = ""
    @State private var ghMissing = false
    @State private var iconMode = IconMode.current
    @State private var mailClient = MailClient.current
    @State private var agentOn = AgentConfig.current.enabled
    @State private var agentSettings = false
    @State private var domain = ""
    @State private var goat = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Socle.M.space4) {
            Text(L.t("settings.title")).socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong)
            ScrollView {
            VStack(alignment: .leading, spacing: Socle.M.space4) {
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
            Field(label: L.t("settings.github")) {
                HStack(spacing: Socle.M.space2) {
                    SecureField(L.t("settings.github.token"), text: $githubToken).socleField()
                    TextField(L.t("settings.github.owner"), text: $omaOwner).socleField().frame(width: 180)
                    Button(L.t("settings.github.gh")) {
                        if let t = OMA.ghToken() { githubToken = t; ghMissing = false } else { ghMissing = true }
                    }
                    .buttonStyle(SocleButtonStyle(.tertiary, height: Socle.M.sizeControl)).fixedSize()
                }
                Text(L.t(ghMissing ? "settings.github.nogh" : "settings.github.note")).socle(Socle.T.meta)
                    .foregroundStyle(ghMissing ? Socle.C.warning : Socle.C.textSubtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Field(label: L.t("settings.reddit")) {
                HStack(spacing: Socle.M.space2) {
                    TextField(L.t("settings.reddit.id"), text: $redditID).socleField()
                    SecureField(L.t("settings.reddit.secret"), text: $redditSecret).socleField()
                }
                HStack(spacing: Socle.M.space2) {
                    Text(L.t("settings.reddit.note")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(L.t("settings.reddit.open")) { openURL("https://www.reddit.com/prefs/apps") }
                        .buttonStyle(SocleButtonStyle(.tertiary, height: Socle.M.sizeControl)).fixedSize()
                }
            }
            HStack(alignment: .top, spacing: Socle.M.space3) {
                Field(label: L.t("settings.site")) { TextField("monsite.com", text: $domain).socleField() }
                Field(label: L.t("settings.goatcounter")) { TextField("code", text: $goat).socleField() }
            }
            Text(L.t("settings.goatcounter.note")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                .fixedSize(horizontal: false, vertical: true)
            Field(label: L.t("platform.settings.title")) {
                VStack(alignment: .leading, spacing: Socle.M.space1_5) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 4) {
                        ForEach(StatPlatform.allCases.filter { $0 != .other && $0 != .nexusPage }) { p in
                            Toggle(p.label, isOn: Binding(
                                get: { store.pinnedPlatforms.contains(p) },
                                set: { on in
                                    var l = store.pinnedPlatforms.filter { $0 != p }
                                    if on { l.append(p) }
                                    store.data.platforms = l.map(\.rawValue)
                                }))
                        }
                    }
                    Text(L.t("platform.settings.note")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Field(label: L.t("upd.title")) { UpdateSection() }
            Field(label: L.t("backup.title")) { BackupSection() }
            Field(label: L.t("window.reset.title")) {
                VStack(alignment: .leading, spacing: Socle.M.space1_5) {
                    Button(L.t("window.reset")) { WindowMemory.reset() }
                        .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                    Text(L.t("window.reset.note")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Field(label: L.t("mail.client")) {
                SocleSegmented(options: MailClient.allCases, selection: mailClient, label: { $0 == .mail ? "Mail" : L.t("mail.client.shortother") },
                               onSelect: { mailClient = $0 })
                Text(mailClient.label).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted).lineLimit(1)
                Text(L.t("mail.client.note")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
            }
            .padding(.trailing, Socle.M.space3)
            }
            HStack(spacing: Socle.M.space2) {
                Spacer()
                Button(L.t("action.cancel")) { dismiss() }
                    .buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
                Button(L.t("action.save")) {
                    Keychain.set(key.trimmingCharacters(in: .whitespacesAndNewlines), "nexus")
                    Keychain.set(youtubeKey.trimmingCharacters(in: .whitespacesAndNewlines), "youtube")
                    Keychain.set(redditID.trimmingCharacters(in: .whitespacesAndNewlines), "reddit.id")
                    Keychain.set(redditSecret.trimmingCharacters(in: .whitespacesAndNewlines), "reddit.secret")
                    let tok = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
                    let own = omaOwner.trimmingCharacters(in: .whitespaces)
                    let omaChanged = tok != Keychain.get("github") || own != (store.data.oma?.owner ?? "")
                    Keychain.set(tok, "github")
                    if omaChanged {
                        var o = store.oma; o.owner = own.isEmpty ? nil : own; o.checked = nil; store.data.oma = o
                        Task { await store.refreshOMA() }
                    }
                    store.data.siteDomain = SiteInput.domain(domain)
                    store.data.goatcounter = SiteInput.goatcounter(goat)
                    var ac = AgentConfig.current; ac.enabled = agentOn; AgentConfig.current = ac
                    IconMode.current = iconMode
                    MailClient.current = mailClient
                    Presence.shared.apply()
                    dismiss()
                }
                    .buttonStyle(SocleButtonStyle(.primary)).fixedSize().keyboardShortcut(.defaultAction)
            }
        }
        .padding(Socle.M.space6)
        .frame(width: 660, height: 640)
        .onAppear { domain = store.data.siteDomain ?? ""; goat = store.data.goatcounter ?? ""; omaOwner = store.data.oma?.owner ?? "" }
        .sheet(isPresented: $agentSettings) { AgentSettingsView() }
        .background(Socle.C.surface)
    }
}
