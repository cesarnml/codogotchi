#!/usr/bin/env bash
#
# Compile the standalone Codogotchi CLI binaries.
#
# Produces two self-contained arm64 executables (the Bun runtime is embedded, so
# there is no PATH or workspace-runtime prerequisite at run time):
#
#   codogotchi        — the user-facing CLI (packages/cli/bin/codogotchi.ts)
#   codogotchi-hook   — the per-event hook entrypoint (packages/cli/bin/codogotchi-hook.ts)
#
# Usage:
#   scripts/build-binaries.sh [OUTPUT_DIR]
#
# OUTPUT_DIR defaults to apps/menubar/Generated/binaries. The Xcode build phase
# passes the app bundle's Resources directory so the binaries are embedded
# directly into Codogotchi.app/Contents/Resources/.
#
# arm64-only for v1. Intel/universal is a documented fast-follow (see
# docs/product/delivery/phase-08/ticket-01-compile-bundle-binaries.md).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="${1:-$REPO_ROOT/apps/menubar/Generated/binaries}"

# Xcode run-script phases do not inherit the interactive login PATH, so locate
# bun explicitly before falling back to common install locations.
BUN_BIN="$(command -v bun || true)"
if [ -z "$BUN_BIN" ]; then
  for candidate in "$HOME/.bun/bin/bun" /opt/homebrew/bin/bun /usr/local/bin/bun; do
    if [ -x "$candidate" ]; then
      BUN_BIN="$candidate"
      break
    fi
  done
fi
if [ -z "$BUN_BIN" ]; then
  echo "error: bun not found on PATH or in ~/.bun/bin, /opt/homebrew/bin, /usr/local/bin." >&2
  echo "       Install bun (https://bun.sh) before building the standalone binaries." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

build_one() {
  local entry="$1"
  local name="$2"
  "$BUN_BIN" build --compile --target=bun-darwin-arm64 \
    "$REPO_ROOT/packages/cli/bin/$entry" \
    --outfile "$OUT_DIR/$name"
  chmod +x "$OUT_DIR/$name"
}

build_one codogotchi.ts codogotchi
build_one codogotchi-hook.ts codogotchi-hook

echo "Built standalone binaries into $OUT_DIR:"
echo "  $OUT_DIR/codogotchi"
echo "  $OUT_DIR/codogotchi-hook"
