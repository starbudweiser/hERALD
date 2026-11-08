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

// Boîte de dépôt : fusion prudente, correspondances, tout ou rien, plan complet, rangement des fichiers
var box = Sample.make(now: Date())
let firstPost = box.campaigns[0].posts[0]
box.campaigns[0].posts[0].notes = "saisi à la main"
let changes = """
{"format": "herald-changes", "campaign": "\(box.campaigns[0].name)",
 "channels": [{"name": "r/macgaming", "kind": "reddit", "url": "https://reddit.com/r/macgaming"}, {"name": "reddit", "notes": "x"}],
 "watch": [{"url": "https://github.com/owner/tool", "name": "Tool"}, {"url": "https://github.com/OWNER/tool"}],
 "milestones": [{"title": "Bêta", "date": "2030-01-05", "kind": "teaser"}],
 "posts": [
  {"title": "Nouveau post", "date": "2030-01-06 18:30", "channel": "r/macgaming", "milestone": "Bêta", "status": "draft",
   "drafts": {"fr": "Bonjour", "en": "Hello"}, "feedback": [{"date": "2030-01-07", "kind": "comment", "value": 2, "text": "top"}]},
  {"id": "\(firstPost.id.uuidString)", "notes": "écrasé ?", "drafts": {"it": "Ciao"}, "link": "https://example.com"}
 ],
 "feedback": [{"post": "Nouveau post", "date": "2030-01-07", "kind": "comment", "value": 2, "text": "top"},
              {"post": "Nouveau post", "date": "2030-01-08", "kind": "downloads", "value": 40}]}
"""
let r1 = try! Inbox.merge(Data(changes.utf8), into: &box)
let np = box.campaigns[0].posts.first { $0.title == "Nouveau post" }
check(box.channels.contains { $0.name == "r/macgaming" } && box.channels.count == 8, "canal ajouté, nom existant reconnu")
check(box.watch.count == 1 && box.watch[0].ref == "owner/tool", "veille : doublon (casse) ignoré")
check(box.campaigns[0].milestones.contains { $0.title == "Bêta" }, "jalon ajouté")
check(np?.drafts["en"] == "Hello" && np?.status == .draft && np?.channelID == box.channels.last?.id, "publication ajoutée et rattachée")
check(np?.feedback.count == 2 && np?.total(.downloads) == 40, "retours ajoutés sans doublon")
check(Calendar.current.component(.hour, from: np!.date) == 18, "date avec heure")
let fp = box.campaigns[0].posts.first { $0.id == firstPost.id }!
check(fp.notes == "saisi à la main" && fp.link == "https://example.com" && fp.drafts["it"] == "Ciao", "champs vides complétés, saisie conservée")
check(r1.added == 4 && r1.updated == 2, "compte des ajouts (\(r1.added)) et mises à jour (\(r1.updated))")
let again = try! Inbox.merge(Data(changes.utf8), into: &box)
check(again.added == 0 && again.updated == 0, "refaire le même fichier ne change rien")
let forced = try! Inbox.merge(Data(#"{"overwrite": true, "posts": [{"id": "\#(firstPost.id.uuidString)", "notes": "remplacé"}]}"#.utf8), into: &box)
check(forced.updated == 1 && box.campaigns[0].posts.first { $0.id == firstPost.id }!.notes == "remplacé", "écrasement demandé")
let before = box.campaigns[0].posts.count
let bad = #"{"posts": [{"title": "A", "date": "2030-01-01"}, {"title": "B", "date": "2030-01-01", "channel": "inconnu"}]}"#
check((try? Inbox.merge(Data(bad.utf8), into: &box)) == nil && box.campaigns[0].posts.count == before, "tout ou rien sur erreur")
check((try? Inbox.merge(Data("pas du json".utf8), into: &box)) == nil, "JSON illisible refusé")

// Plan complet : fusion dans un autre plan sans doublon
var other = AppData(channels: Sample.channels())
let planJSON = try! Storage.encode(box)
let rp = try! Inbox.merge(planJSON, into: &other)
check(other.campaigns.count == 1 && other.campaigns[0].posts.count == box.campaigns[0].posts.count, "plan complet fusionné (\(rp.added) ajouts)")
check(other.campaigns[0].posts.allSatisfy { p in p.channelID == nil || other.channels.contains { $0.id == p.channelID } }, "canaux rattachés aux canaux locaux")
check(other.channels.count == box.channels.count && other.watch.count == 1, "canaux et veille sans doublon")
let rp2 = try! Inbox.merge(planJSON, into: &other)
check(rp2.added == 0 && rp2.updated == 0, "plan refusionné : aucun changement")

// Dossier : rangement dans processed/errors et journal
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("herald-inbox-\(UUID().uuidString)")
Inbox.prepare(tmp)
try! Data(#"{"watch": [{"url": "skyrim/42", "name": "Mod"}]}"#.utf8).write(to: tmp.appendingPathComponent("a.json"))
try! Data("{".utf8).write(to: tmp.appendingPathComponent("b.json"))
try! Data("ignoré".utf8).write(to: tmp.appendingPathComponent("note.txt"))
var dd = AppData()
let lines = Inbox.process(tmp, into: &dd)
let fm = FileManager.default
check(dd.watch.count == 1 && dd.watch[0].kind == .nexus, "fichier du dossier fusionné")
check(fm.fileExists(atPath: tmp.appendingPathComponent("processed/a.json").path)
      && fm.fileExists(atPath: tmp.appendingPathComponent("errors/b.json").path)
      && fm.fileExists(atPath: tmp.appendingPathComponent("note.txt").path), "fichiers rangés, autres ignorés")
check(lines.count == 3 && Inbox.readLog(tmp).count == 3, "journal écrit")
try? fm.removeItem(at: tmp)

// Statistiques : reconnaissance des liens
check(StatLink.youtubeID("https://www.youtube.com/watch?v=abc123&t=4") == "abc123", "YouTube watch")
check(StatLink.youtubeID("https://youtu.be/xyz789") == "xyz789", "YouTube court")
check(StatLink.youtubeID("youtube.com/shorts/SH0RT") == "SH0RT", "YouTube Shorts")
check(StatLink.redditID("https://www.reddit.com/r/skyrimmods/comments/1abcde/titre/") == "1abcde", "Reddit")
check(StatLink.bluesky("https://bsky.app/profile/moi.bsky.social/post/3kx")! == ("moi.bsky.social", "3kx"), "Bluesky")
check(StatLink.github("https://github.com/o/r/releases/tag/v1.0")! == ("o/r", "v1.0"), "GitHub release")
check(StatLink.github("https://github.com/o/r")!.1 == nil, "GitHub dépôt")
check(StatPlatform.detect(link: "https://www.instagram.com/reel/x", channel: nil, site: "") == .instagram, "Instagram détecté")
check(StatPlatform.detect(link: "https://monsite.com/fr/", channel: nil, site: "monsite.com") == .site, "page du site")
check(StatPlatform.detect(link: "", channel: .discord, site: "") == .discord && StatPlatform.detect(link: "https://autre.com", channel: .nexus, site: "") == .other, "plateforme du canal ou lien inconnu")
check(SiteInput.domain("https://www.MonSite.com/") == "monsite.com" && SiteInput.goatcounter("https://abc.goatcounter.com") == "abc", "réglages nettoyés")
check(StatsFetcher.int("1,234") == 1234 && StatsFetcher.int(NSNumber(value: 7)) == 7, "nombres lus")

// Statistiques : historique et cumul par période
var h: [StatSnapshot] = []
let t0 = Date().addingTimeInterval(-3 * 86400)
StatHistory.append(StatSnapshot(date: t0, views: 100), to: &h)
StatHistory.append(StatSnapshot(date: t0.addingTimeInterval(3600), views: 100), to: &h)
StatHistory.append(StatSnapshot(date: t0.addingTimeInterval(7200), views: 100), to: &h)
check(h.count == 2 && h[1].date == t0.addingTimeInterval(7200), "relevés identiques regroupés")
StatHistory.append(StatSnapshot(date: Date().addingTimeInterval(-60), views: 400, likes: 10, comments: 2), to: &h)
var camp = Campaign(); var sp = Post(); sp.title = "Vidéo"; sp.status = .published; sp.link = "https://youtu.be/a"; sp.stats = h
var nolink = Post(); nolink.title = "Sans lien"; nolink.status = .published
camp.posts = [sp, nolink]
let all = StatsSummary(campaign: camp, data: AppData(), platform: { _ in .youtube }, period: .campaign)
let day = StatsSummary(campaign: camp, data: AppData(), platform: { _ in .youtube }, period: .day)
check(all.views == 400 && all.interactions == 12, "totaux de la campagne")
check(day.views == 300 && day.rows[0].growth24h == 300, "évolution sur 24 h")
check(all.missingLinks.map(\.title) == ["Sans lien"], "publications sans lien repérées")
check(!all.curve.isEmpty && all.markdown(title: "Test").contains("| YouTube · Vidéo |"), "courbe et rapport")
let oldPlan = #"{"format":1,"campaigns":[{"id":"\#(UUID().uuidString)","name":"A","eventDate":"2026-11-11T11:00:00Z","notes":"","milestones":[],"posts":[{"id":"\#(UUID().uuidString)","title":"P","date":"2026-11-08T11:00:00Z","status":"idea","link":"","notes":"","drafts":{},"feedback":[]}]}],"channels":[],"watch":[]}"#
check((try? Storage.decode(Data(oldPlan.utf8)))?.campaigns[0].posts[0].stats == nil, "ancien plan relu sans statistiques")

// Agent IA : propositions, garde-fous, annulation, sous-sessions, relecture tolérante
var ac = Campaign(name: "Camp"); ac.notes = "Notes de départ"
var ap1 = Post(); ap1.title = "Annonce"; ap1.notes = "anciennes notes"; ap1.drafts["fr"] = "ancien brouillon"
var ap2 = Post(); ap2.title = "Rappel J-1"
ac.posts = [ap1, ap2]
let reply = """
Voici une proposition.
```herald-proposal
{"summary": "Brouillons", "changes": [
 {"post": "Annonce", "notes": "nouvelles notes", "status": "draft", "drafts": {"fr": "nouveau FR", "en": "new EN", "xx": "ignoré"}, "why": "plus clair"},
 {"post": "Rappel", "status": "published"},
 {"post": "Inconnue", "notes": "x"}],
 "campaign_notes_append": "Décision : ton sobre."}
```
Dites-moi si ça convient.
"""
let split = AgentParse.split(reply)
check(split.text.contains("Voici") && split.text.contains("convient") && !split.text.contains("herald-proposal"), "bloc retiré du texte")
check(split.proposal?.changes.count == 3 && split.proposal?.changes[0].drafts.count == 2, "langues inconnues écartées")
var worked = ac
let res = AgentParse.apply(split.proposal!, to: &worked, current: nil)
check(worked.posts[0].notes == "nouvelles notes" && worked.posts[0].status == .draft && worked.posts[0].drafts["en"] == "new EN", "proposition appliquée")
check(worked.posts[1].status != .published, "« Publié » jamais appliqué par l'agent")
check(worked.notes.hasSuffix("Décision : ton sobre.") && worked.notes.hasPrefix("Notes de départ"), "notes de campagne complétées, pas remplacées")
check(res.lines.contains { $0.contains("Inconnue") }, "publication introuvable signalée")
AgentParse.revert(res.undo, in: &worked)
check(worked.posts[0].notes == "anciennes notes" && worked.posts[0].drafts["fr"] == "ancien brouillon" && worked.posts[0].drafts["en"] == nil
      && worked.posts[0].status == .idea && worked.notes == "Notes de départ", "annulation complète")
check(AgentParse.find("Rappel", in: ac, current: nil) == 1 && AgentParse.find(nil, in: ac, current: ap2.id) == 1, "publication retrouvée (titre partiel, ou celle en cours)")
let sid = UUID().uuidString.lowercased()
let sub = AgentParse.sessions("Fait.\n```herald-session\n{\"id\": \"\(sid)\", \"name\": \"hERALD › Annonce\", \"task\": \"Annonce\"}\n```\n```herald-session\n{\"id\": \"pas-un-uuid\"}\n```")
check(sub.items.count == 1 && sub.items[0].id == sid && sub.clean == "Fait.", "sous-session annoncée, identifiant invalide refusé")
check(AgentParse.split("Rien à proposer.").proposal == nil, "réponse sans proposition")
// contexte : une tâche seule, sans rien de propre à une campagne précise
let cfgA = AgentConfig()
let sys = AgentContext.system(config: cfgA, campaign: ac)
check(sys.contains("never publish") && sys.contains("herald-proposal") && sys.contains("hERALD") && !sys.lowercased().contains("skyrim"), "consignes génériques")
let blk = AgentContext.postBlock(ap1, in: ac, config: cfgA, channel: { _ in "Canal" })
check(blk.contains(ap1.id.uuidString) && blk.contains("Annonce") && blk.contains("ancien brouillon"), "fiche de la tâche")
var cfgB = AgentConfig(); cfgB.shareDrafts = false
check(!AgentContext.postBlock(ap1, in: ac, config: cfgB, channel: { _ in "Canal" }).contains("ancien brouillon"), "brouillons non joints si désactivé")
check(AgentContext.hash("a") == AgentContext.hash("a") && AgentContext.hash("a") != AgentContext.hash("b"), "empreinte stable")
check(AgentConfig().enabled == false && AgentConfig.isEnabled(Data()) == false, "agent désactivé par défaut")
let partial = try! JSONDecoder().decode(AgentConfig.self, from: Data(#"{"enabled": true, "model": "m"}"#.utf8))
check(partial.enabled && partial.model == "m" && partial.sessionName == "hERALD" && partial.shareStats, "réglages partiels relus avec défauts")
check(AgentConfig().quick.count == 5, "actions rapides par défaut")
var cfgQ = AgentConfig(); cfgQ.quickPrompts = "Court | fais court\nligne sans barre"
check(cfgQ.quick.count == 1 && cfgQ.quick[0].title == "Court", "actions rapides personnalisées")
var threaded = ac; threaded.agent = AgentThread(messages: [AgentMessage(role: .user, text: "q")], subSessions: [AgentSubSession(id: sid, name: "n")], contextHash: "h")
threaded.brief = nil; threaded.agentBrief = "Ton sobre"
let rt = try! Storage.decode(try! Storage.encode(AppData(campaigns: [threaded])))
check(rt.campaigns[0].agent?.subSessions.first?.id == sid && rt.campaigns[0].agentBrief == "Ton sobre", "fils et consignes enregistrés")

// Agent IA : avant/après, application champ par champ, avancement en direct
let items = split.proposal!.items(in: ac, current: nil)
check(items.contains { $0.id == "0.notes" && $0.old == "anciennes notes" && $0.new == "nouvelles notes" }, "avant/après des notes")
check(items.contains { $0.id == "0.draft.fr" && $0.old == "ancien brouillon" } && items.contains { $0.id == "0.draft.en" && $0.old.isEmpty }, "avant/après des brouillons")
check(items.contains { $0.id == "campaign" } && !items.contains { $0.id.hasPrefix("1.") }, "ajout aux notes de campagne ; « Publié » absent de la liste")
var partialC = ac
let pr = AgentParse.apply(split.proposal!, to: &partialC, current: nil, only: ["0.draft.en"])
check(partialC.posts[0].drafts["en"] == "new EN" && partialC.posts[0].notes == "anciennes notes" && partialC.posts[0].drafts["fr"] == "ancien brouillon"
      && partialC.notes == "Notes de départ" && pr.undo.count == 1, "seuls les champs cochés sont appliqués")
AgentParse.revert(pr.undo, in: &partialC)
check(partialC.posts[0].drafts["en"] == nil, "annulation d'une application partielle")
let toolLine = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/a/b/plan.md"}}]}}"#
check(AgentRunner.status(fromStreamLine: toolLine)?.contains("plan.md") == true, "avancement : fichier lu")
check(AgentRunner.status(fromStreamLine: #"{"type":"assistant","message":{"content":[{"type":"text","text":"Bonjour"}]}}"#) != nil, "avancement : rédaction")
check(AgentRunner.status(fromStreamLine: #"{"type":"result","result":"ok"}"#) == nil && AgentRunner.status(fromStreamLine: "pas du json") == nil, "lignes sans avancement ignorées")

// Markdown des réponses
let md = Markdown.parse("""
# Titre
Un paragraphe avec **gras** et `code`,
sur deux lignes.

- premier
  suite du premier
- deuxième
  - sous-élément
1. un
2. deux

> citation
> sur deux lignes

```swift
let x = 1
```

| Canal | Vues |
|---|---:|
| YouTube | 120 |
| Reddit | 45 |

---
Fin
""")
check(md.first == .heading(1, "Titre"), "titre")
check(md.contains(.paragraph("Un paragraphe avec **gras** et `code`,\nsur deux lignes.")), "paragraphe sur deux lignes")
check(md.contains { if case .list(let it) = $0 { return it.count == 3 && it[0].text == "premier\nsuite du premier" && it[2].level == 1 } else { return false } }, "liste à puces, suite de ligne et sous-niveau")
check(md.contains { if case .list(let it) = $0 { return it.count == 2 && it[0].number == 1 && it[1].number == 2 } else { return false } }, "liste numérotée")
check(md.contains(.quote("citation\nsur deux lignes")), "citation")
check(md.contains(.code(lang: "swift", text: "let x = 1")), "bloc de code")
check(md.contains(.table(header: ["Canal", "Vues"], rows: [["YouTube", "120"], ["Reddit", "45"]])), "tableau")
check(md.contains(.rule) && md.last == .paragraph("Fin"), "filet puis paragraphe")
check(Markdown.parse("```\nsans fin") == [.code(lang: "", text: "sans fin")], "bloc de code jamais refermé")
check(Markdown.parse("") .isEmpty && Markdown.parse("\n\n").isEmpty, "texte vide")
// usage et coût
let claudeObj = try! JSONSerialization.jsonObject(with: Data(#"{"total_cost_usd": 0.028, "usage": {"input_tokens": 2, "cache_creation_input_tokens": 7028, "cache_read_input_tokens": 100, "output_tokens": 5}}"#.utf8)) as! [String: Any]
let cu = AgentRunner.usage(from: claudeObj)!
check(cu.input == 7130 && cu.output == 5 && cu.cost == 0.028, "usage Claude Code (cache compris)")
let oaObj = try! JSONSerialization.jsonObject(with: Data(#"{"usage": {"prompt_tokens": 1200, "completion_tokens": 300, "total_tokens": 1500}}"#.utf8)) as! [String: Any]
let ou = AgentRunner.usage(from: oaObj)!
check(ou.input == 1200 && ou.output == 300 && ou.cost == nil, "usage API OpenAI")
check(AgentRunner.usage(from: ["result": "x"]) == nil, "réponse sans usage")
var priced = AgentConfig(); priced.priceIn = 2.5; priced.priceOut = 10
check(abs((ou.dollars(priced) ?? 0) - 0.006) < 1e-9, "coût calculé avec les tarifs")
check(ou.dollars(AgentConfig()) == nil && cu.dollars(AgentConfig()) == 0.028, "sans tarifs : pas de coût inventé ; coût de l'agent repris tel quel")
var uc = Campaign(name: "U"); var up = Post(); up.agent = AgentThread(messages: [AgentMessage(role: .assistant, text: "a", usage: ou)])
uc.posts = [up]; uc.agent = AgentThread(messages: [AgentMessage(role: .assistant, text: "b", usage: AgentUsage(input: 10, output: 5, cost: nil))])
check(uc.agentUsage.tokens == 1515 && uc.agent!.usage.tokens == 15, "cumul de la campagne et de la discussion")
let ur = try! Storage.decode(try! Storage.encode(AppData(campaigns: [uc])))
check(ur.campaigns[0].agentUsage.tokens == 1515, "usage enregistré et relu")

check(ou.label(priced).contains("$") && ou.label(priced).contains("≈") && !ou.label(AgentConfig()).contains("$"), "affichage du coût seulement s'il est connu")
check(AgentUsage.money(0.0042).contains("0,0042") || AgentUsage.money(0.0042).contains("0.0042") || AgentUsage.money(0.0042).contains("0,0038") || AgentUsage.money(0.0042).contains("0.0038"), "petit coût affiché avec 4 décimales (dollars ou devise convertie)")

// Devise du système : conversion depuis le dollar
let frLoc = Locale(identifier: "fr_FR"), usLoc = Locale(identifier: "en_US")
let eur = AgentCurrency.format(dollars: 0.0100, code: "EUR", rate: 0.9, locale: frLoc)
check(eur.contains("€") && (eur.contains("0,0090")), "euro au taux donné, 4 décimales pour un petit montant : \(eur)")
let eurBig = AgentCurrency.format(dollars: 12.5, code: "EUR", rate: 0.9, locale: frLoc)
check(eurBig.contains("11,25") && eurBig.contains("€"), "montant courant avec 2 décimales : \(eurBig)")
let usd = AgentCurrency.format(dollars: 12.5, code: "EUR", rate: nil, locale: frLoc)
check(usd.contains("$") && usd.contains("12,50"), "taux inconnu : dollars, jamais un montant converti inventé : \(usd)")
check(AgentCurrency.format(dollars: 1, code: "USD", rate: 1, locale: usLoc).contains("$1.00"), "dollars pour une région en dollars")
var fixed = AgentConfig(); fixed.fxRate = 0.5
check(AgentCurrency.code != "USD" ? AgentCurrency.rate(fixed) == 0.5 : AgentCurrency.rate(fixed) == 1, "taux fixé à la main prioritaire")
check(AgentConfig().fxRate == 0 && (try! JSONDecoder().decode(AgentConfig.self, from: Data(#"{"fxRate": 0.8}"#.utf8))).fxRate == 0.8, "taux manuel enregistré et relu")

var cfgS = AgentConfig(); cfgS.sessionID = "86f09b56-284f-4d83-a4e6-382a37ca4568"
check(AgentContext.system(config: cfgS, campaign: ac).contains("claude --resume 86f09b56-284f-4d83-a4e6-382a37ca4568"), "l'agent connaît l'identifiant de sa session")
check(!AgentContext.system(config: AgentConfig(), campaign: ac).contains("This session's id"), "pas d'identifiant tant que la session n'existe pas")

print(failures == 0 ? "OK : tous les tests passent" : "\(failures) échec(s)")
exit(failures == 0 ? 0 : 1)
