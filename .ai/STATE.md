# 📍 État vivant — Monster Islands (Roblox)

> Contexte **optimal** à lire en début de session (auto-chargé via `AGENTS.md`).
> Partie haute = maintenue à la main (ou via `/handoff`). Partie basse = régénérée par `.ai/ctx.sh`.

## 🎯 Focus actuel
- Issues #18–#25 corrigées et mergées sur `dev` (poussé, `d811c5c`) — **jamais testées dans Roblox Studio**.
- Prochaine étape : validation en jeu, puis PR `dev` → `main` (les `Closes #18…#25` fermeront les issues).

## ✅ Fait récemment
- **#19 tests réels** : `./tools/test.sh` embarque `src/` (`build/test_sources.luau`), compile tout `src/` et teste
  le vrai `src/shared` → 42 tests. Logique extraite : `CombatMath`, `BreedingMath`, `PlotMath`, `EconomyMath`.
- **Bug critique corrigé** : `CombatService`/`MatchmakingService` utilisaient `x!` (invalide en Luau) → combat et PvP
  ne se chargeaient pas du tout avant (`rojo build` ne parse pas le Luau).
- **#20** verrou de session `UpdateAsync` + kick si lecture échoue ; **#21** une île (slot) par joueur (`PlotSlots`,
  `Config.PLOTS[].LocalPosition`) ; **#24** abandon en combat = victoire adverse.
- **#18** quêtes via `Signal` + `CompletedQuests` (1 récompense/quête) + onglet Quests ; **#23** file PvP annulable,
  choix d'équipe, remotes inutiles retirés ; **#22/#25** docs (ARCHITECTURE §3-4, 6 monstres, `assets/README.md`).
- Nouvelles issues : #28 (compétence non validée), #29 (nid partagé), #30 (XP/niveau jamais appliqués), #31 (file PvP en combat).

## 🔧 En cours / à faire
- [ ] Tester dans Studio (`./tools/studio.sh`) : combat bot + PvP 2 joueurs, déconnexion en combat, quêtes, îles par
      joueur, file PvP + Cancel, équipe, élevage ; DataStore réel (`STUDIO_MOCK_DATASTORE = false`).
- [ ] Régler **Max Players ≤ 8** dans Game Settings (8 îles max).
- [ ] Issues prioritaires : #30 (parcelles 3–5 inachetables faute de montée de niveau), #28 (sécurité combat).
- [ ] Décider du limiteur de débit réseau (design proposé : token bucket par joueur/remote dans `Network.Handle*`).
- [ ] Puis Phase 2 : habitats élémentaires, production passive d'or.

## 🧠 Décisions clés (ne pas re-débattre)
- **Architecture Server-Authoritative** : Le client ne valide aucun argent, aucun monstre, aucun dégât.
- **Stratégie Git** : `main` (stable), `dev` (intégration), branches `feature/*` / `fix/*` depuis `dev`, merge `--no-ff`.
- **Barrière qualité** : hook pre-commit = `./tools/test.sh` (42 tests, syntaxe de tout `src/`) + build Rojo.
  Le hook ne tourne pas sur un merge sans conflit → relancer `./tools/test.sh` après chaque merge.
- **Luau strict / modulaire** : types dans `src/shared/Types.luau` ; logique testable dans des modules purs de `src/shared`.
- **Découplage inter-services** par `Signal` déclaré au niveau module (ex. `CombatService.BattleWonSignal`).
- **DataStore** : nom fixe `MonsterIslands_PlayerData_v1`, format `{ RecordFormat, Profile, SessionLock }` ;
  nouveau champ de profil → `createDefaultProfile` + `backfillProfile`. Publier avec « Shut down all servers ».
- **Parcelles** : une île par joueur (8 slots), invites d'achat créées côté client.

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
### 🔄 Snapshot auto — 2026-10-08 13:54

- **Branche** : `dev` · **fichiers modifiés** : 1

- **5 derniers commits** :
  - d811c5c docs: drop references to getters removed in #23
  - cb75c49 merge: fix/issue-21-per-player-plots into dev (#21)
  - 777137d merge: fix/issue-23-orphan-remotes into dev (#23)
  - 78f9ba6 merge: fix/issue-18-quest-completion into dev (#18)
  - ee368ec merge: fix/issue-20-data-safety into dev (#20)

- **Issues ouvertes (8 max)** :
  - #31 [PvP] On peut rejoindre la file PvP pendant un combat en cours
  - #30 [Progression] L'XP de combat n'est jamais ajoutée au profil, et il n'y a pas de montée de niveau
  - #29 [Multijoueur] Le nid du sanctuaire d'élevage est partagé entre tous les joueurs
  - #28 [Sécurité] SubmitBattleAction accepte n'importe quelle compétence, et l'action Switch n'est pas implémentée
  - #25 [Nettoyage] Signal.luau inutilisé, dossiers assets vides, roadmap à 5 monstres au lieu de 6
  - #24 [Combat] Un joueur qui quitte en plein combat n'est pas retiré du combat
  - #23 [Réseau] 5 événements serveur sans écouteur et 6 fonctions serveur jamais appelées
  - #22 [Docs] ARCHITECTURE.md décrit un limiteur de débit et une API réseau qui n'existent pas
<!-- CTX:AUTO:END -->
