// hERALD — lecture du Markdown des réponses de l'agent : titres, listes, citations, blocs de code, tableaux, filets.
// Le texte courant (gras, italique, code, liens) est laissé à AttributedString. Logique pure, sans interface.
import Foundation

struct MDItem: Equatable {
    var level: Int          // 0 = premier niveau, 1 = sous-liste…
    var number: Int?        // numéro d'une liste ordonnée
    var text: String
}

enum MDBlock: Equatable {
    case heading(Int, String)
    case paragraph(String)
    case list([MDItem])
    case quote(String)
    case code(lang: String, text: String)
    case rule
    case table(header: [String], rows: [[String]])
}

enum Markdown {
    private static func match(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: s).map { String(s[$0]) } ?? "" }
    }

    private static func cells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isSeparatorRow(_ line: String) -> Bool {
        let c = cells(line)
        return !c.isEmpty && c.allSatisfy { match("^:?-{2,}:?$", $0) != nil }
    }

    private static func isBlockStart(_ line: String, next: String?) -> Bool {
        if line.hasPrefix("```") || match("^#{1,6}\\s", line) != nil || match("^\\s*>", line) != nil { return true }
        if match("^\\s*([-*+]|\\d+[.)])\\s+\\S", line) != nil { return true }
        if match("^\\s*([-*_])(\\s*\\1){2,}\\s*$", line) != nil { return true }
        if line.contains("|"), let next, isSeparatorRow(next) { return true }
        return false
    }

    static func parse(_ text: String) -> [MDBlock] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var out: [MDBlock] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { i += 1; continue }

            // bloc de code
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") { body.append(lines[i]); i += 1 }
                i += 1   // fermeture (absente : le bloc va jusqu'à la fin)
                out.append(.code(lang: lang, text: body.joined(separator: "\n")))
                continue
            }
            // titre
            if let m = match("^(#{1,6})\\s+(.*?)\\s*#*\\s*$", trimmed) {
                out.append(.heading(m[1].count, m[2])); i += 1; continue
            }
            // filet
            if match("^([-*_])(\\s*\\1){2,}$", trimmed) != nil { out.append(.rule); i += 1; continue }
            // tableau
            if line.contains("|"), i + 1 < lines.count, isSeparatorRow(lines[i + 1]) {
                let header = cells(line)
                var rows: [[String]] = []
                i += 2
                while i < lines.count, lines[i].contains("|"), !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    var r = cells(lines[i])
                    while r.count < header.count { r.append("") }
                    rows.append(Array(r.prefix(max(header.count, 1))))
                    i += 1
                }
                out.append(.table(header: header, rows: rows))
                continue
            }
            // citation
            if match("^\\s*>", line) != nil {
                var q: [String] = []
                while i < lines.count, let m = match("^\\s*>\\s?(.*)$", lines[i]) { q.append(m[1]); i += 1 }
                out.append(.quote(q.joined(separator: "\n")))
                continue
            }
            // liste (une suite d'éléments, avec sous-niveaux par l'indentation et suite de ligne indentée)
            if match("^\\s*([-*+]|\\d+[.)])\\s+\\S", line) != nil {
                var items: [MDItem] = []
                var firstOrdered: Bool?
                while i < lines.count {
                    let l = lines[i]
                    if let m = match("^(\\s*)([-*+]|\\d+[.)])\\s+(.*)$", l) {
                        let indent = m[1].replacingOccurrences(of: "\t", with: "    ").count
                        let num = Int(m[2].dropLast())
                        // un niveau 0 d'une autre nature (puces puis numéros) ouvre une nouvelle liste
                        if indent / 2 == 0 { if let f = firstOrdered, f != (num != nil) { break }; firstOrdered = num != nil }
                        items.append(MDItem(level: min(indent / 2, 3), number: num, text: m[3]))
                        i += 1
                    } else if !l.trimmingCharacters(in: .whitespaces).isEmpty, l.hasPrefix(" "), !items.isEmpty,
                              match("^\\s*([-*+]|\\d+[.)])\\s", l) == nil {
                        items[items.count - 1].text += "\n" + l.trimmingCharacters(in: .whitespaces); i += 1
                    } else if l.trimmingCharacters(in: .whitespaces).isEmpty, i + 1 < lines.count,
                              match("^\\s*([-*+]|\\d+[.)])\\s+\\S", lines[i + 1]) != nil {
                        i += 1   // ligne vide entre deux éléments : la liste continue
                    } else { break }
                }
                out.append(.list(items))
                continue
            }
            // paragraphe : lignes consécutives jusqu'au prochain bloc
            var para: [String] = [trimmed]
            i += 1
            while i < lines.count {
                let l = lines[i]
                if l.trimmingCharacters(in: .whitespaces).isEmpty || isBlockStart(l, next: i + 1 < lines.count ? lines[i + 1] : nil) { break }
                para.append(l.trimmingCharacters(in: .whitespaces)); i += 1
            }
            out.append(.paragraph(para.joined(separator: "\n")))
        }
        return out
    }
}
