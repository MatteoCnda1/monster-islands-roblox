# 📍 État vivant — Monster Islands (Roblox)

> Contexte **optimal** à lire en début de session (auto-chargé via `AGENTS.md`).
> Partie haute = maintenue à la main (ou via `/handoff`). Partie basse = régénérée par `.ai/ctx.sh`.

## 🎯 Focus actuel
- Tous les bugs ouverts corrigés et mergés sur `dev` (poussé, `29aae9c`) : #16–#25, #28, #29, #31 —
  **jamais testés dans Roblox Studio**. Restent ouvertes : la roadmap (#3–#14), le playtest #2, l'onboarding #1.
- Prochaine étape : validation en jeu, puis PR `dev` → `main` (les `Closes #…` fermeront les issues).

## ✅ Fait récemment
- **Série 1 (#18–#25)** : tests sur le vrai `src/` (#19, + bug `x!` qui empêchait combat/PvP de se charger),
  verrou de session DataStore (#20), une île par joueur (#21), docs réseau (#22), remotes branchés (#23),
  abandon en combat (#24), quêtes persistées + onglet (#18), nettoyage docs/assets (#25).
- **#16** 2e monstre de départ (`StarterMonsters`, Mossaur/Zephlyn, aussi ajouté aux anciens profils).
- **#17** XP joueur + montée de niveau (`ProgressionMath`, `PlayerDataService:AddPlayerXP`, `PlayerLevelUp`) ;
  `Progression.XP` = XP dans le niveau courant. #30 fermée (doublon de #17).
- **#28** validation des actions de combat (`CombatActions`) + Switch implémenté (serveur, UI, modèle 3D).
- **#29** un nid d'élevage par île ; **#31** file PvP refusée en combat (`IsInBattle`, `MatchmakingRules`). 79 tests.

## 🔧 En cours / à faire
- [ ] Tester dans Studio (`./tools/studio.sh`, Test > 2 joueurs) : combat bot/PvP + Switch, déconnexion en combat,
      XP/niveaux, quêtes, îles + nids, élevage avec le 2e starter, file PvP ; DataStore réel (`STUDIO_MOCK_DATASTORE = false`).
- [ ] Régler **Max Players ≤ 8** dans Game Settings (8 îles max).
- [ ] À arbitrer (équilibrage) : XP/pièces farmables contre le bot ; joueur à 2 monstres contre 1 pour le bot.
- [ ] Décider du limiteur de débit réseau (design proposé : token bucket par joueur/remote dans `Network.Handle*`).
- [ ] Puis Phase 2 : habitats élémentaires, production passive d'or (#9).

## 🧠 Décisions clés (ne pas re-débattre)
- **Architecture Server-Authoritative** : Le client ne valide aucun argent, aucun monstre, aucun dégât.
- **Stratégie Git** : `main` (stable), `dev` (intégration), branches `feature/*` / `fix/*` depuis `dev`, merge `--no-ff`.
- **Barrière qualité** : hook pre-commit = `./tools/test.sh` (79 tests, syntaxe de tout `src/`) + build Rojo.
  Le hook ne tourne pas sur un merge sans conflit → relancer `./tools/test.sh` après chaque merge.
- **Luau strict / modulaire** : types dans `src/shared/Types.luau` ; logique testable dans des modules purs de `src/shared`.
- **Découplage inter-services** par `Signal` déclaré au niveau module (ex. `CombatService.BattleWonSignal`).
- **DataStore** : nom fixe `MonsterIslands_PlayerData_v1`, format `{ RecordFormat, Profile, SessionLock }` ;
  nouveau champ de profil → `createDefaultProfile` + `backfillProfile` (non-yield). Publier avec « Shut down all servers ».
- **Parcelles / nids** : une île par joueur (8 slots) ; invites réservées au propriétaire créées côté client (`PlotController`).
- **Sous-agents en worktree** : créer la branche depuis `dev` (`git checkout -b … dev`), le worktree part d'`origin/main`.

## 🗺️ Où regarder
- Code du jeu (Luau) : `src/` (client, server, shared)
- Mapping Rojo : `default.project.json`
- Tests unitaires : `tests/run_tests.luau`
- Outils : `tools/` (`test.sh`, `build.sh`, `serve.sh`, `studio.sh`, `pre-commit.sh`)
- Documentation de conception : `docs/`
- Conventions de contribution & workflow : `CONTRIBUTING.md`

## 🔌 Commandes utiles
- Exécuter les tests : `./tools/test.sh`
- Compiler la place Roblox : `./tools/build.sh`
- Lancer la sync en direct Rojo : `./tools/serve.sh`
- Ouvrir dans Roblox Studio (Linux) : `./tools/studio.sh`

<!-- CTX:AUTO:START — ne rien écrire à la main sous cette ligne, régénéré par .ai/ctx.sh -->
### 🔄 Snapshot auto — 2026-10-08 14:13

- **Branche** : `dev` · **fichiers modifiés** : 1

- **5 derniers commits** :
  - 29aae9c docs: describe PlotController's client-side prompts in CLAUDE.md
  - d0e4945 merge: fix/issue-29-per-player-nest into dev (#29)
  - 9af9182 merge: fix/issue-16-second-monster into dev (#16)
  - 046f28f merge: fix/issue-28-battle-action-validation into dev (#28)
  - 855370a merge: fix/issue-17-player-xp into dev (#17)

- **Issues ouvertes (8 max)** :
  - #31 [PvP] On peut rejoindre la file PvP pendant un combat en cours
  - #29 [Multijoueur] Le nid du sanctuaire d'élevage est partagé entre tous les joueurs
  - #28 [Sécurité] SubmitBattleAction accepte n'importe quelle compétence, et l'action Switch n'est pas implémentée
  - #25 [Nettoyage] Signal.luau inutilisé, dossiers assets vides, roadmap à 5 monstres au lieu de 6
  - #24 [Combat] Un joueur qui quitte en plein combat n'est pas retiré du combat
  - #23 [Réseau] 5 événements serveur sans écouteur et 6 fonctions serveur jamais appelées
  - #22 [Docs] ARCHITECTURE.md décrit un limiteur de débit et une API réseau qui n'existent pas
  - #21 [Multijoueur] Parcelles partagées : un seul jeu de socles pour tous les joueurs du serveur
<!-- CTX:AUTO:END -->
