# PROVENANCE — how every encoding in this study was produced

**Status: written 2026-09-01, after both measurement arms completed, by extracting the
launch-time material from the producing session's transcript while that transcript still
existed.** Everything below is either (a) a committed file a reviewer can open, (b) a verbatim
quotation from the session transcript, marked as such, or (c) an explicitly disclosed gap. The
distinction a reviewer needs first: the **scoring** is bit-reproducible from committed artifacts
(`bench/score-k10.sh`, `bench/score-restored.sh` re-execute every encoding); the **trials** are
sample-reproducible only — an LLM encoder is a stochastic instrument, so a re-run draws fresh
samples from the protocol specified here, and should be compared distributionally, never
trial-for-trial.

## 1. What determines a trial encoding, and where each factor is recorded

| factor                                          | value                                                                                                                                                                                                           | recorded where                                                                                                                  |
| ----------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| sandbox contents                                | fixture + blind queries + cell prompt (+ schema in guided cells)                                                                                                                                                | committed: `fixtures/`, `prompts/cell-*.md`, `bench/schema*.md`, staged by `bench/setup-{pilot,k10,restored}.sh` (leak-checked) |
| wrapper prompt (the agent's launch instruction) | §2 below, verbatim                                                                                                                                                                                              | **this file only** — it was never a repo artifact                                                                               |
| encoder model                                   | alias `sonnet` on every launch; resolved model string **`claude-sonnet-5`**, verified 2026-09-01 by inspecting a sampled encoder agent's own task record (17 request entries, all `"model":"claude-sonnet-5"`)  | this file                                                                                                                       |
| sampling parameters                             | never set by us; the agent harness's defaults applied; temperature/seed **not captured**                                                                                                                        | disclosed gap, §6                                                                                                               |
| harness                                         | Claude Code's Agent tool, `subagent_type: general-purpose`, concurrency ≤ 20; orchestrating session `papers-kant (c1881847-0452-4e2d-bab9-49cb2315f002)`; harness version not captured                          | this file; gap in §6                                                                                                            |
| dates                                           | pilot t1–t2: 2026-08-31 · top-up t3–t10 and the entire restored arm: 2026-09-01 (SGT)                                                                                                                           | commit history                                                                                                                  |
| relaunches                                      | 3 agents died on API timeouts with **zero bytes written** and were relaunched with identical wrappers into pristine sandboxes: as-published `prolog-guided/t3`, `prolog-guided/t6`, restored `prolog-guided/t2` | `README.md` §5, §5.3                                                                                                            |
| toolchain at run time                           | `l4` built from this branch (provenance commit `ccff478a`; runs spanned `8a240121`–`5cb93bb5`) · SWI-Prolog 9.2.9 · node v26.4.0 · GHC 9.10.3                                                                   | this file + lockfiles                                                                                                           |

One wrapper existed per cell; **the only text that varied between trials of a cell was the
`TRIAL DIRECTORY` path.** The restored arm reused the as-published wrappers with two changes,
both shown in §2.3: the path root, and two additions to the forbidden-files list
(`bench/keys-restored.json`, `bench/PREREGISTRATION-restored.md`). The relaunched trials used
byte-identical wrappers.

## 2. The wrapper prompts, verbatim

Extracted from the session transcript
(`~/.claude/projects/-Users-mengwong-src-legalese-l4-ide/c1881847-0452-4e2d-bab9-49cb2315f002.jsonl`)
on 2026-09-01. The pilot's wrappers and the k=10 top-up's wrappers are byte-identical modulo the
trial path (pilot paths use `trials/pilot-k2/`, top-up `trials/k10/`).

### 2.1 As-published arm — `vanilla`

```
You are producing ONE trial for a blind replication experiment. Work only inside your trial directory.

TRIAL DIRECTORY: <repo>/paper/kant-replication/trials/<arm-root>/vanilla/t<N>

Read `inputs/TASK.md` in that directory — it is your complete task specification. Also in `inputs/`: the insurance contract and the nine questions.

RULES THAT OVERRIDE EVERYTHING ELSE:

1. Do NOT read anything outside your trial directory. In particular you must NOT open any of: `paper/kant-replication/bench/keys.json`, `paper/kant-replication/fixtures/queries.json`, `paper/kant-replication/artifacts/`, `paper/kant-replication/FOUNDATION.md`, `paper/kant-replication/source-defects.md`, `paper/kant-replication/README.md`, or `jl4/examples/legal/chubb/`. Those contain the answer key or reference encodings. Reading any of them invalidates this trial.
2. Do NOT search the web. The source paper is arXiv 2502.17638 and it publishes the answers; finding them invalidates the trial.
3. Write your output file to the TRIAL DIRECTORY ROOT, not inside `inputs/`.
4. Also write a short `NOTES.md` recording any point where you had to make a judgement call about what the policy means.

Answer from the contract text as given. If the contract genuinely does not determine an answer, "I do not know" is a permitted answer — do not guess to avoid it.

When done, report in two sentences what you produced.
```

### 2.2 As-published arm — the four encoding cells

`prolog-unguided` adds to rule 1's forbidden list `paper/kant-replication/bench/schema-prolog.md`
("a fact vocabulary this cell must NOT have"); its rules 3–5 read:

```
3. Write `policy.pl` and `queries.pl` to the TRIAL DIRECTORY ROOT, not inside `inputs/`.
4. You MAY check that your files load: `swipl -q -g halt policy.pl queries.pl` should be silent. You may NOT run q1..q9 or otherwise test your encoding against the nine questions.
5. Write a short `NOTES.md` recording whether you ran the load check and what it said, plus any point where you had to make a judgement call about what the policy means.

`swipl` is on PATH (SWI-Prolog 9.2.9).
```

`prolog-guided` drops the schema file from the forbidden list (its copy is staged in `inputs/`),
notes in the preamble that `inputs/` also contains "`schema.md` (the fact vocabulary and
supporting predicates you must use)", and appends:

```
Use ALL OF, and ONLY, the claim facts in `inputs/schema.md`. Use the supporting predicates it defines rather than writing your own equivalents. `swipl` is on PATH (SWI-Prolog 9.2.9).
```

`l4-unguided` forbids `bench/schema-l4.md`, permits language documentation, and carries the L4
tooling block:

```
PERMITTED LANGUAGE REFERENCE (this is language documentation, not domain material, so it is allowed): the `writing-l4-rules` skill, and `<repo>/doc/reference/`. You may also read other `.l4` files under `jl4-core/libraries/` for syntax reference — but NOT `jl4/examples/legal/chubb/`.

Toolchain: `l4` is on PATH. Run checks with `JL4_LIBRARY_PATH=<repo>/jl4-core/libraries l4 check apply.l4` from your trial directory.

IMPORTANT L4 GOTCHAS: a file cannot `IMPORT` a library sharing its own basename. Each `#EVAL` line must carry a bare token `q1`..`q9` so the scorer can find it; name any extra probes `Q4b` or `S4` so they do not collide.
```

with rules 3–5 requiring `policy.l4` + `apply.l4`, permitting typecheck only ("You may NOT run
the nine evaluations"), and requiring `NOTES.md`. `l4-guided` = `l4-unguided` minus the schema
prohibition, plus the same "Use ALL OF, and ONLY, the `Claim` fields" sentence as
`prolog-guided`. **The L4 GOTCHAS block is treatment-relevant** (the Prolog cells received no
analogous hints beyond the swipl invocation); it exists because the `#EVAL` labelling is a
scoring-harness contract, and the self-import trap is a documented language gotcha, not domain
material — but a replicator should reproduce it as part of the L4 condition, and a reviewer may
fairly ask whether it advantaged L4. (The measured answer: the unguided cells it applied to
scored within one Q5 flip of their Prolog counterparts.)

### 2.3 Restored arm

Identical wrappers with `trials/restored-k10/` paths and rule 1 extended by two entries:
`paper/kant-replication/bench/keys-restored.json` and
`paper/kant-replication/bench/PREREGISTRATION-restored.md`. The unguided cells' forbidden lists
also name `bench/schema-restored-{prolog,l4}.md`. Guided sandboxes staged the restored schemas
under the same in-sandbox name `schema.md`, so the cell prompts stayed byte-identical across
arms (see `bench/setup-restored.sh`).

## 3. The corpus-side oracle encoding: `jl4/examples/legal/chubb/chubb.l4`

Produced **2026-08-31**, before any benchmark trial, as one of **three independent blind
encodings** (inert, guarded-rows, and record house styles), each written by a separate agent
shown only the policy text — not the nine questions, not the key, not each other's work — with
the questions mapped on afterwards by a fourth agent, also key-blind. The three frozen blind
artifacts are committed at `artifacts/encodings/` (`ref-{inert,guarded,record}.l4` +
`apply-*.l4`); `chubb.l4` is the inert arm plus a post-hoc benchmark-scenario section whose
non-blind status is documented where the encoding is deposited (the canon repository's
`subjects/us/chubb-hospital-cash/…/NOTES.md` §3). **The prompts that produced the trio live in
the producing session's transcript, not in this repository** — the protocol they implemented
(inputs shown, blindness rules, style mandates) is described in `FOUNDATION.md`, but the exact
prompt bytes were not preserved as artifacts. Disclosed gap; see §6.

## 4. The de novo oracle encoding: `jl4/examples/legal/chubb/denovo/chubb-denovo.l4`

Produced **2026-08-31** under the go-pipeline cleanroom discipline for subject `chubb`
(`etc/go/subjects/chubb/`): the encoder was given the hash-pinned source deposit —
`denovo/source-policy.txt`, whose assembly from the arXiv PDF is specified byte-for-byte in
`denovo/source-bundle.json` (PDF sha256, extraction rule, whitespace-normalised diff check) —
and **not** `chubb.l4`. Its interpretive choices are recorded in `denovo/fork-register.json`
(28 entries, each with both readings and the one taken) and its input pins in
`denovo/surface-map.json`. The phase _instructions_ are split: the pipeline contract is
committed (`etc/go/go.sh`, `subject.json`), but the phase-executing agents' session prompts are,
again, transcript material. The independence claim a reviewer can check without any transcript:
the fork register documents readings the corpus encoding did not take, and the §8 oracle's 107
reproducible witnesses (`etc/go/lib/denovo-diff.mjs run --map …/surface-map.json`) are the
measurable difference between the two texts.

## 5. What is bit-reproducible today

- **Scores**: both score scripts re-execute every committed trial artifact from scratch; the
  on-disk `out/` is never trusted (a stale mid-run snapshot once said prolog-guided scored 0/2,
  which is why).
- **Oracle witnesses**: deterministic given the two committed encodings + surface map;
  regenerated 2026-09-01 and matched the committed count (107) exactly.
- **Fixture assembly**: `fixtures/chubb-policy-restored.txt` verified byte-identical to the
  as-published text where it reuses it (`fixtures/chubb-policy-restored-NOTE.md`); source
  deposit hashes in `denovo/source-bundle.json`.
- **Schema parity**: `bench/check-schema-parity.mjs` compiles and compares both schema triples.

## 6. Disclosed gaps, in decreasing order of pain to a replicator

1. **Sampling parameters were never exposed by the harness** — no temperature, top-p, or seed
   was set or recorded, for the trials or for the oracle encodings. A replication is therefore
   distributional by necessity.
2. **The oracle encodings' production prompts** (§3, §4) were session-level and are preserved
   only in transcripts; this file records the protocol and every on-disk input they were given,
   which is sufficient to run a _new_ independent encoding — the scientifically meaningful
   replication — but not to re-issue the identical prompt bytes.
3. **Harness identity**: Claude Code, version not captured at run time; run dates given above.
4. **T9** (`FOUNDATION.md`): the harness's memory index leaked result-adjacent content into
   as-published-arm sandboxes; held constant within that arm, sanitized before the restored arm.
   A replicator using an agent harness with ambient memory must audit that channel as part of
   the blinding boundary.

If a factor is not listed in this file or in the files it points to, it was not controlled, and
the right assumption is that it took the harness default of 2026-08-31/09-01.
