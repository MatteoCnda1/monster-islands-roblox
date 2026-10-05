# Contributing to Monster Islands — Roblox

Ce guide définit les règles d'architecture, de sécurité, de code Luau et de workflow Git pour le projet **Monster Islands**.

---

## 1. Principes Fondamentaux : Architecture Server-Authoritative

> [!IMPORTANT]
> **Le client Roblox ne doit JAMAIS être considéré comme fiable.**
> N'importe quel client peut manipuler la mémoire locale, falsifier les arguments envoyés via `RemoteEvent` / `RemoteFunction`, et contourner les interfaces.

### Règles absolues de sécurité côté serveur

Le serveur détient l'unique autorité sur :
1. **L'économie & l'inventaire** : soldes de pièces (`Coins`), gemmes (`Gems`), objets et œufs possédés.
2. **Les monstres** : création, statistiques de base, IVs, niveaux, compétences, santé actuelle et statut.
3. **Le breeding** : compatibilité génétique, temps de reproduction restant, tirages de caractéristiques et mutations.
4. **Les parcelles** : propriété, coût, statut de déverrouillage, permissions de placement de monstres ou bâtiments.
5. **Le combat** : tour en cours, calcul des dégâts, application des effets et coups critiques, KO, validation des récompenses.
6. **La sauvegarde** : persistance exclusive via `PlayerDataService` avec gestion de session locking et migrations de schéma.

### Cycle d'interaction Client ↔ Serveur
```text
[ Client ]                        [ Serveur ]
    |                                  |
    |---- 1. Demande d'action -------->|  (Ex: Demande d'achat de parcelle)
    |     (RemoteFunction/Event)       |
    |                                  |-- 2. Vérification d'existence du joueur
    |                                  |-- 3. Vérification des conditions / cooldowns
    |                                  |-- 4. Vérification des ressources disponibles
    |                                  |-- 5. Exécution atomique de la transaction
    |                                  |-- 6. Sauvegarde / Mise à jour de l'état
    |<--- 7. Notification d'état ------|
    |     (Succès/Échec + payload)     |
    |                                  |
    |-- 8. Mise à jour UI & VFX        |
```

---

## 2. Conventions de Code Luau

### Typage et Clarté
- Utilisez Luau avec typage explicite (`--!strict` ou `--!nonstrict` avec types documentés dans `src/shared/Types.luau`).
- Évitez les globales : chaque fichier doit être un module (`ModuleScript`) ou un script autonome (`ServerBootstrap.server.luau`, `ClientBootstrap.client.luau`).
- Nommez les variables et propriétés en **PascalCase** pour les membres publics et exports de services/modules.
- Utilisez **camelCase** pour les variables locales et arguments de fonctions internes.
- Préfixez les variables privées par un underscore `_` si nécessaire.

### Organisation des Modules
Chaque service ou contrôleur doit exposer une interface claire :
```lua
local MyService = {}
MyService.__index = MyService

function MyService:Init()
    -- Enregistrement des remotes, liaisons d'événements
end

function MyService:Start()
    -- Démarrage des boucles, écoute des connexions joueurs
end

return MyService
```

### Journalisation avec `Logger`
N'utilisez pas de `print()` direct dispersé dans le code. Utilisez le module `Logger` partagé :
```lua
local Logger = require(ReplicatedStorage.Shared.Utility.Logger)

Logger:Info("ECONOMY", "Player %s purchased plot %d for %d coins", player.Name, plotId, price)
Logger:Warn("SECURITY", "Player %s attempted unauthorized action %s", player.Name, action)
Logger:Error("DATA", "Failed to save profile for player %s", player.Name)
```

---

## 3. Gestion des Remotes & Anti-Cheat

### Validation systématique des inputs
1. Vérifiez le type et la plage de chaque argument reçu depuis le client (`typeof(arg) == "number"`).
2. Vérifiez la distance physique pour les interactions monde (ex: joueur proche de la parcelle pour interagir).
3. Utilisez un dictionnaire de cooldowns côté serveur pour empêcher le spamming d'actions.
4. En cas d'anomalie manifeste (ex: montant négatif, monstre inexistant), rejetez silencieusement ou alertez via `Logger:Warn("SECURITY", ...)` sans crasher le serveur.

---

## 4. Conventions Git & Workflow

### Format des Commits (Conventional Commits)
Chaque commit doit suivre le format standardisé :
- `feat: add plot purchasing logic in PlotService`
- `fix: prevent negative balance on invalid purchase request`
- `refactor: extract element chart to ElementDefinitions`
- `docs: update COMBAT.md with status effects matrix`
- `test: add unit test for breeding mutation odds`

### Hygiène de Repo
- Ne committez **JAMAIS** de clés d'API, cookies Roblox, `.env` ou secrets.
- Ne committez pas de fichiers binaires non indispensables dans le repository Git (utilisez les scripts Rojo pour générer le place file local).
- Testez toujours vos modifications via Rojo et Roblox Studio avant de pousser.
