# 📍 État vivant — Monster Islands (Roblox)

> Contexte **optimal** à lire en début de session (auto-chargé via `AGENTS.md`).
> Partie haute = maintenue à la main (ou via `/handoff`). Partie basse = régénérée par `.ai/ctx.sh`.

## 🎯 Focus actuel
- Architecture Git à deux branches (`main` pour production/releases, `dev` pour le développement actif).
- Tranche verticale (Vertical Slice) opérationnelle et testable dans Roblox Studio.

## ✅ Fait récemment
- Repository GitHub officiel créé et lié : `https://github.com/MatteoCnda1/monster-islands-roblox`.
- Branche `dev` créée, configurée et poussée sur le remote `origin`.
- Mise en place de la rigueur de développement : hook Git `pre-commit` automatisé (`tools/pre-commit.sh`) bloquant tout commit dont les tests unitaires ou la compilation Rojo échouent.
- Documentation mise à jour (`CONTRIBUTING.md`, `README.md`, 8 documents de conception dans `docs/`).
- Installation de Roblox Studio sur Linux Debian via Flatpak/Vinegar avec lanceur `tools/studio.sh`.
- Tranche verticale complète : 5 monstres prototypes, parcelles 3D, économie sécurisée, breeding avec hérédité génétique, combat tour par tour et interface utilisateur.

## 🔧 En cours / à faire
- [ ] Tester le lancement du projet dans Roblox Studio via `./tools/studio.sh`.
- [ ] Tester les interactions en jeu (achat de la parcelle 2, incubation d'un œuf, combat d'entraînement).
- [ ] Préparer la Phase 2 de la roadmap (bâtiments interactifs, habitats élémentaires, quêtes dynamiques).

## 🧠 Décisions clés (ne pas re-débattre)
- **Architecture Server-Authoritative** : Le client ne valide aucun argent, aucun monstre, aucun dégât.
- **Stratégie Git** : Branche `main` (stable/livrable), branche `dev` (intégration active). Les nouvelles fonctionnalités démarrent sur `feature/<nom>` depuis `dev`.
- **Barrière qualité automatique** : Tout commit passe obligatoirement les 17 tests unitaires et le build Rojo (`.git/hooks/pre-commit`).
- **Luau strict / modulaire** : Tous les types centralisés dans `src/shared/Types.luau`.

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
### 🔄 Snapshot auto — 2026-10-05 18:47

- **Branche** : `dev` · **fichiers modifiés** : 0

- **5 derniers commits** :
  - f49ae42 docs: update AGENTS.md and living state with GitHub remote and branch workflow
  - 9a22c5c docs(state): update living context with GitHub repository and development workflow
  - 277b22e docs: add branching strategy and pre-commit quality gate
  - efe064d infra(context): kit de contexte vivant .ai/STATE.md
  - c23af59 feat: add studio.sh launcher script integrating with Vinegar on Linux

- **Issues ouvertes (8 max)** :
  - #14 [Live-Ops] Boss mondiaux coopératifs et événements de raid communautaires
  - #13 [Combat] Mode d'arène PvP temps réel (Action-RPG) avec compétences et cooldowns
  - #12 [PvP] Système de ligues classées (Ranked), cote Elo/MMR et saisons compétitives
  - #11 [Exploration] Zone sauvage 3D (Wild Zone) et mécanisme de capture de créatures
  - #10 [Quêtes] Quêtes quotidiennes avec rotation, défis hebdomadaires et hauts-faits
  - #9 [Économie] Habitats élémentaires sur les parcelles et production passive de pièces
  - #8 [Évolution] Paliers d'évolution visuelle et compétences ultimes des créatures
  - #7 [Progression] Système d'alimentation, expérience (XP) et montée de niveau des monstres
<!-- CTX:AUTO:END -->
