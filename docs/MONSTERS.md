# Monster Islands — Conception et Registre des Monstres

## 1. Structure de Données d'un Monstre (Data-Driven)

Chaque espèce de créature est définie de façon déclarative. Le script n'embarque aucune logique codée en dur par espèce.

### Définition d'Espèce (`MonsterDefinition`)
```lua
export type MonsterDefinition = {
    Id: string,
    DisplayName: string,
    Description: string,
    Rarity: "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary",
    Elements: { string },
    BaseStats: {
        Health: number,
        Attack: number,
        Defense: number,
        Speed: number,
    },
    Growth: {
        Health: number,
        Attack: number,
        Defense: number,
        Speed: number,
    },
    Breeding: {
        CompatibleElements: { string },
        BreedingTime: number, -- Secondes
        IncubationTime: number, -- Secondes
    },
    Skills: { string },
    ModelTemplateName: string,
}
```

### Instance Possédée par un Joueur (`MonsterInstance`)
```lua
export type MonsterInstance = {
    UUID: string,
    SpeciesId: string,
    Nickname: string?,
    Level: number,
    XP: number,
    CurrentHealth: number,
    IVs: {
        Health: number, -- Bonus génétique de 0 à 15
        Attack: number,
        Defense: number,
        Speed: number,
    },
    SkillsEquipped: { string },
    Parents: { string }?, -- [UUID1, UUID2]
    Generation: number,
    AssignedPlotId: number?,
}
```

---

## 2. Formule de Calcul des Statistiques

Au niveau `Level` avec les IVs (Individual Values) héréditaires :
$$\text{Stat} = \text{BaseStat} + (\text{Growth} \times (\text{Level} - 1)) + \text{IV}$$

$$\text{HealthMax} = \text{BaseHealth} \times 2 + (\text{GrowthHealth} \times (\text{Level} - 1) \times 1.5) + \text{IV} \times 3$$

Ce système assure que :
1. Les créatures progressent de façon gratifiante à chaque niveau.
2. Deux créatures de la même espèce ont des variations génétiques subtiles perceptibles par les éleveurs optimisateurs.

---

## 3. Les 6 Monstres Prototypes

Le registre (`src/shared/MonsterDefinitions.luau`) compte **5 espèces de base** et **1 espèce de mutation** (`Voidfox`), obtenue uniquement par reproduction.

### 1. Emberfox
- **ID** : `emberfox`
- **Nom** : Emberfox
- **Rareté** : Rare
- **Élément** : Fire
- **Description** : Un petit canidé agile dont la queue flamboyante s'embrase lorsqu'il ressent le frisson du combat.
- **BaseStats** : Health 95, Attack 28, Defense 14, Speed 24
- **Growth** : Health 9, Attack 4.2, Defense 2.2, Speed 3.5
- **Compétences** : `FlameBurst`, `QuickStrike`

### 2. Mossaur
- **ID** : `mossaur`
- **Nom** : Mossaur
- **Rareté** : Uncommon
- **Éléments** : Nature, Earth
- **Description** : Un reptile massif recouvert d'une carapace de roche et de mousse vivante, doué d'une résistance impressionnante.
- **BaseStats** : Health 135, Attack 20, Defense 26, Speed 12
- **Growth** : Health 14, Attack 2.8, Defense 4.5, Speed 1.4
- **Compétences** : `BrambleSlam`, `StoneShield`

### 3. Aquaphin
- **ID** : `aquaphin`
- **Nom** : Aquaphin
- **Rareté** : Rare
- **Élément** : Water
- **Description** : Une créature aquatique élancée capable de glisser sur les flux d'eau avec une grâce et une fluidité remarquables.
- **BaseStats** : Health 105, Attack 24, Defense 18, Speed 22
- **Growth** : Health 10, Attack 3.5, Defense 2.8, Speed 3.0
- **Compétences** : `WaterSurge`, `BubbleGuard`

### 4. Zephlyn
- **ID** : `zephlyn`
- **Nom** : Zephlyn
- **Rareté** : Rare
- **Élément** : Wind
- **Description** : Un hybride oiseau-dragon miniature qui chevauche les courants thermiques et fond sur ses cibles avec une vitesse fulgurante.
- **BaseStats** : Health 90, Attack 26, Defense 13, Speed 28
- **Growth** : Health 8, Attack 3.9, Defense 2.0, Speed 4.2
- **Compétences** : `GaleSlash`, `Tailwind`

### 5. Noctyra
- **ID** : `noctyra`
- **Nom** : Noctyra
- **Rareté** : Epic
- **Élément** : Shadow
- **Description** : Une panthère ailée spectrale qui se déplace sans un bruit dans la pénombre pour asséner des coups perçants.
- **BaseStats** : Health 98, Attack 32, Defense 15, Speed 25
- **Growth** : Health 9.5, Attack 4.8, Defense 2.3, Speed 3.6
- **Compétences** : `ShadowClaw`, `VoidPulse`

### 6. Voidfox *(espèce de mutation)*
- **ID** : `voidfox`
- **Nom** : Voidfox
- **Rareté** : Legendary
- **Éléments** : Fire, Shadow
- **Description** : Une mutation légendaire née du Feu et de l'Ombre. Ses flammes sombres et spectrales consument toute matière.
- **Obtention** : Uniquement par reproduction `Emberfox` + `Noctyra` (dans un sens ou dans l'autre), avec une probabilité de mutation de `Config.BREEDING.BASE_MUTATION_CHANCE` (8 %). Voir [BREEDING.md](BREEDING.md).
- **BaseStats** : Health 115, Attack 36, Defense 19, Speed 29
- **Growth** : Health 11, Attack 5.2, Defense 2.9, Speed 4.0
- **Compétences** : `FlameBurst`, `VoidPulse`
