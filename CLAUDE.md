# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

`AGENTS.md` (règles agents + import de `.ai/STATE.md`, l'état vivant du projet) est chargé ci-dessus.
En fin de session, mettre à jour l'état avec `/handoff` (ou `bash .ai/ctx.sh` pour le seul snapshot git/issues).

## Commandes

| But | Commande |
|---|---|
| Tests unitaires (CLI `luau`, hors Roblox) | `./tools/test.sh` (génère `build/test_sources.luau` puis `luau tests/run_tests.luau`) |
| Build de la place | `./tools/build.sh [sortie]` → `build/MonsterIslands.rbxl` (`rojo build`) |
| Sync live vers Studio | `./tools/serve.sh [port]` (défaut 34872) puis Connect dans le plugin Rojo |
| Ouvrir dans Studio (Linux) | `./tools/studio.sh` (rebuild puis lance Vinegar via flatpak) |
| Hook pre-commit | `ln -sf ../../tools/pre-commit.sh .git/hooks/pre-commit` — lance `test.sh` + `build.sh`, bloque le commit en cas d'échec |

- **Pas de lancement d'un test isolé** : `tests/run_tests.luau` est un fichier unique avec son propre mini-framework
  (`test(name, fn)`, `assert_eq`, `assert_near`, `assert_true`, `assert_false`, `assert_errors`). Pour cibler un
  test, le lancer en entier ou commenter les autres temporairement. Toujours passer par `./tools/test.sh`
  (`luau tests/run_tests.luau` seul échoue si le bundle n'a pas été généré).
- **Les tests exercent le vrai code de `src/shared`** : la CLI `luau` n'a pas d'`io` et ses globals sont en lecture
  seule, donc `test.sh` embarque le texte de chaque `src/**/*.luau` dans `build/test_sources.luau`, et le runner
  exécute les modules partagés via `loadstring` + `setfenv` avec un faux `script` (`script.Parent.X` résolu vers
  les modules frères) et des mocks minimaux (`Vector3`, `Color3`, `Enum`, `warn`) — détails en tête du fichier.
  Tous les fichiers de `src/` (serveur/client compris) sont aussi compilés : une erreur de syntaxe fait échouer la suite.
- **Seuls les modules purs sont testables** (pas de `game:GetService`). Pour tester de la logique de service, l'extraire
  dans un module pur de `src/shared` utilisé par le service et les tests (cf. `CombatMath`, `BreedingMath`,
  `PlotMath`, `EconomyMath`).
- `./tools/analyze.sh` (`luau-analyze`) n'est **pas** un indicateur fiable : sans définitions de types Roblox, il
  remonte ~1300 erreurs « Unknown global » (`game`, `task`, `TweenInfo`…). Seuls tests + build Rojo comptent.
- Toolchain dans `~/.cargo/bin` : `luau`, `luau-analyze`, `rojo`.

## Architecture

### Mapping Rojo (`default.project.json`)
- `src/shared` → `ReplicatedStorage.Shared` (requis via `require(ReplicatedStorage.Shared.X)`)
- `src/server` → `ServerScriptService.Server`
- `src/client` → `StarterPlayer.StarterPlayerScripts.Client`

Il n'existe pas de `src/modules/` versionné (dossier vide, non mappé par Rojo) : les utilitaires génériques vont dans `src/shared/Utility/`.

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
- Nom de DataStore **fixe** (`Config.DATASTORE.NAME` = `MonsterIslands_PlayerData_v1`, à ne jamais changer) ;
  la version de schéma est le champ `Version` du profil, mis à niveau au chargement par `migrateProfile`
  (table `MIGRATIONS`). Les champs ajoutés aux profils doivent être rétro-remplis dans `backfillProfile`
  (cf. `PlacedDecorations`) et ajoutés dans `createDefaultProfile`. Ces deux fonctions tournent dans une
  transformation `UpdateAsync` : ni yield, ni effet de bord hors du profil.
- Verrou de session maison via `UpdateAsync` (issue #20, détails dans `docs/ARCHITECTURE.md` §3) : une erreur de
  lecture n'aboutit jamais à un profil neuf (réessais puis `Kick`), et un serveur n'écrit que tant qu'il détient
  le verrou. Le format stocké est `{ RecordFormat, Profile, SessionLock }` (les anciennes sauvegardes « profil
  brut » sont relues telles quelles). Lors d'une mise en ligne, préférer « Shut down all servers ».

### Réseau
- Tous les remotes passent par `src/shared/Utility/Network.luau`, référencés **par nom (string)** et créés à la
  demande dans `ReplicatedStorage.Remotes` :
  - serveur : `Network.HandleFunction(name, fn)`, `Network.HandleEvent`, `Network.FireClient`, `Network.FireAllClients`
  - client : `Network.InvokeServer`, `Network.FireServer`, `Network.OnClientEvent`
- Les `HandleFunction` retournent par convention `(success: boolean, errOrPayload)`. Chaque handler valide lui-même
  les arguments (`typeof(...)`) — il n'y a pas de couche de validation ni de limiteur de débit centralisés
  (cf. `docs/ARCHITECTURE.md` §4.4). Exception à la convention : `GetPlayerData` renvoie directement le profil.
- Le nom d'un remote est un contrat implicite client↔serveur : vérifier les deux côtés avec
  `grep -rn '"NomDuRemote"' src`. Tout remote déclaré doit avoir ses deux côtés branchés.

### Données data-driven (`src/shared`)
- `Types.luau` : tous les types partagés (modifier ici d'abord).
- `Config.luau` : constantes de jeu (parcelles avec position **relative au slot**/coût/capacité, `PLOT_SLOTS`,
  monnaies de départ, autosave…).
- Parcelles par joueur (issue #21) : `PlotService` attribue à chaque joueur un slot = une île annexe (géométrie
  dans `PlotSlots.luau`, îles + ponts construits par le bootstrap), y construit ses parcelles dans
  `Workspace.Plots.Slot_<n>` et libère tout (parcelles, décorations, monstres rendus) à son départ. Les invites
  d'achat sont créées côté client par `PlotController`, uniquement sur les parcelles du joueur local.
- `MonsterDefinitions.luau` (espèces + `CalculateStats`), `AttackDefinitions.luau`, `ElementDefinitions.luau`
  (matrice d'efficacité).
- Formules pures extraites des services (sans effets de bord, aléa injectable) : `CombatMath.luau` (ordre d'action,
  dégâts, bouclier, brûlure), `BreedingMath.luau` (compatibilité, héritage d'IVs, espèce/mutation), `PlotMath.luau`
  (grille de décoration), `EconomyMath.luau` (validation des montants).
- Les modèles 3D (monstres, œufs, décorations) sont **générés procéduralement en code** (ex.
  `MonsterService.buildProceduralMonsterModel`) ; `assets/` ne contient que la structure prévue (`assets/README.md` + `.gitkeep`), non mappée par Rojo.

### Côté client
- `UIController` (le plus gros fichier) construit toute l'UI en code et orchestre les onglets ;
  `CombatController` gère le rendu du combat et pilote `CameraController` pour la caméra cinématique.
  `PlotController` crée côté client les `ProximityPrompt` réservés au propriétaire (achat de parcelle, éclosion
  des œufs du nid de l'île), à partir d'attributs posés par le serveur (`OwnerUserId`, `IsUnlocked`, `IsReady`…).
  `MonsterController` est quasi vide.

## Conventions (détails dans `CONTRIBUTING.md`)
- `--!strict` en tête de chaque fichier ; PascalCase pour les membres publics, camelCase pour les locales.
- Pas de `print()` dans `src/` : utiliser `Logger:Info/Warn/Error/Debug("TAG", fmt, ...)`.
  Les tentatives suspectes du client se loguent en `Logger:Warn("SECURITY", ...)` sans faire planter le serveur.
- Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`…). Branches `feature/*` / `fix/*` depuis `dev`,
  merge `--no-ff` dans `dev` ; `main` = releases.
- Les docs de conception (`docs/*.md`) sont parfois en avance ou en décalage par rapport au code :
  le code fait foi.
