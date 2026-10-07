# Directives agents — Monster Islands (Roblox)

Règles de collaboration pour les agents (Claude / Gemini) sur le jeu Roblox **Monster Islands**.

---

## 📍 0. Contexte vivant (lire en premier)

L'état **dynamique** du projet (focus, en cours, décisions) est maintenu dans
**[`.ai/STATE.md`](.ai/STATE.md)** pour éviter de le re-dériver — et donc de rebrûler des %
de session — à chaque conversation. Il est importé ici :

@.ai/STATE.md

Les skills à utiliser selon la tâche (dont `grill-me`) sont listées dans
[`.ai/SKILLS.md`](.ai/SKILLS.md), importé ci-dessous :

@.ai/SKILLS.md

Convention complète dans [`.ai/README.md`](.ai/README.md). En fin de session, rafraîchir
l'état : `bash .ai/ctx.sh` (ou la commande `/handoff` sous Claude Code).

---

## 🧱 Stack
- Jeu **Roblox** en **Luau** (mode strict), code dans `src/`.
- Build / sync via **Rojo** (`default.project.json`).
- Tests dans `tests/`, outils dans `tools/`, assets dans `assets/`, docs dans `docs/`.
- Remote **GitHub** : `MatteoCnda1/monster-islands-roblox` (branches `main` et `dev`).
- Conventions de branches : développement sur `dev` ou `feature/*`, merge vers `main` pour les releases.

Voir aussi `CONTRIBUTING.md` pour les conventions de contribution existantes.

<!-- Ajoute ici les règles statiques du projet (workflow git, conventions, contraintes). -->
