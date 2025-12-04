#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ "${1:-}" == "--check" ]]; then
    zig fmt --check src/
else
    zig fmt src/
fi
