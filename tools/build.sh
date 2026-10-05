#!/usr/bin/env bash
set -e

mkdir -p build
OUTPUT="${1:-build/MonsterIslands.rbxl}"
echo "Building Roblox place file to $OUTPUT..."
rojo build default.project.json --output "$OUTPUT"
echo "Build complete: $OUTPUT"
