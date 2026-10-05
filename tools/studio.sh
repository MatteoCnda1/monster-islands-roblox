#!/usr/bin/env bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLACE_FILE="$PROJECT_DIR/build/MonsterIslands.rbxl"

# Rebuild place to ensure it is up-to-date
"$PROJECT_DIR/tools/build.sh" "$PLACE_FILE"

echo "Launching Roblox Studio via Vinegar..."
flatpak run org.vinegarhq.Vinegar "$PLACE_FILE"
