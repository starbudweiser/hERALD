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
- **Feedback**: record comments, downloads, endorsements, stars or views per post, or import a CSV `date;type;value;text` (`2026-11-11;comment;3;Nice`).
- Local data in `~/Library/Application Support/hERALD/plan.json`; export/import of the whole plan (keys never included).
- Optional example campaign (a fictional mod launch with milestones, channels and placeholder drafts), offered at first launch and deletable; *Plan → Add the example campaign* brings it back.
- Plans are saved and shared as `.herald` files (JSON).
- Zoom the whole interface with ⌥+ / ⌥− (⌥0 for actual size), from 70 % to 200 %.
- Interface in English, French, Spanish and Italian (follows your Mac's language, English otherwise). macOS 14+.

Build: `./build_app.sh` · tests: `tests/run_tests.sh`

---
## 🇫🇷 Français

**Règle d'or :** hERALD prépare et suit. Il ne publie jamais et n'envoie aucun message : vous copiez le texte et publiez vous-même.

- **Plan** : campagnes avec date d'événement et compte à rebours, jalons datés (teaser, annonce du Jour J, suivi), publications par canal avec statut *idée → brouillon → validé → publié* et lien. Calendrier du mois et tableau de suivi.
- **Brouillons** par publication en français, anglais, espagnol et italien, copiés en un clic.
- **Veille** : versions GitHub et pages de mods Nexus (lecture seule, API publiques ; la clé API Nexus facultative reste dans le trousseau macOS). Vérification automatique une fois par semaine au lancement ; rapport hebdomadaire lisible dans l'appli et copiable en Markdown.
- **Retours** : commentaires, téléchargements, endorsements, étoiles ou vues par publication, saisis à la main ou importés d'un CSV `date;type;valeur;texte`.
- Données locales dans `~/Library/Application Support/hERALD/plan.json` ; export/import du plan complet (sans aucune clé).
- Campagne d'exemple facultative (lancement fictif d'un mod : jalons, canaux, brouillons à compléter), proposée au premier lancement et supprimable ; *Plan → Ajouter la campagne d'exemple* la recrée.
- Les plans s'enregistrent et s'échangent en fichiers `.herald` (JSON).
- Zoom de toute l'interface avec ⌥+ / ⌥− (⌥0 pour la taille normale), de 70 % à 200 %.
- Interface en français, anglais, espagnol et italien (langue du Mac, anglais sinon). macOS 14+.

Compilation : `./build_app.sh` · tests : `tests/run_tests.sh`

MIT License.
