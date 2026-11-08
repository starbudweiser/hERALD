# Visite guidée (à créer)

Notes pour la future visite guidée de hERALD, au premier lancement et depuis le menu Aide.

## Étapes prévues
1. Règle d'or : hERALD prépare et suit, il ne publie jamais.
2. Campagnes et jalons, compte à rebours.
3. Calendrier et tableau de suivi (statuts, lignes alternées, publications faites estompées).
4. Brouillons en quatre langues, copie en un clic.
5. Statistiques : relevés automatiques par lien, saisie manuelle, rapport.
6. Veille GitHub et Nexus.
7. Boîte de dépôt (automatisation).
8. **Agent IA (étape à mettre en avant)** : à placer en bonne place, pas en fin de visite.
   - Montrer l'interrupteur dans les Réglages : facultatif, désactivé par défaut, rien ne change sans lui.
   - Pour qui a un agent IA local (Claude Code, Codex…) : une seule session retrouvable, l'agent retrouve la tâche tout seul, il lit les fichiers du dossier de travail, sous-sessions pour les gros travaux, mode léger.
   - Pour tous : propositions appliquées d'un clic et annulables, jamais de publication, consignes de campagne, actions rapides.
   - Mentionner l'autorisation « volume amovible » de macOS au premier essai sur un disque externe.
   - Les autres utilisateurs doivent pouvoir passer cette étape en un clic et ne rien voir de l'agent ensuite.
9. Icône : Dock, barre de menus ou les deux.

Documentation détaillée à lier depuis l'étape 8 : `docs/AGENT_IA.md` et `docs/AI_AGENT.md`.

## À refaire : ergonomie du module Agent IA
Demande de Stéphan (08/11/2026) : refaire l'ergonomie du module. Constats faits pendant l'essai réel :
- la discussion ne défile pas jusqu'à la dernière réponse : la carte de proposition arrive coupée, il faut faire défiler à la main ;
- la fenêtre de discussion est une feuille modale étroite posée sur le calendrier : prévoir un volet latéral ou une fenêtre à part, redimensionnable, qui reste ouverte pendant qu'on travaille sur le plan ;
- l'attente d'une réponse (souvent plusieurs dizaines de secondes) n'a que « L'agent travaille… » : afficher l'avancement et permettre d'interrompre ;
- la boîte d'autorisation macOS (volumes amovibles) bloque la première demande sans explication : la prévoir dans un premier écran de configuration ;
- les propositions devraient montrer l'avant et l'après, et pouvoir s'appliquer champ par champ.
