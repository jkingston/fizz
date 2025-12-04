#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Checking format..."
./scripts/fmt.sh --check

echo "Building..."
zig build

echo "Running tests..."
./scripts/test.sh

echo "All checks passed!"
