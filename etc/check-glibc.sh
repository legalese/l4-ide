#!/usr/bin/env bash
# check-glibc.sh BINARY... — fail if a Linux binary needs a newer glibc than
# the oldest one it has to run on.
#
# jl4-service runs in production on Amazon Linux 2023, whose glibc stays at
# 2.34 for the life of the release, and l4 and jl4-lsp ship in the VS Code
# extension to Linux machines nobody here controls. A dynamically linked binary
# records a glibc version for every glibc symbol it uses, and it runs only where
# glibc is at least the newest of them. Those versions come from the glibc the
# binary was linked against, not from its source: build 112, linked on
# ubuntu-26.04 (glibc 2.43), recorded GLIBC_2.43 for six float functions in
# libm, and no jl4-service process in production could start.
#
# Usage: etc/check-glibc.sh bin/linux-x64/jl4-service bin/linux-x64/l4 ...
set -euo pipefail

MAX_GLIBC=2.34

# Is the glibc version $1 newer than MAX_GLIBC?
newer_than_max() {
  [ "$(printf '%s\n%s\n' "$MAX_GLIBC" "$1" | sort -V | tail -n 1)" != "$MAX_GLIBC" ]
}

status=0
for bin in "$@"; do
  # The glibc versions under "Version References" in the dynamic section.
  versions=$(objdump -p "$bin" | { grep -oE 'GLIBC_[A-Za-z0-9_.]+' || true; } | sort -u)
  too_new=()
  for v in $versions; do
    n=${v#GLIBC_}
    # A version that is not a number (GLIBC_ABI_DT_RELR, say) cannot be
    # compared, so it fails too.
    if [[ ! $n =~ ^[0-9]+(\.[0-9]+)*$ ]] || newer_than_max "$n"; then
      too_new+=("$v")
    fi
  done
  if [ ${#too_new[@]} -eq 0 ]; then
    newest=$(sed -n 's/^GLIBC_\([0-9][0-9.]*\)$/\1/p' <<<"$versions" | sort -V | tail -n 1)
    echo "$bin needs glibc ${newest:-(none)}, no newer than $MAX_GLIBC"
  else
    status=1
    echo "::error::$bin needs ${too_new[*]}, but it must run on glibc $MAX_GLIBC (production's Amazon Linux 2023). Was it linked on a newer system?"
    for v in "${too_new[@]}"; do
      symbols=$(objdump -T "$bin" | awk -v v="$v" '{ for (i = 1; i <= NF; i++) { f = $i; gsub(/[()]/, "", f); if (f == v) { printf "%s ", $NF; break } } }')
      echo "  $v is needed by: $symbols"
    done
  fi
done
exit $status
