# `assets/` — Assets du jeu (structure prévue)

> **État actuel : aucun asset n'est versionné ici.** Tous les modèles du jeu (île et carte
> `Workspace.WorldMap`, monstres, œufs, décorations de parcelles, arène PvP…) sont **générés
> procéduralement en code** au démarrage (`ServerBootstrap.server.luau`,
> `MonsterService.buildProceduralMonsterModel`, etc.). Les sous-dossiers ci-dessous ne contiennent
> qu'un `.gitkeep` pour que Git conserve l'arborescence.

Ce dossier n'est **pas** mappé par Rojo (`default.project.json` ne synchronise que `src/shared`,
`src/server` et `src/client`). Le jour où des assets réels seront ajoutés (fichiers `.rbxm`,
animations…), il faudra les y déclarer, par exemple sous `ReplicatedStorage.Assets`, et adapter le
code pour charger le modèle plutôt que de le générer.

## Arborescence prévue

| Dossier | Contenu prévu | Nomenclature (cf. [`docs/ART_DIRECTION.md`](../docs/ART_DIRECTION.md)) |
|---|---|---|
| `monsters/` | Modèles 3D des créatures (un par espèce) | `Monster_<SpeciesId>` — ex. `Monster_Emberfox` |
| `animations/` | Jeu d'animations standard par monstre : `Idle`, `Walk`, `Run`, `Attack`, `Hit`, `KO`, `Victory` | non fixée (proposition : `<SpeciesId>_<Animation>`) |
| `buildings/` | Bâtiments et habitats (couvoir, centre de reproduction, habitats élémentaires) | `Building_<BuildingId>`, `Habitat_<Element>` |
| `props/` | Décors et décorations de parcelles (arbres, rochers, lanternes…) | `Prop_<Category>_<Id>_<Index>` — ex. `Prop_Tree_Oak_01` |
| `environments/` | Terrain et zones (île principale, futures zones Volcan, Forêt Mystique, Toundra Givrée) | non fixée |
| `ui/` | Icônes et images d'interface | `UI_Icon_<Name>` — ex. `UI_Icon_Coin` |

## Conventions de modélisation (rappel)

Voir [`docs/ART_DIRECTION.md`](../docs/ART_DIRECTION.md) pour le détail :

- Style stylisé low/mid-poly, couleurs vives par élément, matériaux `SmoothPlastic` / `Neon`.
- `PrimaryPart` nommée `HumanoidRootPart` (ou `RootPart`), face avant orientée vers **-Z**,
  pivot centré au niveau du sol.
- Gabarits de créatures Small / Medium / Large (hauteur et emprise au sol en studs).
