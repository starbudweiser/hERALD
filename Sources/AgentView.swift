// hERALD — discussion avec l'agent IA (campagne ou publication) et réglages de l'agent.
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

struct AgentView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let target: AgentTarget
    @State private var input = ""
    @State private var settings = false
    @State private var cfg = AgentConfig.current

    var body: some View {
        let thread = store.agentThread(target)
        let busy = store.agentBusy.contains(target)
        VStack(alignment: .leading, spacing: Socle.M.space3) {
            header(thread)
            if !cfg.isReady {
                Callout(kind: .warning, text: L.t("agent.notconfigured"))
            }
            if cfg.kind == .claude, cfg.isReady { sessionLine(thread) }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Socle.M.space3) {
                        if thread.messages.isEmpty { EmptyState(text: L.t("agent.empty")).frame(height: 120) }
                        ForEach(thread.messages) { m in AgentBubble(target: target, message: m).id(m.id) }
                        if busy {
                            HStack(spacing: Socle.M.space2) {
                                ProgressView().controlSize(.small)
                                Text(L.t("agent.thinking")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                            }.id("busy")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: thread.messages.count) { _ in
                    withAnimation {
                        if busy { proxy.scrollTo("busy", anchor: .bottom) }
                        else if let last = thread.messages.last?.id { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
                .onChange(of: busy) { b in if b { withAnimation { proxy.scrollTo("busy", anchor: .bottom) } } }
            }
            .frame(maxHeight: .infinity)
            if let e = store.agentError[target] { Callout(kind: .warning, text: e) }
            quickActions(busy)
            HStack(alignment: .bottom, spacing: Socle.M.space2) {
                TextEditor(text: $input).socle(Socle.T.body).socleField(multiline: true).frame(height: 70)
                Button(L.t("agent.send")) { send() }
                    .buttonStyle(SocleButtonStyle(.primary, height: Socle.M.sizeControlLg)).fixedSize()
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(busy || !cfg.isReady || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text(L.t("agent.rights")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).fixedSize(horizontal: false, vertical: true)
        }
        .padding(Socle.M.space5)
        .frame(width: 780, height: 700)
        .background(Socle.C.surface)
        .sheet(isPresented: $settings, onDismiss: { cfg = AgentConfig.current }) { AgentSettingsView() }
    }

    private func header(_ thread: AgentThread) -> some View {
        HStack(spacing: Socle.M.space2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L.t("agent.chat")).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textSubtle)
                Text(store.agentTitle(target)).socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong).lineLimit(1)
            }
            Spacer()
            Button(L.t("agent.clear")) { store.clearThread(target) }
                .buttonStyle(SocleButtonStyle(.tertiary, height: Socle.M.sizeControl)).fixedSize().disabled(thread.messages.isEmpty)
            Button(L.t("agent.configure")) { settings = true }
                .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
            Button(L.t("action.done")) { dismiss() }
                .buttonStyle(SocleButtonStyle(.primary, height: Socle.M.sizeControl)).fixedSize().keyboardShortcut(.cancelAction)
        }
    }

    /// Session Claude Code qui reçoit les demandes, et sous-sessions ouvertes par l'agent pour cette discussion.
    private func sessionLine(_ thread: AgentThread) -> some View {
        let id = cfg.sessionID
        return VStack(alignment: .leading, spacing: Socle.M.space1_5) {
            HStack(spacing: Socle.M.space2) {
                Badge(text: cfg.sessionName.isEmpty ? "hERALD" : cfg.sessionName, kind: .accent)
                Text(id.isEmpty ? L.t("agent.session.new") : L.t("agent.session.id", String(id.prefix(8))))
                    .socle(Socle.T.monoSm).foregroundStyle(Socle.C.textSubtle)
                Spacer()
                if !id.isEmpty {
                    CopyButton(title: L.t("agent.copyresume")) { "cd \"\(cfg.workURL.path)\" && claude --resume \(id)" }
                }
            }
            if !thread.subSessions.isEmpty {
                HStack(spacing: Socle.M.space2) {
                    Text(L.t("agent.subsessions").uppercased()).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textSubtle)
                    ForEach(thread.subSessions) { s in
                        CopyButton(title: s.name) { "cd \"\(cfg.workURL.path)\" && claude --resume \(s.id)" }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func quickActions(_ busy: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Socle.M.space1_5) {
                ForEach(Array(cfg.quick.enumerated()), id: \.offset) { _, q in
                    Button(q.title) { input = q.prompt; send() }
                        .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                        .disabled(busy || !cfg.isReady)
                }
            }
        }
    }

    private func send() {
        let q = input
        input = ""
        Task { await store.askAgent(target, q) }
    }
}

// MARK: Bulle de message et carte de proposition

struct AgentBubble: View {
    @EnvironmentObject var store: Store
    let target: AgentTarget
    let message: AgentMessage

    private func md(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }

    var body: some View {
        let isUser = message.role == .user
        let parsed = isUser ? (text: message.text, proposal: nil as AgentProposal?) : AgentParse.split(message.text)
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 80) }
            VStack(alignment: .leading, spacing: Socle.M.space2) {
                if !parsed.text.isEmpty {
                    Text(md(parsed.text)).socle(Socle.T.body).foregroundStyle(Socle.C.text).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let p = parsed.proposal { proposal(p) }
                Text(L.date(message.date)).socle(Socle.T.caption).foregroundStyle(Socle.C.textDisabled)
            }
            .padding(Socle.M.space3)
            .background(isUser ? Socle.C.surfaceSelected : Socle.C.bg, in: RoundedRectangle(cornerRadius: Socle.M.radiusMd))
            .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusMd).stroke(isUser ? Socle.C.infoBorder.opacity(0.5) : Socle.C.border, lineWidth: 1))
            if !isUser { Spacer(minLength: 80) }
        }
    }

    private func proposal(_ p: AgentProposal) -> some View {
        VStack(alignment: .leading, spacing: Socle.M.space2) {
            Text(L.t("agent.proposal").uppercased()).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.warning)
            if !p.summary.isEmpty { Text(p.summary).socle(Socle.T.label).foregroundStyle(Socle.C.textStrong) }
            ForEach(Array(p.changes.enumerated()), id: \.offset) { _, ch in change(ch) }
            if let a = p.campaignNotesAppend { preview(L.t("campaign.notes"), a) }
            HStack(spacing: Socle.M.space2) {
                if let d = message.applied {
                    Badge(text: L.t("agent.applied", L.date(d)), kind: .success)
                    Button(L.t("agent.undo")) { store.undoProposal(target, message: message.id) }
                        .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                } else if message.dismissed == true {
                    Badge(text: L.t("agent.dismissed"))
                } else {
                    Button(L.t("agent.apply")) { store.applyProposal(target, message: message.id) }
                        .buttonStyle(SocleButtonStyle(.primary, height: Socle.M.sizeControl)).fixedSize()
                    Button(L.t("agent.dismiss")) { store.dismissProposal(target, message: message.id) }
                        .buttonStyle(SocleButtonStyle(.tertiary, height: Socle.M.sizeControl)).fixedSize()
                }
            }
        }
        .padding(Socle.M.space3).frame(maxWidth: .infinity, alignment: .leading)
        .background(Socle.C.surface, in: RoundedRectangle(cornerRadius: Socle.M.radius))
        .overlay(RoundedRectangle(cornerRadius: Socle.M.radius).stroke(Socle.C.warningBorder, lineWidth: 1))
        .opacity(message.dismissed == true ? 0.6 : 1)
    }

    private func change(_ ch: AgentProposal.Change) -> some View {
        var current: UUID?; if case .post(let id) = target { current = id }
        let title = AgentParse.find(ch.post, in: store.campaign, current: current).map { store.campaign.posts[$0].title } ?? (ch.post ?? "—")
        return VStack(alignment: .leading, spacing: Socle.M.space1) {
            Text(title).socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong)
            if let w = ch.why, !w.isEmpty { Text(w).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted) }
            if let s = ch.status { Text("\(L.t("col.status")) → \(s == .published ? L.t("agent.apply.ignored") : s.label)").socle(Socle.T.meta).foregroundStyle(Socle.C.text) }
            if let n = ch.notes { preview(L.t("col.notes"), n) }
            ForEach(ch.drafts.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in preview("\(L.t("tab.drafts")) \(k.uppercased())", v) }
        }
    }

    private func preview(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).socle(Socle.T.caption).foregroundStyle(Socle.C.textSubtle)
            Text(text.count > 420 ? String(text.prefix(420)) + "…" : text).socle(Socle.T.meta).foregroundStyle(Socle.C.text)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .padding(Socle.M.space2).frame(maxWidth: .infinity, alignment: .leading)
                .background(Socle.C.bg, in: RoundedRectangle(cornerRadius: Socle.M.radius))
        }
    }
}

// MARK: Réglages de l'agent

struct AgentSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cfg = AgentConfig.current
    @State private var apiKey = Keychain.get("openai")

    var body: some View {
        VStack(alignment: .leading, spacing: Socle.M.space4) {
            Text(L.t("agent.settings.title")).socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong)
            Field(label: L.t("agent.settings.kind")) {
                SocleSegmented(options: AgentKind.allCases, selection: cfg.kind, label: \.label, onSelect: { cfg.kind = $0 })
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
            }
            if cfg.kind == .claude {
                Field(label: L.t("agent.settings.model")) { TextField(L.t("agent.settings.model.default"), text: $cfg.model).socleField() }
            }
            Field(label: L.t("agent.settings.workdir")) {
                HStack(spacing: Socle.M.space2) {
                    TextField(NSHomeDirectory(), text: $cfg.workdir).socleField()
                    Button(L.t("agent.settings.choose")) { chooseFolder() }
                        .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                }
                Text(L.t("agent.settings.workdir.note")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).fixedSize(horizontal: false, vertical: true)
            }
            Field(label: L.t("agent.settings.share")) {
                HStack(spacing: Socle.M.space4) {
                    Toggle(L.t("agent.settings.share.drafts"), isOn: $cfg.shareDrafts)
                    Toggle(L.t("agent.settings.share.stats"), isOn: $cfg.shareStats)
                    Toggle(L.t("agent.settings.share.notes"), isOn: $cfg.shareCampaignNotes)
                }
                Text(L.t("agent.settings.share.note")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).fixedSize(horizontal: false, vertical: true)
            }
            Field(label: L.t("agent.settings.quick")) {
                TextEditor(text: $cfg.quickPrompts).socle(Socle.T.monoSm).socleField(multiline: true).frame(height: 80)
                Text(L.t("agent.settings.quick.note")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).fixedSize(horizontal: false, vertical: true)
            }
            Callout(kind: .info, text: L.t("agent.rights"))
            HStack(spacing: Socle.M.space2) {
                Spacer()
                Button(L.t("action.cancel")) { dismiss() }.buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
                Button(L.t("action.save")) {
                    AgentConfig.current = cfg
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

    private func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false
        if p.runModal() == .OK, let u = p.url { cfg.workdir = u.path }
    }
}
