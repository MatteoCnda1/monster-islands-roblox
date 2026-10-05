# Monster Islands — Système de Génétique et Breeding

## 1. Principes de la Reproduction

Le système de reproduction (**Breeding**) est l'un des piliers centraux de progression.
Deux monstres compatibles placés dans le Centre de Reproduction génèrent un œuf doté de caractéristiques génétiques héritées et d'une probabilité de mutation.

---

## 2. Règles de Compatibilité et Détermination de l'Espèce

Deux monstres peuvent se reproduire si :
1. Ils appartiennent au même joueur et sont disponibles (non engagés dans un combat).
2. Leurs éléments respectifs figurent dans les listes de compatibilité de `MonsterDefinitions.luau`.

### Arbre de Résolution de l'Espèce de l'Œuf
```text
Parent A (Éléments: E_A)  +  Parent B (Éléments: E_B)
                           |
            [ Test Mutation Rare (5% à 8%) ]
            /                              \
       OUI                                 NON
        |                                   |
Espèce Mutation Spéciale        Tirage Pondéré :
(Ex: Fire + Shadow -> Voidfox)  - 45% Héritage Espèce Parent A
                                - 45% Héritage Espèce Parent B
                                - 10% Hybride Éléments (E_A + E_B)
```

---

## 3. Héritage des Statistiques Génétiques (IVs)

Chaque statistique (`Health`, `Attack`, `Defense`, `Speed`) possède une valeur individuelle (IV) comprise entre 0 et 15.
Lors de la reproduction :
1. Pour chaque statistique, la valeur est transmise selon la formule :
   $$\text{IV}_{\text{Enfant}} = \text{math.clamp}\left(\text{math.round}\left(\frac{\text{IV}_{\text{ParentA}} + \text{IV}_{\text{ParentB}}}{2}\right) + \text{random}(-2, 2), 0, 15\right)$$
2. **Mutation Génétique Spontanée (1%)** : L'un des IVs peut bondir directement à la valeur maximale (15).

---

## 4. Cycle de Reproduction et Incubation

```text
Placement des Parents -> Phase de Romance (Timer ex: 120s) -> Production de l'Œuf
                                                                      |
Éclosion dans l'Incubateur <- Incubation (Timer ex: 60s) <------------+
       |
Nouvelle Créature ajoutée à la Collection du Joueur
```

Les temps sont calculés côté serveur via timestamps UNIX (`os.time()`).
Même si le joueur se déconnecte, le décompte continue normalement.
