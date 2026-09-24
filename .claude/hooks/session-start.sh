#!/bin/bash
# SessionStart hook: install the Haskell toolchain in Claude Code cloud sessions.
#
# A cloud container starts with no GHC, so `cabal build` cannot run until
# someone installs one by hand. A developer's own machine already has a
# toolchain, so this exits at once unless CLAUDE_CODE_REMOTE=true.
#
# The version is the one CLAUDE.md §3 pins (GHC 9.10.2). Every step checks
# before it installs, so a resumed or cached container pays a few stat calls.
#
# What this does NOT do: build the Hackage dependencies or jl4-core. That is
# the long part (tens of minutes), and running it here would either block the
# session from starting or, run in the background, race the session's own
# `cabal build` in the same dist-newstyle (CLAUDE.md §2.1).
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

GHC_VERSION=9.10.2
GHCUP_BIN="$HOME/.ghcup/bin"

# libgmp: GHC links every program against it. libnuma: the RTS wants it.
missing=()
for pkg in libgmp-dev libnuma-dev; do
  dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
done
if [ ${#missing[@]} -gt 0 ]; then
  # Try without `apt-get update` first: the image's lists are usually fresh
  # enough, and the update is the slow half.
  apt-get install -y -qq "${missing[@]}" >/dev/null 2>&1 || {
    apt-get update -qq >/dev/null
    apt-get install -y -qq "${missing[@]}" >/dev/null
  }
fi

if [ ! -x "$GHCUP_BIN/ghcup" ]; then
  curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org |
    BOOTSTRAP_HASKELL_NONINTERACTIVE=1 \
      BOOTSTRAP_HASKELL_MINIMAL=1 \
      BOOTSTRAP_HASKELL_ADJUST_BASHRC=0 \
      sh >/dev/null
fi

if ! "$GHCUP_BIN/ghcup" whereis ghc "$GHC_VERSION" >/dev/null 2>&1; then
  "$GHCUP_BIN/ghcup" install ghc "$GHC_VERSION" >/dev/null
fi
"$GHCUP_BIN/ghcup" set ghc "$GHC_VERSION" >/dev/null 2>&1

if [ ! -x "$GHCUP_BIN/cabal" ]; then
  "$GHCUP_BIN/ghcup" install cabal recommended --set >/dev/null
fi

# cabal.project pins an index-state, so a store with no index cannot resolve
# the plan at all. Fetch it once; after that the pin makes refreshing moot.
if [ ! -d "$HOME/.cache/cabal/packages/hackage.haskell.org" ]; then
  "$GHCUP_BIN/cabal" update >/dev/null
fi

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$GHCUP_BIN:\$PATH\"" >>"$CLAUDE_ENV_FILE"
fi

# SessionStart stdout becomes session context: say what is now available.
echo "Haskell toolchain ready: $("$GHCUP_BIN/ghc" --numeric-version | sed 's/^/GHC /'), $("$GHCUP_BIN/cabal" --numeric-version | sed 's/^/cabal /'), on PATH via $GHCUP_BIN. Dependencies are not prebuilt; the first cabal build compiles them."
