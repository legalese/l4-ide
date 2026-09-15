# The regression corpus spans two repos: `jl4/examples/legal` and canon's blessed dirs

**Status:** RULED 2026-09-15 (Meng). §3B **BUILT 2026-09-15** — see the Built / Not built lists at
§3B; §4's migration is **not** built and nothing is deleted yet. ~~Nothing below changes a workflow,
a test harness or a file under `jl4/examples/` yet.~~ That sentence was true when written and is
now false: §3B added a CI job, a golden glob and 85 files under `jl4/examples/canon/`. The measurements are from `unstable` `388f8605` and canon
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
  (`sg-succession-cases.l4`, `sg-succession-wizard.l4`) ~~have no canon counterpart~~.
  **Corrected 2026-09-15: true of `sg-succession-wizard.l4` only.** `sg-succession-cases.l4` IS in
  canon, at `.../encodings/legalese/cases/` — byte-identical, and all four of its goldens
  byte-identical too (measured at `9a1a3155`). It was missed for the same reason the count in the
  fourth bullet was: it sits one level down, in `cases/`. The count got corrected and the two
  sentences resting on it did not, which is the drift this document is otherwise about. `regcf`, `bna`,
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
ep.golden,nlg.golden,schema.golden}`) — `sg/child-support/encodings/legalese` ~~5~~ **6** `.l4` / 24
  goldens, `sg/succession/encodings/legalese` ~~5~~ **6** / 24, both chubb encodings 1 / 4 each,
  `sg/penal-code-1871` 1 / 4. `il/ofek-hadash-2008` (~~9~~ **10** `.l4`) and `sg/pdpa-2012` carry none.
  The tenth is `source/_salary-table-tail.l4` — the SAME "missed the one a level down" error, in
  the very bullet that corrects it elsewhere. It is not a module: bare `§§`, no `IMPORT prelude`,
  concatenated by a script beside it. `sync-canon.mjs`'s allowlist excludes it by directory, so
  blessing ofek later will not vendor it.
  **Corrected 2026-09-15 while building §3B:** each of those two dirs keeps a SIXTH `.l4`
  one level down, in `cases/`, which the original count missed. The GOLDEN count was right all
  along — 24 is 6 stems × 4 — so the two halves of that sentence disagreed with each other and
  the `.l4` half was the wrong one. Across the five blessed dirs: **15 `.l4`, 60 goldens**,
  exactly four per file. The miscount is the reason §3B.2's hoist exists at all, so it is
  corrected here rather than quietly fixed.
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
   (`failFirstTime = True`, four goldens per file; ~~`--accept` to bless~~ **blessing is
   delete-the-golden-and-run-twice — see §3B's review note**). Locally, `L4_CANON_DIR`
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

**Built 2026-09-15**, on `mengwong/canon-vendor`, cut from `unstable` `388f8605`. What follows
replaces this section's earlier "proposed" standing; the numbered design below is unchanged and is
what was implemented, with the two departures named under _What review changed_.

**Built:**

- **`etc/canon-pin.json`** — repo, 40-hex SHA, and the five blessed dirs as `{from, to}`. It also
  carries, in its own header, why each _unblessed_ dir is unblessed, so the next person does not
  re-derive it.
- **`etc/sync-canon.mjs`** — `--pull` (shallow-fetches canon at the pin into a temp dir and
  rewrites the mirror), `--check` (tree diff, what CI runs), `--bump <sha>`, `--selftest`
  (16 cases: hoist, collision refusal, allowlist, the three mutations — hand-edited mirror, pin
  moved without pull, stale canon golden — plus a blessed dir absent at the pin and a malformed
  pin).
- **`jl4/examples/canon/`** — 85 files: 15 `.l4`, 60 goldens, 5 `encoding.json`, 5
  `SOURCE-LICENSE.md`. Plus a `README.md` of this repo's own, exempt from `--check` by name.
- **The golden glob.** `canon/**` joins `legal/**` in `jl4/tests/Main.hs` and
  `etc/check-corpus-goldens.mjs`, which CLAUDE.md §3.1 requires to stay in step. Measured after:
  `check-corpus-goldens` reports **470 corpus files, each with all four goldens**.
- **`canon/**`joins the`prettyLayout` round-trip too\*\* (§3B.2 did not say either way; GM's view
  and this implementation's). The block's own comment defines its corpus as "exactly the files the
  'ok files' block typechecks", so excluding canon would have falsified that sentence.
- **One CI job, `Canon Mirror`** — `--selftest` then `--check`, no path filter and no build,
  because what it checks is whether the mirror still equals canon at the pin, which no `paths:`
  filter can predict.
- **Docs**: `jl4/examples/canon/README.md`, a new `jl4/examples/legal/README.md` stating the split,
  and CLAUDE.md §3.1's glob list.

**Not built, and each is a place this document still describes more than the tree does:**

- **`--push-goldens`** (§3B.3). The mirror reads canon's goldens and never writes them back, so
  re-blessing after an output change is a canon-side edit plus a pin bump. The consequence is
  handled rather than hidden: `--check` reports a differing golden **separately and non-fatally**,
  because making it fatal would reintroduce exactly the cross-repo blessing deadlock §5 says
  vendoring was chosen to avoid. §6's open question — whether canon or l4-ide owns the goldens —
  is therefore still open, and this implementation assumes canon owns them.
- **The migration (§4).** Nothing is deleted: `legal/chubb` and `legal/sg-succession` still exist
  and are still globbed, so those two subjects are duplicated _within this repository_ until §4
  runs. That is deliberate — ship the mechanism, see it green, then move.
- **The merge-queue requirement.** `Canon Mirror` is not a required check in the ruleset.
- **The pin is on a canon BRANCH, not on `main`**, which §3A.4/§3B.6 require. It is
  `gm/rebless-2026-09-15`, cut from `mengwong/drafts`, created because the first run needed a
  re-blessed golden. It stays valid when that branch merges — a merge does not change the
  commit. None of the five blessed dirs is on `main` yet, so the requirement cannot be met
  today. None of the five
  blessed dirs is on `main` yet, so the requirement cannot be met today; the pin's header says the
  target is `main` and `--pull` fails loudly if the shelf SHA is rebased away.

**What review changed** (two read-only adversarial refuters, plus GM's own reading):

- **The wrinkle was real and the reason for it was not.** Two blessed dirs keep a cases file at
  `cases/x.l4` with its goldens in the dir-level `tests/`. The obvious diagnosis — that a nested
  file cannot resolve its sibling imports — is **false**: measured at the pin, both layouts pass
  `l4 check`. The hoist is needed for **goldens only**, because
  `takeDirectory inputFile </> "tests"` would look in `cases/tests/`, and canon has no
  `cases/tests/` directory anywhere. Had the change shipped on the import rationale it would have
  been right for the wrong reason and the next person would have re-derived it wrongly.
- **`--accept` never existed, and this document is where it came from.** §3A.2 above said the
  golden harness takes "`--accept` to bless". It does not — measured:

  ```
  $ cabal test jl4-test --test-options='--accept --match "canon/sg/penal"'
  jl4-test: unrecognized option `--accept'
  ```

  The sentence entered the tree in this spec's own first commit (`9853462d`, merged via #396) and
  was then copied, unchecked, into `jl4/tests/Main.hs`, `jl4/examples/canon/README.md` and
  **`CLAUDE.md`** — where it was sharpened into "do not bless its goldens with `--accept`", an
  instruction not to use a flag that does not exist, which implies that it does. That is the
  borrowed-claim rule failing twice over: once where the claim was written, once at each site that
  repeated it without running it.

  The real mechanism is the one CLAUDE.md §3.1 already taught: delete the stale `.golden` and run
  `cabal test jl4-test` twice — once to write it and fail, once to prove it holds. It cost a wrong
  reading before it was caught: an "accept" run reported `FAIL` and was read as a test failure when
  it was the unrecognized-option error, and the goldens that appeared came from the _next_ run's
  `failFirstTime` rather than from any blessing.

- **The first run found a stale canon golden, which is what the mechanism is for.**
  `sg-csp.golden` carried two lines; today's binary adds a 19-line Info block at `sg-csp.l4:79:8`
  telling the author that `ASSUME` is being retired in favour of a section-level `GIVEN`. The
  **binary is right and the golden is stale** — that diagnostic is landed behaviour (the
  ASSUME-as-implicit-parameter arc), and l4-ide's own corpus was swept for it in #337 while
  canon's was not. It was re-blessed in canon and the pin bumped, exercising the §5 loop on a
  real divergence rather than a constructed one. Note what did **not** happen: the mirror was not
  re-blessed in place, which would have made this repository's copy disagree with canon silently.
- **`--check` counted build output as a difference.** `jl4-test` writes a gitignored
  `<stem>.actual` beside every golden; the raw directory walk called all sixty of them EXTRA and
  failed. It fires only for someone who has just run the tests and never in CI, so the person who
  meets it is the one least able to believe it. `--check` now filters through `git check-ignore`.
- **§2's count and §4's paths were both wrong** and are corrected in place above rather than
  silently — see the two _Corrected 2026-09-15_ notes.

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
6. **Blessed is explicit and lives on canon `main`** — §3A.4's _location_ requirement applies
   unchanged, and so does the first list. **Its eligibility test does not.** §3A.4 said a dir is
   eligible once it "checks green at the pin", which was written before there was a harness to ask.

   **RULED 2026-09-15, replacing that clause: a directory is blessed when its four goldens per
   file match the pinned binary's output UNDER THE HARNESS.** `l4 check` exiting zero is
   necessary and **not sufficient** — it is a weaker question, and the first run showed the two
   answers diverge. `canon/sg/child-support/sg-csp.l4` passes `l4 check` (0 of 15 mirrored files
   exit non-zero) and **fails** the harness (1 of 90 examples), because the binary emits an
   Info-level ASSUME-retirement diagnostic that canon's golden predates. The harness is the
   definition of green, because the harness is what CI runs.

## 4. The migration — DONE 2026-09-16

**Built**, on `mengwong/canon-migrate`, after §3B merged as #398. The plan below is
kept for the record; three of its steps turned out to rest on a false premise, and
what was actually done differs. Read this block first.

**The premise that failed: "the mirror carries every file." It does not**, in two
independent ways, both measured before anything was deleted:

1. **`legal/sg-succession/cleanroom-2026-08/`** — 6 `.l4`, 24 goldens — is the
   encoding the pin deliberately does **not** bless (§3B's header says why: two of
   its files fail `l4 check` while canon's goldens claim success). **l4-ide's copy
   is the healthy one.** Deleting the parent directory would have dropped six
   corpus files from the regression suite to match a staler copy elsewhere.
2. **The mirror carries no deposit data.** The allowlist takes `.l4`,
   `tests/*.golden`, `encoding.json`, `SOURCE-LICENSE.md` — not `registers/`. Both
   go sidecars name four deposit JSONs each that have nowhere to go.

**What was done instead (ruled by GM, 2026-09-16): delete only what the mirror
carries.**

- `legal/chubb/{chubb.l4, tests/}` and `denovo/{chubb-denovo.l4, tests/}` deleted;
  `denovo/*.json`, `denovo/source/` kept.
- `legal/sg-succession/`'s 7 top-level `.l4` and `tests/` (28 goldens) deleted;
  `cleanroom-2026-08/`, `app/`, `denovo/`, `source/` kept.
- **45 files deleted, none lost** — every one is in the mirror.
- `etc/go/subjects/{chubb,sg-succession}` had **only their corpus-module paths**
  retargeted (5 files: both `subject.json`, both `pins.json`, one
  `known-defects.json`). Deposit paths untouched. All three subjects resolve;
  `etc/go/selftest.mjs` passes — run explicitly, because `verify-branch.sh` does
  not cover it and says so in its own footer.
- Three spec citations retargeted with **line numbers re-verified in the mirror,
  not carried over** (`SET-OPERATORS` §, `SUBJECT-TO-NOTWITHSTANDING`,
  `NLG-TNR-ROUNDTRIP`). The `cleanroom-2026-08` citations in the first two were
  left alone — that directory did not move.
- `jl4/examples/legal/README.md` states the split, including why the two things
  that stayed, stayed.

**Still open, boarded rather than decided here:** whether `registers/*.json` join
the mirror allowlist — which is really the question of how `etc/go` addresses a
canon-hosted subject — and re-blessing canon's `cleanroom-2026-08` from l4-ide's
healthy copy, which is "moved, not lost" running in the other direction.

### 4.1 The plan as written before any of it was measured

- `legal/chubb` → deleted; its mirror is ~~`canon/us/chubb-hospital-cash/blind-inert-2026-08/`~~
  **`jl4/examples/canon/us/chubb-hospital-cash/blind-inert/`**. `etc/go/subjects/chubb` → that path.
  **Corrected 2026-09-15:** this section was written before the blessed list was confirmed, and
  names a path the pin does not produce. The `to` values in `etc/canon-pin.json` are the
  confirmed ones and drop the date suffix — `blind-inert`, `blind-guarded`, `sg/child-support`,
  `sg/succession`, `sg/penal-code-1871`. Said here rather than silently rewritten, because a
  migration section that quietly agrees with the code teaches nobody which one moved.
- `legal/sg-succession` → ~~`sg-succession-cases.l4` and~~ `sg-succession-wizard.l4` lands in canon's
  `sg/succession/encodings/legalese/` first (with goldens, same commit); then the dir is deleted;
  **Corrected 2026-09-15: `sg-succession-cases.l4` is ALREADY there**, with its four goldens, all
  byte-identical to l4-ide's copies. Only the wizard has to move.
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
