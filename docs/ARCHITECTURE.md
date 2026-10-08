# Monster Islands — Architecture Technique

## 1. Vue d'Ensemble des Composants

L'architecture repose sur le découpage standard moderne Roblox / Luau, synchronisé via **Rojo**
(`default.project.json` : `src/shared` → `ReplicatedStorage.Shared`, `src/server` → `ServerScriptService.Server`,
`src/client` → `StarterPlayer.StarterPlayerScripts.Client`). Le second arbre ci-dessous n'existe pas dans le projet
Rojo : ces instances sont créées par le code au lancement.

```text
Game Container (DataModel)
│
├── ReplicatedStorage
│   └── Shared/
│       ├── Types.luau                  -- Définitions des types Luau stricts
│       ├── Config.luau                 -- Variables de configuration globales
│       ├── MonsterDefinitions.luau     -- Registre data-driven des monstres
│       ├── AttackDefinitions.luau      -- Définitions des compétences et attaques
│       ├── ElementDefinitions.luau     -- Matrice élémentaire et modificateurs
│       └── Utility/
│           ├── Logger.luau             -- Journalisation structurée avec tags
│           ├── Signal.luau             -- Événements Luau haute performance
│           └── Network.luau            -- Surcouche des remotes (création paresseuse, aucune validation)
│
├── ServerScriptService
│   └── Server/
│       ├── ServerBootstrap.server.luau -- Point d'entrée : génère la carte, puis Init/Start des services
│       └── Services/
│           ├── PlayerDataService.luau  -- Abstraction DataStore, sessions et profils
│           ├── EconomyService.luau     -- Gestion des devises (Coins, Gems)
│           ├── PlotService.luau        -- Gestion et persistance des parcelles
│           ├── MonsterService.luau     -- Instanciation, stats et inventaire de monstres
│           ├── BreedingService.luau    -- Reproduction, hérédité et incubations
│           ├── CombatService.luau      -- Moteur de combat tour par tour
│           ├── MatchmakingService.luau -- File d'attente PvP, appariement puis CombatService:CreateBattle
│           ├── InventoryService.luau   -- Gestion des objets, potions et consommables
│           └── QuestService.luau       -- Suivi et complétion des quêtes
│
└── StarterPlayer
    └── StarterPlayerScripts
        └── Client/
            ├── ClientBootstrap.client.luau -- Point d'entrée client : Init/Start des controllers
            └── Controllers/
                ├── UIController.luau       -- Construit toute l'UI en code (HUD, onglets, achats, breeding, décoration)
                ├── CombatController.luau   -- Interface, dégâts flottants et VFX du combat ; pilote CameraController
                ├── PlotController.luau     -- Invites (côté client, île du joueur local) : achat de parcelles, éclosion des œufs
                ├── MonsterController.luau  -- Quasi vide : demande au serveur le rendu des monstres placés
                └── CameraController.luau   -- Caméra cinématique (focus sur une position, arène de combat)

Instances créées au lancement (runtime, côté serveur, répliquées aux clients)
├── ReplicatedStorage.Remotes/   -- RemoteEvent / RemoteFunction créés à la demande par Network (cf. §4)
└── Workspace/
    ├── WorldMap/                -- Île, chemins, sanctuaire de breeding, arène PvP (ServerBootstrap)
    ├── Plots/                   -- Une île par joueur (Slot_<n>) : parcelles, décorations, nid et œufs en incubation (PlotService, BreedingService)
    ├── PlacedMonsters/          -- Modèles 3D des monstres placés (MonsterService)
    └── ActiveBattleArenas/      -- Monstres des combats en cours, un dossier Battle_<id> par combat (CombatService)
```

Les modèles 3D (monstres, œufs, décorations) sont construits en code par les services serveur ; aucun asset importé n'est utilisé.

---

## 2. Cycle de Vie des Modules (Lifecycle)

Il n'y a pas de framework ni de découverte automatique : chaque bootstrap requiert explicitement ses modules et
les range dans une **liste ordonnée**, puis appelle `:Init()` sur tous, puis `:Start()` sur tous (chaque méthode est
optionnelle, testée par `typeof(x.Init) == "function"`).

- **Serveur** (`ServerBootstrap.server.luau`) : génère d'abord la carte (`Workspace.WorldMap`), puis traite les
  services dans cet ordre : `PlayerDataService`, `EconomyService`, `MonsterService`, `PlotService`,
  `BreedingService`, `CombatService`, `MatchmakingService`, `InventoryService`, `QuestService`.
- **Client** (`ClientBootstrap.client.luau`) : `UIController`, `CombatController`, `PlotController`,
  `MonsterController`, `CameraController`.
- **Un nouveau service/controller doit être ajouté à cette liste**, sinon il n'est jamais initialisé.
- Les appels sont directs et séquentiels, sans `pcall` : une erreur dans un `Init()`/`Start()` interrompt le
  bootstrap et les modules suivants ne sont pas initialisés. Un `Start()` qui boucle doit le faire dans `task.spawn`.

Rôle de chaque phase :
1. `:Init()` : résout les dépendances vers les autres services (`PlayerDataService = require(script.Parent.PlayerDataService)`
   sur une variable locale déclarée en haut du module, pour éviter les `require` circulaires), crée les dossiers
   `Workspace` du service et enregistre la plupart des remotes. Un service ne doit pas appeler les méthodes d'un autre
   service pendant cette phase : l'ordre de la liste ne garantit pas que celui-ci soit prêt.
2. `:Start()` : se lance une fois tous les modules initialisés. Connecte `Players.PlayerAdded` / `PlayerRemoving`,
   démarre les boucles périodiques (`task.spawn`) et les `ProximityPrompt`. Quelques remotes de rafraîchissement
   (`HandleEvent`) y sont aussi enregistrés ; les deux emplacements fonctionnent car tout le bootstrap serveur
   s'exécute au démarrage de l'instance.

---

## 3. Gestion des Données Joueur (`PlayerDataService`)

Pour garantir l'intégrité des profils sans écriture conflictuelle (implémentation maison, sans dépendance externe) :

- **Profil en cache mémoire** : chaque joueur a une *session* (`Loading → Active → Releasing → Released`). Tant
  qu'elle est active, `GetProfile` / `UpdateProfile` agissent sur le profil en mémoire ; ces API ne changent pas.
- **Stockage** : DataStore au nom **fixe** `Config.DATASTORE.NAME` (`MonsterIslands_PlayerData_v1`), clé
  `User_<UserId>`, valeur `{ RecordFormat = 1, Profile = <PlayerData>, SessionLock = { JobId, SessionId, LockedAt }? }`.
  Les sauvegardes antérieures (profil brut à la racine de la clé) sont reconnues et réécrites dans ce format au
  premier chargement. Une valeur illisible n'est jamais écrasée (le joueur est expulsé).
- **Versions & migrations** : la version de schéma est le champ `Profile.Version` (`Config.DATA_VERSION`). Au
  chargement, `migrateProfile` applique les étapes de la table `MIGRATIONS` (vide pour l'instant) puis
  `backfillProfile` rétro-remplit les champs récents. Un profil écrit par une version **plus récente** du jeu
  n'est pas chargé par un serveur plus ancien (expulsion, pour ne pas perdre les nouveaux champs).
- **Chargement** : un seul `UpdateAsync` lit la valeur et pose le verrou de manière atomique.
  - clé vide (lecture réussie, `nil`) → nouveau joueur : profil par défaut créé et écrit avec le verrou ;
  - **erreur de lecture** → réessais (`LOAD_MAX_ATTEMPTS`, délai croissant) puis `player:Kick(...)` ; on ne crée
    **jamais** de profil neuf en cas d'erreur, et une session non chargée n'est jamais sauvegardée ;
  - verrou détenu par une autre session vivante → attente (`LOCK_WAIT_SECONDS`, cas du changement de serveur dont
    la sauvegarde finale est en cours) puis expulsion avec un message explicite.
- **Session Locking** : le verrou contient l'identifiant du serveur (`game.JobId`, `"Studio"` en Studio où il est
  vide), un identifiant de session unique (GUID) et un horodatage `LockedAt`. Il est considéré comme **périmé**
  (serveur planté) au-delà de `LOCK_STALE_SECONDS` (600 s) ; un verrou laissé par ce même serveur sans session
  vivante (reconnexion rapide après un échec de sauvegarde) est repris immédiatement. Toute écriture vérifie, dans
  la transformation `UpdateAsync`, que la session possède toujours le verrou ; sinon elle est annulée, le profil
  local est abandonné et le joueur expulsé (« save opened on another server »).
- **Sauvegarde périodique** : toutes les `AUTOSAVE_INTERVAL_SECONDS` (180 s), ce qui rafraîchit aussi `LockedAt`.
  Les écritures d'une session sont sérialisées (pas d'autosave pendant une autre écriture ou après le début du départ).
- **Départ / arrêt** : `PlayerRemoving` et `BindToClose` déclenchent la sauvegarde finale, qui écrit le profil
  **et libère le verrou dans la même écriture**, exactement une fois : un second appel attend la fin du premier,
  et aucune écriture n'est possible après libération. `BindToClose` attend toutes les sessions (25 s max) ; un
  joueur parti pendant son chargement voit son verrou rendu dès l'acquisition.
- **Mode Studio / Hors-ligne** : en Studio avec `Config.STUDIO_MOCK_DATASTORE = true` (ou si le DataStore est
  inaccessible en Studio), profils en mémoire sans persistance ni verrou. En production, un DataStore inaccessible
  entraîne l'expulsion plutôt qu'une partie sur un profil vierge.
- **Déploiement** : les anciens serveurs ne connaissent pas le verrou ; lors de la mise en ligne de ce format,
  utiliser « Shut down all servers » plutôt qu'une migration progressive.

---

## 4. Communication Réseau

Tous les échanges client ↔ serveur passent par `src/shared/Utility/Network.luau`, une **fine surcouche** aux
`RemoteEvent` / `RemoteFunction` de Roblox. Elle ne fait que créer/retrouver les remotes et y brancher les
callbacks : **elle ne valide rien et ne limite pas le débit** (voir 4.4).

### 4.1 Remotes nommés par chaîne, créés à la demande

- Il n'y a pas de registre déclaratif des remotes : chacun est désigné par **son nom (string)** à chaque appel.
  Ce nom est un contrat implicite entre client et serveur ; une faute de frappe ne produit aucune erreur à la
  compilation. Pour vérifier qu'un remote est branché des deux côtés : `grep -rn '"NomDuRemote"' src`.
- Les instances vivent dans **`ReplicatedStorage.Remotes`** (dossier créé par le serveur au premier `require`
  de `Network`).
- **Création paresseuse** : côté serveur, le premier appel de l'API avec un nom donné crée le `RemoteEvent` ou la
  `RemoteFunction` correspondant. Côté client, le module attend l'instance (`WaitForChild(name, 10)`) ; si le
  serveur ne l'a pas créée sous 10 s, l'appel échoue. Un remote n'existe donc côté client que si le serveur l'a
  enregistré ou utilisé au moins une fois.
- Les instances sont mises en cache par nom dans le module (une table pour les events, une pour les functions).

### 4.2 API exposée

Chaque fonction vérifie par `assert` qu'elle est appelée du bon côté.

| Côté | Fonction | Remote | Comportement |
|---|---|---|---|
| Serveur | `Network.HandleFunction(name, handler)` | `RemoteFunction` | Affecte `OnServerInvoke = handler` : un seul handler par nom, le dernier enregistré gagne. |
| Serveur | `Network.HandleEvent(name, handler)` | `RemoteEvent` | Connecte `handler` à `OnServerEvent` (plusieurs handlers possibles). |
| Serveur | `Network.FireClient(name, player, ...)` | `RemoteEvent` | Envoie un événement à un joueur. |
| Serveur | `Network.FireAllClients(name, ...)` | `RemoteEvent` | Diffuse un événement à tous les joueurs. |
| Client | `Network.InvokeServer(name, ...)` | `RemoteFunction` | Appel bloquant (yield) jusqu'à la réponse du handler serveur. |
| Client | `Network.FireServer(name, ...)` | `RemoteEvent` | Envoi sans réponse. |
| Client | `Network.OnClientEvent(name, handler)` | `RemoteEvent` | Connecte `handler` et renvoie la connexion. |

Les handlers serveur reçoivent `player: Player` en premier argument : il est injecté par Roblox et constitue la
**seule donnée fiable** de la requête. Tous les autres arguments sont contrôlés par le client.

### 4.3 Conventions

**Retour des `HandleFunction`.** Les actions qui modifient l'état renvoient `(success: boolean, errOrPayload)` :
`true` suivi d'un payload éventuel, ou `false` suivi d'un message d'erreur affichable. Exception : `GetPlayerData`
renvoie directement le profil (ou `nil` s'il n'est pas chargé). Les soldes, monstres et inventaire n'ont pas de
getter dédié : le client les lit dans le profil complet (`GetPlayerData` / `PlayerDataUpdated`).

**Validation par handler.** Chaque handler valide lui-même la forme des arguments avec `typeof(...)` avant de
déléguer à une méthode du service, qui porte les contrôles métier (profil chargé, propriété du monstre ou de la
parcelle, solde suffisant, état du combat…). Exemple réel (`PlotService:Init`) :

```lua
Network.HandleFunction("RequestPurchasePlot", function(player: Player, plotId: any)
	if typeof(plotId) ~= "number" then
		return false, "Invalid Plot ID"
	end
	return self:PurchasePlot(player, math.floor(plotId))
end)

Network.HandleFunction("PlaceMonsterOnPlot", function(player: Player, payload: any)
	if typeof(payload) ~= "table" or typeof(payload.PlotId) ~= "number" or typeof(payload.MonsterUUID) ~= "string" then
		return false, "Invalid placement parameters"
	end
	return self:PlaceMonster(player, payload.PlotId, payload.MonsterUUID)
end)
```

Et côté client (`UIController`) :

```lua
local success, err = Network.InvokeServer("RequestPurchasePlot", plotConfig.Id)
```

Règles à respecter pour tout nouveau remote :
- typer chaque argument reçu en `any` et le vérifier avec `typeof` avant usage, y compris les champs d'une table ;
- ne jamais recevoir du client une valeur que le serveur peut calculer (prix, dégâts, récompenses, stats) ;
- en cas d'échec, renvoyer `false, "message"` plutôt que lever une erreur (`assert`/`error` dans un handler
  remonte une erreur à l'appelant et pollue les logs serveur) ;
- après une mutation via `PlayerDataService:UpdateProfile`, le profil complet est renvoyé automatiquement au client
  par `PlayerDataUpdated` : inutile d'ajouter un remote dédié pour resynchroniser l'UI.

### 4.4 Limites actuelles (non implémenté)

- **Aucun limiteur de débit** : un client peut appeler n'importe quel remote en boucle. Les plus exposés sont ceux
  qui coûtent cher côté serveur (`GetPlayerData` renvoie le profil complet, `RequestRenderPlacedMonsters` reconstruit
  des modèles 3D, `SubmitBattleAction` peut déclencher la résolution d'un tour). Un limiteur par joueur et par remote
  branché dans `Network.HandleFunction` / `HandleEvent` est **envisagé** mais pas décidé (issue #22).
- **Aucune validation centralisée** (schéma de payload, bornes numériques, taille des tables, NaN) : la validation
  se limite aux tests `typeof` écrits dans chaque handler, et leur profondeur varie d'un remote à l'autre.
- Ni cooldown par action, ni vérification de distance pour les interactions monde déclenchées par remote, bien que
  `CONTRIBUTING.md` les recommande (les `ProximityPrompt` bénéficient en revanche de la distance d'activation
  gérée par Roblox).

---

## 5. Extensibilité & Data-Driven Design

Les données d'équilibrage sont extraites dans `src/shared` : espèces et calcul des stats (`MonsterDefinitions`),
compétences (`AttackDefinitions`), matrice d'efficacité élémentaire (`ElementDefinitions`), parcelles, monnaies de
départ, catalogue de décorations et constantes diverses (`Config`). Les types partagés sont centralisés dans
`Types.luau`. Équilibrer une valeur existante ne demande donc pas de toucher aux services.

Ajouter un contenu nouveau demande en revanche encore du code dans les services :
- les traits distinctifs du modèle 3D d'une espèce (oreilles, nageoires…) sont codés par identifiant dans
  `MonsterService` (une nouvelle espèce sans branche dédiée n'a que le corps générique) ;
- la géométrie de chaque décoration est codée par identifiant dans `PlotService` ;
- les espèces des adversaires bot sont listées dans `CombatService` ;
- les quêtes sont définies dans `QuestService`, pas dans un module de définitions.

Les tests (`tests/run_tests.luau`) recopient les formules au lieu d'importer `src/` : une formule modifiée dans
`src/shared` doit aussi être mise à jour dans les tests.
