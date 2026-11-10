// hERALD — vue Contacts : liste filtrable, fiche, fil des messages et éditeur de mail (envoi par l'app Mail).
import SwiftUI

enum ContactFilter: String, CaseIterable, Identifiable {
    case all, youtubers, press, others
    var id: String { rawValue }
    var label: String { L.t("contact.filter.\(rawValue)") }
    func accepts(_ k: ContactKind) -> Bool {
        switch self {
        case .all: true
        case .youtubers: k == .youtuber
        case .press: k == .press
        case .others: k != .youtuber && k != .press
        }
    }
}

struct ContactStatusBadge: View {
    let status: ContactStatus
    var body: some View { Badge(text: status.label, kind: kind) }
    private var kind: Badge.Kind {
        switch status {
        case .toContact: .neutral
        case .contacted, .followedUp: .accent
        case .replied: .warning
        case .accepted, .covered: .success
        case .declined: .danger
        }
    }
}

struct ContactsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    @State private var filter: ContactFilter = .all
    @State private var scanNote: String?
    @State private var scanIsError = false

    private var rows: [Contact] {
        store.contacts.filter { filter.accepts($0.kind) && ui.matches($0.name, $0.email, $0.url, $0.notes) }
    }

    var body: some View {
        SplitLayout(width: 480) {
            HStack(spacing: Socle.M.space2) {
                SocleSegmented(options: ContactFilter.allCases, selection: filter, label: \.label, onSelect: { filter = $0 })
                Spacer(minLength: 0)
                Button(L.t("contact.scan")) { scan() }
                    .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                    .disabled(MailClient.current != .mail || store.contacts.allSatisfy { $0.email.isEmpty })
                    .help(MailClient.current == .mail ? L.t("contact.scan") : L.t("mail.scan.unavailable"))
            }
            .padding(Socle.M.space3)
            if let n = scanNote {
                Text(n).socle(Socle.T.meta).foregroundStyle(scanIsError ? Socle.C.danger : Socle.C.success).lineLimit(1)
                    .padding(.horizontal, Socle.M.space3).padding(.bottom, Socle.M.space2)
            }
            Divider().overlay(Socle.C.borderSubtle)
            if rows.isEmpty { Text(L.t("contact.none")).socle(Socle.T.body).foregroundStyle(Socle.C.textSubtle).padding(Socle.M.space4) }
            ForEach(rows) { c in
                let due = c.followUpDue()
                ItemRow(selected: c.id == ui.selectedContact, symbol: c.kind.symbol, tint: due ? Socle.C.warning : Socle.C.textMuted,
                        title: c.name,
                        meta: c.status.waiting ? (c.nextFollowUp.map { L.t("contact.followup.on", L.shortDay($0)) } ?? "") : "",
                        metaColor: due ? Socle.C.warning : Socle.C.textSubtle,
                        action: { ui.selectedContact = c.id }) { ContactStatusBadge(status: c.status) }
            }
        } detail: {
            if let id = ui.selectedContact, store.contact(id) != nil { ContactDetail(id: id) }
            else { EmptyState(text: L.t("contact.select")) }
        }
    }
}

extension ContactsView {
    fileprivate func scan() {
        let r = store.scanReplies()
        scanIsError = r.error != nil
        scanNote = r.error.map { L.t("contact.scan.err", $0) } ?? (r.count > 0 ? L.t("contact.scan.done", r.count) : L.t("contact.scan.none"))
    }
}

struct ContactDetail: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    let id: UUID
    @State private var to = ""
    @State private var subject = ""
    @State private var bodyText = ""
    @State private var kind: MessageKind = .first
    @State private var draftID: UUID?
    @State private var loaded: UUID?
    @State private var confirming = false
    @State private var sendError: String?
    @State private var expanded: UUID?
    @State private var removing = false
    @State private var sendNote: String?
    @State private var trashing: UUID?

    private var contact: Binding<Contact> { Binding(get: { store.contact(id) ?? Contact() }, set: { store.updateContact($0) }) }
    private var c: Contact { contact.wrappedValue }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Socle.M.space4) {
                header
                fiche
                thread
                editor
            }
            .padding(Socle.M.space4)
        }
        .onAppear(perform: load)
        .onChange(of: id) { _, _ in load() }
        .confirmationDialog(L.t("mail.confirm", to), isPresented: $confirming) {
            Button(L.t("mail.send")) { send() }
        } message: { Text(L.t("mail.confirm.note")) }
        .confirmationDialog(L.t("mail.delete.confirm"), isPresented: Binding(get: { trashing != nil }, set: { if !$0 { trashing = nil } })) {
            Button(L.t("mail.delete"), role: .destructive) {
                if let m = trashing { sendError = store.trashReply(contact: id, message: m).map { L.t("mail.delete.err", $0) } }
                trashing = nil
            }
        }
        .confirmationDialog(L.t("contact.remove.confirm", c.name), isPresented: $removing) {
            Button(L.t("contact.remove"), role: .destructive) { store.removeContact(id); ui.selectedContact = nil }
        }
    }

    // MARK: Fiche

    private var header: some View {
        VStack(alignment: .leading, spacing: Socle.M.space2) {
            TextField("", text: contact.name).socleField().socle(Socle.T.heading)
            HStack(spacing: Socle.M.space2) {
                Picker("", selection: contact.kind) { ForEach(ContactKind.allCases) { Text($0.label).tag($0) } }
                    .labelsHidden().fixedSize()
                Picker("", selection: contact.status) { ForEach(ContactStatus.allCases) { Text($0.label).tag($0) } }
                    .labelsHidden().fixedSize()
                Spacer(minLength: 0)
                if ui.workspace == nil {
                    Button(L.t("publish.site")) { ui.openWorkspace(.contact(id), store) }
                        .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize().disabled(c.url.isEmpty)
                }
            }
        }
    }

    private var fiche: some View {
        VStack(alignment: .leading, spacing: Socle.M.space3) {
            HStack(alignment: .top, spacing: Socle.M.space3) {
                Field(label: L.t("contact.email")) { TextField("", text: contact.email).socleField() }
                Field(label: L.t("contact.lang")) {
                    SocleSegmented(options: Lang.allCases, selection: c.lang, label: { $0.label }, onSelect: { contact.wrappedValue.lang = $0 })
                }.fixedSize()
            }
            Field(label: L.t("contact.site")) {
                HStack(spacing: Socle.M.space2) {
                    TextField("https://…", text: contact.url).socleField()
                    Button(L.t("action.open")) { Browser.open(c.url) }
                        .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize().disabled(c.url.isEmpty)
                }
            }
            HStack(alignment: .top, spacing: Socle.M.space3) {
                Field(label: L.t("contact.followup")) {
                    HStack(spacing: Socle.M.space2) {
                        Toggle("", isOn: Binding(get: { c.nextFollowUp != nil },
                                                 set: { contact.wrappedValue.nextFollowUp = $0 ? Date().addingTimeInterval(8 * 86400) : nil }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        if c.nextFollowUp != nil {
                            DatePicker("", selection: Binding(get: { c.nextFollowUp ?? Date() }, set: { contact.wrappedValue.nextFollowUp = $0 }),
                                       displayedComponents: .date).labelsHidden().fixedSize()
                        }
                    }
                    .frame(minHeight: Socle.M.sizeControlLg, alignment: .leading)
                }.fixedSize()
                Field(label: L.t("contact.coverage")) {
                    HStack(spacing: Socle.M.space2) {
                        TextField("https://…", text: contact.coverage).socleField()
                        Button { Browser.open(c.coverage) } label: { Image(systemName: "arrow.up.right.square") }
                            .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize().disabled(c.coverage.isEmpty)
                            .accessibilityLabel(L.t("action.open"))
                    }
                }
            }
            Field(label: L.t("col.notes")) {
                TextEditor(text: contact.notes).socle(Socle.T.body).socleField(multiline: true).frame(height: 64)
            }
            HStack {
                Spacer(minLength: 0)
                Button(L.t("contact.remove")) { removing = true }
                    .buttonStyle(SocleButtonStyle(.tertiary, height: Socle.M.sizeControl)).fixedSize()
            }
        }
    }

    // MARK: Fil des messages

    private var thread: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L.t("contact.thread").uppercased()).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textSubtle).padding(.bottom, Socle.M.space2)
            if c.messages.isEmpty { Text(L.t("contact.thread.none")).socle(Socle.T.body).foregroundStyle(Socle.C.textSubtle) }
            ForEach(c.messages.sorted { $0.date > $1.date }) { m in
                Button { expanded = expanded == m.id ? nil : m.id } label: {
                    HStack(spacing: Socle.M.space2) {
                        Text(L.day(m.date)).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).frame(width: 96, alignment: .leading).lineLimit(1)
                        Badge(text: m.direction.label, kind: m.direction == .sent ? .success : m.direction == .received ? .warning : .neutral)
                        Text(m.subject.isEmpty ? m.kind.label : m.subject).socle(Socle.T.label).foregroundStyle(Socle.C.text).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: expanded == m.id ? "chevron.up" : "chevron.down").font(.system(size: 9)).foregroundStyle(Socle.C.textSubtle)
                    }
                    .frame(height: 34).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if expanded == m.id {
                    Text(m.body).socle(Socle.T.body).foregroundStyle(Socle.C.text).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(Socle.M.space3)
                        .background(Socle.C.bgSunken, in: RoundedRectangle(cornerRadius: Socle.M.radius))
                        .padding(.bottom, m.mailID == nil ? Socle.M.space2 : 0)
                    if m.mailID != nil {
                        HStack {
                            Spacer()
                            Button(L.t("mail.delete")) { trashing = m.id }
                                .buttonStyle(SocleButtonStyle(.tertiary, height: Socle.M.sizeControl)).fixedSize()
                        }
                        .padding(.bottom, Socle.M.space2)
                    }
                }
                Divider().overlay(Socle.C.borderSubtle)
            }
        }
    }

    // MARK: Éditeur de mail

    private var editor: some View {
        VStack(alignment: .leading, spacing: Socle.M.space2) {
            HStack(spacing: Socle.M.space2) {
                Text(L.t("mail.title").uppercased()).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textSubtle)
                Spacer()
                Menu(L.t("mail.template")) {
                    Button(L.t("message.kind.first")) { applyTemplate(.first) }
                    Button(L.t("message.kind.followUp")) { applyTemplate(.followUp) }
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
            Field(label: L.t("mail.to")) { TextField("", text: $to).socleField() }
            Field(label: L.t("mail.subject")) { TextField("", text: $subject).socleField() }
            TextEditor(text: $bodyText).socle(Socle.T.body).socleField(multiline: true).frame(height: 190)
            if let n = sendNote { Callout(kind: .info, text: n) }
            if let e = sendError {
                Callout(kind: .warning, text: e)
                Button(L.t("mail.openmail")) { MailSender.openDraft(to: to, subject: subject, body: bodyText) }
                    .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
            }
            HStack(spacing: Socle.M.space2) {
                Spacer()
                Button(L.t("mail.savedraft")) { saveDraft() }
                    .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControlLg)).fixedSize()
                    .disabled(subject.isEmpty && bodyText.isEmpty)
                Button(L.t("mail.send")) { sendError = nil; confirming = true }
                    .buttonStyle(SocleButtonStyle(.primary, height: Socle.M.sizeControlLg)).fixedSize()
                    .disabled(to.trimmingCharacters(in: .whitespaces).isEmpty || subject.isEmpty || bodyText.isEmpty)
            }
            Text(L.t("mail.note")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).lineLimit(1)
        }
    }

    private func load() {
        guard loaded != id else { return }
        loaded = id; sendError = nil; sendNote = nil; expanded = nil
        to = c.email
        if let d = c.messages.filter({ $0.direction == .draft }).max(by: { $0.date < $1.date }) {
            draftID = d.id; kind = d.kind; subject = d.subject; bodyText = d.body; if !d.to.isEmpty { to = d.to }
        } else {
            draftID = nil
            applyTemplate(c.status.waiting ? .followUp : .first)
        }
    }

    private func applyTemplate(_ k: MessageKind) {
        kind = k
        let t = Outreach.template(k, for: c, campaign: store.campaign)
        subject = t.subject; bodyText = t.body
    }

    private func saveDraft() {
        var x = c
        let m = OutreachMessage(id: draftID ?? UUID(), date: Date(), kind: kind, direction: .draft, subject: subject, body: bodyText, to: to)
        if let i = x.messages.firstIndex(where: { $0.id == m.id }) { x.messages[i] = m } else { x.messages.append(m) }
        draftID = m.id
        store.updateContact(x)
    }

    /// Envoi par Mail ; après succès : message ajouté au fil, statut mis à jour, relance dans 8 jours.
    private func send() {
        sendNote = nil
        if MailClient.current == .other {
            MailSender.openDraft(to: to, subject: subject, body: bodyText)
            sendNote = L.t("mail.sent.other")
            return
        }
        switch MailSender.send(to: to, subject: subject, body: bodyText) {
        case .failure(.script(let msg)):
            sendError = L.t("mail.err", msg)
        case .success:
            var x = c
            x.messages.removeAll { $0.id == draftID }
            x.messages.append(OutreachMessage(date: Date(), kind: kind, direction: .sent, subject: subject, body: bodyText, to: to))
            if x.email.isEmpty { x.email = to }
            x.status = kind == .first ? .contacted : .followedUp
            x.nextFollowUp = Calendar.current.date(byAdding: .day, value: 8, to: Date())
            store.updateContact(x)
            draftID = nil; loaded = nil; load()
        }
    }
}
