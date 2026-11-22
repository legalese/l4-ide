#!/usr/bin/env bash
# Print the path of an `l4` built from `main`, fetching and caching it if need be.
#
# Why this exists: `main` and `unstable` are two compilers (see references/dialects.md in the
# writing-l4-rules skill). An encoding written with an unstable `l4` can be rejected, or read
# differently, by a main build, and the only mechanical way to know is to run a main build over it.
# check.sh does that, and calls this script to get the binary.
#
# Main releases ship no standalone `l4` archive. Each platform's VS Code extension (.vsix, a zip)
# carries the binary at extension/bin/<platform>/l4, so this downloads that platform's vsix,
# unzips that one member, and keeps only the binary.
#
# Usage:  fetch-main-l4.sh [BUILD]
#           BUILD   a build number (97) or a release tag (l4-ide-build-97).
#                   Default: the newest l4-ide-build-* release, by number.
#
# stdout: the path of the binary, and nothing else. Progress, warnings and errors go to stderr.
# The binary is cached at ${XDG_CACHE_HOME:-$HOME/.cache}/l4-main/<build>/l4 and reused.
#
# Fallbacks, each announced on stderr:
#   * offline (the newest-release lookup fails) with no BUILD: the newest build already cached;
#   * the newest release has no package for this platform: the next older release that has one,
#     looking back at most 5 releases.
# With a cold cache and no network it exits 4. To pin a build, give BUILD (check.sh passes
# L4_MAIN_BUILD through).
#
# A build older than 98, the build references/dialects.md is measured at, is still fetched (give
# BUILD, or fall back to an old cached build) but with a warning on stderr: the page's rows may
# not describe it.
#
# Platforms with a main binary: darwin-arm64, linux-x64, linux-arm64. On any other platform
# (Intel macOS, Windows, anything else) this exits 3 and fetches nothing: there is no main build
# to run, so there is no main check to make, and the caller must say so rather than skip it.
#
# WHAT YOU ARE TRUSTING. There is no digest: the release publishes none for the package (only
# jl4-service-linux-x64.sha256, which is for another file). And this script RUNS the downloaded
# binary, `l4 --version`, before it reports the path, to see that it is a main build. So the
# download is trusted to the extent GitHub's release page for legalese/l4-ide is. What it does to
# limit the damage from a bad package: it takes only the one named zip member, refuses it if the
# package marks it as anything but a regular file (a symlink, a directory; an entry with no Unix
# type bits at all is accepted, because that is not a link), checks that what it extracted is a
# regular file reached through real directories, and does not cache a binary whose `--version` is
# not a main build's. A package unzip cannot read is reported as truncated or corrupt.
#
# Uses `gh` when it is installed and works; otherwise `curl` against the public release API.
# The only network calls are GitHub's release endpoints: the list of releases, one release, one
# package. Needs `unzip`. It prints nothing from your environment. Needs a cache directory:
# XDG_CACHE_HOME, or HOME (without either it exits 2).
# Exit status: 0 the path was printed; 2 bad usage or nowhere to cache; 3 no main binary for this
# platform; 4 the download, the unzip or the check of the binary failed.
set -u

REPO="legalese/l4-ide"
TAG_PREFIX="l4-ide-build-"
LOOKBACK=5
# The first main build that answers `l4 --version` (the flag landed on 2026-10-15). A build older
# than this may print nothing for it; a newer one that does is not a real main build.
FIRST_VERSIONED=97
# The build references/dialects.md is measured at. Keep it in step with that page's header.
MINIMUM=98

die() { echo "fetch-main-l4: $1" >&2; exit "${2:-4}"; }
warn() { echo "fetch-main-l4: warning: $1" >&2; }
old_note() { warn "build $1 is older than $MINIMUM, the minimum references/dialects.md is measured at; its rows may not describe it."; }

case "${1:-}" in
  -h|--help) sed -n '2,/^set -u/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//' >&2; exit 0 ;;
esac
[ $# -le 1 ] || die "usage: fetch-main-l4.sh [BUILD]" 2

# --- platform ---------------------------------------------------------------------------------
os="$(uname -s 2>/dev/null)"; arch="$(uname -m 2>/dev/null)"
case "$os/$arch" in
  Darwin/arm64)                platform=darwin-arm64 ;;
  Linux/x86_64)                platform=linux-x64 ;;
  Linux/aarch64|Linux/arm64)   platform=linux-arm64 ;;
  *) die "no main build for $os/$arch. Main releases carry binaries for darwin-arm64, linux-x64 and linux-arm64 only, so the main check cannot be made here." 3 ;;
esac

command -v unzip >/dev/null 2>&1 || die "unzip is needed to take the binary out of the extension package." 4

have_gh=0; have_curl=0
command -v gh >/dev/null 2>&1 && have_gh=1
command -v curl >/dev/null 2>&1 && have_curl=1
[ "$have_gh" = 1 ] || [ "$have_curl" = 1 ] || die "neither gh nor curl is available to download with." 4

# --- the cache --------------------------------------------------------------------------------
base="${XDG_CACHE_HOME:-}"
if [ -z "$base" ]; then
  [ -n "${HOME:-}" ] || die "neither XDG_CACHE_HOME nor HOME is set, so there is nowhere to cache the binary. Set XDG_CACHE_HOME." 2
  base="$HOME/.cache"
fi
root="$base/l4-main"

# --- which build ------------------------------------------------------------------------------
want="${1:-}"
want="${want#"$TAG_PREFIX"}"
if [ $# -eq 1 ]; then
  case "$want" in ""|*[!0-9]*) die "BUILD must be a number such as 97 or a tag such as ${TAG_PREFIX}97, not '$1'." 2 ;; esac
fi

[ -z "$want" ] || [ "$want" -ge "$MINIMUM" ] || old_note "$want"

work=""
trap '[ -n "$work" ] && rm -rf -- "$work"' EXIT

# fetch_build N: put build N in the cache and print its path. Returns 0 on success,
#   5 the release has no package for this platform,
#   6 there is no such release,
#   7 the download failed (network, rate limit, or gh); the message has been printed,
#   8 the package is not acceptable (not a regular file, or not a main build); the message has been printed.
fetch_build() {
  n="$1"; tag="${TAG_PREFIX}${n}"; dest="$root/$n/l4"
  if [ -x "$dest" ]; then printf '%s\n' "$dest"; return 0; fi
  mkdir -p "$root" || die "cannot create $root" 4
  [ -n "$work" ] && rm -rf -- "$work"
  work="$(mktemp -d "$root/.fetch.XXXXXX")" || die "cannot make a work directory under $root" 4
  echo "fetch-main-l4: fetching $tag ($platform)" >&2
  vsix=""
  if [ "$have_gh" = 1 ]; then
    if gh release download "$tag" --repo "$REPO" -p "l4-vscode-${platform}-*.vsix" -D "$work" >/dev/null 2>"$work/gh.err"; then
      vsix="$(ls "$work"/l4-vscode-"${platform}"-*.vsix 2>/dev/null | head -n 1)"
    else
      if grep -qi 'release not found' "$work/gh.err"; then return 6; fi
      if grep -qi 'no assets match' "$work/gh.err"; then return 5; fi
      # Anything else (no network, not signed in, a gh bug): try curl before giving up.
      if [ "$have_curl" = 0 ]; then
        echo "fetch-main-l4: network failure or gh error: gh could not download $tag: $(tail -n 1 "$work/gh.err" | cut -c1-150)" >&2
        return 7
      fi
    fi
  fi
  if [ -z "$vsix" ] && [ "$have_curl" = 1 ]; then
    code="$(curl -sS --connect-timeout 20 --max-time 120 -o "$work/rel.json" -w '%{http_code}' "https://api.github.com/repos/$REPO/releases/tags/$tag" 2>"$work/curl.err")" || code=000
    case "$code" in
      200) ;;
      404) return 6 ;;
      000) echo "fetch-main-l4: network failure: could not reach api.github.com to look up $tag." >&2; return 7 ;;
      *)   echo "fetch-main-l4: GitHub answered HTTP $code to the lookup of $tag (a rate limit, if 403 or 429)." >&2; return 7 ;;
    esac
    url="$(grep -o "\"browser_download_url\": *\"[^\"]*l4-vscode-${platform}-[^\"]*\\.vsix\"" "$work/rel.json" | head -n 1 | sed 's/.*"\(https[^"]*\)"/\1/')"
    [ -n "$url" ] || return 5
    if ! curl -fsSL --connect-timeout 20 --max-time 900 -o "$work/l4.vsix" "$url" 2>"$work/curl.err"; then
      echo "fetch-main-l4: network failure: the download of $url failed." >&2
      return 7
    fi
    vsix="$work/l4.vsix"
  fi
  if [ -z "$vsix" ] || [ ! -s "$vsix" ]; then
    echo "fetch-main-l4: could not download the $platform package of $tag." >&2
    return 7
  fi

  # --- take out the one binary, and only if it is a regular file ------------------------------
  member="extension/bin/${platform}/l4"
  if ! listing="$(unzip -Z -1 "$vsix" 2>/dev/null)"; then
    echo "fetch-main-l4: $tag's package is truncated or corrupt: unzip cannot read it." >&2
    return 8
  fi
  if ! printf '%s\n' "$listing" | grep -qxF "$member"; then
    echo "fetch-main-l4: $tag's package has no $member." >&2
    return 8
  fi
  entry="$(unzip -Z "$vsix" "$member" 2>/dev/null | head -n 1)"
  case "$entry" in
    -*) ;;
    # No Unix type bits (a package made on another system): not a link, so go on to the checks of what is on disk.
    \?*) ;;
    *)  echo "fetch-main-l4: $tag's $member is not a regular file in the package (its entry reads '$(printf '%s' "$entry" | cut -c1-60)'). Refusing it." >&2; return 8 ;;
  esac
  mkdir "$work/x" || die "cannot make a directory under $work" 4
  unzip -o -q "$vsix" "$member" -d "$work/x" 2>/dev/null
  bin="$work/x/$member"
  # Whatever the package said, what is on disk must be a regular file reached through real directories.
  p="$work/x"
  for part in extension bin "$platform" l4; do
    p="$p/$part"
    if [ -L "$p" ]; then echo "fetch-main-l4: $tag's package put a symbolic link at $part. Refusing it." >&2; return 8; fi
  done
  [ -f "$bin" ] || { echo "fetch-main-l4: $tag's package did not give a regular file at $member." >&2; return 8; }
  chmod +x "$bin"
  [ "$os" = Darwin ] && command -v xattr >/dev/null 2>&1 && xattr -c "$bin" 2>/dev/null

  # --- it must be a main build ----------------------------------------------------------------
  ver="$("$bin" --version 2>/dev/null | head -n 1)"
  case "$ver" in
    [0-9]*"(main,"*) ;;
    "")
      if [ "$n" -lt "$FIRST_VERSIONED" ]; then
        warn "$tag's l4 does not answer --version, which a build before $FIRST_VERSIONED may not; using it as a main build."
      else
        echo "fetch-main-l4: $tag's l4 prints nothing for --version, and a main build $FIRST_VERSIONED or later does. Not using it." >&2
        return 8
      fi ;;
    *) echo "fetch-main-l4: $tag's l4 says '$ver', which is not a main build. Not using it." >&2; return 8 ;;
  esac

  mkdir -p "$root/$n" || die "cannot create $root/$n" 4
  mv "$bin" "$dest.new.$$" && mv "$dest.new.$$" "$dest" || die "cannot place the binary at $dest" 4
  echo "fetch-main-l4: $tag is ${ver:-unversioned}, cached at $dest" >&2
  printf '%s\n' "$dest"
  return 0
}

fail_with() { # fail_with TAG CODE: the message for a code fetch_build returned without saying anything itself
  case "$2" in
    5) die "$1 has no package for $platform." 4 ;;
    6) die "$1 does not exist on $REPO (is the build number right?)." 4 ;;
    *) exit 4 ;;
  esac
}

if [ -n "$want" ]; then
  fetch_build "$want"; rc=$?
  [ "$rc" = 0 ] && exit 0
  fail_with "${TAG_PREFIX}${want}" "$rc"
fi

# --- the newest build: look the releases up (newest by NUMBER, not by position in a listing) ----
tags=""
[ "$have_gh" = 1 ] && tags="$(gh release list --repo "$REPO" --limit 100 --json tagName --jq '.[].tagName' 2>/dev/null)"
if [ -z "$tags" ] && [ "$have_curl" = 1 ]; then
  tags="$(curl -fsSL --connect-timeout 20 --max-time 120 "https://api.github.com/repos/$REPO/releases?per_page=100" 2>/dev/null | grep -o "\"tag_name\": *\"${TAG_PREFIX}[0-9]*\"" | grep -o "${TAG_PREFIX}[0-9]*")"
fi
numbers="$(printf '%s\n' "$tags" | grep -E "^${TAG_PREFIX}[0-9]+\$" | sed "s/^${TAG_PREFIX}//" | sort -rn | head -n "$LOOKBACK")"

if [ -z "$numbers" ]; then
  # Offline, or the lookup failed. A warm cache still has a build we can use.
  cached="$(ls "$root" 2>/dev/null | grep -E '^[0-9]+$' | sort -n | tail -n 1)"
  if [ -n "$cached" ] && [ -x "$root/$cached/l4" ]; then
    warn "could not look up the newest release (network failure?); using the newest build already cached, ${TAG_PREFIX}${cached}. It may not be the newest main build."
    [ "$cached" -ge "$MINIMUM" ] || old_note "$cached"
    printf '%s\n' "$root/$cached/l4"
    exit 0
  fi
  die "could not look up the newest ${TAG_PREFIX}* release of $REPO, and no build is cached under $root. Is there a network? Give BUILD to name one." 4
fi

newest="$(printf '%s\n' "$numbers" | head -n 1)"
for n in $numbers; do
  fetch_build "$n"; rc=$?
  if [ "$rc" = 0 ]; then
    [ "$n" = "$newest" ] || warn "${TAG_PREFIX}${newest} has no package for $platform; used the next older release that has one, ${TAG_PREFIX}${n}."
    [ "$n" -ge "$MINIMUM" ] || old_note "$n"
    exit 0
  fi
  [ "$rc" = 5 ] || fail_with "${TAG_PREFIX}${n}" "$rc"
  echo "fetch-main-l4: ${TAG_PREFIX}${n} has no package for $platform; looking at the next older release." >&2
done
die "none of the newest $LOOKBACK releases has a package for $platform." 4
