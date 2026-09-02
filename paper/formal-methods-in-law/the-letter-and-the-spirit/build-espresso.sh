#!/usr/bin/env bash
# Build the genuine Berkeley Espresso two-level logic minimiser (modern rehost)
# and install it. The original pyeda wrapper no longer compiles on current
# clang; this rehost does. Reproducible: clone + make + copy.
#
#   ./build-espresso.sh            # installs to ~/.local/bin/espresso
#   ./build-espresso.sh /usr/local/bin
set -euo pipefail
DEST="${1:-$HOME/.local/bin}"
REPO="https://github.com/classabbyamp/espresso-logic.git"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "cloning $REPO ..."
git clone --depth 1 "$REPO" "$TMP/espresso-logic"
echo "building (make) ..."
make -C "$TMP/espresso-logic/espresso-src" >/dev/null
mkdir -p "$DEST"
cp "$TMP/espresso-logic/bin/espresso" "$DEST/espresso"
echo "installed: $DEST/espresso"
"$DEST/espresso" --version 2>/dev/null || echo "(run 'espresso' on a .pla file; see REPRODUCE.md)"
