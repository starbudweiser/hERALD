# Agent IA dans hERALD (facultatif)

hERALD peut discuter avec un agent IA de votre campagne et de chaque tâche de votre plan. **C'est facultatif et désactivé par défaut.** Sans lui, hERALD s'affiche et fonctionne exactement comme avant.

Activez-le dans **Réglages → Agent IA (facultatif)**, puis **Configurer l'agent…**.

## Ce que vous obtenez

| | |
|---|---|
| **Un volet à droite, toujours à portée** | Bouton « Agent IA » dans l'en-tête, ou « Discuter avec l'agent » dans une tâche. Le volet reste ouvert pendant que vous travaillez sur le plan ; basculez entre la campagne et la tâche sélectionnée. Redimensionnable à la souris, la fenêtre s'élargit si besoin. |
| **Un suivi en direct** | « Lit : fichier… », « Cherche… », durée écoulée, bouton **Arrêter** ; la discussion défile seule jusqu'à la dernière réponse ; Entrée envoie, ⇧Entrée fait un retour à la ligne. |
| **L'agent connaît la tâche** | Chaque demande porte la fiche de la tâche : identifiant, titre, date, canal, statut, lien, notes, brouillons en quatre langues, dernières statistiques. Le plan et les notes de campagne s'ajoutent quand ils ont changé. |
| **Des propositions appliquées d'un clic** | L'agent peut proposer des modifications des notes, des brouillons (fr, en, es, it), du statut, et un ajout aux notes de campagne. Chaque champ s'affiche avec sa valeur **avant** et **après** et une case à cocher : vous appliquez tout, ou seulement la sélection. **Annuler** remet tout en place. |
| **Limites strictes** | L'agent ne publie jamais, ne marque jamais une publication « Publié » (toute proposition en ce sens est ignorée) et ne peut modifier aucun autre champ. |
| **Consignes de campagne** | *Modifier la campagne → Consignes pour l'agent* : ton, public, contraintes. Envoyées à chaque demande. |
| **Actions rapides** | Boutons au-dessus de la saisie (rédiger, améliorer l'accroche, traduire, vérifier avant publication, et ensuite ?). Modifiables dans les réglages de l'agent : une par ligne, `Titre | consigne`. |
| **Contexte partagé** | Choisissez si les brouillons, les statistiques et les notes de campagne sont envoyés. La fiche de la tâche l'est toujours. |

## Pourquoi c'est précieux avec un agent local (Claude Code)

- **Une seule session pour tout.** Toutes les demandes vont dans une session Claude Code nommée (par défaut « hERALD »). Reprenez-la quand vous voulez depuis le terminal (`claude --resume`, le bouton **Copier la commande de reprise** donne la ligne exacte) ou retrouvez-la dans l'application Claude. Ce que vous demandez dans hERALD et dans Claude Code partage la même mémoire.
- **Sous-sessions.** Pour un long travail, l'agent peut ouvrir une sous-session et le dire à hERALD, qui la rattache à la tâche (affichée au-dessus de la discussion, avec un bouton pour la reprendre).
- **Il lit vos fichiers.** Le *dossier de travail* est l'endroit où l'agent peut lire (vidéos, scripts, dossier de presse, notes). Choisissez le dossier qui contient le matériel de votre campagne. C'est aussi le projet sous lequel la session apparaît dans Claude Code.
- **Utiliser une session existante.** Collez un identifiant de session dans les réglages de l'agent pour que hERALD utilise une session que vous avez déjà au lieu d'en créer une.
- **Mode léger (par défaut).** Claude Code démarre avec `--safe-mode` : ni serveurs MCP, ni skills, ni hooks, ni CLAUDE.md. Une demande coûte alors environ cent fois moins de jetons (mesuré : environ 7 000 jetons pour une demande minimale, contre plusieurs centaines de milliers avec une grosse configuration). Décochez-le si vous voulez que l'agent profite de tout votre environnement.
- **Outils sûrs.** L'agent peut seulement lire des fichiers (Read, Glob, Grep) et lancer la commande `claude` (pour ouvrir des sous-sessions). Tout le reste est refusé, sans question.

### Première utilisation sur un Mac : volumes amovibles

Si le dossier de travail est sur un disque externe, macOS demande une fois : *« hERALD souhaite accéder aux fichiers d'un volume amovible »*. Cliquez sur **Autoriser**. Le bouton **Tester l'agent** des réglages vérifie le programme et l'accès au dossier sans rien demander à l'agent, et c'est le bon moment pour répondre à macOS. Si l'accès est refusé, hERALD l'explique et indique où l'autoriser (Réglages Système, Confidentialité et sécurité, Fichiers et dossiers, hERALD, Volumes amovibles).

## Autres agents

| Agent | Comment | Mémoire de la conversation |
|---|---|---|
| **Claude Code** | La commande `claude` (trouvée automatiquement dans `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, ou indiquez son chemin). | Dans la session de Claude Code elle-même. |
| **Tout agent en ligne de commande (Codex, …)** | Une commande qui lit la question sur l'entrée standard et écrit la réponse sur la sortie standard, par exemple `codex exec -` (bouton fourni). Lancée par votre shell de connexion. | hERALD renvoie l'historique à chaque question. |
| **ChatGPT / API compatible OpenAI** | Adresse de l'API (par défaut `https://api.openai.com/v1/chat/completions`), nom du modèle, clé API (rangée dans le trousseau macOS). Fonctionne avec tout service ou serveur local qui parle le même format. | hERALD renvoie l'historique à chaque question. |

Seul Claude Code donne des sessions retrouvables dans l'application de l'agent, et les sous-sessions.

## Confidentialité

Tout reste sur votre Mac. La seule chose envoyée quelque part est votre question et le contexte que vous avez choisi de partager, à l'agent que vous avez choisi. Les conversations sont enregistrées dans votre fichier de plan (`plan.json`) : elles figurent donc aussi dans un plan exporté. Utilisez **Effacer** dans une discussion pour la retirer avant de partager un plan.
