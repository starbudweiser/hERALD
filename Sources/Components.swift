// hERALD — petits composants d'interface communs, au design Socle.
import AppKit
import SwiftUI

func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

struct Badge: View {
    enum Kind { case neutral, accent, success, warning, danger }
    let text: String
    var kind: Kind = .neutral

    var body: some View {
        Text(text).socle(Socle.T.caption).fontWeight(.semibold)
            .foregroundStyle(fg)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(bg, in: RoundedRectangle(cornerRadius: Socle.M.radius))
            .overlay(RoundedRectangle(cornerRadius: Socle.M.radius).stroke(border, lineWidth: 1))
            .fixedSize()
    }
    private var fg: Color {
        switch kind {
        case .neutral: Socle.C.textMuted
        case .accent: Socle.C.accentText
        case .success: Socle.C.success
        case .warning: Socle.C.warning
        case .danger: Socle.C.danger
        }
    }
    private var bg: Color {
        switch kind {
        case .neutral, .accent: Socle.C.control
        case .success: Socle.C.successBg
        case .warning: Socle.C.warningBg
        case .danger: Socle.C.dangerBg
        }
    }
    private var border: Color {
        switch kind {
        case .neutral: Socle.C.border
        case .accent: Socle.C.infoBorder
        case .success: Socle.C.successBorder
        case .warning: Socle.C.warningBorder
        case .danger: Socle.C.dangerBorder
        }
    }
}

struct StatusBadge: View {
    let status: PostStatus
    var body: some View {
        Badge(text: status.label, kind: kind)
    }
    private var kind: Badge.Kind {
        switch status {
        case .idea: .neutral
        case .draft: .warning
        case .approved: .accent
        case .published: .success
        }
    }
}

struct Callout: View {
    enum Kind { case info, warning, danger }
    let kind: Kind
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Socle.M.space2) {
            Image(systemName: kind == .info ? "hand.raised" : "exclamationmark.triangle")
            Text(branded: text).socle(Socle.T.body).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(fg)
        .padding(.horizontal, Socle.M.space3).padding(.vertical, Socle.M.space2)
        .background(bg, in: RoundedRectangle(cornerRadius: Socle.M.radius))
        .overlay(RoundedRectangle(cornerRadius: Socle.M.radius).stroke(border, lineWidth: 1))
    }
    private var fg: Color { kind == .info ? Socle.C.infoSoft : kind == .danger ? Socle.C.dangerSoft : Socle.C.warningSoft }
    private var bg: Color { kind == .info ? Socle.C.control : kind == .danger ? Socle.C.dangerBg : Socle.C.warningBg }
    private var border: Color { kind == .info ? Socle.C.infoBorder : kind == .danger ? Socle.C.dangerBorder : Socle.C.warningBorder }
}

struct EmptyState: View {
    let text: String
    var body: some View {
        Text(text).socle(Socle.T.bodyLg).foregroundStyle(Socle.C.textSubtle)
            .multilineTextAlignment(.center).padding(Socle.M.space6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Panneau de détail : le cadre reste immobile, seul le contenu s'estompe (150 ms) quand l'élément affiché change.
/// Rien si « Réduire les animations » est actif.
struct FadeOnChange<Key: Equatable>: ViewModifier {
    let key: Key
    @State private var opacity = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.opacity(opacity)
            .onChange(of: key) { _, _ in
                guard !reduceMotion else { return }
                opacity = 0
                withAnimation(.easeOut(duration: 0.15)) { opacity = 1 }
            }
    }
}

extension View {
    func fadeOnChange<Key: Equatable>(_ key: Key) -> some View { modifier(FadeOnChange(key: key)) }
}

/// Liste vide : message court et, quand une recherche ou un filtre est actif, bouton « Tout afficher ».
struct ListEmpty: View {
    let text: String
    var showAll: (() -> Void)?
    var body: some View {
        VStack(spacing: Socle.M.space2) {
            Text(text).socle(Socle.T.body).foregroundStyle(Socle.C.textSubtle).multilineTextAlignment(.center)
            if let showAll {
                Button(L.t("list.empty.show"), action: showAll)
                    .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
            }
        }
        .padding(Socle.M.space5).frame(maxWidth: .infinity)
    }
}

/// Liste à gauche, détail à droite : deux panneaux arrondis.
struct SplitLayout<List: View, Detail: View>: View {
    var width: CGFloat = 440
    @ViewBuilder var list: List
    @ViewBuilder var detail: Detail
    var body: some View {
        HStack(spacing: 12) {
            ScrollView { LazyVStack(spacing: 0) { list } }
                .frame(width: width)
                .soclePanel()
            detail.frame(maxWidth: .infinity, maxHeight: .infinity).soclePanel()
        }
    }
}

/// Ligne de liste de 46 px, sur une seule ligne : icône 26 px, titre (tronqué), méta à droite, badge d'état.
struct ItemRow<Trailing: View>: View {
    let selected: Bool
    var symbol: String
    var tint: Color = Socle.C.textMuted
    let title: String
    var meta: String = ""
    var metaColor: Color = Socle.C.textSubtle
    var highlight = false
    let action: () -> Void
    @ViewBuilder var trailing: Trailing
    @State private var hover = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// États neutres (règle Socle « États ») : survol = surface-hover, sélection = surface-selected, jamais de contour ni de fond d'accent.
    private var rowFill: Color { selected ? Socle.C.surfaceSelected : hover ? Socle.C.surfaceHover : .clear }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Socle.M.space2_5) {
                Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(highlight ? Socle.C.accentText : tint)
                    .frame(width: 26, height: 26).background(Socle.C.control, in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityHidden(true)
                Text(title).socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong).lineLimit(1).truncationMode(.tail)
                    .help(title).frame(maxWidth: .infinity, alignment: .leading)
                if !meta.isEmpty {
                    Text(meta).socle(Socle.T.meta).foregroundStyle(metaColor).lineLimit(1).fixedSize()
                }
                trailing.fixedSize()
            }
            .padding(.horizontal, Socle.M.space3)
            .frame(height: 46)
            .background(rowFill)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: rowFill)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        Divider().overlay(Socle.C.borderSubtle)
    }
}

extension ItemRow where Trailing == EmptyView {
    init(selected: Bool, symbol: String, tint: Color = Socle.C.textMuted, title: String, meta: String = "",
         metaColor: Color = Socle.C.textSubtle, highlight: Bool = false, action: @escaping () -> Void) {
        self.init(selected: selected, symbol: symbol, tint: tint, title: title, meta: meta, metaColor: metaColor, highlight: highlight, action: action) { EmptyView() }
    }
}

struct ListRow<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var content: Content
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let fill = selected ? Socle.C.surfaceSelected : hover ? Socle.C.surfaceHover : Color.clear
        Button(action: action) {
            VStack(alignment: .leading, spacing: Socle.M.space1) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Socle.M.space3).padding(.vertical, Socle.M.space2_5)
                .background(fill)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: fill)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        Divider().overlay(Socle.C.borderSubtle)
    }
}

/// En-tête de section : surtitre en capitales, actions à droite.
struct SectionBar<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: Socle.M.space2) {
            Text(title.uppercased()).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textSubtle)
            Spacer()
            trailing
        }
        .padding(.horizontal, Socle.M.space3)
        .frame(minHeight: Socle.M.sizeBar)
    }
}

/// Champ libellé + contrôle, empilés.
struct Field<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Socle.M.space1_5) {
            Text(label).socle(Socle.T.label).foregroundStyle(Socle.C.textMuted)
            content
        }
    }
}

struct CopyButton: View {
    let title: String
    var variant: SocleButtonStyle.Variant = .secondary
    let text: () -> String
    @State private var copied = false

    var body: some View {
        Button(copied ? L.t("action.copied") : title) {
            copyToPasteboard(text()); copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
        }
        .buttonStyle(SocleButtonStyle(variant, height: Socle.M.sizeControl)).fixedSize()
    }
}

/// Lien web : ouvert dans le navigateur intégré (⌥ enfoncé : navigateur du Mac).
@MainActor func openURL(_ s: String) { Browser.open(s) }

/// Fond d'état neutre pour une tuile ou une puce sélectionnable (règle Socle « États ») : repos `base`, survol
/// surface-hover, sélection surface-selected, jamais de contour ni de teinte d'accent. Fondu de 130 ms, coupé si
/// « Réduire les animations » est actif.
struct StateFill: ViewModifier {
    let selected: Bool
    var base: Color = .clear
    var radius: CGFloat = Socle.M.radius
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let fill = selected ? Socle.C.surfaceSelected : hover ? Socle.C.surfaceHover : base
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: fill)
            .onHover { hover = $0 }
    }
}

extension View {
    func stateFill(selected: Bool, base: Color = .clear, radius: CGFloat = Socle.M.radius) -> some View {
        modifier(StateFill(selected: selected, base: base, radius: radius))
    }
}
