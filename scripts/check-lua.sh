#!/usr/bin/env bash
set -euo pipefail

echo "Checking Lua syntax..."

find . \
  -name "*.lua" \
  -not -path "./.git/*" \
  -print0 | while IFS= read -r -d '' file; do
    echo "  luac5.1 -p $file"
    luac5.1 -p "$file"
  done

echo "Lua syntax check passed."
