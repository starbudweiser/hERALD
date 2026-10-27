// Tests de la logique de hERALD (sans interface) : lancer tests/run_tests.sh.
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) { if !ok { failures += 1; print("ÉCHEC : \(what)") } }

// Analyse des adresses de veille
check(WatchItem.parse("https://github.com/Nexus-Mods/Vortex")! == (.github, "Nexus-Mods/Vortex"), "URL GitHub")
check(WatchItem.parse("https://www.nexusmods.com/skyrimspecialedition/mods/12604?tab=files")! == (.nexus, "skyrimspecialedition/12604"), "URL Nexus")
check(WatchItem.parse("owner/repo")! == (.github, "owner/repo"), "raccourci GitHub")
check(WatchItem.parse("skyrim/42")! == (.nexus, "skyrim/42"), "raccourci Nexus")
check(WatchItem.parse("n'importe quoi") == nil, "adresse invalide")

// Import CSV des retours
let csv = "date;type;valeur;texte\n2026-11-11;comment;3;Super\n2026-11-12,downloads,120,\n2026-11-13;inconnu;x;?\n"
let fb = FeedbackCSV.parse(csv)
check(fb.count == 3, "3 lignes CSV lues (en-tête ignoré)")
check(fb[0].kind == .comment && fb[0].value == 3 && fb[0].text == "Super", "ligne point-virgule")
check(fb[1].kind == .downloads && fb[1].value == 120, "ligne virgule")
check(fb[2].kind == .other && fb[2].value == 1, "type inconnu → autre")

// Totaux par publication
var p = Post(); p.feedback = fb + [Feedback(date: Date().addingTimeInterval(400 * 86400), kind: .downloads, value: 300)]
check(p.total(.comment) == 3, "somme des commentaires")
check(p.total(.downloads) == 300, "dernier relevé de téléchargements")

// Exemple générique : cohérent, 4 langues, aucune trace personnelle, aller-retour JSON
let sample = Sample.make()
let c = sample.campaigns[0]
check(c.posts.count == 12 && c.milestones.count == 6 && sample.channels.count == 7, "taille de l'exemple")
check(c.posts.allSatisfy { p in sample.channels.contains { $0.id == p.channelID } && c.milestones.contains { $0.id == p.milestoneID } }, "liens canal/jalon")
check(c.posts.filter { !$0.drafts.isEmpty }.allSatisfy { p in Lang.allCases.allSatisfy { !p.draft($0).isEmpty } }, "brouillons en 4 langues")
check(sample.watch.isEmpty, "aucun produit surveillé imposé")
let json = String(decoding: try! Storage.encode(sample), as: UTF8.self).lowercased()
check(!["skyrim", "starbud", "stephan", "mortex"].contains { json.contains($0) }, "exemple sans donnée personnelle")
var chans = [Channel(name: "Mon Discord", kind: .discord)]
_ = Sample.campaign(using: &chans)
check(chans.filter { $0.kind == .discord }.count == 1 && chans.count == 7, "l'exemple réutilise les canaux existants")
let back = try! Storage.decode(try! Storage.encode(sample))
check(back.campaigns[0].posts.count == 12, "aller-retour JSON")

// Rapport hebdomadaire
var data = sample
data.watch = [WatchItem(name: "Outil", kind: .github, ref: "a/b")]
data.watch[0].history = [WatchSnapshot(date: Date().addingTimeInterval(-20 * 86400), version: "1.0"),
                         WatchSnapshot(date: Date().addingTimeInterval(-86400), version: "1.1")]
data.campaigns[0].posts[0].status = .published
data.campaigns[0].posts[0].date = Date().addingTimeInterval(-86400)
let r = WeekReport(data: data, campaign: data.campaigns[0])
check(r.releases.count == 1 && r.releases[0].version == "1.1", "nouvelle version repérée")
check(r.published.count == 1, "publication de la semaine")
check(r.markdown(channel: { id in data.channels.first { $0.id == id } }).contains("1.1"), "rapport Markdown")

print(failures == 0 ? "OK : tous les tests passent" : "\(failures) échec(s)")
exit(failures == 0 ? 0 : 1)
