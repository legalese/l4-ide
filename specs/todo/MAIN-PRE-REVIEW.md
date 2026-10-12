# Main pre-review — a reviewer agent for every main-bound PR, before a person reads it

> **Status: adopted 2026-10-08 by Meng (word REHEARSAL), and recorded beside D9.1 in [`RELEASE-MODEL-SPEC.md`](RELEASE-MODEL-SPEC.md).**
> It is run by hand, one agent per PR.
> It is not automated and not run in CI.
> The three standing probes (§6) are built: `etc/probe-parse-scaling.mjs`, `etc/probe-service-restart.mjs` and `etc/probe-cli-crlf.mjs`, which `etc/verify-branch.sh` runs when a diff touches their paths.
> FLOTILLA is to run the pre-review per PR; that is proposed, not built.

## 1. What it is

Every topic PR into `main` (D9.1) is read by an agent before its human reviewer reads it.
The agent's prompt is the one backtested as STUNTDOUBLE on five reviewed PRs (§8), plus a checklist built from what that reviewer, serrynaimo, has asked to change so far (§5).
Its job is to find what he would ask to change, so that a review round is spent on judgement rather than on defects a script or a careful reading would have found.

## 2. When it runs

- Before a main-bound PR opens.
- Before each re-request of review, on the head that will be pushed.
- On every main-bound PR, whatever it touches.
  A PR that touches only `jl4/examples/**` gets no Haskell CI on main, so there the pre-review is the only build that runs.

The pre-review is for main-bound PRs; a branch into `unstable` has `etc/verify-branch.sh`, which runs the same three probes.

## 3. How to run it

1. Fetch, then fill the placeholders in §4:
   - `{PR}` is the PR number; before the PR opens, a short name for the branch, with no slash.
   - `{HEAD}` is the commit that will be pushed.
   - `{BASE}` is `origin/main` as fetched.
   - `{UNSTABLE}` is `origin/unstable` as fetched, as a hash.
   - `{BODY}` is a file holding the PR description, as posted or as it will be posted.
2. Start one agent per PR with the filled prompt.
   It makes its own worktrees at `{HEAD}` and at the merge base, and builds both (the prompt's Setup).
   Each run took 45 to 75 minutes of wall clock in the backtest.
3. The agent sends its findings by message, in parts.
   The harness refuses report files from subagents, and in the backtest long messages were cut short in the idle notice, so the prompt asks for parts from the start.
4. Fix every blocking finding before the PR opens or review is re-requested.
   A finding the author disagrees with goes in the PR description with the reason.
5. The agent removes its worktrees and copied binaries when it is done; check that it did.

## 4. The prompt

Fill the placeholders and send everything inside the fence.

````text
# Pre-review: legalese/l4-ide PR #{PR} into `main`

You review PR #{PR} at commit `{HEAD}` before its human maintainer does, to find what the maintainer would ask to change. `{BASE}` is `main` as of the review. `{UNSTABLE}` is the `unstable` commit to compare against. `{BODY}` holds the PR description. Report defects only: no praise, no summary of the PR.

## Rules

- Make no GitHub writes.
- Scope: the diff `MB..{HEAD}`, where `MB=$(git merge-base {HEAD} {BASE})`, plus anything that diff breaks. If `{BASE}` ≠ `MB`, check `git merge-tree --write-tree {BASE} {HEAD}` is clean.
- If the PR has been reviewed before, read every review and comment on it (`gh api repos/legalese/l4-ide/pulls/{PR}/reviews`, `gh api repos/legalese/l4-ide/pulls/{PR}/comments`, `gh pr view {PR} --repo legalese/l4-ide --comments`) and answer lens 9.
- After the lenses, work through the checklist: `git show {UNSTABLE}:specs/todo/MAIN-PRE-REVIEW.md`, §5. Each item is a kind of defect the maintainer has already asked to change in this repository. For each item that applies to this diff, say what you checked.

## Setup

```
R=~/src/legalese/l4-ide; S=<your scratch dir>; git -C $R fetch origin
H=~/src/legalese/l4wt/rv{PR}-head; B=~/src/legalese/l4wt/rv{PR}-base
git -C $R worktree add --detach $H {HEAD}; git -C $R worktree add --detach $B $MB
(cd $H && nice -n 19 cabal build -j2 --enable-tests all) >$S/h.log 2>&1 & echo $! >$S/h.pid
(cd $B && nice -n 19 cabal build -j2 exe:l4 exe:jl4-repl exe:jl4-service) >$S/b.log 2>&1 & echo $! >$S/b.pid
until ! kill -0 $(cat $S/h.pid) 2>/dev/null; do sleep 30; done   # likewise b.pid
```

Wait on the PID, never `pgrep` by name: the waiting shell matches itself. Run one `cabal` per worktree at a time. Copy each binary into `$S` (`cabal list-bin exe:l4`, and so on) and probe only with the copies, because a rebuild relinks the original. Set `JL4_LIBRARY_PATH` to the tree under test's `jl4-core/libraries` on every run. When done, `git worktree remove --force` both trees and delete the copied binaries.

**Main is not unstable.** They differ by thousands of commits. Main has no `CLAUDE.md`, no `etc/verify-branch.sh`, no `etc/*.mjs` checkers, no `prettyLayout` round-trip test, no golden path scrubber and no `jl4-lsp` test suite, and `jl4-wasm` is not in its `cabal.project`. Do not run `verify-branch.sh` on `$H`. Main's gate is its CI: `cabal test all` with `JL4_LIBRARY_PATH` pinned; `./doc/test-docs.sh` with `$H`'s `l4` first on `PATH` (the script uses whatever `l4` is on `PATH`); `npx prettier@3.4.2 --check` over changed files. Main's CI runs the Haskell job only when `*.hs`, `*.cabal`, `cabal.project`, `jl4-core/libraries/**` or `doc/**` change, so a PR that touches only `jl4/examples/**` gets no Haskell CI and your run is the only one.

The repo's rulebook is `git show {UNSTABLE}:CLAUDE.md`.

## Lenses

### 1. Tree

Collect every reference in the diff, the PR body and each commit message (`git log MB..{HEAD}`). Each must resolve in `{HEAD}`'s tree, which is what main becomes, not only on unstable. Check claims about main's current behaviour at `MB`.

- **Path:** `git cat-file -e {HEAD}:<path>`.
- **`file:line`:** `git show {HEAD}:<path> | sed -n '<L>p'`; the line must say what the sentence claims. With `@ <sha>`, check at that sha.
- **Commit hash:** `git merge-base --is-ancestor <sha> {HEAD}`. Otherwise the text must say where it lives, and `--is-ancestor <sha> {UNSTABLE}` must succeed.
- **Function, type, constructor, flag, message:** `git grep -n` at `{HEAD}`.
- **Spec file or §section:** the file exists at `{HEAD}` and has the heading. Main has under half of unstable's specs; most of `specs/todo/`, and `CLAUDE.md`, are unstable-only.
- **`#N`** is a legalese PR. Read its `baseRefName`: "fixed by #N" where #N merged into `unstable` is no fix on main. Issues live in `smucclaw/l4-ide` and must be written so; a bare `#N` meant as an issue is a finding.
- **"Tested" and "Independence" claims:** re-run them and compare counts.

### 2. Silent behaviour change

From the diff, not the body, list each behaviour change as `input → old output → new output`. Probe each on `$B` and `$H`, recording exit code and output. **Loud** is a new or changed diagnostic or a non-zero exit; **silent** is exit 0 with a different answer. Name the test that pins each change and show it fails without the change: run the fixture through the base binary and diff against the new golden, or revert the source hunk in a scratch copy and rerun that suite with `--test-options='--match "…"'`. A silent change with no test is blocking.

### 3. Every surface

Run each probe on both builds, through every path the change can reach:

- **`l4`:** `run` (and bare `l4 FILE`), `run --json`, `run --trace`, `check`, `check --json`, `format`, `ast`, `batch`, `trace`, `state-graph`, `render --format html|text|json|plan`, plus anything new in `$H`'s `l4 --help`.
- **REPL:** `printf ':load f.l4\n<expr>\n:q\n' | jl4-repl`.
- `l4 batch` and the REPL re-print the module through `prettyLayout (filterIdeDirectives …)` and re-run it, so they can answer differently from `l4 run`. `jl4-service` filters source text instead, so it can differ from both.
- **`jl4-service --port <p> --store-path $S/store`:** POST `/deployments` (multipart `id` plus a `sources` zip) and poll `/deployments/{id}/updates/{job}`; then `/{id}/functions`, `/{id}/{fn}/evaluation`, `…/evaluation/batch`, `…/query-plan`, `/{id}/openapi.json`, and `/.mcp` `tools/list` and `tools/call`. Kill it by PID.
- **LSP:** main pins it only through the `lsp/hover` and `lsp/semantic-tokens` goldens. If the diff touches `jl4-lsp/`, drive it over stdio or name the gap. **`jl4-wasm`:** only CI builds it; say so if touched.

Report a table of surface × base × head, quoting each output that differs.

### 4. Consumers

For every type, constructor, field, JSON key, output format, schema or message the diff changes, `git grep` at `{HEAD}` across `jl4*/`, `ts-apps/`, `ts-shared/`, `doc/`, goldens and `specs/`. Mark each consumer updated, tested, unaffected (say why) or unverified. A missed Haskell pattern is loud under `-Werror`; string consumers (JSON keys, TypeScript, docs quoting a message) are silent. Then name the consumers outside this repository (the console, `jl4-auth-proxy`, clients of the published OpenAPI and MCP schemas) and say, for each behaviour change in your lens 3 table, what such a client now loses or must be told.

### 5. Removed checks

From `git diff MB {HEAD}`, list every removed or weakened `it`/`shouldBe`, `#ASSERT`/`#CHECK`, golden file, diagnostic line in a golden, error demoted to warning, added `pending`, new `-Wno-` flag, CI step or doc-test exclusion. For each, quote where the PR or a commit says it is deliberate and why; if nothing does, it is a finding.

### 6. Docs and limits

A user-facing change (syntax, verb, flag, diagnostic, output field) needs a page under `doc/`, linked from `doc/SUMMARY.md`; main's `AGENTS.md` adds new keywords to `doc/reference/` and `doc/reference/GLOSSARY.md`. The page states the limits a user will hit. Run every command a changed page quotes with `$H`'s binary and diff the output against the quote. Grep `doc/` for every diagnostic the diff rewords.

### 7. Repo rules main does not carry

From unstable's `CLAUDE.md`:

- **Unstable first** (§1; D9.1 in `specs/todo/RELEASE-MODEL-SPEC.md`): main takes topic PRs carved from unstable. Mark each hunk carried, adapted or main-only against `{UNSTABLE}`; a main-only hunk needs a stated reason. Test every defect you find on `{UNSTABLE}` too, because the prerelease shelf ships from unstable.
- **Goldens** (§3.1): a new `.l4` under main's globs (`jl4/tests/Main.hs`) ships its goldens; read them. `grep -l /Users/` over added goldens: main has no path scrubber, so an absolute path passes locally and fails in CI forever (§3.1.1).
- **Two printers** (§3.2): main has no round-trip test. If the diff touches `L4/Print.hs`, `Parser.hs` or `Syntax.hs`, or adds syntax, compare `l4 run` with `l4 batch` and the REPL on each new or changed corpus file, and check that `l4 format` output still passes `l4 check`.
- **Retired vocabulary** (§7): `git show {UNSTABLE}:etc/check-retired-terms.mjs >$S/crt.mjs; node $S/crt.mjs --dir $H/doc/tutorials $H/doc/courses`, and grep new diagnostics for "binder".
- **Decisions** (§4): every ruling the PR body cites is recorded in a document in the diff, usually `specs/as-built/`, or that is a finding.

### 8. Standing probes

Main has none of these scripts, so take each from `{UNSTABLE}` (`git -C $R show {UNSTABLE}:etc/<probe> >$S/<probe>`) and run it with `node` on your copies of the binaries. Each applies only when the diff touches its paths.

- `jl4-core/src/L4/Parser*`: `node $S/probe-parse-scaling.mjs <copy of $H's l4>`. It FAILs above a ratio of 8 between 4,000 and 1,000 lines.
- `jl4-service/`: `node $S/probe-service-restart.mjs <copy of $H's jl4-service>`, and again with `$B`'s. A difference `$B` shows too is not introduced by the PR; report it as pre-existing.
- `jl4/tests-cli/`: `node $S/probe-cli-crlf.mjs --base $MB $H`, and read every line it names: it is a heuristic.

### 9. Earlier review points

For each point in each earlier review, quote it and say how `{HEAD}` answers it, with evidence. A point answered by a comment, a doc limit, an issue or a later PR, where the review asked for a change, is a blocking finding unless the reviewer has accepted that answer in a comment on the PR. A point the reviewer marked optional may be deferred if `{BODY}` says so.

## Output

Findings only, most severe first. Each has: **lens** (or checklist §); **file:line** at `{HEAD}`; **defect** in one sentence; **evidence**, a command and its output or a quote; **blocking** or **nit**. Label a finding you did not reproduce "unverified". After the findings, list each probe you could not run, and why.

You cannot write a report file. Send the findings by message from the start, in parts of a few thousand characters each, headed "part i of n".
````

## 5. The checklist

Each item generalises one or more points serrynaimo raised in a change-requesting review of a main-bound PR, cited as "#PR r1" or "r2" for the review round.
They are grouped in five kinds.
The lenses of §4 catch many of them; the checklist names the ones a careful reader still has to think to try.

### 5.1 Scale and real conditions

- **Time a parser or checker change at the size users reach.** Time it at 1,000 and 4,000 lines, including a run of one repeated name, not on corpus files alone (#545 r2: 4,000 lines of `f x MEANS i` took 284 s to check, against 0.7 s on main). Probe (a) does this.
- **Exercise the restart.** Anything the service holds after a deploy is checked again after a restart that reads the store (#545 r2: the clause wording of a no-match error was lost after a reload from `bundle.cbor`). Probe (b) does this.
- **Exercise Windows line endings.** A CLI test drops `'\r'` from both sides before it compares output across a line break (#545 r2: `jl4/tests-cli/Main.hs:327`). Probe (c) looks for the shapes that need it.
- **Merge against main as it is now.** Run `git merge-tree` against current `main`, not the branch point, and again after anything merges into `main` (#540 r1: #534 merged meanwhile, and both PRs appended tests at the end of `jl4/tests-cli/Main.hs`).
- **Cover the whole class, not the shapes in the corpus.** A fix to a kind of expression is tested on every shape of the kind, enumerated (#540 r1: an IF-THEN-ELSE or a function call as the left operand of AND/OR still lost its brackets; he enumerated 72 operator pairings and 60 IF/EQUALS expressions).
- **Pin a fix with an input that exercises it.** (#544 r2: none of the 221 schema goldens held a non-ASCII character, so nothing exercised the UTF-8 fix.)
- **Count what a harness runs against what exists.** (#544 r2: eight fixtures were matched by no pattern, so the suite never ran them.)

### 5.2 Drafter mistakes

The person writing L4 misspells names, leaves cases out, and names things as they like.
Try each of these on purpose against any new construct.

- **A typo must not become a new meaning silently.** A misspelt constructor in a pattern binds a new name, so the clauses after it can never be reached; that is a warning in the drafter's terms (#545 r2: `Red` / `Gren` / `Blue` checked clean).
- **Every case analysis the feature claims is checked at compile time,** including literal patterns and groups with no catch-all (#545 r1: a group that missed a case passed `l4 check`; r2: a column of number or string literals with no catch-all is always incomplete, and must warn).
- **Code the drafter wrote is type-checked even when it cannot be reached** (#545 r1: clauses after a catch-all were dropped before type checking, so `l4 check` passed ill-typed rules, and nothing said they were unreachable).
- **Generated code is marked by a flag, not by its name.** A user name spelled like a generated one keeps every check (#545 r1: suppressing by the prefix `__pm_fallthrough_` also silenced a function the user named `__pm_fallthrough_0`, and any CONSIDER the user wrote in clauses 2..n).
- **Every message about generated code speaks of what the drafter wrote, at the drafter's source range.** No internal name, no `<no location>`, no construct the drafter did not write (#545 r1: the run-time error spoke of a CONSIDER where the drafter wrote clauses; type errors named `_pm_arg_1` at no location).
- **A new reading of existing syntax must not capture a program that meant something else.** A file that checks on `main` checks on the branch with the same answers (#545 r2: two overloads, `show n` and `show b`, were fused into one clause group and failed).
- **One mistake, one error.** An unsupported use gets one clear message, and the doc page names the limit (#545 r2, optional: clause groups are top-level only, and a mixfix head gave eleven errors).

### 5.3 Fix, don't document

- **A defect found during the work is fixed, not written up as a workaround.** If it cannot be fixed in this PR, make the failure loud meanwhile (#545 r1: `l4 format` deleted the clause bodies of a multi-clause definition and exited 0, and the PR documented a workaround; he asked for the fix, and a non-zero exit with a diagnostic until then).
- **A golden never blesses output known to be wrong** (#545 r1: three `.ep.golden` files enshrined the lossy `l4 format` output as expected).
- **An admission in a spec is not a test.** A silent behaviour change gets a test that fails without the change, and the PR shows it failing (#547 r1: the bracketing fix had no regression test, though the bug produces no diagnostic; #571 r1: the deployment dedup change had none, and the as-built spec said so).
- **A test guards the call site, not only the function.** If deleting the call that applies a fix leaves every test green, the fix is not pinned (#544 r2: nothing fails if the call at `Handlers.hs:209` or `:797` is dropped).

### 5.4 Specs that read right on main, and full PR descriptions

- **Every citation resolves on `main`.** A `file:line`, commit hash, PR number or work item in a spec, comment or PR body points into the tree the PR merges, not into `unstable` (#547 r1: every line reference in "Where it lives" pointed at unstable's `Print.hs`; #544 r2: a comment spoke of "the other `SInfo`s", where `main` has only one).
- **An as-built spec describes `main` after the merge, not a delta against `unstable`** (#547 r1: the spec read as a delta against unstable work items #214, #334 and #356 and commit `73a953821`).
- **The spec follows the last commit.** When a fix commit changes behaviour, the spec's "Relation to main", "Where it lives" and "Tests" sections change with it (#544 r2: `golden-harness.md:56-60` still said every reader of `infos` sees warnings after `047e910c` stopped that).
- **No private links, no stale locations.** Replace artifact links with the decision text, and keep branch names and `todo/` or `done/` placement current (#545 r2, optional).
- **Docs on `main` agree with the tree** (#544 r2: `AGENTS.md:75` said `not-ok/` holds files that fail, while three `not-ok/export-*.l4` fixtures now had to type-check).
- **The PR description names every user-visible change, good news included, and claims no more than is true** (#540 r1: "the answer the rule says" overstated a partial fix, and changes to `TIMEZONE IS`, prefix `EXPONENT` and `DECLARE`/`ASSUME` layout went unmentioned; #544 r1: it did not say what the change does in the editor; #571 r1: it left out a cross-tenant metadata disclosure it closed on `POST /deployments`, and its agreement with the client's renderer; #545 r2: release notes for `l4 run --json` error text).

### 5.5 Outside consumers

For every changed output, field, message or schema, list who reads it, in this repository and outside it, and what each now loses or must be told.

- **Editor and assistant clients read the language server's rows** (#544 r1: warnings moved into `infos` reached the editor as `#CHECK` rows marked success, 7 rows where `main` sent 4; the inspector panel showed warning text in place of a type; the AI assistant listed them as results).
- **Editor features cover a new construct** (#545 r2, optional: semantic tokens and go-to-definition inside a clause group).
- **Every backend handles a new construct or refuses it** (#545 r2, optional: `jl4-mlir` compiled string and `EXACTLY` patterns as always matching; #571 r1: the `jl4-mlir` parity harness would report differences until its WASM backend took the new encodings).
- **Published schemas match the answers.** Check each `returnSchema` against real responses; `jl4-auth-proxy` publishes them through OpenAPI and MCP (#571 r1).
- **A client keeps what it had, and can tell "could not compute" from "no"** (#571 r1: a batch case refused on a null disappeared from `cases` and should carry its `@id` and the refusal; an omitted answer that used to be a 422 now arrived as null with 200, which a legal decision reads as "no").
- **Operators are told about new costs, and errors name what was checked** (#571 r1: an upload without an id now always compiles and takes a deployment slot, up to `--max-deployments`; a fallback error should name the function and the inputs it checked).
- **Consumers outside this repository are checked, or named as unchecked** (#571 r1: the console's deploy driver).
- **The customer-facing page documents the wire format** (#571 r1: `module-a4-production.md` stopped at the request body).

## 6. The probes

Each probe guards a defect that review found after every test suite had passed.
`etc/verify-branch.sh` runs each when the diff against `--base` touches its paths, on copies of the worktree's binaries, and prints which did not apply.
For a main-bound PR, lens 8 of the prompt runs them from `{UNSTABLE}`, since `main` has none of them.

### (a) Parse time, when `jl4-core/src/L4/Parser*` changes

`node etc/probe-parse-scaling.mjs <l4> [N]` times `l4 check` on N and 4N lines (N is 1,000) of two shapes: ordinary definitions with distinct names (`f1 x MEANS 1`), and one name repeated (`f x MEANS 1`, `f x MEANS 2`, …).
Linear is a ratio of 4, and it FAILs above 8.
It needs both shapes: at the #545 head serrynaimo reviewed in round 2 (`6d0146f27`), 4,000 distinct names checked in about 1 s, while 1,000 lines of one name took 24 to 33 s.
It reads CPU time, user plus system, from `/usr/bin/time -p`, because load moves wall-clock time: on a Mac at load 15 to 30, one wall-clock run of that build took 285 s at 1,000 lines and 1,426 s at 4,000, a ratio of 5, which would have passed.
On that build the probe FAILs: one name took 23.7 s of CPU at 1,000 lines and 503.6 s at 4,000, a ratio of 21, while distinct names scored 2.7.
That run took 11 minutes, under load in which a PASS took about a minute, so a FAIL is slow.
A build from the round-3 fix branch, `fix/clause-group-round3`, passes on both shapes, at 3.7 and 4.1.
`unstable` itself, at `c6f121dee` on 2026-10-09, is quadratic on the repeated name (125, 250 and 500 lines: 0.85, 3.31 and 12.37 s of CPU), so until that fix lands, the probe FAILs on any branch into `unstable` that touches the parser.
`--selftest` runs it on two stand-ins for `l4`, shell scripts whose CPU time grows with a file's line count and with its square, and passes only if the first scores PASS and the second FAIL.

### (b) A restart from the store, when `jl4-service/` changes

`node etc/probe-service-restart.mjs <jl4-service>` starts the service on a fresh store and a free port, deploys an ordinary boolean rule and a rule written as clauses, and makes five calls: the boolean rule twice, its query plan, a matching clause, and an input no clause matches.
It stops the service by PID, checks that `bundle.cbor` was written, restarts it on the same store, waits for both deployments, and makes the same calls; any difference FAILs.
On a build without clause groups it says so and probes the ordinary rule alone.
`--perturb` asks for a different colour after the restart, so a working probe FAILs.
On `6d0146f27`, two of the five answers changed after a restart: the no-match error lost its clause wording, and the query plan of the ordinary rule turned into a 400 ("Can only visualize, as a ladder diagram, a DECIDE that returns a boolean").
Unstable re-checks sources on a restart since `d2dd71f94`, which is not on `main`.

### (c) Carriage returns, when `jl4/tests-cli/` changes

`node etc/probe-cli-crlf.mjs [--base <ref>] <worktree>` reads the lines the branch adds under `jl4/tests-cli/` and names each that compares output across a line break, by whole lines, or whole, without mentioning `'\r'`.
It only warns, because it reads text: it does not see an output passed through a helper first.
No PR check runs on Windows; the one Windows run of `l4-cli-test` is in the release workflow, `main-tag.yml`, dispatched by hand after a merge to `main`.
The fix is the house idiom, `map (filter (/= '\r')) (lines sout)`.
On `6d0146f27` against `main` it names `jl4/tests-cli/Main.hs:327`, the line of the review.
Run on `unstable` against `main`, it names 28 lines that `unstable` has added since; they have not been sorted into real and false, and the real ones are owed before those tests reach `main`.

## 7. A review point is answered as asked

When a review asks for a change, the next push makes that change.
If the author thinks another answer is better, such as documenting the limit, a comment, an issue or a later PR, the author asks the reviewer first, on the PR, and waits for the answer before re-requesting review.
A point the reviewer marked optional, or fine in a later PR, may be deferred without asking, and the PR description says where it went.
The pre-review checks this on every re-request (lens 9).

> **Why.** #545 documented a workaround for `l4 format` destroying clause groups, and round 1 asked for the fix instead.
> Round 2 then had to finish two round-1 points that had been answered in part: "This completes review point 3", and "This completes the compile-time half of review point 4".

## 8. Evidence: the STUNTDOUBLE backtest, 2026-10-08

Five agents, one per PR, reviewed the five main-bound PRs serrynaimo had asked to change, each at the head he reviewed and with the PR description as it stood then.
They could not read his reviews, PR comments, memory files or later commits.
His 33 findings, 23 of them blocking, in 20 root causes, were the answer key; each was scored found (1), partly found (½) or missed (0).
The prompt in §4 is that prompt with the blind-only rules removed, and with `{BODY}`, a sentence in lens 4, lenses 8 and 9, the checklist and the output in parts added; the additions have not been backtested.

| PR    | findings | found    | blocking found  | root causes found |
| ----- | -------- | -------- | --------------- | ----------------- |
| #540  | 5        | 5        | 1 / 1           | 3 / 3             |
| #544  | 4        | 3.5      | 2.5 / 3         | 2 / 2             |
| #545  | 9        | 6        | 6 / 9           | 4 / 4             |
| #547  | 3        | 2.5      | 2.5 / 3         | 2 / 2             |
| #571  | 12       | 5        | 3.5 / 7         | 4 / 9             |
| total | 33       | 22 (67%) | 15.5 / 23 (67%) | 15 / 20 (75%)     |

### What it missed, and where the checklist now asks

- **Generated-code hygiene a reviewer must think to try** (#545 r1: a user name spelled like a generated one; a group that misses a case; an error naming the CONSIDER the drafter never wrote): §5.2.
- **Behaviour it measured and judged acceptable without asking what a client loses** (#571 r1: the batch case counted only in `casesIgnored`; the `returnSchema` mismatches): lens 4's added sentence and §5.5.
- **Saying more in the PR description, good news included** (#571 r1: the closed cross-tenant disclosure; agreement with the client's renderer): §5.4.
- **A consumer outside this repository** (#571 r1: the console's deploy driver): lens 4 and §5.5.
- Halves of #544 r1 (the inspector panel) and #547 r1 (the spec's narrative deltas), and the `Map.toList` simplification (#571 r1), which fits none of the five kinds and is not in the checklist.

### What it found that he had not raised

Two defects it raised that he had not were confirmed live afterwards, the first by reading `main` and `unstable`, the second by a rerun on both: a deontic answer spells one party and action two ways, with and without backticks (#571); and query-plan refuses a boolean rule written as clauses (#545).

### #545 round 2 against the blind run of round 1

At the earlier head, `d0905e1d8`, the blind reviewer flagged three of the six points serrynaimo raised in round 2 at `6d0146f27`: two in full and one as a nit.

- Fusing same-named definitions into one clause group (his point 1): blocking, through a different example. It showed two same-typed `DECIDE`s accepted with the second body dropped where `main` says "multiple definitions"; his were two overloads of different types that stopped checking.
- A clause made unreachable by a misspelt constructor (his point 3): blocking. Its `covered Watr` answered wrongly, with only a redundancy warning at 1:1 naming `__pm_fallthrough_0`.
- The parse slowdown (his point 2): a nit, read as parsing each `DECIDE` twice, which about doubled `l4 check` time. It timed a file of 400 functions and 400 constants, each with its own name, about 2,000 lines. The quadratic needs a run of one repeated name, which that file did not have, so the shape of the file hid it more than its size did. Whether `d0905e1d8` was already quadratic on such a run was not measured.

It missed his other three: literal patterns in the missing-case check, the clause wording after a reload from the cache, and `'\r'` in a new CLI test.
The first is now in §5.2; the second and third are probes (b) and (c).
