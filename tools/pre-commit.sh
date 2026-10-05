#!/usr/bin/env bash
set -e

echo "=== [Git Pre-Commit Hook] Vérification de la rigueur du code ==="

# 1. Vérification des tests unitaires
echo "1. Exécution des tests unitaires (Luau)..."
./tools/test.sh

# 2. Vérification de la compilation Rojo
echo "2. Vérification de la compilation de la place Roblox (Rojo build)..."
./tools/build.sh > /dev/null

echo "=== ✓ Toutes les vérifications de qualité sont validées. Commit autorisé. ==="
