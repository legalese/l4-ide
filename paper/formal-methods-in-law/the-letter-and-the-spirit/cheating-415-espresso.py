#!/usr/bin/env python3
"""
Poh Yuan Nie v PP [2022] SGCA 74 — surplusage as boolean minimisation.

Watch the 'dishonest concealment' literal VANISH from the minimised formula under
the applicants' reading, while surviving as essential under the court's. That
disappearance IS the presumption against surplusage, computed: a clause the
minimiser can delete is a clause that does no work.

Two engines, cross-checked against each other:
  • the genuine Berkeley ESPRESSO heuristic minimiser, if the `espresso` binary
    is on PATH (build: github.com/classabbyamp/espresso-logic — `make`);
  • a self-contained QUINE–McCLUSKEY exact minimiser (stdlib only) — always runs,
    so the result reproduces with zero dependencies.
They must agree on which literals survive.

    python3 cheating-415-espresso.py
"""
import shutil, subprocess

# ===========================================================================
# Engine 1 — exact two-level minimiser (Quine–McCluskey), pure stdlib
# ===========================================================================
def _combine(a, b, n):
    diff = -1
    for i in range(n):
        if (a[i] is None) != (b[i] is None): return None
        if a[i] != b[i]:
            if diff != -1: return None
            diff = i
    if diff == -1: return None
    r = list(a); r[diff] = None
    return tuple(r)

def _primes(minterms, n):
    cur = {tuple((m >> (n - 1 - i)) & 1 for i in range(n)) for m in minterms}
    primes = set()
    while cur:
        used, nxt = set(), set()
        ts = list(cur)
        for i in range(len(ts)):
            for j in range(i + 1, len(ts)):
                c = _combine(ts[i], ts[j], n)
                if c is not None:
                    used |= {ts[i], ts[j]}; nxt.add(c)
        primes |= {t for t in ts if t not in used}
        cur = nxt
    return primes

def _covered(impl, n):
    free = [i for i in range(n) if impl[i] is None]
    base = sum(1 << (n - 1 - i) for i in range(n) if impl[i] == 1)
    out = set()
    for k in range(1 << len(free)):
        m = base
        for b, i in enumerate(free):
            if (k >> b) & 1: m |= 1 << (n - 1 - i)
        out.add(m)
    return out

def qm_minimise(varnames, onset):
    n = len(varnames)
    if not onset: return []
    if len(onset) == (1 << n): return [tuple([None] * n)]
    primes = list(_primes(onset, n))
    pcov = {p: _covered(p, n) & onset for p in primes}
    chosen, covered = set(), set()
    changed = True
    while changed:
        changed = False
        for m in onset - covered:
            cov = [p for p in primes if m in pcov[p]]
            if len(cov) == 1 and cov[0] not in chosen:
                chosen.add(cov[0]); covered |= pcov[cov[0]]; changed = True
    while covered < onset:
        best = max(primes, key=lambda p: len(pcov[p] - covered))
        chosen.add(best); covered |= pcov[best]
    return list(chosen)

# ===========================================================================
# Engine 2 — the genuine Berkeley Espresso binary (via PLA over a pipe)
# ===========================================================================
ESPRESSO = shutil.which("espresso")

def _to_pla(varnames, onset):
    n = len(varnames)
    rows = []
    for x in range(1 << n):
        bits = "".join("1" if (x >> (n - 1 - i)) & 1 else "0" for i in range(n))
        rows.append(f"{bits} {'1' if x in onset else '0'}")
    return "\n".join([f".i {n}", ".o 1", ".ilb " + " ".join(varnames), ".ob f", *rows, ".e"]) + "\n"

def espresso_minimise(varnames, onset):
    out = subprocess.run([ESPRESSO], input=_to_pla(varnames, onset),
                         capture_output=True, text=True).stdout
    cover = []
    for line in out.splitlines():
        line = line.strip()
        if not line or line.startswith("."): continue
        cube, _, o = line.partition(" ")
        if o.strip() != "1": continue
        cover.append(tuple(None if c == "-" else int(c) for c in cube))
    return cover

# ===========================================================================
# Rendering
# ===========================================================================
def term_str(impl, names):
    parts = [("" if v == 1 else "¬") + names[i] for i, v in enumerate(impl) if v is not None]
    return " ∧ ".join(parts) if parts else "TRUE"

def sop_str(cover, names):
    return "   ∨   ".join(term_str(t, names) for t in cover) if cover else "FALSE"

def support(cover, names):
    return {names[i] for impl in cover for i, v in enumerate(impl) if v is not None}

def minimise(varnames, onset):
    """Run the real Espresso if available; always cross-check against Quine–McCluskey."""
    qm = qm_minimise(varnames, onset)
    if ESPRESSO:
        esp = espresso_minimise(varnames, onset)
        assert support(esp, varnames) == support(qm, varnames), \
            "Espresso and Quine–McCluskey disagree on the surviving literals!"
        return esp, "Espresso"
    return qm, "Quine–McCluskey"

# ===========================================================================
# s 415 (2008) — the same model as the L4 file and the Z3 proof
# ===========================================================================
def concealment_counts(reading, v):
    return (v['conceal'] and v['prop_intent']) if reading == 'Second' else v['conceal']
def deception(reading, v):
    return v['by_deceiving'] or concealment_counts(reading, v)
def first_limb(reading, v):
    return deception(reading, v) and (v['fraudulently'] or v['prop_intent']) and v['prop_delivery']
def second_limb(reading, v):
    return (deception(reading, v) and v['intentionally'] and v['causes_harm']
            and (v['harm_body'] or v['harm_mind'] or v['harm_reputation'] or v['harm_property']))
def cheats(reading, v):
    return first_limb(reading, v) or second_limb(reading, v)

NICE = {'by_deceiving': 'by-deceiving', 'conceal': 'DISHONEST-CONCEALMENT',
        'intentionally': 'intentionally', 'causes_harm': 'causes-harm',
        'harm_body': 'harm-body', 'harm_mind': 'harm-mind',
        'harm_reputation': 'harm-reputation', 'harm_property': 'harm-property'}

def build_onset(func, reading, free_vars, fixed):
    n = len(free_vars); on = set()
    for x in range(1 << n):
        v = dict(fixed)
        for i, name in enumerate(free_vars):
            v[name] = bool((x >> (n - 1 - i)) & 1)
        if func(reading, v): on.add(x)
    return on

# ===========================================================================
print(f"minimiser: {'genuine Berkeley Espresso  (' + ESPRESSO + ')' if ESPRESSO else 'Quine–McCluskey (Espresso binary not found)'}\n")

print("=" * 78)
print("DEMO 1 — the deception gateway, minimised in the no-property world")
print("=" * 78)
gw = ['by_deceiving', 'conceal']; gl = [NICE[v] for v in gw]
for reading, who in [('Fourth', "the court's reading"), ('Second', "the applicants' reading")]:
    cover, eng = minimise(gw, build_onset(deception, reading, gw, {'prop_intent': False}))
    gone = "" if 'conceal' in support(cover, gw) else "   <-- DISHONEST-CONCEALMENT ELIMINATED"
    print(f"  {who:24}  deception  =  {sop_str(cover, gl)}{gone}")

print()
print("=" * 78)
print("DEMO 2 — the whole offence, minimised in the no-property world")
print("=" * 78)
free = ['by_deceiving', 'conceal', 'intentionally', 'causes_harm',
        'harm_body', 'harm_mind', 'harm_reputation', 'harm_property']
fl = [NICE[v] for v in free]
fixed = {'prop_intent': False, 'prop_delivery': False, 'fraudulently': False}
for reading, who in [('Fourth', "the court's reading"), ('Second', "the applicants' reading")]:
    cover, eng = minimise(free, build_onset(cheats, reading, free, fixed))
    nc = sum(1 for t in cover if t[free.index('conceal')] is not None)
    print(f"  {who}:  {len(cover)} product terms, {nc} mention DISHONEST-CONCEALMENT "
          f"(in support: {'conceal' in support(cover, free)})")

print()
print("=" * 78)
print(f"Engine: {eng}.  The minimiser deletes the clause the court called 'otiose'.")
print("Surplusage and dead-code elimination are the same operation. (GD [30], [32].)")
print("=" * 78)
