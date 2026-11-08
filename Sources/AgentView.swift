// hERALD — volet de discussion avec l'agent IA (à droite de la fenêtre, reste ouvert pendant qu'on travaille sur le plan)
// et réglages de l'agent.
import AppKit
import SwiftUI

extension AgentConfig {
    /// L'agent choisi est utilisable.
    var isReady: Bool {
        switch kind {
        case .claude: AgentRunner.claudeURL(self) != nil
        case .command: !command.trimmingCharacters(in: .whitespaces).isEmpty
        case .openai: !model.isEmpty && !apiURL.isEmpty
        }
    }
}

// MARK: Volet

struct AgentPanel: View {
    @EnvironmentObject var store: Store
    @Binding var selectedPost: UUID?
    @AppStorage("agentPanelWidth") private var width = 440.0
    @AppStorage(AgentConfig.key) private var configRaw = Data()
    @State private var startWidth: Double?
    @State private var input = ""
    @State private var settings = false

    private var cfg: AgentConfig { _ = configRaw; return AgentConfig.current }

    /// Discussion affichée : la tâche sélectionnée ou, sinon, la campagne.
    private var target: AgentTarget? {
        store.agentScopeTask ? selectedPost.flatMap { store.post($0) }.map { AgentTarget.post($0.id) } : .campaign
    }

    var body: some View {
        HStack(spacing: 0) {
            handle
            VStack(alignment: .leading, spacing: Socle.M.space3) {
                header
                scope
                if !cfg.isReady { Callout(kind: .warning, text: L.t("agent.notconfigured")) }
                if let t = target {
                    conversation(t)
                    composer(t)
                } else {
                    EmptyState(text: L.t("agent.scope.pick")).frame(maxHeight: .infinity)
                }
            }
            .padding(Socle.M.space4)
            .frame(width: width)
        }
        .background(Socle.C.surface)
        .sheet(isPresented: $settings) { AgentSettingsView() }
        .task { if await AgentCurrency.refreshIfNeeded() { store.objectWillChange.send() } }
    }

    // MARK: Poignée de redimensionnement

    private var handle: some View {
        Rectangle().fill(Color.clear).frame(width: 6).contentShape(Rectangle())
            .overlay(Rectangle().fill(Socle.C.border).frame(width: 1), alignment: .leading)
            .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { v in
                    if startWidth == nil { startWidth = width }
                    width = min(780, max(340, (startWidth ?? width) - v.translation.width))
                }
                .onEnded { _ in startWidth = nil })
    }

    // MARK: En-tête

    private var header: some View {
        HStack(spacing: Socle.M.space2) {
            Text(L.t("agent.button").uppercased()).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textSubtle)
            Spacer()
            if let t = target {
                Button { store.clearThread(t) } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).foregroundStyle(Socle.C.textMuted).help(L.t("agent.clear"))
                    .disabled(store.agentThread(t).messages.isEmpty)
            }
            Button { settings = true } label: { Image(systemName: "gearshape") }
                .buttonStyle(.plain).foregroundStyle(Socle.C.textMuted).help(L.t("agent.configure"))
            Button { store.agentOpen = false } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(Socle.C.textMuted).help(L.t("agent.close"))
        }
    }

    private var scope: some View {
        VStack(alignment: .leading, spacing: Socle.M.space1_5) {
            SocleSegmented(options: [false, true], selection: store.agentScopeTask,
                           label: { $0 ? L.t("agent.scope.task") : L.t("agent.scope.campaign") },
                           onSelect: { store.agentScopeTask = $0 })
            if let t = target {
                Text(store.agentTitle(t)).socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong).lineLimit(2)
                if cfg.kind == .claude, cfg.isReady { sessionLine(store.agentThread(t)) }
                usageLine(t)
            }
        }
    }

    /// Consommation cumulée de cette discussion et de toute la campagne (jetons, et coût quand on le connaît).
    @ViewBuilder private func usageLine(_ t: AgentTarget) -> some View {
        let mine = store.agentThread(t).usage, all = store.campaign.agentUsage
        if all.tokens > 0 || all.cost != nil {
            Text(L.t("agent.usage.total", mine.label(cfg), all.label(cfg)))
                .socle(Socle.T.caption).foregroundStyle(Socle.C.textSubtle).fixedSize(horizontal: false, vertical: true)
                .help(cfg.kind == .claude ? L.t("agent.usage.note") : "")
        }
    }

    /// Session Claude Code qui reçoit les demandes, et sous-sessions ouvertes par l'agent pour cette discussion.
    private func sessionLine(_ thread: AgentThread) -> some View {
        let id = cfg.sessionID
        return VStack(alignment: .leading, spacing: Socle.M.space1_5) {
            HStack(spacing: Socle.M.space2) {
                Badge(text: cfg.sessionName.isEmpty ? "hERALD" : cfg.sessionName, kind: .accent)
                Text(id.isEmpty ? L.t("agent.session.new") : String(id.prefix(8)) + "…")
                    .socle(Socle.T.monoSm).foregroundStyle(Socle.C.textSubtle).lineLimit(1)
                Spacer(minLength: 0)
                if !id.isEmpty {
                    CopyButton(title: L.t("agent.copyresume")) { "cd \"\(cfg.workURL.path)\" && claude --resume \(id)" }
                }
            }
            if !thread.subSessions.isEmpty {
                HStack(spacing: Socle.M.space1_5) {
                    Text(L.t("agent.subsessions").uppercased()).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textSubtle)
                    ForEach(thread.subSessions) { s in
                        CopyButton(title: s.name) { "cd \"\(cfg.workURL.path)\" && claude --resume \(s.id)" }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: Conversation

    private func conversation(_ t: AgentTarget) -> some View {
        let thread = store.agentThread(t)
        let busy = store.agentBusy.contains(t)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Socle.M.space3) {
                    if thread.messages.isEmpty {
                        VStack(spacing: Socle.M.space2) {
                            EmptyState(text: L.t("agent.empty")).frame(height: 90)
                            if cfg.workdir.hasPrefix("/Volumes/") {
                                Text(L.t("agent.volume.hint")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    ForEach(thread.messages) { m in AgentBubble(target: t, message: m) }
                    if busy { busyRow(t) }
                    Color.clear.frame(height: 1).id("end")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: thread.messages.count) { _ in proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: busy) { _ in proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: store.agentStatus[t]) { _ in proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: store.agentError[t]) { _ in proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: t) { _ in proxy.scrollTo("end", anchor: .bottom) }
        }
        .frame(maxHeight: .infinity)
    }

    /// Ce que fait l'agent, depuis combien de temps, et le bouton pour l'arrêter.
    private func busyRow(_ t: AgentTarget) -> some View {
        HStack(spacing: Socle.M.space2) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 0) {
                Text(store.agentStatus[t] ?? L.t("agent.status.think")).socle(Socle.T.label).foregroundStyle(Socle.C.text).lineLimit(1)
                if let start = store.agentStart[t] {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(L.t("agent.elapsed", Int(ctx.date.timeIntervalSince(start)))).socle(Socle.T.caption).foregroundStyle(Socle.C.textSubtle)
                    }
                }
            }
            Spacer(minLength: 0)
            Button(L.t("agent.stop")) { store.cancelAgent(t) }
                .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
        }
        .padding(Socle.M.space2_5)
        .background(Socle.C.bg, in: RoundedRectangle(cornerRadius: Socle.M.radius))
    }

    // MARK: Saisie

    private func composer(_ t: AgentTarget) -> some View {
        let busy = store.agentBusy.contains(t)
        return VStack(alignment: .leading, spacing: Socle.M.space2) {
            if let e = store.agentError[t] { Callout(kind: .warning, text: e) }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $input).socle(Socle.T.body).socleField(multiline: true)
                    .frame(height: 76)
                    .onKeyPress(keys: [.return], phases: .down) { press in
                        if press.modifiers.contains(.shift) { return .ignored }
                        send(t); return .handled
                    }
                if input.isEmpty {
                    Text(L.t("agent.placeholder")).socle(Socle.T.body).foregroundStyle(Socle.C.textDisabled)
                        .padding(.horizontal, 12).padding(.vertical, 10).allowsHitTesting(false)
                }
            }
            HStack(spacing: Socle.M.space2) {
                Menu {
                    ForEach(Array(cfg.quick.enumerated()), id: \.offset) { _, q in
                        Button(q.title) { input = ""; store.startAgent(t, q.prompt) }
                    }
                } label: { Text(L.t("agent.actions")) }
                    .menuStyle(.borderlessButton).fixedSize().disabled(busy || !cfg.isReady)
                Spacer()
                Button(L.t("agent.send")) { send(t) }
                    .buttonStyle(SocleButtonStyle(.primary, height: Socle.M.sizeControl)).fixedSize()
                    .disabled(busy || !cfg.isReady || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text(L.t("agent.rights")).socle(Socle.T.caption).foregroundStyle(Socle.C.textSubtle).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func send(_ t: AgentTarget) {
        let q = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, cfg.isReady, !store.agentBusy.contains(t) else { return }
        input = ""
        store.startAgent(t, q)
    }
}

// MARK: Bulle de message et carte de proposition (avant / après)

struct AgentBubble: View {
    @EnvironmentObject var store: Store
    let target: AgentTarget
    let message: AgentMessage
    @State private var picked: Set<String>?
    @State private var expanded: Set<String> = []

    private func md(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }

    var body: some View {
        let isUser = message.role == .user
        let parsed = isUser ? (text: message.text, proposal: nil as AgentProposal?) : AgentParse.split(message.text)
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: Socle.M.space2) {
                if !parsed.text.isEmpty {
                    if isUser {
                        Text(md(parsed.text)).socle(Socle.T.body).foregroundStyle(Socle.C.text).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        MarkdownView(text: parsed.text)
                    }
                }
                if let p = parsed.proposal { proposal(p) }
                HStack(spacing: Socle.M.space2) {
                    Text(L.date(message.date)).socle(Socle.T.caption).foregroundStyle(Socle.C.textDisabled)
                    if let u = message.usage {
                        Text(u.label(AgentConfig.current)).socle(Socle.T.caption).foregroundStyle(Socle.C.textDisabled)
                            .help(AgentConfig.current.kind == .claude ? L.t("agent.usage.note") : "")
                    }
                }
            }
            .padding(Socle.M.space3)
            .background(isUser ? Socle.C.surfaceSelected : Socle.C.bg, in: RoundedRectangle(cornerRadius: Socle.M.radiusMd))
            .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusMd).stroke(isUser ? Socle.C.infoBorder.opacity(0.5) : Socle.C.border, lineWidth: 1))
            if !isUser { Spacer(minLength: 0) }
        }
    }

    private func currentPost() -> UUID? { if case .post(let id) = target { return id }; return nil }

    private func proposal(_ p: AgentProposal) -> some View {
        let items = p.items(in: store.campaign, current: currentPost())
        let chosen = picked ?? Set(items.map(\.id))
        return VStack(alignment: .leading, spacing: Socle.M.space2) {
            Text(L.t("agent.proposal").uppercased()).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.warning)
            if !p.summary.isEmpty { Text(p.summary).socle(Socle.T.label).foregroundStyle(Socle.C.textStrong) }
            if message.applied != nil {
                Text(L.t("agent.applied.count", message.undo?.count ?? 0)).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted)
            } else if message.dismissed != true {
                if items.isEmpty { Text(L.t("agent.proposal.empty")).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted) }
                ForEach(items) { item in row(item, chosen: chosen.contains(item.id), all: Set(items.map(\.id))) }
            }
            HStack(spacing: Socle.M.space2) {
                if let d = message.applied {
                    Badge(text: L.t("agent.applied", L.date(d)), kind: .success)
                    Button(L.t("agent.undo")) { store.undoProposal(target, message: message.id) }
                        .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                } else if message.dismissed == true {
                    Badge(text: L.t("agent.dismissed"))
                } else if !items.isEmpty {
                    Button(chosen.count == items.count ? L.t("agent.apply") : L.t("agent.apply.selected", chosen.count)) {
                        store.applyProposal(target, message: message.id, only: chosen)
                    }
                    .buttonStyle(SocleButtonStyle(.primary, height: Socle.M.sizeControl)).fixedSize().disabled(chosen.isEmpty)
                    Button(L.t("agent.dismiss")) { store.dismissProposal(target, message: message.id) }
                        .buttonStyle(SocleButtonStyle(.tertiary, height: Socle.M.sizeControl)).fixedSize()
                }
            }
        }
        .padding(Socle.M.space3).frame(maxWidth: .infinity, alignment: .leading)
        .background(Socle.C.surface, in: RoundedRectangle(cornerRadius: Socle.M.radius))
        .overlay(RoundedRectangle(cornerRadius: Socle.M.radius).stroke(Socle.C.warningBorder, lineWidth: 1))
    }

    /// Un champ : case à cocher, puis la valeur actuelle et la valeur proposée l'une sous l'autre.
    private func row(_ item: AgentItem, chosen: Bool, all: Set<String>) -> some View {
        let long = item.old.count > 160 || item.new.count > 160
        let open = expanded.contains(item.id)
        return VStack(alignment: .leading, spacing: Socle.M.space1_5) {
            Toggle(isOn: Binding(get: { chosen }, set: { on in
                var s = picked ?? all
                if on { s.insert(item.id) } else { s.remove(item.id) }
                picked = s
            })) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.label).socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong)
                    if let post = item.post { Text(post).socle(Socle.T.caption).foregroundStyle(Socle.C.textSubtle).lineLimit(1) }
                }
            }
            .toggleStyle(.checkbox)
            diffBlock(L.t("agent.before"), item.old.isEmpty ? L.t("agent.empty.value") : item.old, tint: Socle.C.dangerBg, open: open)
            diffBlock(L.t("agent.after"), item.new, tint: Socle.C.successBg, open: open)
            if long {
                Button(open ? L.t("agent.showless") : L.t("agent.showall")) {
                    if open { expanded.remove(item.id) } else { expanded.insert(item.id) }
                }
                .buttonStyle(.plain).socle(Socle.T.caption).foregroundStyle(Socle.C.accentText)
            }
        }
        .padding(Socle.M.space2)
        .overlay(RoundedRectangle(cornerRadius: Socle.M.radius).stroke(Socle.C.borderSubtle, lineWidth: 1))
    }

    private func diffBlock(_ title: String, _ text: String, tint: Color, open: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textSubtle)
            Text(open || text.count <= 160 ? text : String(text.prefix(160)) + "…")
                .socle(Socle.T.meta).foregroundStyle(Socle.C.text).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Socle.M.space2).frame(maxWidth: .infinity, alignment: .leading)
                .background(tint.opacity(0.6), in: RoundedRectangle(cornerRadius: Socle.M.radius))
        }
    }
}

// MARK: Réglages de l'agent

struct AgentSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cfg = AgentConfig.current
    @State private var apiKey = Keychain.get("openai")
    @State private var testing = false
    @State private var testResult: (ok: Bool, text: String)?

    var body: some View {
        VStack(alignment: .leading, spacing: Socle.M.space4) {
            Text(L.t("agent.settings.title")).socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong)
            Field(label: L.t("agent.settings.kind")) {
                SocleSegmented(options: AgentKind.allCases, selection: cfg.kind, label: \.label, onSelect: { cfg.kind = $0; testResult = nil })
            }
            switch cfg.kind {
            case .claude:
                Field(label: L.t("agent.settings.claudepath")) {
                    TextField("", text: $cfg.claudePath).socleField()
                    Text(AgentRunner.claudeURL(cfg).map { L.t("agent.settings.detected", $0.path) } ?? L.t("agent.settings.notfound"))
                        .socle(Socle.T.meta).foregroundStyle(AgentRunner.claudeURL(cfg) == nil ? Socle.C.warning : Socle.C.textSubtle)
                }
                HStack(alignment: .top, spacing: Socle.M.space3) {
                    Field(label: L.t("agent.settings.session.name")) { TextField("hERALD", text: $cfg.sessionName).socleField() }
                    Field(label: L.t("agent.settings.session.id")) { TextField("", text: $cfg.sessionID).socleField() }
                }
                Toggle(L.t("agent.settings.light"), isOn: $cfg.lightMode)
                Text(L.t("agent.settings.light.note")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).fixedSize(horizontal: false, vertical: true)
                Text(L.t("agent.settings.session.note")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).fixedSize(horizontal: false, vertical: true)
            case .command:
                Field(label: L.t("agent.settings.command")) {
                    TextField("codex exec -", text: $cfg.command).socleField()
                    HStack(spacing: Socle.M.space2) {
                        Text(L.t("agent.settings.command.note")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button("Codex") { cfg.command = "codex exec -" }
                            .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                    }
                }
            case .openai:
                Field(label: L.t("agent.settings.apiurl")) { TextField("https://…", text: $cfg.apiURL).socleField() }
                HStack(alignment: .top, spacing: Socle.M.space3) {
                    Field(label: L.t("agent.settings.model")) { TextField("", text: $cfg.model).socleField() }
                    Field(label: L.t("agent.settings.apikey")) { SecureField("", text: $apiKey).socleField() }
                }
                HStack(alignment: .top, spacing: Socle.M.space3) {
                    Field(label: L.t("agent.settings.price.in")) { TextField("0", value: $cfg.priceIn, format: .number).socleField() }
                    Field(label: L.t("agent.settings.price.out")) { TextField("0", value: $cfg.priceOut, format: .number).socleField() }
                }
                Text(L.t("agent.settings.price.note", AgentCurrency.code)).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).fixedSize(horizontal: false, vertical: true)
            }
            if cfg.kind == .claude {
                Field(label: L.t("agent.settings.model")) { TextField(L.t("agent.settings.model.default"), text: $cfg.model).socleField() }
            }
            if cfg.kind != .openai {
                Field(label: L.t("agent.settings.workdir")) {
                    HStack(spacing: Socle.M.space2) {
                        TextField(NSHomeDirectory(), text: $cfg.workdir).socleField()
                        Button(L.t("agent.settings.choose")) { chooseFolder() }
                            .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                    }
                    Text(L.t("agent.settings.workdir.note")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).fixedSize(horizontal: false, vertical: true)
                }
            }
            Field(label: L.t("agent.settings.share")) {
                HStack(spacing: Socle.M.space4) {
                    Toggle(L.t("agent.settings.share.drafts"), isOn: $cfg.shareDrafts)
                    Toggle(L.t("agent.settings.share.stats"), isOn: $cfg.shareStats)
                    Toggle(L.t("agent.settings.share.notes"), isOn: $cfg.shareCampaignNotes)
                }
                Text(L.t("agent.settings.share.note")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).fixedSize(horizontal: false, vertical: true)
            }
            if AgentCurrency.code != "USD" {
                Field(label: L.t("agent.settings.fx", AgentCurrency.code)) {
                    TextField(AgentCurrency.rate(AgentConfig()).map { String(format: "%.4f", $0) } ?? "0", value: $cfg.fxRate, format: .number).socleField().frame(width: 160)
                    Text(L.t("agent.settings.fx.note", AgentCurrency.code)).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).fixedSize(horizontal: false, vertical: true)
                }
            }
            Field(label: L.t("agent.settings.quick")) {
                TextEditor(text: $cfg.quickPrompts).socle(Socle.T.monoSm).socleField(multiline: true).frame(height: 70)
                Text(L.t("agent.settings.quick.note")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).fixedSize(horizontal: false, vertical: true)
            }
            // essai sans rien demander à l'agent : c'est ici que macOS pose sa question pour un disque externe
            VStack(alignment: .leading, spacing: Socle.M.space1_5) {
                HStack(spacing: Socle.M.space2) {
                    Button(L.t("agent.test")) { runTest() }
                        .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize().disabled(testing)
                    if testing { ProgressView().controlSize(.small) }
                    if let r = testResult {
                        Text(r.text).socle(Socle.T.meta).foregroundStyle(r.ok ? Socle.C.success : Socle.C.warning).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if cfg.workdir.hasPrefix("/Volumes/") {
                    Text(L.t("agent.volume.hint")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).fixedSize(horizontal: false, vertical: true)
                }
            }
            Callout(kind: .info, text: L.t("agent.rights"))
            HStack(spacing: Socle.M.space2) {
                Spacer()
                Button(L.t("action.cancel")) { dismiss() }.buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
                Button(L.t("action.save")) {
                    var c = cfg; c.enabled = AgentConfig.current.enabled
                    AgentConfig.current = c
                    Keychain.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), "openai")
                    dismiss()
                }
                .buttonStyle(SocleButtonStyle(.primary)).fixedSize().keyboardShortcut(.defaultAction)
            }
        }
        .padding(Socle.M.space6)
        .frame(width: 680)
        .background(Socle.C.surface)
    }

    private func runTest() {
        testing = true; testResult = nil
        let c = cfg
        Task {
            let r = await AgentRunner.test(c)
            await MainActor.run {
                testing = false
                switch r {
                case .success(let t): testResult = (true, t)
                case .failure(let e): testResult = (false, e.message)
                }
            }
        }
    }

    private func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false
        if p.runModal() == .OK, let u = p.url { cfg.workdir = u.path; testResult = nil }
    }
}
