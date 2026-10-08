# Monster Islands — Direction Artistique & Pipeline 3D

## 1. Vision Visuelle & Style

Le style de **Monster Islands** est résolument **stylisé, chaleureux et lisible** :
- **Silhouettes fortes et distinctes** : Chaque monstre doit être immédiatement reconnaissable de loin ou sur mobile à sa forme extérieure.
- **Faible à moyenne complexité polygonale** (Low/Mid-poly optimisé pour Roblox).
- **Couleurs vives et saturées** : Chaque élément possède une identité chromatique marquée.
- **Matériaux Roblox adaptés** : Utilisation privilégiée de `SmoothPlastic`, `Neon` subtil pour les runes ou yeux magiques, et `Wood`/`Grass` pour les décors insulaires.

---

## 2. Échelles et Conventions de Modélisation

Dans l'univers Roblox :
- 1 stud $\approx 28\text{ cm}$.
- Un personnage Roblox standard mesure environ 5 studs de hauteur.

### Gabarits de Créatures
| Gabarit | Exemples | Hauteur (Studs) | Emprise au Sol | Utilisation |
|---|---|---|---|---|
| **Small** | `Emberfox`, `Zephlyn` | 3.5 à 5.0 | 4x4 studs | Créatures véloces, agiles |
| **Medium** | `Aquaphin`, `Noctyra`, `Voidfox` | 5.0 à 6.5 | 6x6 studs | Combattants équilibrés |
| **Large** | `Mossaur` | 7.0 à 9.5 | 8x8 studs | Tanks, géants colossaux |

### Pivot et Orientation
- **PrimaryPart** : Chaque modèle possède une pièce maîtresse nommée `HumanoidRootPart` (ou `RootPart`), ancrée ou motorisée selon l'usage.
- **Orientation avant** : L'axe avant de la créature doit rigoureusement pointer vers **-Z** (standard Roblox).
- **Pivot au sol** : Le point de pivot (Pivot point) est positionné au centre horizontal et exactement au niveau du sol (`Y = 0` des pattes).

---

## 3. Charte Chromatique par Élément

| Élément | Couleur Primaire (Hex) | Couleur Secondaire (Hex) | Accents Lumineux (Neon) |
|---|---|---|---|
| **Fire** | `#E25822` (Braises vives) | `#F88379` (Pêche corail) | `#FF4500` (Flammes) |
| **Nature**| `#2E8B57` (Vert forêt) | `#8FBC8F` (Vert sauge) | `#7CFC00` (Spores vives) |
| **Water** | `#1E90FF` (Bleu azur) | `#87CEEB` (Bleu ciel) | `#00FFFF` (Gouttes d'eau) |
| **Wind**  | `#00CED1` (Turquoise vent)| `#E0FFFF` (Brume claire) | `#F0F8FF` (Courants d'air)|
| **Shadow**| `#4B0082` (Indigo sombre) | `#9370DB` (Violet mystique)| `#DA70D6` (Flamme noire) |

---

## 4. Nomenclature des Assets

Pour assurer l'interopérabilité entre les artistes 3D et le code :
```text
Monster_<SpeciesId>              Ex: Monster_Emberfox, Monster_Mossaur
Building_<BuildingId>            Ex: Building_Hatchery, Building_BreedingCenter
Habitat_<Element>                Ex: Habitat_Fire, Habitat_Nature
Prop_<Category>_<Id>_<Index>     Ex: Prop_Tree_Oak_01, Prop_Rock_Mossy_02
UI_Icon_<Name>                   Ex: UI_Icon_Coin, UI_Icon_Element_Fire
```

---

## 5. Jeu d'Animations Standard

Chaque monstre dispose à terme de 7 animations fondamentales :
1. `Idle` : Respiration et mouvements d'écoute (queue, oreilles, ailes).
2. `Walk` : Déplacement régulier sur la parcelle.
3. `Run` : Course pour le combat ou les attaques rapprochées.
4. `Attack` : Déclenchement de compétence ou morsure/griffe.
5. `Hit` : Réaction d'impact lors de la réception de dégâts.
6. `KO` : Chute au sol ou dissipation stylisée.
7. `Victory` : Cri de célébration ou saut festif.
