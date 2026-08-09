#!/usr/bin/env bash
# Toolchain discovery — the "provision" half of the front-door doctor.
#
# The fragility this closes, measured 2026-08-09: the same explainer rendered
# three different ways in one day depending on which env vars the invoking
# agent happened to export. Every skip was honest and named its remedy — the
# ladder receipt literally printed the dist-newstyle path it wanted — but the
# knowledge lived in receipts read AFTER a ten-minute run, and the remedy was
# a hand-typed export. A path a receipt can print is a path a script can find.
#
# Policy, in order:
#   1. Explicit env ALWAYS wins. Discovery only fills variables that are unset
#      or empty; CI and any caller with an opinion are untouched.
#   2. The worktree's OWN dist-newstyle is preferred over siblings even when a
#      sibling is newer: the binary that was built from this tree is the one
#      whose CLI surface the stage table was measured against. p0-preflight's
#      pin check still guards the case where even that binary has drifted.
#   3. Among sibling worktrees ((dirname ROOT)/*/dist-newstyle — the l4wt
#      convention), newest mtime wins: the most recently built binary is the
#      most likely to carry the current CLI surface.
#
# Nothing here builds anything. The build lock (CLAUDE.md §2.1) is why this
# file exists at all: `cabal` in a shared worktree corrupts a concurrent
# build, so the orchestrator's answer to "no binary" is discovery, then a
# named refusal — never a build.

# go_discover_tool ROOT PKG_GLOB EXE
#   Print the path of a built EXE under ROOT's own dist-newstyle, else the
#   newest-mtime candidate among sibling worktrees; print nothing when no
#   candidate exists. PKG_GLOB is expanded unquoted on purpose — 'jl4-*'
#   matches jl4-0.1 and jl4-lsp-0.1 alike, and the /x/EXE/ path segment is
#   what disambiguates the executable.
go_discover_tool() {
  local root="$1" pkg="$2" exe="$3"
  local roots=("$root") parent d
  parent="$(dirname "$root")"
  for d in "$parent"/*/; do
    d="${d%/}"
    [[ "$d" == "$root" ]] && continue
    [[ -d "$d/dist-newstyle" ]] && roots+=("$d")
  done
  local r c m own="" own_m=-1 best="" best_m=-1
  for r in "${roots[@]}"; do
    # shellcheck disable=SC2231  # $pkg must glob
    for c in "$r"/dist-newstyle/build/*/ghc-*/$pkg/x/"$exe"/build/"$exe"/"$exe"; do
      [[ -x "$c" ]] || continue
      # stat -f is macOS, -c is GNU; a stat that fails ranks the candidate last
      # rather than losing it.
      m="$(stat -f %m "$c" 2>/dev/null || stat -c %Y "$c" 2>/dev/null || echo 0)"
      if [[ "$r" == "$root" ]]; then
        if ((m > own_m)); then
          own_m=$m
          own="$c"
        fi
      else
        if ((m > best_m)); then
          best_m=$m
          best="$c"
        fi
      fi
    done
  done
  if [[ -n "$own" ]]; then
    printf '%s\n' "$own"
  elif [[ -n "$best" ]]; then
    printf '%s\n' "$best"
  fi
}

# go_provision_toolchain ROOT
#   Fill L4 and JL4_LSP_CMD from discovery when unset, and export a provenance
#   marker for each so every later line of output can say WHERE the binary came
#   from — "discovered" is a materially different claim from "explicit", and a
#   report that cannot tell them apart cannot be audited.
#
#   JL4_GO_SERVICE_URL is deliberately NOT provisioned: a live service is not a
#   file, and auto-connecting a deployment leg to whatever happens to be
#   listening would aim a write at a target the caller never named. The doctor
#   reports it; only a human export sets it.
go_provision_toolchain() {
  local root="$1" found
  if [[ -n "${L4:-}" ]]; then
    export GO_L4_PROVENANCE="explicit"
  else
    found="$(go_discover_tool "$root" 'jl4-*' l4)"
    if [[ -n "$found" ]]; then
      export L4="$found" GO_L4_PROVENANCE="discovered"
    else
      export GO_L4_PROVENANCE="none"
    fi
  fi
  if [[ -n "${JL4_LSP_CMD:-}" ]]; then
    export GO_LSP_PROVENANCE="explicit"
  else
    found="$(go_discover_tool "$root" 'jl4-*' jl4-lsp)"
    if [[ -n "$found" ]]; then
      export JL4_LSP_CMD="$found" GO_LSP_PROVENANCE="discovered"
    else
      export GO_LSP_PROVENANCE="none"
    fi
  fi
}
