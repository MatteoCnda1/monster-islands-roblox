# Monster Islands — Roblox

[![Luau](https://img.shields.io/badge/Luau-Strict-blue.svg)](https://luau-lang.org/)
[![Rojo](https://img.shields.io/badge/Rojo-7.7.1-red.svg)](https://rojo.space/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Monster Islands** est un jeu Roblox original combinant collection de monstres, propriété et développement d'îles personnelles (parcelles), exploration 3D, reproduction génétique (breeding) et combats multijoueurs stratégiques au tour par tour (avec évolution vers le PvP temps réel).

---

## 🌟 Caractéristiques Clés

- **Territoire & Parcelles** : Débloquez, achetez et aménagez des parcelles sur votre île personnelle. Assignez-y vos créatures pour qu'elles vaquent à leurs occupations.
- **Collection Originale de Créatures** : 5 monstres prototypes data-driven aux silhouettes et éléments distinctifs (`Emberfox`, `Mossaur`, `Aquaphin`, `Zephlyn`, `Noctyra`).
- **Génétique & Reproduction (Breeding)** : Combinez deux parents compatibles pour créer de nouvelles espèces, hériter de caractéristiques individuelles (IVs) et découvrir des mutations rares.
- **Combat Stratégique Tour par Tour** : Matrice élémentaire à 8 éléments, compétences uniques, calculs de dégâts et coups critiques 100% sécurisés côté serveur.
- **Architecture Server-Authoritative** : Aucune décision sensible (argent, monstres, dégâts, parcelles) n'est confiée au client.
- **Compatible Rojo & Roblox Studio** : Workflow moderne basé sur des fichiers sources versionnés dans Git.

---

## 📁 Structure du Projet

```text
monster-islands-roblox/
├── README.md                   -- Présentation et guide de démarrage
├── CONTRIBUTING.md             -- Règles d'architecture, Luau et Git
├── LICENSE                     -- Licence MIT
├── default.project.json        -- Configuration de synchronisation Rojo
│
├── docs/                       -- Documentation de conception technique
│   ├── GAME_DESIGN.md          -- Game Design Document (GDD)
│   ├── ARCHITECTURE.md         -- Architecture technique des services
│   ├── MONSTERS.md             -- Spécifications et registre des monstres
│   ├── COMBAT.md               -- Moteur de combat et formules
│   ├── BREEDING.md             -- Reproduction, hérédité et mutations
│   ├── ECONOMY.md              -- Économie, monnaies et coûts
│   ├── ROADMAP.md              -- Feuille de route par phases
│   └── ART_DIRECTION.md        -- Direction artistique et pipeline 3D
│
├── src/
│   ├── client/                 -- Code exécuté sur le client (UI, Caméra, VFX)
│   │   ├── Controllers/        -- Contrôleurs (UI, Plot, Monster, Combat)
│   │   └── ClientBootstrap.client.luau
│   ├── server/                 -- Code exécuté sur le serveur (Autorité absolue)
│   │   ├── Services/           -- Services (PlayerData, Economy, Plot, Breeding...)
│   │   └── ServerBootstrap.server.luau
│   ├── shared/                 -- Code partagé sécurisé (Types, Config, Registres)
│   │   ├── Types.luau
│   │   ├── Config.luau
│   │   ├── MonsterDefinitions.luau
│   │   ├── AttackDefinitions.luau
│   │   ├── ElementDefinitions.luau
│   │   └── Utility/
│   └── modules/                -- Modules génériques réutilisables
│
├── tools/                      -- Scripts d'outillage (build, serve, analyze)
└── tests/                      -- Suites de tests unitaires pour la logique
```

---

## 🚀 Démarrage Rapide

### Prérequis
1. [Roblox Studio](https://www.roblox.com/create)
2. [Rojo CLI](https://rojo.space/docs/v7/getting-started/installation/) (v7.4+)
3. Plugin Rojo installé dans Roblox Studio

### Lancement avec synchronisation en direct (Workflow recommandé)
1. Clonez le dépôt et ouvrez un terminal dans le dossier :
   ```bash
   git clone https://github.com/votre-compte/monster-islands-roblox.git
   cd monster-islands-roblox
   ```
2. Démarrez le serveur Rojo :
   ```bash
   ./tools/serve.sh
   # ou directement : rojo serve
   ```
3. Ouvrez un projet vierge dans **Roblox Studio**.
4. Dans l'onglet **Plugins** de Studio, cliquez sur le bouton du plugin **Rojo** et faites **Connect**.
5. Le code, les services, les parcelles et l'UI se synchronisent instantanément !

### Compilation d'un fichier `.rbxl` autonome
Pour générer un fichier de place Roblox autonome :
```bash
./tools/build.sh
# Fichier produit dans build/MonsterIslands.rbxl
```
Ouvrez ensuite simplement `build/MonsterIslands.rbxl` dans Roblox Studio.

---

## 🧪 Tests Unitaires

Pour exécuter les vérifications statiques et les tests :
```bash
./tools/analyze.sh
```

---

## 📜 Documentation Complète

Pour aller plus loin, consultez les documents dans le dossier [docs/](docs/) :
- [Architecture Technique](docs/ARCHITECTURE.md)
- [Conception des Monstres](docs/MONSTERS.md)
- [Système de Combat](docs/COMBAT.md)
- [Reproduction & Génétique](docs/BREEDING.md)
- [Économie & Progression](docs/ECONOMY.md)
- [Direction Artistique](docs/ART_DIRECTION.md)
- [Feuille de Route](docs/ROADMAP.md)
- [Règles de Contribution](CONTRIBUTING.md)
