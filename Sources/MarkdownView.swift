// hERALD — affichage des blocs Markdown (voir Markdown.swift).
import AppKit
import SwiftUI

struct MarkdownView: View {
    let text: String

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }

    var body: some View {
        let blocks = Markdown.parse(text)
        VStack(alignment: .leading, spacing: Socle.M.space2) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in block(b) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder private func block(_ b: MDBlock) -> some View {
        switch b {
        case .heading(let level, let t):
            Text(inline(t)).socle(level <= 1 ? Socle.T.heading : Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong)
                .padding(.top, level <= 2 ? Socle.M.space1 : 0).fixedSize(horizontal: false, vertical: true)
        case .paragraph(let t):
            Text(inline(t)).socle(Socle.T.body).foregroundStyle(Socle.C.text).fixedSize(horizontal: false, vertical: true)
        case .list(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(it.number.map { "\($0)." } ?? (it.level == 0 ? "•" : "◦")).socle(Socle.T.body).foregroundStyle(Socle.C.textSubtle)
                            .frame(minWidth: 14, alignment: .trailing)
                        Text(inline(it.text)).socle(Socle.T.body).foregroundStyle(Socle.C.text).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(it.level) * 16)
                }
            }
        case .quote(let t):
            HStack(alignment: .top, spacing: Socle.M.space2) {
                Rectangle().fill(Socle.C.borderStrong).frame(width: 3)
                Text(inline(t)).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted).fixedSize(horizontal: false, vertical: true)
            }
        case .code(let lang, let t):
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(lang.isEmpty ? "" : lang).socle(Socle.T.caption).foregroundStyle(Socle.C.textSubtle)
                    Spacer()
                    CopyButton(title: L.t("action.copy"), variant: .tertiary) { t }
                }
                Text(t).socle(Socle.T.monoSm).foregroundStyle(Socle.C.text)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Socle.M.space2)
            .background(Socle.C.bgSunken, in: RoundedRectangle(cornerRadius: Socle.M.radius))
        case .rule:
            Divider().overlay(Socle.C.border).padding(.vertical, 2)
        case .table(let header, let rows):
            VStack(spacing: 0) {
                tableRow(header, bold: true)
                Divider().overlay(Socle.C.border)
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                    tableRow(r, bold: false).background(i % 2 == 1 ? Socle.C.textStrong.opacity(0.04) : .clear)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: Socle.M.radius).stroke(Socle.C.border, lineWidth: 1))
        }
    }

    private func tableRow(_ cells: [String], bold: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, c in
                Text(inline(c)).socle(bold ? Socle.T.labelStrong : Socle.T.meta).foregroundStyle(bold ? Socle.C.textStrong : Socle.C.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Socle.M.space1_5).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
