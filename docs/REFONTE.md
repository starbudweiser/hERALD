# Refonte de hERALD (validée par Stéphan le 10/11/2026)

Objectif : appli complète et ergonomique, au style de la refonte de hdCLEANER. Aucun élément sur deux lignes, aucun
chevauchement, fenêtre plus grande. Socle partout, 4 langues (fr d'abord, en, es, it, mêmes clés), thème sombre,
« Réduire les animations » respecté, libellés VoiceOver sur toutes les icônes. Données existantes conservées.

## 1. Fenêtre (maquette v2 validée)

- Taille par défaut 1280 × 800, minimum 1180 × 720. Barre de titre système vide de contrôles.
- **Barre latérale en panneau** (largeur 228, coins 10, fond `surface`, marge 12 autour) comme hdCLEANER :
  - en haut : « hERALD » (h orange, 19 pt gras), puis sélecteur de campagne sur une ligne (pastille orange, nom
    tronqué, badge J-x, chevron ; menu : campagnes, nouvelle, modifier, supprimer) ;
  - groupes titrés (11 pt, `textSubtle`) :
    - **Campagne** : Aujourd'hui (compteur), Calendrier, Publications ;
    - **Démarchage** : Contacts (compteur des relances dues) ;
    - **Résultats** : Statistiques, Retours (non lus), Veille ;
    - **Outils** : Canaux, Agent IA (si activé), Navigateur ;
  - en bas : Réglages, À propos, puis séparateur, « 18 / 26 publiées » + %, barre de progression, pastille verte
    « Boîte de dépôt à jour » (ou orange avec le nombre de fichiers traités, cliquable vers les Réglages).
  - raccourcis ⌘1 à ⌘9 dans l'ordre des entrées ; la sélection = fond `#333` (control), texte blanc.
- **Contenu de chaque vue** : en-tête = titre 22 pt gras + une ligne d'explication (`textMuted`) à gauche ; à droite
  recherche (⌘F, filtre la vue courante) et un seul bouton principal propre à la vue (« Nouvelle publication »,
  « Nouveau contact »…). Puis le corps en panneaux arrondis (liste à gauche ~520, détail à droite).
- **Barre d'état** en bas du contenu (panneau, hauteur 36) : dernier / prochain relevé des statistiques, état de la
  surveillance, à droite la règle d'or en une ligne. La bannière bleue « Règle d'or » disparaît.
- L'en-tête actuel (Plan, Agent IA, Modifier la campagne, roue dentée) est supprimé : Plan (export/import/boîte de
  dépôt/exemple) va dans le menu du sélecteur de campagne et dans le menu Fichier ; l'agent devient une entrée de la
  barre latérale qui ouvre le volet de droite actuel (AgentPanel, inchangé).
- Toute ligne : `lineLimit(1)` + troncature ; largeur minimale calculée pour que rien ne se tronque en italien
  à 1280 px. Lignes de liste de 46 px, une seule ligne : icône 26 px, titre, méta à droite, badge d'état.

## 2. Vues

- **Aujourd'hui** (nouvelle, vue d'ouverture) : 4 chiffres (Vues +24 h, Interactions, Téléchargements, Prochaine
  étape = prochain jalon) ; liste « À faire » : publications du jour (approuvées/brouillon), publications publiées
  sans lien, retours non lus, relances de contacts dues, suivis en cours ; la ligne choisie s'ouvre à droite dans
  l'inspecteur correspondant (publication ou contact). « Prochains jours » : 3 jalons suivants.
- **Calendrier** : vue actuelle dans le nouveau cadre.
- **Publications** = fusion de Suivi + Brouillons : liste filtrable (statut, canal) + **inspecteur** à onglets
  Texte (FR/EN/ES/IT, compteur de caractères, Copier) / Chiffres / Retours / Notes ; pied : Copier, champ « Lien
  après publication », « Marquer publié » (principal).
- **Statistiques, Retours, Veille, Canaux** : vues actuelles dans le nouveau cadre (en-tête + panneaux), sans
  éléments sur deux lignes.
- **Navigateur** : voir § 4.

## 3. Démarchage (nouveau panneau « Contacts »)

Séparer les opérations de contact (youtubeurs, presse, sites, Discord…) des publications.

- Modèle (dans `Campaign`, champ **facultatif** pour relire les anciens plans) :
  `var outreach: [Contact]?` ;
  `Contact { id, name, kind: youtuber|press|site|discord|forum|other, url, email, lang: Lang, status, nextFollowUp:
  Date?, coverage: String (lien de l'article/vidéo obtenu), notes, messages: [OutreachMessage] }` ;
  `status: toContact, contacted, followedUp, replied, accepted, declined, covered` ;
  `OutreachMessage { id, date, kind: first|followUp|reply|note, direction: draft|sent|received, subject, body, to }`.
- Vue : en-tête « Contacts » + filtres segmentés (Tous, Youtubeurs, Presse, Autres) ; liste une ligne (icône de
  type, nom, statut, « relance le 18/11 » en orange si due) ; détail à droite : fiche (nom, type, e-mail, site
  cliquable → navigateur intégré, langue, statut, prochaine relance, lien obtenu), **fil des messages** (dates,
  envoyé/reçu), **éditeur de mail** (À, Objet, corps, modèles « Premier contact » / « Relance » remplis depuis la
  fiche et la campagne), boutons « Envoyer » (principal) et « Enregistrer le brouillon ».
- **Envoi** : par l'app Mail de l'utilisateur via AppleScript (`NSAppleScript` : nouveau message visible:false, to,
  subject, content, `send`). Aucun mot de passe manipulé. Confirmation avant envoi (« Envoyer à x@y ? »). Ajouter
  `NSAppleEventsUsageDescription` (4 langues dans InfoPlist si possible, sinon fr/en) au `Resources/Info.plist`.
  Après envoi : message ajouté au fil (sent), statut → contacted / followedUp, prochaine relance = +8 jours
  (modifiable). Échec (Mail absent, autorisation refusée) : message clair + bouton « Ouvrir dans Mail » (mailto).
- **Règle d'or** mise à jour dans les 4 langues : « hERALD ne publie jamais ; il n'envoie un e-mail que sur votre
  clic. » (README, splash, textes de l'agent : l'agent ne peut toujours ni publier ni envoyer).
- **Reprise des données existantes** (une fois, au chargement) : les publications du canal « YouTubeurs
  (démarchage) » et du canal « Discord MacProTips » deviennent des contacts (Andrew Tsai, MacProTips, Snazzy Labs,
  Nightech : e-mail lu dans le lien mailto ou les notes, texte du mail en message envoyé ou brouillon selon le
  statut, relance = date de la publication « Relance … »), puis ces publications sont retirées. Écrire un test.
- **Boîte de dépôt** : accepter `"contacts": [...]` dans `herald-changes` (fusion par nom, `overwrite` comme pour
  les publications) ; mettre à jour `docs/herald-changes.schema.json`.

## 4. Navigateur intégré

- Vue `BrowserView` (WKWebView via NSViewRepresentable) : barre d'outils sur une ligne (précédent, suivant,
  recharger, champ d'adresse, « Ouvrir dans le navigateur »), plusieurs onglets facultatifs.
- Toute URL ouverte dans l'appli (liens des publications, contacts, veille, retours, canaux) passe par le
  navigateur intégré ; ⌥-clic ou le bouton ouvre le navigateur système. Remplacer les appels à `openURL()`.
- Profil persistant (cookies) dans `WKWebsiteDataStore.default()`. Pas de saisie automatique de mots de passe.

## 5. Vérification et livraison

- `tests/run_tests.sh` : ajouter tests (ancien plan sans `outreach` relu, migration des contacts, fusion Inbox des
  contacts, échappement AppleScript du sujet/corps).
- Compiler `NO_OPEN=1 ./build_app.sh`, installer par `../_tools/build_all.sh hERALD` si présent dans la liste.
- Essais en arrière-plan (outils `app_*`, jamais de vol de focus) : capture de chaque vue en français et en italien,
  contrôler : rien sur deux lignes, rien de tronqué, rien qui se chevauche, alignements.
- Ne pas envoyer de vrai mail pendant les essais (essayer l'envoi vers l'adresse de Stéphan seulement s'il le
  demande).
- Mettre à jour `README.md` (section About inchangée, fonctionnalités), `docs/GUIDE_TOUR.md`, `docs/AI_AGENT.md`.
- Commits en français sur `main`, push. Pas de release sans accord de Stéphan.
