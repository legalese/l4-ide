# The regression corpus spans two repos: `jl4/examples/legal` and canon's blessed dirs

**Status:** RULED 2026-09-15 (Meng), NOT BUILT. Nothing below changes a workflow, a test harness or
a file under `jl4/examples/` yet. The measurements are from `unstable` `388f8605` and canon
`mengwong/drafts` `299dd490`, taken the evening of 2026-09-15.

## 1. The ruling, verbatim

> i appreciate that we have been using jl4/examples/legal as a regression corpus; but we should
> write README and memory and other docs or scripts to note that regressions are to run against
> certain blessed dirs of the canon as well as what's in l4-ide; so i believe that if we were to
> refactor that way nothing would be lost, just moved; and there would also be some corpora left
> inside jl4/examples/legal that are not in canon, and that's ok too

and, on the consequence:

> i suppose this will present some challenges to the CI which assumes everything is in one repo.

What it settles: `jl4/examples/legal/` **is** the language's regression corpus and stays one; a
second set of directories in `legalese/canon` — explicitly blessed, not "everything" — joins it;
a subject that is already in canon leaves l4-ide (moved, not lost); subjects that are not in
canon stay where they are.

## 2. What was measured before ruling

- **Only two l4-ide subjects duplicate canon today.** `legal/chubb/chubb.l4` is byte-identical to
  `subjects/us/chubb-hospital-cash/encodings/blind-inert-2026-08/chubb.l4`. `legal/sg-succession/`
  has seven `.l4`; five are the same names as `subjects/sg/succession/encodings/legalese/` and two
  (`sg-succession-cases.l4`, `sg-succession-wizard.l4`) have no canon counterpart. `regcf`, `bna`,
  `charities-cleanroom` and the seven single-file subjects are not in canon.
- **What hangs off the two:** an `etc/go/subjects/<subject>/subject.json` each, pointing at
  `jl4/examples/legal/...` paths (every registered subject does — `chubb`, `regcf`, `sg-succession`);
  32 goldens between them under the `legal/**` glob (`jl4/tests/Main.hs`); three specs cite
  `sg-succession` files by `path:line` (`SUBJECT-TO-NOTWITHSTANDING-SPEC.md`,
  `NLG-TNR-ROUNDTRIP-SPEC.md`, `SET-OPERATORS-SPEC.md`). The `pr-checks.yml` and
  `etc/check-not-precedence.mjs` mentions are comments. `chubb` has no importers outside its dir.
- **canon is public** (`gh api repos/legalese/canon` → `visibility: public`), so CI can check it
  out at a pinned SHA with no token.
- **canon's encoding dirs already carry the four jl4-test goldens per file** (`tests/<stem>.{golden,
ep.golden,nlg.golden,schema.golden}`) — `sg/child-support/encodings/legalese` 5 `.l4` / 24
  goldens, `sg/succession/encodings/legalese` 5 / 24, both chubb encodings 1 / 4 each,
  `sg/penal-code-1871` 1 / 4. `il/ofek-hadash-2008` (9 `.l4`) and `sg/pdpa-2012` carry none.
- **Not every canon dir checks green with today's binary.** With the `unstable` `388f8605` `l4`
  and its embedded prelude, every encoding dir under `subjects/{sg,us,il,contracts,doctrine}`
  passes `l4 check` except `sg/succession/encodings/cleanroom-2026-08`, where `family-cases.l4`
  and `probate-administration-act.l4` exit non-zero on an Info-level diagnostic at
  `daydate.l4:104:8-104:50` — while their canon goldens say `Evaluation successful`. The goldens
  were blessed by an older binary. **This is the drift the ruling is about, observed before the
  mechanism exists**, and it is why §3's list is explicit.
- **Most of canon's content is on a per-person shelf**, `mengwong/drafts` (3572 files, 59 `.l4`),
  not `main` (3319 / 55). A dir blessed at a SHA on a shelf is a dir that can be rebased away.

## 3. The mechanism — two shapes, one chosen

Meng, later the same evening, on the CI cost of the cross-repo shape:

> if it is really unpleasant to have regression CI split across to the canon repo then i'm okay
> with vendoring in

**Chosen: vendoring (§3B), under that conditional.** The GM's assessment of "really unpleasant":
the checkout is one step, but the split makes every output-changing compiler PR re-bless goldens
in a second repo before it can merge (§5), makes every local developer and the go pipeline carry
`L4_CANON_DIR`, and leaves `etc/go` unable to address a subject until it learns `canon:` paths.
Vendoring removes all three at the price of a checked-in mirror — and a mirror with a pin and a
CI equality check is _detected_ duplication, not the silent kind the rest of this document is
about. Meng to confirm on return; recorded here so the two shapes are not re-derived.

### 3A. Cross-repo at a pin (not chosen)

1. **A pin, not a tracking ref.** `etc/canon-pin.json` in l4-ide:
   `{ "repo": "legalese/canon", "sha": "<40 hex>", "blessed": ["subjects/sg/child-support/encodings/legalese", ...] }`.
   CI checks canon out at exactly that SHA. The pin is the contract between the two repos: a
   compiler PR whose output changes bumps it to a canon commit carrying re-blessed goldens (any
   reachable SHA — a canon branch commit is fine, since the repo is public); a canon change that
   the compiler no longer accepts arrives in l4-ide as a pin-bump PR and is reviewed as one.
2. **One golden harness, not two.** `jl4-test` (`jl4/tests/Main.hs`) reads the pin and, when
   `L4_CANON_DIR` is set, adds each blessed dir to the golden globs with today's semantics
   (`failFirstTime = True`, four goldens per file, `--accept` to bless). Locally, `L4_CANON_DIR`
   unset → the canon block is skipped with a printed notice, exactly as `etc/validate-dmn.mjs`
   skips without dmnmd. In CI it is never unset.
3. **A CI job, `Canon Corpus`,** in `pr-checks.yml`: `actions/checkout` with
   `repository: legalese/canon`, `ref: ${{ pin.sha }}`, `path: canon`; then the golden suite with
   `L4_CANON_DIR=$GITHUB_WORKSPACE/canon`. Runs whenever `jl4-core/`, `jl4/`, `l4-cli/` or the pin
   changes; reuses the warm-start build artifact the Haskell job already produces. Required in the
   merge-queue ruleset once R1 (issue #394) has shown that adding a required check is a thing that
   happens.
4. **Blessed is explicit and lives on canon `main`.** The list is edited by PR in l4-ide; a dir is
   eligible once it (a) is on canon `main`, (b) carries goldens, (c) checks green at the pin. §2's
   measurement gives the first list: `sg/child-support/encodings/legalese`,
   `sg/succession/encodings/legalese`, `sg/penal-code-1871/encodings/legalese`, both chubb
   encodings. Not `cleanroom-2026-08` until its goldens are re-blessed; not `ofek-hadash-2008` or
   `pdpa-2012` until they have goldens.
5. **`etc/go` learns `L4_CANON_DIR`.** A `subject.json` may point at `canon:subjects/...`; the
   driver resolves it against the checkout. Until then a canon-hosted subject cannot be run by the
   pipeline, which is the open question the programme board carries under "Branches".

### 3B. Vendored at a pin (chosen)

1. **The same pin.** `etc/canon-pin.json`: `{ "repo": "legalese/canon", "sha": "<40 hex>",
"blessed": [ { "from": "subjects/sg/child-support/encodings/legalese", "to": "sg/child-support" }, ... ] }`.
2. **A mirror in the tree.** `jl4/examples/canon/<to>/` holds a verbatim copy of each blessed dir
   at the pin — `.l4`, `tests/` goldens, `encoding.json`, `SOURCE-LICENSE.md`; not `source/raw`,
   not `report/`, not `app/`. `jl4/examples/canon/README.md` says: **do not edit here; edit in
   canon and bump the pin.** The `legal/**` golden glob gains a sibling `canon/**`
   (`jl4/tests/Main.hs`, `etc/check-corpus-goldens.mjs`), with today's semantics unchanged.
3. **`etc/sync-canon.mjs`** does the copying: `--pull` fetches canon at the pin (public repo,
   `git archive` or a shallow clone into a temp dir) and rewrites the mirror; `--check` diffs the
   mirror against the pin and exits non-zero on any difference, naming the files; `--bump <sha>`
   updates the pin and pulls. Goldens are the one exception to "verbatim": the mirror's goldens
   are re-blessed in l4-ide when the compiler's output changes, and `--push-goldens` writes them
   back to a canon branch so canon's copy can catch up by its own PR. Canon's goldens being stale
   is then visible (`--check` reports it) rather than fatal.
4. **One CI job, `Canon Mirror`,** runs `etc/sync-canon.mjs --check` on every PR (no build
   needed — it is a tree diff against a public repo at a SHA) and fails when the mirror has been
   hand-edited or the pin moved without a pull. The regression itself runs in the existing
   Haskell job, because `canon/**` is just another golden glob. Nothing in CI reaches across a
   repo boundary except this one equality check.
5. **`etc/go` is unchanged.** A vendored subject is at an l4-ide path; `subject.json` points at
   `jl4/examples/canon/<to>/...`. The open question about `canon:` addressing closes.
6. **Blessed is explicit and lives on canon `main`** — §3A.4 applies unchanged, and so does the
   first list.

## 4. The migration, once §3B is green in CI

- `legal/chubb` → deleted; its mirror is `canon/us/chubb-hospital-cash/blind-inert-2026-08/`. `etc/go/subjects/chubb` → that path.
- `legal/sg-succession` → `sg-succession-cases.l4` and `sg-succession-wizard.l4` land in canon's
  `sg/succession/encodings/legalese/` first (with goldens, same commit); then the dir is deleted;
  `etc/go/subjects/sg-succession` → the mirror path; the three spec citations retarget to the
  mirror paths.
- `jl4/examples/legal/README.md` states the split: what is here and why, what is in canon and
  where the pin is. `CLAUDE.md` §3.1's "which globs, exactly" gains the canon block. The memory
  note `canon-is-the-home-for-encodings` gains the same sentence.
- Nothing else moves. `regcf`, `bna`, `charities-cleanroom` and the single-file subjects stay in
  l4-ide until they are in canon, and that is fine — the ruling says so.

## 5. The CI challenge the cross-repo shape has, stated plainly (why §3B was chosen)

Two repos means two blessing cadences, and a required cross-repo check can deadlock: the compiler
PR needs canon goldens re-blessed by the new binary, and canon cannot bless with a binary that has
not merged. The pin breaks the cycle — the compiler PR author builds the binary, re-blesses on a
canon branch, pushes that branch, and points the pin at its SHA; the canon PR merges after. It is
one extra step per output-changing compiler PR, and it is the step that today is silently skipped
(§2's `daydate.l4:104` finding is what skipping it looks like). The alternative — tracking canon
`main` — makes every l4-ide PR's CI depend on what someone merged to canon that morning, which is
the one-repo assumption in a worse form.

## 6. Not decided here

- Whether a blessed dir's `tests/` goldens are owned by canon or generated by l4-ide's harness and
  pushed. §3.2 assumes canon owns them and l4-ide reads them.
- What to do when a blessed dir stops parsing because the _language_ moved (a keyword promoted,
  as `EVERY` was in #360): re-bless, or unbless and note. Probably re-bless in the same pin bump.
- Whether `jl4/examples/legal/` single-file subjects should also be in canon eventually. The
  ruling says staying is fine; it does not say forever.
