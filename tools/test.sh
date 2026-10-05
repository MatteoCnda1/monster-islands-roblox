#!/usr/bin/env bash
set -e

echo "Running Monster Islands Test Suite..."
if command -v luau >/dev/null 2>&1; then
    luau tests/run_tests.luau
else
    /home/matteo/.cargo/bin/luau tests/run_tests.luau
fi
