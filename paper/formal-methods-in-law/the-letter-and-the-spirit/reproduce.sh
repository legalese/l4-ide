#!/usr/bin/env bash
# Reproduce every computational claim in "The Letter and the Spirit" (essay.md).
# Each step maps to a claim in the essay and prints PASS / FAIL / SKIP.
#
#   bash reproduce.sh
#
# Prereqs (all optional except python3 — steps SKIP cleanly if a tool is absent):
#   • l4   CLI            — the L4 model evaluation        (github.com/smucclaw/l4-ide)
#   • uv   OR global z3   — the Z3 surplusage proof        (uv: astral.sh/uv)
#   • espresso (optional) — genuine Berkeley minimiser; falls back to bundled
#                           Quine–McCluskey (stdlib).  Build: ./build-espresso.sh
set -uo pipefail
cd "$(dirname "$0")"
pass=0 fail=0
ok(){ echo "  PASS  $1"; pass=$((pass+1)); }
no(){ echo "  FAIL  $1"; fail=$((fail+1)); }
sk(){ echo "  SKIP  $1"; }
have(){ command -v "$1" >/dev/null 2>&1; }

echo "=============================================================="
echo " Reproducing: Penal Code s 415 / Poh Yuan Nie v PP [2022] SGCA 74"
echo "=============================================================="

echo "[1] L4 model — four-reading table + the 'otiose' assertions  (GD [18],[28],[30],[32])"
L4=""
for p in ./cheating-415-poh-yuan-nie.l4 \
         ../../../l4wt/poh-yuan-nie/jl4/ok/inert/cheating-415-poh-yuan-nie.l4 \
         ../../../l4-ide/jl4/ok/inert/cheating-415-poh-yuan-nie.l4 \
         "$HOME/src/legalese/l4wt/poh-yuan-nie/jl4/ok/inert/cheating-415-poh-yuan-nie.l4"; do
  [ -f "$p" ] && L4="$p" && break
done
if have l4 && [ -n "$L4" ]; then
  out=$(l4 run "$L4" 2>&1)
  if grep -q "assertion satisfied" <<<"$out" && ! grep -qiE "assertion (not|failed)|^.*error" <<<"$out"; then
    ok "l4 run: all assertions satisfied, no failures   [$L4]"
  else no "l4 run reported a failure"; fi
else sk "l4 CLI or .l4 not found (install l4, or checkout the poh-yuan-nie branch)"; fi

echo "[2] Z3 — surplusage proved (unsat of negation) + counterexample found  (GD [28],[30])"
if have uv; then RUN=(uv run --quiet --with z3-solver python)
elif python3 -c 'import z3' 2>/dev/null; then RUN=(python3)
else RUN=(); fi
if [ "${#RUN[@]}" -gt 0 ]; then
  out=$("${RUN[@]}" cheating-415-surplusage.z3.py 2>&1)
  np=$(grep -c "\[PROVED \]" <<<"$out")
  if [ "${np:-0}" -ge 2 ] && grep -q "\[WITNESS\]" <<<"$out"; then
    ok "z3: $np theorems PROVED; counterexample class WITNESS-ed"
  else no "z3 proof incomplete"; echo "$out" | tail -4; fi
else sk "no uv and no global z3 (pip install z3-solver, or install uv)"; fi

echo "[3] Minimiser — the 'dishonest concealment' literal vanishes under the applicants' reading"
out=$(python3 cheating-415-espresso.py 2>&1)
if grep -q "DISHONEST-CONCEALMENT ELIMINATED" <<<"$out" && grep -q "0 mention DISHONEST-CONCEALMENT" <<<"$out"; then
  ok "$(grep -m1 '^minimiser:' <<<"$out" | sed 's/minimiser: /literal eliminated  (/' )"
else no "minimiser did not eliminate the literal"; fi

echo "[4] Ladder figure regenerates"
if python3 cheating-415-ladder.py >/dev/null 2>&1 && [ -s cheating-415-ladder.svg ]; then
  ok "ladder SVG regenerated ($(wc -c < cheating-415-ladder.svg | tr -d ' ') bytes)"
else no "ladder generation failed"; fi

echo "=============================================================="
echo "  $pass passed, $fail failed"
echo "=============================================================="
[ "$fail" -eq 0 ]
