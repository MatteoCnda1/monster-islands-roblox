# 📍 État vivant — Monster Islands (Roblox)

> Contexte **optimal** à lire en début de session (auto-chargé via `AGENTS.md`).
> Partie haute = maintenue à la main (ou via `/handoff`). Partie basse = régénérée par `.ai/ctx.sh`.

## 🎯 Focus actuel
- Phase 1 (Vertical Slice) finalisée et fusionnée sur `dev`.
- Prochaine étape : validation en jeu sous Roblox Studio et préparation de la Phase 2.

## ✅ Fait récemment
- **Phase 1 Vertical Slice achevée** :
  - **Décoration de parcelles (Issue #6)** : Système sur grille (4 studs), catalogue de 5 décorations procédurales (`Fence_Wood`, `Lantern_Pillar`, `Elemental_Flower`, `Stone_Bench`, `Training_Dummy`), déduction monétaire server-authoritative, persistance profil et interface complète d'achat/retrait dans l'onglet Parcelles.
  - **Incubateur 3D physique & Écloserie (Issue #4)** : Modèle 3D d'œuf dans le nid du sanctuaire, `BillboardGui` avec timer temps réel, pulsation lumineuse, `ProximityPrompt` pour faire éclore avec animation de secousse/fissuration et burst lumineux.
  - **Combat 3D, VFX et Caméra Dynamique (Issue #5)** : Arène 3D avec téléportation des combattants sur les podiums, modèles 3D des monstres se faisant face, caméra dynamique cinématique, texte flottant de dégâts animés (`BillboardGui` avec tween et critiques) et effets d'impact élémentaires.
- **Rigueur & Tests** : 22/22 tests unitaires passés (100%), compilation Rojo réussie (`build/MonsterIslands.rbxl`).
- **Git** : Branche `feature/phase-1-vertical-slice` mergée dans `dev` et synchronisée sur GitHub remote `origin`.

## 🔧 En cours / à faire
- [ ] Tester les interactions en direct dans Roblox Studio (`./tools/studio.sh` ou `./tools/serve.sh`).
- [ ] Démarrer la Phase 2 : Habitats élémentaires, production passive d'or et quêtes interactives.

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
### 🔄 Snapshot auto — 2026-10-06 00:31

- **Branche** : `dev` · **fichiers modifiés** : 1

- **5 derniers commits** :
  - fd143bc merge: integrate Phase 1 vertical slice into dev
  - 961c666 feat(phase1): implement 3D hatchery, dynamic combat camera & VFX, and plot decoration system
  - b5cd6ce docs(issues): synchronize GitHub issues in living context snapshot
  - f49ae42 docs: update AGENTS.md and living state with GitHub remote and branch workflow
  - 9a22c5c docs(state): update living context with GitHub repository and development workflow

- **Issues ouvertes (8 max)** :
  - #25 [Nettoyage] Signal.luau inutilisé, dossiers assets vides, roadmap à 5 monstres au lieu de 6
  - #24 [Combat] Un joueur qui quitte en plein combat n'est pas retiré du combat
  - #23 [Réseau] 5 événements serveur sans écouteur et 6 fonctions serveur jamais appelées
  - #22 [Docs] ARCHITECTURE.md décrit un limiteur de débit et une API réseau qui n'existent pas
  - #21 [Multijoueur] Parcelles partagées : un seul jeu de socles pour tous les joueurs du serveur
  - #20 [Données] Sauvegarde sans verrou de session, et un échec de GetAsync écrase la vraie sauvegarde
  - #19 [Tests] run_tests.luau recopie les formules au lieu de tester les modules de src/
  - #18 [Bug] Les quêtes ne se terminent jamais : CompleteQuest n'est appelé nulle part
<!-- CTX:AUTO:END -->
