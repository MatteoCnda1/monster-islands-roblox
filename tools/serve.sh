#!/usr/bin/env bash
set -e

# Run Rojo live server for Roblox Studio plugin sync
PORT=${1:-34872}
echo "Starting Rojo server on port $PORT..."
rojo serve --port "$PORT" default.project.json
