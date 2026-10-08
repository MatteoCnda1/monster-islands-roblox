# Monster Islands — Architecture Technique

## 1. Vue d'Ensemble des Composants

L'architecture repose sur le découpage standard moderne Roblox / Luau, synchronisé via **Rojo**.

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
│           └── Network.luau            -- Registre et validation des remotes
│
├── ServerScriptService
│   └── Server/
│       ├── ServerBootstrap.server.luau -- Point d'entrée serveur (initialisation)
│       └── Services/
│           ├── PlayerDataService.luau  -- Abstraction DataStore, sessions et profils
│           ├── EconomyService.luau     -- Gestion des devises (Coins, Gems)
│           ├── PlotService.luau        -- Gestion et persistance des parcelles
│           ├── MonsterService.luau     -- Instanciation, stats et inventaire de monstres
│           ├── BreedingService.luau    -- Reproduction, hérédité et incubations
│           ├── CombatService.luau      -- Moteur de combat tour par tour
│           ├── MatchmakingService.luau -- Files d'attente PvP et création d'instances
│           ├── InventoryService.luau   -- Gestion des objets, potions et consommables
│           └── QuestService.luau       -- Suivi et complétion des quêtes
│
└── StarterPlayer
    └── StarterPlayerScripts
        └── Client/
            ├── ClientBootstrap.client.luau -- Point d'entrée client
            └── Controllers/
                ├── UIController.luau       -- Gestion du HUD, fenêtres modales et menus
                ├── MonsterController.luau  -- Visualisation 3D et interactions monstres
                ├── PlotController.luau     -- Interactions visuelles parcelles & achat
                ├── CombatController.luau    -- Interface et animations du combat
                └── CameraController.luau    -- Transitions caméras (exploration, arène)
```

---

## 2. Cycle de Vie des Modules (Lifecycle)

Chaque service côté serveur et contrôleur côté client implémente deux méthodes standard :
1. `:Init()` : Déclare les récepteurs réseau, alloue la mémoire et prépare les structures de données internes. Aucun service ne doit dépendre de l'initialisation complète d'un autre service pendant cette phase.
2. `:Start()` : Se lance une fois tous les services initialisés. Peut appeler d'autres services, démarrer des écoutes d'événements et des boucles périodiques.

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

## 4. Communication Réseau (Sécurisée)

Toutes les requêtes client passent par un gestionnaire centralisé :
```lua
Network.Request("PurchasePlot", { PlotId = 2 })
```

Côté serveur :
```lua
Network.Handle("PurchasePlot", function(player: Player, payload: any)
    assert(typeof(payload.PlotId) == "number", "Invalid PlotId format")
    return PlotService:PurchasePlot(player, payload.PlotId)
end)
```
- Le serveur ne fait confiance à aucune valeur sensible provenant du client.
- Débit limité par joueur (Rate Limiter anti-flood).

---

## 5. Extensibilité & Data-Driven Design

L'ensemble des mécaniques (monstres, compétences, formules de dégâts, coûts de parcelles) est extrait dans des modules `Definitions` ou `Config`.
Ajouter un nouveau monstre ou équilibrer un élément ne requiert aucune modification dans la logique des services centraux.
