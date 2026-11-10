// hERALD — navigateur intégré (WKWebView) : les liens de la campagne s'ouvrent ici ; ⌥-clic ou le bouton ouvre le navigateur du Mac.
// Profil persistant (cookies) ; aucune saisie automatique de mot de passe.
import SwiftUI
import WebKit

@MainActor
final class BrowserTab: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, WKUIDelegate {
    let id = UUID()
    let webView: WKWebView
    @Published var title = ""
    @Published var url: URL?
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var loading = false
    private var observers: [NSKeyValueObservation] = []
    weak var model: BrowserModel?

    override init() {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: cfg)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observers = [
            webView.observe(\.title) { [weak self] w, _ in MainActor.assumeIsolated { self?.title = w.title ?? "" } },
            webView.observe(\.url) { [weak self] w, _ in MainActor.assumeIsolated { self?.url = w.url } },
            webView.observe(\.canGoBack) { [weak self] w, _ in MainActor.assumeIsolated { self?.canGoBack = w.canGoBack } },
            webView.observe(\.canGoForward) { [weak self] w, _ in MainActor.assumeIsolated { self?.canGoForward = w.canGoForward } },
            webView.observe(\.isLoading) { [weak self] w, _ in MainActor.assumeIsolated { self?.loading = w.isLoading } },
        ]
    }

    func load(_ u: URL) { webView.load(URLRequest(url: u)) }

    @Published var failure: String?
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let msg = error.localizedDescription
        MainActor.assumeIsolated { failure = msg; print("browser fail:", msg) }
    }
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let msg = error.localizedDescription
        MainActor.assumeIsolated { failure = msg }
    }
    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        MainActor.assumeIsolated { failure = nil }
    }

    /// Liens target=_blank : nouvel onglet.
    nonisolated func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                             for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let u = navigationAction.request.url { MainActor.assumeIsolated { model?.open(u, newTab: true) } }
        return nil
    }
}

@MainActor
final class BrowserModel: ObservableObject {
    static let shared = BrowserModel()
    @Published var tabs: [BrowserTab] = []
    @Published var selected: UUID?
    /// Appelé quand un lien est ouvert : l'interface passe sur la vue Navigateur.
    var reveal: (() -> Void)?

    var current: BrowserTab? { tabs.first { $0.id == selected } ?? tabs.first }

    @discardableResult
    func newTab() -> BrowserTab {
        let t = BrowserTab(); t.model = self
        tabs.append(t); selected = t.id
        return t
    }

    func close(_ id: UUID) {
        tabs.removeAll { $0.id == id }
        if selected == id { selected = tabs.last?.id }
    }

    func open(_ u: URL, newTab fresh: Bool = false) {
        let t = (fresh || current == nil) ? newTab() : current!
        selected = t.id
        t.load(u)
        reveal?()
    }
}

enum Browser {
    /// Adresse saisie : lien complet, domaine sans schéma (https), sinon recherche.
    static func url(from text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if t.contains("://") || t.lowercased().hasPrefix("mailto:") { return URL(string: t) }
        if !t.contains(" "), t.contains(".") { return URL(string: "https://\(t)") }
        return URL(string: "https://duckduckgo.com/?q=" + (t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? t))
    }

    /// Ouvre un lien dans le navigateur intégré (⌥ enfoncé : navigateur du Mac). mailto: et autres schémas : le Mac.
    @MainActor static func open(_ s: String) {
        guard let u = url(from: s) else { return }
        openURL(u)
    }

    @MainActor static func openURL(_ u: URL) {
        let web = ["http", "https"].contains(u.scheme?.lowercased() ?? "")
        if !web || NSEvent.modifierFlags.contains(.option) { NSWorkspace.shared.open(u); return }
        BrowserModel.shared.open(u)
    }
}

struct WebViewHost: NSViewRepresentable {
    let tab: BrowserTab
    func makeNSView(context: Context) -> NSView { let v = NSView(); embed(v); return v }
    func updateNSView(_ v: NSView, context: Context) { if v.subviews.first !== tab.webView { embed(v) } }
    private func embed(_ v: NSView) {
        v.subviews.forEach { $0.removeFromSuperview() }
        tab.webView.frame = v.bounds
        tab.webView.autoresizingMask = [.width, .height]
        v.addSubview(tab.webView)
    }
}

struct BrowserView: View {
    @ObservedObject private var model = BrowserModel.shared
    @State private var address = ""

    var body: some View {
        VStack(spacing: 0) {
            if let tab = model.current {
                BrowserBar(tab: tab, model: model, address: $address)
            } else {
                HStack { Spacer(); newTabButton }.padding(Socle.M.space2)
            }
            Divider().overlay(Socle.C.border)
            ZStack {
                if let tab = model.current { BrowserPage(tab: tab).id(tab.id)
                } else { EmptyState(text: L.t("browser.empty")) }
            }
        }
        .onAppear { if model.tabs.isEmpty { model.newTab() } }
    }

    private var newTabButton: some View {
        Button { model.newTab() } label: { Image(systemName: "plus") }
            .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize().accessibilityLabel(L.t("browser.newtab"))
    }
}

struct BrowserPage: View {
    @ObservedObject var tab: BrowserTab
    var body: some View {
        ZStack {
            WebViewHost(tab: tab)
            if tab.url == nil || tab.failure != nil {
                EmptyState(text: tab.failure ?? L.t("browser.empty")).background(Socle.C.surface)
            }
        }
    }
}

struct BrowserBar: View {
    @ObservedObject var tab: BrowserTab
    @ObservedObject var model: BrowserModel
    @Binding var address: String

    var body: some View {
        VStack(spacing: Socle.M.space1_5) {
            HStack(spacing: Socle.M.space1_5) {
                icon("chevron.left", L.t("browser.back"), enabled: tab.canGoBack) { tab.webView.goBack() }
                icon("chevron.right", L.t("browser.forward"), enabled: tab.canGoForward) { tab.webView.goForward() }
                icon(tab.loading ? "xmark" : "arrow.clockwise", L.t("browser.reload"), enabled: tab.url != nil) {
                    if tab.loading { tab.webView.stopLoading() } else { tab.webView.reload() }
                }
                TextField(L.t("browser.address"), text: $address).socleField().onSubmit { go() }
                icon("safari", L.t("browser.external"), enabled: tab.url != nil) { if let u = tab.url { NSWorkspace.shared.open(u) } }
                icon("plus", L.t("browser.newtab"), enabled: true) { model.newTab() }
            }
            if model.tabs.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Socle.M.space1_5) {
                        ForEach(model.tabs) { t in TabChip(tab: t, selected: t.id == tab.id, model: model) }
                    }
                }
            }
        }
        .padding(Socle.M.space2)
        .onChange(of: tab.id) { _, _ in address = tab.url?.absoluteString ?? "" }
        .onChange(of: tab.url) { _, u in address = u?.absoluteString ?? "" }
        .onAppear { address = tab.url?.absoluteString ?? "" }
    }

    private func go() { if let u = Browser.url(from: address) { tab.load(u) } }

    private func icon(_ name: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name) }
            .buttonStyle(SocleButtonStyle(.tertiary, height: Socle.M.sizeControlLg)).fixedSize()
            .disabled(!enabled).accessibilityLabel(label).help(label)
    }
}

struct TabChip: View {
    @ObservedObject var tab: BrowserTab
    let selected: Bool
    let model: BrowserModel

    var body: some View {
        HStack(spacing: 6) {
            Text(tab.title.isEmpty ? (tab.url?.host ?? L.t("browser.newtab")) : tab.title)
                .socle(Socle.T.meta).lineLimit(1).frame(maxWidth: 160)
            Button { model.close(tab.id) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(.plain).accessibilityLabel(L.t("browser.closetab"))
        }
        .foregroundStyle(selected ? Socle.C.textStrong : Socle.C.textMuted)
        .padding(.horizontal, Socle.M.space2).frame(height: 26)
        .background(selected ? Socle.C.control : Socle.C.bgSunken, in: RoundedRectangle(cornerRadius: Socle.M.radius))
        .contentShape(Rectangle())
        .onTapGesture { model.selected = tab.id }
    }
}
