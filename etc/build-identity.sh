#!/bin/sh
# Print the four build-identity variables that LSP.L4.BuildInfo bakes into
# `l4` and `jl4-lsp`, one VAR=value per line, for a CI job to append to
# $GITHUB_ENV before it builds:
#
#   bash etc/build-identity.sh >> "$GITHUB_ENV"
#
#   L4_BUILD_RELEASE  <MAJOR.MINOR>.<run number>, MAJOR.MINOR being the version
#                     in ts-apps/vscode/package.json without its last component.
#                     This is the number the VS Code extension and jl4-service
#                     get in the same workflow.
#   L4_BUILD_BRANCH   the branch the workflow ran on, $GITHUB_REF_NAME, or
#                     `unknown` without it. It is passed in and not worked out
#                     from the checkout, which is a detached HEAD in CI, and Git
#                     is not asked.
#   L4_BUILD_COMMIT   the first seven characters of $GITHUB_SHA
#   L4_BUILD_DATE     today in UTC, YYYY-MM-DD
#
# It reads $GITHUB_RUN_NUMBER and $GITHUB_SHA, which a workflow run sets, and
# refuses to print anything (and exits non-zero) without them, so a local run
# cannot pass for a release. Only plain Unix tools are used (sh, sed, head, cut
# and date -u +FORMAT), which behave the same on the Linux and macOS runners and
# in Git Bash on the Windows runner.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
package_json="$here/../ts-apps/vscode/package.json"

: "${GITHUB_RUN_NUMBER:?GITHUB_RUN_NUMBER is not set: this prints the identity of a CI run}"
: "${GITHUB_SHA:?GITHUB_SHA is not set: this prints the identity of a CI run}"

version=$(sed -n -E 's/.*"version" *: *"([^"]+)".*/\1/p' "$package_json" | head -n 1)
case "$version" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "build-identity.sh: cannot read MAJOR.MINOR.PATCH from $package_json (got '$version')" >&2; exit 1 ;;
esac
major_minor=$(echo "$version" | sed 's/\.[^.]*$//')

branch=${GITHUB_REF_NAME:-unknown}

printf 'L4_BUILD_RELEASE=%s.%s\n' "$major_minor" "$GITHUB_RUN_NUMBER"
printf 'L4_BUILD_BRANCH=%s\n' "$branch"
printf 'L4_BUILD_COMMIT=%s\n' "$(echo "$GITHUB_SHA" | cut -c1-7)"
printf 'L4_BUILD_DATE=%s\n' "$(date -u +%Y-%m-%d)"
