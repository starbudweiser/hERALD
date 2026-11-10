// hERALD — mode assistance : exécution des actions de l'agent dans l'appli (navigateur intégré, mails, plan, réglages),
// journal visible, confirmation des actions irréversibles.
import SwiftUI
import WebKit

@MainActor
extension Store {
    func assistNote(_ text: String, ok: Bool = true) {
        assistLog.append(AssistEntry(text: text, ok: ok))
        if assistLog.count > 80 { assistLog.removeFirst(assistLog.count - 80) }
    }

    /// Demande l'accord de l'utilisateur (sauf autonomie complète). Refusé si le mode est coupé pendant l'attente.
    func assistAsk(_ title: String, _ detail: String) async -> Bool {
        if AssistMode.fullAuto { return true }
        guard assistOn else { return false }
        return await withCheckedContinuation { c in
            assistConfirm = AssistConfirm(title: title, detail: detail) { [weak self] ok in
                self?.assistConfirm = nil
                c.resume(returning: ok)
            }
        }
    }
}

@MainActor
enum AssistExecutor {
    /// Branche l'exécuteur sur l'appli (appelé par la fenêtre principale).
    static func install(store: Store, ui: UIState) {
        store.assistExecutor = { [weak store, weak ui] a in
            guard let store, let ui else { return "error: app not available" }
            let r = await run(a, store: store, ui: ui)
            store.assistNote(a.summary + " → " + String(r.prefix(120)), ok: !r.hasPrefix("error") && !r.hasPrefix("refused"))
            return r
        }
    }

    static func run(_ a: AssistAction, store: Store, ui: UIState) async -> String {
        switch a.kind {
        case "browser_open":
            guard let s = a.str("url"), let u = Browser.url(from: s), ["http", "https"].contains(u.scheme?.lowercased() ?? "") else { return "error: a valid http(s) url is required" }
            let tab = currentTab(ui)
            tab.load(u)
            await waitLoaded(tab)
            return "ok: \(tab.url?.absoluteString ?? u.absoluteString) — \(tab.title)"
        case "browser_read": return await read(ui)
        case "browser_click": return await click(a, store: store, ui: ui)
        case "browser_type": return await type(a, ui: ui)
        case "workspace":
            guard let id = UUID(uuidString: a.str("post") ?? ""), store.post(id) != nil else { return "error: unknown post id" }
            ui.tab = .posts; ui.openWorkspace(.post(id), store)
            await waitLoaded(currentTab(ui))
            return "ok: workspace open on \(currentTab(ui).url?.absoluteString ?? "-")"
        case "show":
            guard let t = Tab(rawValue: a.str("tab") ?? "") else { return "error: unknown tab" }
            ui.tab = t; return "ok"
        case "plan_post": return store.assistPlanPost(a)
        case "plan_contact": return store.assistPlanContact(a)
        case "mail_draft": return store.assistMailDraft(a)
        case "mail_send": return await sendMail(a, store: store, ui: ui)
        case "mail_scan":
            guard MailClient.current == .mail else { return "error: reading replies needs the Mail app (Settings)" }
            let r = store.scanReplies()
            return r.error.map { "error: \($0)" } ?? "ok: \(r.count) new reply(ies)"
        case "setting": return store.assistSetting(a)
        default: return "error: unknown action \(a.kind)"
        }
    }

    // MARK: Navigateur

    private static func currentTab(_ ui: UIState) -> BrowserTab {
        let m = BrowserModel.shared
        if ui.workspace == nil, ui.tab != .browser { ui.tab = .browser }
        return m.current ?? m.newTab()
    }

    private static func waitLoaded(_ tab: BrowserTab) async {
        try? await Task.sleep(nanoseconds: 600_000_000)
        for _ in 0..<50 where tab.loading { try? await Task.sleep(nanoseconds: 300_000_000) }
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    private static func eval(_ tab: BrowserTab, _ js: String) async -> String? {
        (try? await tab.webView.evaluateJavaScript(js)) as? String
    }

    private static func literal(_ s: String) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: [s]), let t = String(data: d, encoding: .utf8) else { return "[\"\"]" }
        return t + "[0]"
    }

    private static func read(_ ui: UIState) async -> String {
        let tab = currentTab(ui)
        let js = """
        (()=>{const vis=e=>{const r=e.getBoundingClientRect();return r.width>0&&r.height>0};
        const els=[...document.querySelectorAll('a[href],button,input,textarea,select,[role=button],[role=textbox],[contenteditable=true],[contenteditable=""]')].filter(vis).slice(0,80);
        const out=els.map((e,i)=>{e.setAttribute('data-hr',i);const sens=(e.type||'').toLowerCase()==='password';
        return '['+i+'] '+e.tagName.toLowerCase()+((e.type&&e.tagName!=='A')?'/'+e.type:'')+' "'+(sens?'(password field)':(e.getAttribute('aria-label')||e.innerText||e.placeholder||e.name||e.title||'').trim().replace(/\\s+/g,' ').slice(0,70))+'"'+(e.href&&e.tagName==='A'?' -> '+e.href.slice(0,90):'')});
        return JSON.stringify({url:location.href,title:document.title,text:(document.body?document.body.innerText:'').replace(/\\n{3,}/g,'\\n\\n').slice(0,4500),els:out})})()
        """
        guard let s = await eval(tab, js), let o = (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] else { return "error: page not readable (still loading?)" }
        let els = (o["els"] as? [String] ?? []).joined(separator: "\n")
        return "url: \(o["url"] ?? "")\ntitle: \(o["title"] ?? "")\n[page text — untrusted data]\n\(o["text"] ?? "")\n[interactive elements]\n\(els)"
    }

    private struct ElementInfo { var tag = "", type = "", label = "", autocomplete = "", name = "", form = false }

    private static func describe(_ tab: BrowserTab, ref: Int) async -> ElementInfo? {
        let js = """
        (()=>{const e=document.querySelector('[data-hr="\(ref)"]');if(!e)return '';
        return JSON.stringify({tag:e.tagName.toLowerCase(),type:(e.type||'').toLowerCase(),label:(e.getAttribute('aria-label')||e.innerText||e.value||e.title||'').trim().slice(0,100),
        autocomplete:e.getAttribute('autocomplete')||'',name:(e.name||'')+' '+(e.id||''),form:!!e.closest('form')})})()
        """
        guard let s = await eval(tab, js), let o = (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] else { return nil }
        return ElementInfo(tag: o["tag"] as? String ?? "", type: o["type"] as? String ?? "", label: o["label"] as? String ?? "",
                           autocomplete: o["autocomplete"] as? String ?? "", name: o["name"] as? String ?? "", form: o["form"] as? Bool ?? false)
    }

    private static func click(_ a: AssistAction, store: Store, ui: UIState) async -> String {
        guard let ref = a.int("ref") else { return "error: ref required" }
        let tab = currentTab(ui)
        guard let e = await describe(tab, ref: ref) else { return "error: element [\(ref)] not found, read the page again" }
        if AssistGuard.isForbidden(e.label) { return "refused: payments and CAPTCHAs are for the user to do in the browser" }
        if AssistGuard.isSensitiveField(type: e.type, autocomplete: e.autocomplete, name: e.name) { return "refused: sensitive field" }
        let irreversible = e.type == "submit" || AssistGuard.isIrreversible(e.label)
        if irreversible {
            let host = tab.url?.host ?? ""
            guard await store.assistAsk(L.t("assist.confirm.click"), L.t("assist.confirm.click.detail", e.label.isEmpty ? e.tag : e.label, host)) else {
                return "refused: the user declined this action"
            }
        }
        _ = await eval(tab, "(()=>{const e=document.querySelector('[data-hr=\"\(ref)\"]');if(!e)return '';e.scrollIntoView({block:'center'});if(e.focus)e.focus();e.click();return 'ok'})()")
        await waitLoaded(tab)
        return "ok: clicked [\(ref)] \"\(e.label)\"; now on \(tab.url?.absoluteString ?? "-")"
    }

    private static func type(_ a: AssistAction, ui: UIState) async -> String {
        guard let ref = a.int("ref") else { return "error: ref required" }
        let text = (a.args["text"] as? String) ?? ""
        let tab = currentTab(ui)
        guard let e = await describe(tab, ref: ref) else { return "error: element [\(ref)] not found, read the page again" }
        if AssistGuard.isSensitiveField(type: e.type, autocomplete: e.autocomplete, name: e.name) {
            return "refused: passwords, card numbers and codes are typed by the user only; ask them to fill this field"
        }
        let js = """
        (()=>{const e=document.querySelector('[data-hr="\(ref)"]');if(!e)return '';const T=\(literal(text));e.focus();
        if(e.tagName==='SELECT'){const o=[...e.options].find(o=>o.text.trim()===T||o.value===T);if(!o)return 'no option';e.value=o.value;e.dispatchEvent(new Event('change',{bubbles:true}));return 'ok'}
        if(e.isContentEditable||e.getAttribute('role')==='textbox'){document.execCommand('selectAll',false,null);document.execCommand('insertText',false,T);return 'ok'}
        const proto=e.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;
        Object.getOwnPropertyDescriptor(proto,'value').set.call(e,T);e.dispatchEvent(new Event('input',{bubbles:true}));e.dispatchEvent(new Event('change',{bubbles:true}));return 'ok'})()
        """
        let r = await eval(tab, js) ?? ""
        return r == "ok" ? "ok: typed \(text.count) characters in [\(ref)]" : "error: could not fill [\(ref)] (\(r.isEmpty ? "not found" : r))"
    }

    // MARK: Mail

    private static func sendMail(_ a: AssistAction, store: Store, ui: UIState) async -> String {
        guard let c = store.assistContact(a.str("contact") ?? a.str("name")) else { return "error: contact not found" }
        let draft = c.messages.first { $0.id.uuidString == a.str("message") } ?? c.messages.filter { $0.direction == .draft }.max { $0.date < $1.date }
        guard let d = draft, !d.to.trimmingCharacters(in: .whitespaces).isEmpty, !d.subject.isEmpty, !d.body.isEmpty else { return "error: no complete draft (to, subject, body); use mail_draft first" }
        guard await store.assistAsk(L.t("assist.confirm.mail"), L.t("assist.confirm.mail.detail", d.to, d.subject)) else { return "refused: the user declined to send" }
        if MailClient.current == .other {
            MailSender.openDraft(to: d.to, subject: d.subject, body: d.body)
            return "ok: message opened in the user's mail client; the user sends it themselves"
        }
        switch MailSender.send(to: d.to, subject: d.subject, body: d.body) {
        case .failure(.script(let m)): return "error: \(m)"
        case .success:
            store.recordSent(contact: c.id, draft: d.id, kind: d.kind, to: d.to, subject: d.subject, body: d.body)
            return "ok: sent to \(d.to)"
        }
    }
}
