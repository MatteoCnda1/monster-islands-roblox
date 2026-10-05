#!/usr/bin/env bash
set -e

echo "Running Luau static analysis on src/..."
if command -v luau-analyze >/dev/null 2>&1; then
    luau-analyze --mode=nonstrict $(find src -name "*.luau" -o -name "*.lua")
    echo "Luau analysis passed without errors."
else
    echo "luau-analyze not found in PATH."
    exit 1
fi
