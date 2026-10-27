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

/// Liste à gauche, détail à droite, séparés par un filet.
struct SplitLayout<List: View, Detail: View>: View {
    var width: CGFloat = 380
    @ViewBuilder var list: List
    @ViewBuilder var detail: Detail
    var body: some View {
        HStack(spacing: 0) {
            ScrollView { LazyVStack(spacing: 0) { list } }
                .frame(width: width)
                .background(Socle.C.surface)
            Divider().overlay(Socle.C.border)
            detail.frame(maxWidth: .infinity, maxHeight: .infinity).background(Socle.C.bg)
        }
    }
}

struct ListRow<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var content: Content
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Socle.M.space1) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Socle.M.space3).padding(.vertical, Socle.M.space2_5)
                .background(selected ? Socle.C.surfaceSelected : hover ? Socle.C.surfaceHover : .clear)
                .overlay(alignment: .leading) { Rectangle().fill(selected ? Socle.C.accent : .clear).frame(width: 2) }
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

/// Lien web ouvert dans le navigateur (lecture ou envoi manuel par l'utilisateur).
func openURL(_ s: String) {
    let t = s.trimmingCharacters(in: .whitespaces)
    guard let u = URL(string: t.contains("://") ? t : "https://\(t)"), !t.isEmpty else { return }
    NSWorkspace.shared.open(u)
}
