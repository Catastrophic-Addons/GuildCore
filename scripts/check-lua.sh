#!/usr/bin/env bash
set -euo pipefail

echo "Checking Lua syntax..."

compiler=""
compiler_mode="luac"
for candidate in luac5.1 luac; do
  if command -v "$candidate" >/dev/null 2>&1; then
    compiler="$candidate"
    break
  fi
done
if [[ -z "$compiler" ]] && command -v lua >/dev/null 2>&1; then
  compiler="lua"
  compiler_mode="lua"
fi

if [[ -z "$compiler" ]]; then
  echo "No Lua compiler found. Install luac5.1, luac, or lua to run syntax checks." >&2
  exit 127
fi

find . \
  -name "*.lua" \
  -not -path "./.git/*" \
  -print0 | while IFS= read -r -d '' file; do
    if [[ "$compiler_mode" == "lua" ]]; then
      echo "  lua loadfile $file"
      "$compiler" -e 'assert(loadfile(arg[1]))' "$file"
    else
      echo "  $compiler -p $file"
      "$compiler" -p "$file"
    fi
  done

echo "Lua syntax check passed."
