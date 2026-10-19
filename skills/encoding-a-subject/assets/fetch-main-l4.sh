#!/usr/bin/env bash
# Print the path of an `l4` built from `main`, fetching and caching it if need be.
#
# Why this exists: `main` and `unstable` are two compilers (see references/dialects.md in the
# writing-l4-rules skill). An encoding written with an unstable `l4` can be rejected, or read
# differently, by a main build, and the only mechanical way to know is to run a main build over it.
# check.sh does that, and calls this script to get the binary.
#
# Main releases ship no standalone `l4` archive. Each platform's VS Code extension (.vsix, a zip)
# carries the binary at extension/bin/<platform>/l4, so this downloads that one file's vsix,
# unzips that one member, and keeps only the binary.
#
# Usage:  fetch-main-l4.sh [BUILD]
#           BUILD   a build number (97) or a release tag (l4-ide-build-97).
#                   Default: the newest l4-ide-build-* release, by number.
#
# stdout: the path of the binary, and nothing else. Progress and errors go to stderr.
# The binary is cached at ${XDG_CACHE_HOME:-$HOME/.cache}/l4-main/<build>/l4 and reused.
#
# Platforms with a main binary: darwin-arm64, linux-x64, linux-arm64. On any other platform
# (Intel macOS, Windows, anything else) this exits 3 and fetches nothing: there is no main build
# to run, so there is no main check to make, and the caller must say so rather than skip it.
#
# Uses `gh` when it is installed and works; otherwise `curl` against the public release API.
# Needs `unzip`. The download is not checked against a digest, because the release publishes none
# for the package. Exit status: 0 the path was printed; 2 bad usage; 3 no main binary for this
# platform; 4 the download or the unzip failed.
set -u

REPO="legalese/l4-ide"
TAG_PREFIX="l4-ide-build-"

die() { echo "fetch-main-l4: $1" >&2; exit "${2:-4}"; }

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

# --- which build ------------------------------------------------------------------------------
want="${1:-}"
want="${want#"$TAG_PREFIX"}"
if [ $# -eq 1 ]; then
  case "$want" in ""|*[!0-9]*) die "BUILD must be a number such as 97 or a tag such as ${TAG_PREFIX}97, not '$1'." 2 ;; esac
fi

if [ -z "$want" ]; then
  # The newest by NUMBER: a release listing is not ordered by number, so do not take its first line.
  tags=""
  [ "$have_gh" = 1 ] && tags="$(gh release list --repo "$REPO" --limit 100 --json tagName --jq '.[].tagName' 2>/dev/null)"
  if [ -z "$tags" ] && [ "$have_curl" = 1 ]; then
    tags="$(curl -fsSL "https://api.github.com/repos/$REPO/releases?per_page=100" 2>/dev/null | grep -o "\"tag_name\": *\"${TAG_PREFIX}[0-9]*\"" | grep -o "${TAG_PREFIX}[0-9]*")"
  fi
  want="$(printf '%s\n' "$tags" | grep -E "^${TAG_PREFIX}[0-9]+\$" | sed "s/^${TAG_PREFIX}//" | sort -n | tail -n 1)"
  [ -n "$want" ] || die "could not find any ${TAG_PREFIX}* release of $REPO." 4
fi
tag="${TAG_PREFIX}${want}"

# --- cache ------------------------------------------------------------------------------------
root="${XDG_CACHE_HOME:-$HOME/.cache}/l4-main"
dest="$root/$want/l4"
if [ -x "$dest" ]; then printf '%s\n' "$dest"; exit 0; fi

mkdir -p "$root" || die "cannot create $root" 4
work="$(mktemp -d "$root/.fetch.XXXXXX")" || die "cannot make a work directory under $root" 4
trap 'rm -rf "$work"' EXIT

# --- download one vsix ------------------------------------------------------------------------
echo "fetch-main-l4: fetching $tag ($platform)" >&2
vsix=""
if [ "$have_gh" = 1 ]; then
  if gh release download "$tag" --repo "$REPO" -p "l4-vscode-${platform}-*.vsix" -D "$work" >/dev/null 2>&1; then
    vsix="$(ls "$work"/l4-vscode-"${platform}"-*.vsix 2>/dev/null | head -n 1)"
  fi
fi
if [ -z "$vsix" ] && [ "$have_curl" = 1 ]; then
  url="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/tags/$tag" 2>/dev/null | grep -o "\"browser_download_url\": *\"[^\"]*l4-vscode-${platform}-[^\"]*\\.vsix\"" | head -n 1 | sed 's/.*"\(https[^"]*\)"/\1/')"
  [ -n "$url" ] || die "$tag has no l4-vscode-${platform} package (is the build number right?)." 4
  curl -fsSL -o "$work/l4.vsix" "$url" || die "download of $url failed." 4
  vsix="$work/l4.vsix"
fi
[ -n "$vsix" ] && [ -s "$vsix" ] || die "could not download the $platform package of $tag." 4

# --- take out the binary ----------------------------------------------------------------------
member="extension/bin/${platform}/l4"
unzip -o -q "$vsix" "$member" -d "$work/x" 2>/dev/null || die "$tag's package has no $member." 4
[ -f "$work/x/$member" ] || die "$tag's package has no $member." 4
chmod +x "$work/x/$member"
[ "$os" = Darwin ] && command -v xattr >/dev/null 2>&1 && xattr -c "$work/x/$member" 2>/dev/null

# --- it must be a main build ------------------------------------------------------------------
# `l4 --version` prints "<number> (main, ...)" for a main build. A build from before the flag
# existed prints an error instead; that is not a reason to refuse it, only to say so.
ver="$("$work/x/$member" --version 2>/dev/null | head -n 1)"
case "$ver" in
  [0-9]*"(main,"*) ;;
  "") echo "fetch-main-l4: warning: $tag's l4 does not answer --version (it predates the flag); using it as a main build." >&2 ;;
  *) die "$tag's l4 says '$ver', which is not a main build." 4 ;;
esac

mkdir -p "$root/$want" || die "cannot create $root/$want" 4
mv "$work/x/$member" "$dest.new.$$" && mv "$dest.new.$$" "$dest" || die "cannot place the binary at $dest" 4
echo "fetch-main-l4: $tag is ${ver:-unversioned}, cached at $dest" >&2
printf '%s\n' "$dest"
