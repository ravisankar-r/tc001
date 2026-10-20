#!/usr/bin/env bash
# Build the reference Berry interpreter used to run the script tests on the Mac.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/tools/berry-src"
[ -d "$SRC" ] || git clone -q --depth 1 https://github.com/berry-lang/berry "$SRC"
make -C "$SRC" -j4 >/dev/null
cp "$SRC/berry" "$ROOT/tools/berry"
echo "built $ROOT/tools/berry"
