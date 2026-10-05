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

Pour garantir l'intégrité des profils sans écriture conflictuelle :
- **Profil en cache mémoire** : Lorsqu'un joueur rejoint la partie (`PlayerAdded`), son profil est chargé depuis `DataStoreService` (ou créé avec les données par défaut si nouveau joueur). Les modifications en cours de jeu (achats, gains de combat, nouveaux monstres) sont appliquées immédiatement sur ce cache mémoire.
- **Session Locking** : Empêche deux serveurs d'écrire simultanément sur le profil d'un joueur en déplacement.
- **Sauvegarde Périodique & Auto-Save** : Sauvegarde échelonnée toutes les 3 minutes et lors du `PlayerRemoving` / `BindToClose`.
- **Mode Studio / Hors-ligne** : En environnement Studio avec API DataStore désactivée, un fallback en mémoire simule la persistance sans générer d'erreurs bloquantes.

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
