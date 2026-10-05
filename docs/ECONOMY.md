# Monster Islands — Conception Économique

## 1. Monnaies de Base

### 1. Coins (Pièces d'Or)
Monnaie principale accessible gratuitement en jeu.
- **Sources** :
  - Victoires en combat (PvE et PvP) : 25 à 150 Coins
  - Quêtes quotidiennes et jalons de progression : 100 à 500 Coins
  - Production passive des habitats de monstres sur les parcelles.
- **Dépenses (Sinks)** :
  - Achat de nouvelles parcelles (ex: 250, 750, 2000 Coins)
  - Coût d'incubation / breeding
  - Amélioration de bâtiments et déblocage de compétences.

### 2. Gems (Gemmes Précieuses)
Monnaie de prestige et de confort.
- **Sources** :
  - Déblocage de hauts faits et victoires d'arène majeures
  - Connexion consécutive (Daily Rewards)
  - Achats optionnels via Robux (Developer Products).
- **Dépenses** :
  - Cosmétiques exclusifs (skins d'île, particules pour monstres)
  - Accélération d'incubation (gain de temps sans avantage de puissance brut)
  - Emplacements d'inventaire supplémentaires.

---

## 2. Coût et Déblocage des Parcelles

| Parcelle | Coût (Coins) | Coût (Gems) | Niveau Requis | Description |
|---|---|---|---|---|
| Parcelle 1 | Gratuit (0) | 0 | 1 | Espace de départ, abrite vos 2 premiers monstres |
| Parcelle 2 | 250 | 0 | 2 | Permet de construire le Couvoir d'incubation |
| Parcelle 3 | 750 | 0 | 4 | Emplacement pour le Centre de Reproduction |
| Parcelle 4 | 2,000 | 0 | 6 | Espace pour un habitat élémentaire supplémentaire |
| Parcelle 5 | 5,000 | 25 | 10 | Grande extension de territoire pour monstres épiques |

---

## 3. Sécurité Économique & Atomicité

Toute modification de solde s'effectue via `EconomyService` à l'aide de méthodes atomiques :
```lua
EconomyService:AddCoins(player: Player, amount: number, reason: string): boolean
EconomyService:DeductCoins(player: Player, amount: number, reason: string): boolean
```
- Vérification systématique que `amount > 0` et `not (amount ~= amount)` (rejet de NaN et infinis).
- Déduction rejetée si `balance < amount`, garantissant qu'aucun solde ne passe en négatif.
- Traçabilité complète via le `Logger` avec motif explicite.
