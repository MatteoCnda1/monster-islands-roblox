# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

`AGENTS.md` (règles agents + import de `.ai/STATE.md`, l'état vivant du projet) est chargé ci-dessus.
En fin de session, mettre à jour l'état avec `/handoff` (ou `bash .ai/ctx.sh` pour le seul snapshot git/issues).

## Commandes

| But | Commande |
|---|---|
| Tests unitaires (CLI `luau`, hors Roblox) | `./tools/test.sh` (= `luau tests/run_tests.luau`) |
| Build de la place | `./tools/build.sh [sortie]` → `build/MonsterIslands.rbxl` (`rojo build`) |
| Sync live vers Studio | `./tools/serve.sh [port]` (défaut 34872) puis Connect dans le plugin Rojo |
| Ouvrir dans Studio (Linux) | `./tools/studio.sh` (rebuild puis lance Vinegar via flatpak) |
| Hook pre-commit | `ln -sf ../../tools/pre-commit.sh .git/hooks/pre-commit` — lance `test.sh` + `build.sh`, bloque le commit en cas d'échec |

- **Pas de lancement d'un test isolé** : `tests/run_tests.luau` est un fichier unique avec son propre mini-framework
  (`test(name, fn)`, `assert_eq`, `assert_true`, `assert_false`). Pour cibler un test, le lancer en entier ou
  commenter les autres temporairement.
- **Les tests n'importent pas `src/`** : ils recopient les formules (économie, dégâts, IVs, migration…) avec des
  mocks minimaux de `Color3`/`Vector3`/`Enum` (issue #19). Modifier une formule dans `src/` ne casse donc pas les
  tests : penser à mettre à jour la copie dans `run_tests.luau`.
- `./tools/analyze.sh` (`luau-analyze`) n'est **pas** un indicateur fiable : sans définitions de types Roblox, il
  remonte ~1300 erreurs « Unknown global » (`game`, `task`, `TweenInfo`…). Seuls tests + build Rojo comptent.
- Toolchain dans `~/.cargo/bin` : `luau`, `luau-analyze`, `rojo`.

## Architecture

### Mapping Rojo (`default.project.json`)
- `src/shared` → `ReplicatedStorage.Shared` (requis via `require(ReplicatedStorage.Shared.X)`)
- `src/server` → `ServerScriptService.Server`
- `src/client` → `StarterPlayer.StarterPlayerScripts.Client`

`src/modules/` est vide et non mappé par Rojo (malgré le README).

### Cycle de vie Services / Controllers
- `ServerBootstrap.server.luau` construit d'abord **toute la carte de manière procédurale** (`Workspace.WorldMap` :
  île, chemins, sanctuaire de breeding à l'ouest, arène PvP au nord avec `PodiumPlayer1/2`), puis requiert les
  services dans une **liste ordonnée** et appelle `:Init()` sur tous, puis `:Start()` sur tous.
  `ClientBootstrap.client.luau` fait de même pour les controllers.
- Un nouveau service/controller doit être **ajouté à la liste du bootstrap**, sinon il n'est jamais initialisé.
- Les dépendances entre services sont résolues **dans `Init()`** (`PlayerDataService = require(script.Parent.PlayerDataService)`
  sur une variable locale déclarée en haut du module) pour éviter les requires circulaires. Conserver ce schéma.
- Convention `Init()` = enregistrer les remotes / bindings ; `Start()` = boucles et connexions `Players.*`.

### État joueur (source de vérité)
- `PlayerDataService` détient les profils en mémoire (`loadedProfiles[player]`, type `Types.PlayerData`).
  Toute mutation passe par `PlayerDataService:UpdateProfile(player, function(profile) ... end)`, qui exécute
  l'updater sous `pcall` puis **renvoie le profil complet au client** via `PlayerDataUpdated`.
- Au chargement, le client reçoit `PlayerDataLoaded` ; les controllers lisent aussi `GetPlayerData`.
- En Studio avec `Config.STUDIO_MOCK_DATASTORE = true`, aucun DataStore : profils en mémoire uniquement.
- Le nom du DataStore inclut `Config.DATA_VERSION`. Les champs ajoutés aux profils doivent être rétro-remplis
  dans `_loadPlayerProfile` (cf. `PlacedDecorations`) et ajoutés dans `createDefaultProfile`.
- Limites connues : pas de session locking, et un `GetAsync` en échec crée un profil par défaut qui écrase la
  sauvegarde réelle (issue #20).

### Réseau
- Tous les remotes passent par `src/shared/Utility/Network.luau`, référencés **par nom (string)** et créés à la
  demande dans `ReplicatedStorage.Remotes` :
  - serveur : `Network.HandleFunction(name, fn)`, `Network.HandleEvent`, `Network.FireClient`, `Network.FireAllClients`
  - client : `Network.InvokeServer`, `Network.FireServer`, `Network.OnClientEvent`
- Les `HandleFunction` retournent par convention `(success: boolean, errOrPayload)`. Chaque handler valide lui-même
  les arguments (`typeof(...)`) — il n'y a pas de couche de validation/limitation de débit centralisée, malgré
  `docs/ARCHITECTURE.md` (issue #22).
- Le nom d'un remote est un contrat implicite client↔serveur : vérifier les deux côtés avec
  `grep -rn '"NomDuRemote"' src`. Plusieurs remotes n'ont qu'un seul côté branché (issue #23).

### Données data-driven (`src/shared`)
- `Types.luau` : tous les types partagés (modifier ici d'abord).
- `Config.luau` : constantes de jeu (parcelles avec position monde/coût/capacité, monnaies de départ, autosave…).
- `MonsterDefinitions.luau` (espèces + `CalculateStats`), `AttackDefinitions.luau`, `ElementDefinitions.luau`
  (matrice d'efficacité).
- Les modèles 3D (monstres, œufs, décorations) sont **générés procéduralement en code** (ex.
  `MonsterService.buildProceduralMonsterModel`) ; `assets/` est vide.

### Côté client
- `UIController` (le plus gros fichier) construit toute l'UI en code et orchestre les onglets ;
  `CombatController` gère le rendu du combat et pilote `CameraController` pour la caméra cinématique.
  `PlotController` et `MonsterController` sont quasi vides.

## Conventions (détails dans `CONTRIBUTING.md`)
- `--!strict` en tête de chaque fichier ; PascalCase pour les membres publics, camelCase pour les locales.
- Pas de `print()` dans `src/` : utiliser `Logger:Info/Warn/Error/Debug("TAG", fmt, ...)`.
  Les tentatives suspectes du client se loguent en `Logger:Warn("SECURITY", ...)` sans faire planter le serveur.
- Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`…). Branches `feature/*` / `fix/*` depuis `dev`,
  merge `--no-ff` dans `dev` ; `main` = releases.
- Les docs de conception (`docs/*.md`) sont parfois en avance ou en décalage par rapport au code :
  le code fait foi.
