# hERALD

**Communication campaign management for modders — hERALD never publishes anything itself.**  
*Gestion de campagne de communication pour moddeurs — hERALD ne publie jamais rien lui-même.*

🇬🇧 [English](#-english) · 🇫🇷 [Français](#-français)

---
## 🇬🇧 English

**Golden rule:** hERALD prepares and tracks. It never posts, never sends a message: you copy the text and publish it yourself.

- **Plan**: campaigns with an event date and countdown, dated milestones (teaser, D-day announcement, follow-up), posts per channel (Nexus, Reddit, Discord, YouTube, GitHub, X/Bluesky, Instagram, forums) with status *idea → draft → approved → published* and link. Month calendar and tracking table.
- **Drafts** per post in French, English, Spanish and Italian, copied in one click.
- **Monitoring**: watch GitHub releases and Nexus mod pages (read only, public APIs; the optional Nexus API key stays in the macOS keychain). Checked automatically once a week at launch; weekly report readable in the app and copyable as Markdown.
- **Statistics**: one panel for everything published in the campaign. Views, likes, comments, shares and downloads read from each post's link (YouTube with a free API key, Reddit, Bluesky, GitHub, Nexus) and site visits (GoatCounter, free, no cookies); Instagram, Facebook, Discord or X are entered by hand. Hourly readings during a campaign, daily otherwise, in the background. Key figures, cumulative curve per platform with milestones, 24 h / 7 days / whole campaign, best performer, posts published without a link, Markdown report.
- **App icon**: Dock, menu bar (colour icon at the top of the screen) or both, in Settings. With the menu bar, closing the window keeps hERALD running (readings continue) and a click on the icon reopens it.
- **Feedback**: record comments, downloads, endorsements, stars or views per post, or import a CSV `date;type;value;text` (`2026-11-11;comment;3;Nice`).
- Local data in `~/Library/Application Support/hERALD/plan.json`; export/import of the whole plan (keys never included).
- Optional example campaign (a fictional mod launch with milestones, channels and placeholder drafts), offered at first launch and deletable; *Plan → Add the example campaign* brings it back.
- Plans are saved and shared as `.herald` files (JSON).
- **Drop box**: JSON files dropped in a watched folder are merged automatically (see below).
- Zoom the whole interface with ⌥+ / ⌥− (⌥0 for actual size), from 70 % to 200 %.
- Interface in English, French, Spanish and Italian (follows your Mac's language, English otherwise). macOS 14+.

### Drop box (automation)

hERALD watches `~/Library/Application Support/hERALD/Inbox`. Every `.json` file dropped there (a change file, or a whole `.herald` plan) is merged into the plan at once, then moved to `processed/` or `errors/`; each change is logged in `journal.log` (also visible in Settings). Merge is careful: an existing item (same `id`, else same title and same day, or same name) only gets its empty fields filled — use `"overwrite": true` to replace. All or nothing: one error and nothing is applied. hERALD still never publishes anything.

`tools/herald_add` (python3, no dependency) writes these files for you, so a script or an AI assistant can feed hERALD:

```bash
tools/herald_add post --title "Launch" --date 2026-11-11 --channel reddit --status draft --draft en="Hello…" --draft-file fr=launch_fr.md
tools/herald_add milestone --title "D-day" --date 2026-11-11 --kind announce
tools/herald_add watch https://github.com/owner/repo --name "My tool"
tools/herald_add feedback --post "Launch" --date 2026-11-12 --kind downloads --value 120
tools/herald_add json changes.json     # or a .herald plan; "-" reads stdin
tools/herald_add schema                # JSON Schema of the format
```

Change file format ([full JSON Schema](docs/herald-changes.schema.json)):

```json
{
  "format": "herald-changes",
  "campaign": "My campaign",
  "channels":   [{"name": "r/macgaming", "kind": "reddit", "url": "https://www.reddit.com/r/macgaming"}],
  "watch":      [{"url": "https://github.com/owner/repo", "name": "My tool"}],
  "milestones": [{"title": "Teaser", "date": "2026-11-04", "kind": "teaser"}],
  "posts": [{
    "title": "Launch post", "date": "2026-11-11 18:00", "channel": "r/macgaming", "milestone": "Teaser",
    "status": "draft", "link": "", "notes": "",
    "drafts": {"fr": "…", "en": "…", "es": "…", "it": "…"},
    "feedback": [{"date": "2026-11-12", "kind": "comment", "value": 3, "text": "Nice"}]
  }],
  "feedback": [{"post": "Launch post", "date": "2026-11-13", "kind": "downloads", "value": 250}]
}
```

`campaign` (id or name, created if missing; default: the campaign on screen), `channel` (id, name or kind), `milestone` (id or title). Dates: `YYYY-MM-DD` (noon), `YYYY-MM-DD HH:MM` (local time) or ISO 8601. Status: `idea`, `draft`, `approved`, `published`. Feedback kinds: `comment`, `downloads`, `endorsements`, `stars`, `views`, `other`.

Build: `./build_app.sh` · tests: `tests/run_tests.sh`

---
## 🇫🇷 Français

**Règle d'or :** hERALD prépare et suit. Il ne publie jamais et n'envoie aucun message : vous copiez le texte et publiez vous-même.

- **Plan** : campagnes avec date d'événement et compte à rebours, jalons datés (teaser, annonce du Jour J, suivi), publications par canal avec statut *idée → brouillon → validé → publié* et lien. Calendrier du mois et tableau de suivi.
- **Brouillons** par publication en français, anglais, espagnol et italien, copiés en un clic.
- **Veille** : versions GitHub et pages de mods Nexus (lecture seule, API publiques ; la clé API Nexus facultative reste dans le trousseau macOS). Vérification automatique une fois par semaine au lancement ; rapport hebdomadaire lisible dans l'appli et copiable en Markdown.
- **Statistiques** : un seul panneau pour tout ce qui a été diffusé dans la campagne. Vues, j'aime, commentaires, partages et téléchargements lus depuis le lien de chaque publication (YouTube avec une clé API gratuite, Reddit, Bluesky, GitHub, Nexus) et visites du site (GoatCounter, gratuit, sans cookies) ; Instagram, Facebook, Discord ou X se saisissent à la main. Un relevé par heure pendant une campagne, un par jour sinon, en arrière-plan. Chiffres clés, courbe cumulée par plateforme avec les jalons, 24 h / 7 jours / toute la campagne, publication la plus en forme, publications sans lien, rapport Markdown.
- **Icône de l'appli** : Dock, barre de menus (silhouette en couleur en haut de l'écran) ou les deux, dans les Réglages. Avec la barre de menus, fermer la fenêtre laisse hERALD tourner (les relevés continuent) et un clic sur l'icône la rouvre.
- **Retours** : commentaires, téléchargements, endorsements, étoiles ou vues par publication, saisis à la main ou importés d'un CSV `date;type;valeur;texte`.
- Données locales dans `~/Library/Application Support/hERALD/plan.json` ; export/import du plan complet (sans aucune clé).
- Campagne d'exemple facultative (lancement fictif d'un mod : jalons, canaux, brouillons à compléter), proposée au premier lancement et supprimable ; *Plan → Ajouter la campagne d'exemple* la recrée.
- Les plans s'enregistrent et s'échangent en fichiers `.herald` (JSON).
- **Boîte de dépôt** : des fichiers JSON déposés dans un dossier surveillé sont fusionnés automatiquement (voir plus bas).
- Zoom de toute l'interface avec ⌥+ / ⌥− (⌥0 pour la taille normale), de 70 % à 200 %.
- Interface en français, anglais, espagnol et italien (langue du Mac, anglais sinon). macOS 14+.

### Boîte de dépôt (automatisation)

hERALD surveille `~/Library/Application Support/hERALD/Inbox`. Chaque fichier `.json` déposé (fichier de changements, ou plan `.herald` complet) est fusionné aussitôt dans le plan, puis rangé dans `processed/` ou `errors/` ; chaque changement est noté dans `journal.log` (visible aussi dans les Réglages). Fusion prudente : un élément existant (même `id`, sinon même titre et même jour, ou même nom) voit seulement ses champs vides complétés — `"overwrite": true` pour remplacer. Tout ou rien : une erreur et rien n'est appliqué. hERALD ne publie toujours rien.

`tools/herald_add` (python3, sans dépendance) écrit ces fichiers pour vous, pour qu'un script ou un assistant IA alimente hERALD : voir les exemples et le format ci-dessus ([schéma JSON](docs/herald-changes.schema.json)).

Compilation : `./build_app.sh` · tests : `tests/run_tests.sh`

MIT License.
