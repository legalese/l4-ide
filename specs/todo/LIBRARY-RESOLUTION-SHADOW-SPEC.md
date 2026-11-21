# Library Resolution Shadow Specification

> **Status: IMPLEMENTED on this branch (2026-07-19)** — Stage 1 (Option A
> visibility + Option D resolver de-dup) and Stage 2 (Option B′ surgical
> precedence flip + Option E shadow warning) are implemented in
> `jl4-lsp/src/LSP/L4/Rules.hs` (`resolveLibrary` + `resolveImportShared`, the
> single code path now shared by `GetMixfixRegistry` and `GetImports`), with
> the §3.4 staleness caveat documented in `jl4-core/libraries/README.md` and
> inline in `EmbeddedLibraries/TH.hs`. Targets `unstable` per repo convention.
>
> Implementation notes / deliberate deviations:
>
> - **Option C (`--library-path` flag) deferred** — additive, can land
>   separately (§4C).
> - **Dev-regime gating:** the candidate-order Debug line, the canonicalized
>   winner detail, and the Option E shadow warning are emitted only when
>   `JL4_LIBRARY_PATH` is **unset**. With the env var set the operator has
>   already taken explicit control, and the golden suites pin the variable —
>   their captured logs must stay machine-independent, while the ambient
>   XDG/bundle state this reporting exposes is precisely the machine-dependent
>   part. The incident class (§3.1) lives entirely in the unset regime, which
>   retains full reporting.
> - **Option E gate is content equality**, not path canonicalization: an XDG
>   symlink pointing at byte-identical sources is harmless and stays silent;
>   canonicalization is used for _display_ (the warning prints each symlink's
>   real target). Warned once per configuration per session.
> - **§6 (bundle dir)** left open: B′ keeps the bundle as an ambient tier
>   below the embed, so nothing forces the question yet.
>
> **Amended 2026-09-05 — an implicit `IMPORT prelude` would make the dev-regime
> gate above reachable from every file.** Ruling D8 proposed that every script
> get the prelude without asking. Measured at `88d9f8b9` plus that branch, over
> every `.l4` in the worktree: **283 of 894** files opt into prelude resolution
> today by writing the import; under an implicit one, **all 894** would,
> silently. The failure the repo `CLAUDE.md` §3.1 records — a pinned
> `JL4_LIBRARY_PATH` at a prelude newer than the binary, which presents as
> cascading "could not find a definition" errors rather than as a version
> mismatch — would then be reachable from files that never mentioned the
> prelude, in the one regime where this spec deliberately stays quiet. Three
> files in the tree are named `prelude.l4`, and two of them are fixtures pinning
> this spec's own resolution order (`sibling-wins`, and the vendored copy in
> `jl4/experiments/thailand-cosmetics/`), so an implicit import would also have
> to state which prelude it resolves to and be checked against all four
> `library-shadow` fixtures. This is one of the reasons
> `specs/todo/MODULE-BOUNDARY-SPEC.md` R3 does not build it; see its §5.6.
> Nothing in this spec changed.
>
> **Amended 2026-11-21 — capitals count in a module name (§11).** Built on branch
> `fix/import-case-1080`, not on `main`: every tier matches a module name
> exactly, where the folder tiers used to accept any capitalisation on a
> case-insensitive disk. Its rulings are assumed by GM for Meng's review.

**Status:** Implemented on branch (2026-07)
**Author:** Meng Wong, with analysis from Claude
**Date:** 2026-07-19
**Branch:** `docs/library-resolution-shadow`
**Component:** `jl4-lsp` import resolution (shared by the LSP server and the `l4` CLI check path)
**Classification:** Tier-2 — DX/infra, low-risk, high-annoyance (see `TIER1-WIP-INDEX.md`)

---

## 1. Motivation

### 1.1 Why the search paths exist (this is a good feature)

An installed or bundled `jl4` binary has **no source checkout** to import the
standard library (`prelude.l4`, `math.l4`, …) from. Two commits added a
priority-ordered filesystem search so a deployed binary could still find the
stdlib:

- `8c796c24` (Thomas Gorissen, 2026-01-10) — "Fix library path: go up two levels
  from executable to extension root" — the VSCode extension ships `libraries/*.l4`
  next to the bundled binary, reachable at `<exeDir>/../../libraries`.
- `7d763367` (Meng, 2026-02-05) — "Add XDG and env var library search paths for
  jl4-lsp" — a `cabal install`'d binary looks in the XDG data dir
  (`~/.local/share/jl4/libraries/`), and `JL4_LIBRARY_PATH` is the explicit
  operator override.

The intent was sound: give a binary with no checkout a well-defined way to locate
the stdlib, with an explicit env-var escape hatch for operators. Nothing below
argues against **having** these paths — only against their **ordering relative to
the binary's own hermetic copy**.

### 1.2 The hermetic copy: embedded libraries

Independently, `jl4-core` embeds the entire stdlib into the binary at compile time
via Template Haskell (`L4.API.EmbeddedLibraries`, `.../EmbeddedLibraries/TH.hs`).
`lookupEmbeddedLibrary "prelude"` returns the source that was compiled in. This
copy is **guaranteed to match the binary you built** — it is the one source that
cannot drift from the code that consumes it. In the current ordering it is the
**last** resort, consulted only when every filesystem location misses.

---

## 2. Where the code lives (anchors)

All in `jl4-lsp/src/LSP/L4/Rules.hs` unless noted. Line numbers are as of this
branch's HEAD; treat them as starting points, not guarantees.

| What                                                                        | Location                                            |
| --------------------------------------------------------------------------- | --------------------------------------------------- |
| `data LibraryResolution { resolvedPath, searchedPaths, hasExplicitPath }`   | `Rules.hs:236-240`                                  |
| `resolveLibraryFromFilesystem` (the single filesystem resolver)             | `Rules.hs:252-289`                                  |
| priority list assembly (`envPaths <> [rootPath, relPath] <> discoverPaths`) | `Rules.hs:277`                                      |
| `discoverPaths = [xdgPath, bundledPath]`                                    | `Rules.hs:266-275`                                  |
| **Resolver #1** — inline `resolveImportUri` inside `GetMixfixRegistry`      | `Rules.hs:336-374`                                  |
| **Resolver #2** — `mkImportPath` inside `GetImports`                        | `Rules.hs:431-478`                                  |
| `hasExplicitPath` gate on the embedded fallback                             | `Rules.hs:367`, `Rules.hs:462`                      |
| `LogImportResolution` log payload                                           | `Rules.hs:218`, `Rules.hs:233`                      |
| Embedded-library lookup (TH-compiled stdlib)                                | `jl4-core/src/L4/API/EmbeddedLibraries.hs`          |
| TH embed + `addDependentFile` (build-time datadir)                          | `jl4-core/src/L4/API/EmbeddedLibraries/TH.hs:34-46` |
| CLI check path (uses the same `jl4Rules`)                                   | `jl4-lsp/src/LSP/L4/Oneshot.hs:56`                  |

### 2.1 The actual resolution order (correcting a common miscount)

For a bare module name `<mod>`, each resolver tries, **first match wins**:

1. **VFS** candidates (web/editor in-memory): `project:/<mod>.l4`, importer-dir
   relative, root-dir relative (`Rules.hs:340-347` / `404-415`).
2. **Filesystem** via `resolveLibraryFromFilesystem`, in this order:
   1. `$JL4_LIBRARY_PATH/<mod>.l4` — only if the env var is set
   2. `<rootDirectory>/<mod>.l4` — project root
   3. `<dir-of-importer>/<mod>.l4` — sibling of the importing file
   4. `~/.local/share/jl4/libraries/<mod>.l4` — **XDG data dir (ambient/global)**
   5. `<exeDir>/../../libraries/<mod>.l4` — **VSCode bundle (ambient/global)**
3. **Embedded** copy via `lookupEmbeddedLibrary` — **last**, and skipped entirely
   when `JL4_LIBRARY_PATH` is set (`hasExplicitPath`).

Note two things the folklore gets wrong:

- The runtime filesystem search has **five** locations, not more. `discoverPaths`
  is exactly `[xdgPath, bundledPath]` (`Rules.hs:275`).
- The Cabal `getDataDir`/`Paths_jl4_core` path is **not** a runtime search
  location. It appears only in the **compile-time** TH splice
  (`EmbeddedLibraries.hs:47`) that populates the embedded map. Do not add it to
  the runtime search "to be consistent" — it is already covered by the embedded
  copy. (This conflation is itself a footgun; call it out in review.)

---

## 3. The problem

The ordering runs **every filesystem location — including the two ambient/global
ones — above the binary's own hermetic embedded copy.** For a _deployed_ binary
with no checkout, that is fine. For _development with multiple checkouts or git
worktrees_, it inverts what you want:

- The XDG entry (`~/.local/share/jl4/libraries/`) is, on dev machines, commonly a
  **symlink into one checkout** — a convenience so an installed `jl4` "just works"
  against your working tree. With several worktrees it points at **exactly one** of
  them. Edits made in **any other** worktree are silently overridden: the resolver
  finds the XDG path (step 2.iv) before it would ever reach the worktree you are
  actually editing (unless that worktree happens to be root/importer-relative), and
  **before** the embedded copy. There is **no diagnostic** — the import resolves,
  just to the wrong file.
- The path that "wins" is printed (when logging is on at all — see §3.2) as the
  innocuous `~/.local/share/jl4/libraries/prelude.l4`. The fact that it is a
  **symlink into a different checkout** is invisible, because the resolver never
  canonicalizes the path.

### 3.1 The motivating incident (has happened at least twice)

A session added `@infixl` fixity annotations to its worktree's `prelude.l4`. With
`JL4_LIBRARY_PATH` **unset**, `IMPORT prelude` resolved via the XDG symlink to the
**main checkout's** un-annotated `prelude.l4`. The fixity edits "did not take
effect" — not because the parser ignored them, but because the binary never loaded
the file that contained them. Debugging burned time on the wrong layer (parser,
fixity handling) before the resolution shadow was found.

This is the second occurrence of the pattern; an earlier "XDG library shadow moved
aside" episode was worked around by hand (renaming/moving the offending symlink).
A hand-move is not a fix — the next worktree re-creates the hazard.

Why the project-scoped locations did **not** save the day: in the incident the
importing file's directory and `rootDirectory` did **not** contain a sibling
`prelude.l4`, so steps 2.ii/2.iii missed and resolution fell through to the XDG
symlink (2.iv). This is the normal case for corpus files that `IMPORT prelude`
without keeping a local copy beside them.

### 3.2 Logging exists but does not surface the shadow

`GetImports`/`mkImportPath` **already** logs resolution at `Info`
(`Rules.hs:436-478`, `LogImportResolution`). It did not prevent either incident,
for three compounding reasons:

1. **Wrong resolver.** The `GetMixfixRegistry` inline resolver
   (`resolveImportUri`, `Rules.hs:336-374`) — which decides parser/fixity hints —
   logs **nothing**. So the very resolution that mattered in the fixity incident
   was silent.
2. **Below the surfaced threshold.** `Info` is filtered out in practice: `jl4-repl`
   pins the recorder to `>= Warning` (`jl4-repl/app/Main.hs:96`); the CLI oneshot
   path collects logs into a ref but does not print `Info` to the user
   (`Oneshot.hs:31-37`); the LSP routes `Info` to an editor output channel most
   devs never open (`Logger.hs:280`).
3. **No canonicalization.** Even when shown, the log prints the symlink path, not
   its real target, so "which checkout won" stays hidden.

### 3.3 Two resolvers, one latent hazard

There are **two** independent resolvers: `GetMixfixRegistry`'s inline
`resolveImportUri` (parser-hint resolution) and `GetImports`'s `mkImportPath`
(typecheck-dependency resolution). Today both delegate filesystem lookup to the
same `resolveLibraryFromFilesystem`, so they pick the **same source** given the
same inputs — they are not currently observed to disagree. But:

- Their VFS candidate construction and embedded-fallback handling are **copy-pasted**
  (`Rules.hs:340-374` vs `404-478`), so they can **drift** on the next edit.
- Only one of them logs.

A future divergence here produces the worst possible symptom class: a module that
**parses** (mixfix resolver picked source A) but **does not typecheck** (import
resolver picked source B), with no hint that two different files were loaded.
De-duplicating now is cheap insurance.

### 3.4 The Template-Haskell staleness gotcha (document, do not "fix")

The embedded copy is frozen at **build time**. `embedOneLibrary` calls
`addDependentFile path` (`EmbeddedLibraries/TH.hs:40`) on a **build-time datadir
path** (`Paths_jl4_core.getDataDir </> "libraries"`, resolved by the TH splice at
`EmbeddedLibraries.hs:47`). Consequences a dev must know:

- Editing a **worktree** `jl4-core/libraries/*.l4` does **not** invalidate the TH
  splice unless that worktree's datadir is the one `getDataDir` resolves to at
  build time — so `cabal build` may **not** re-embed your edit, and the binary
  keeps the old stdlib.
- Therefore "make embedded win" (§4, Option B) is **not** a substitute for editing
  the stdlib during development. If you are changing `prelude.l4`, point
  `JL4_LIBRARY_PATH` at the worktree (or force a clean rebuild of `jl4-core`).

This is a documentation/known-gotcha item, not a code change. Any option below that
leans on the embedded copy must state this caveat where devs will read it.

> **Corrected 2026-10-13 (measured; the mechanism above was drifted).** For a
> checkout built with `cabal build` (GHC 9.10.3, Cabal 3.16) the datadir the
> splice resolves **is the checkout**: GHC records
> `<checkout>/jl4-core/libraries/<name>.l4` with a content hash, and recompiles
> `L4.API.EmbeddedLibraries` when one changes. The bullet "unless that worktree's
> datadir is the one `getDataDir` resolves to" therefore describes the normal case,
> not an exception. The staleness is real but sits one step earlier: after an edit
> to `libraries/*.l4` alone, `cabal build` prints `Up to date` and never calls GHC.
> Any real change to a `jl4-core` source file does, and the embed then refreshes;
> `touch` does not. Measurement and wording:
> `doc/reference/libraries/resolution.md`, "The embed-staleness gotcha".

---

## 4. Options

### Option A — Visibility first (cheap; do regardless)

Make the silent shadow a **visible** one, without changing precedence at all.

- Log the **winning** source for every import at a level devs actually see (promote
  the existing `Info` line, or add a dedicated always-on notice on the CLI check
  path), including the **full ordered candidate list** that was tried and which
  index won.
- **Canonicalize** the winning path (`canonicalizePath` / real-path) before logging
  so a symlinked XDG entry prints its real target checkout.
- Mirror the same logging into the `GetMixfixRegistry` resolver so parser-hint
  resolution is no longer silent.

|            |                                                                                                                                                                          |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Pros**   | ~One-line-per-site; would have surfaced **both** incidents immediately; zero behavior change; unblocks diagnosis of any future shadow.                                   |
| **Cons**   | Does not prevent the wrong file from loading — only makes it observable. Noise if over-logged (mitigate: log winner at a visible level, full candidate list at `Debug`). |
| **Effort** | Low.                                                                                                                                                                     |

### Option B — Full precedence flip (embedded wins unless overridden)

Make the embedded copy the **default** source. Consult filesystem locations only
when `JL4_LIBRARY_PATH` is explicitly set (ambient filesystem lookup becomes
opt-out-by-default).

|            |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Pros**   | Hermetic by default: the binary always uses the stdlib it was built with; cross-checkout contamination impossible without an explicit opt-in.                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| **Cons**   | Breaks the legitimate **project-local override** and **sibling file** cases (steps 2.ii/2.iii) that devs rely on — you would have to set `JL4_LIBRARY_PATH` to import a locally-modified `prelude`. Also, per §3.4, embedded may itself be stale, so this can mask worktree edits differently. **Deployment question to resolve:** does the VSCode bundle still need `<exeDir>/../../libraries` at all if the full stdlib is embedded? (Investigate: if the embed already carries the complete stdlib at build time, the bundled `libraries/` dir may be removable, collapsing step 2.v — see §6.) |
| **Effort** | Low-medium (reorder + settle the bundle question).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |

### Option B′ — Surgical precedence flip (RECOMMENDED core; see §5)

Demote **only the two ambient/global locations** (XDG 2.iv, bundle 2.v) to **below**
the embedded copy. Keep the **project-scoped** locations (env 2.i, root 2.ii,
importer-relative 2.iii) **above** embedded.

Resulting order: `JL4_LIBRARY_PATH → root → importer-relative → EMBEDDED →
XDG → bundle`.

|            |                                                                                                                                                                                                                                                                                                                                     |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Pros**   | Preserves every **intentional** override (explicit env var, project-root lib, sibling file) while making a machine-global symlink no longer able to shadow the binary's own stdlib. Directly kills the incident class: a bare `IMPORT prelude` with no local copy now gets the hermetic embedded copy, not a random other checkout. |
| **Cons**   | A dev who _wants_ the XDG symlink to win for a bare import must now set `JL4_LIBRARY_PATH` (this is arguably correct — it makes the override conscious). Slightly more nuanced than a blanket flip.                                                                                                                                 |
| **Effort** | Low (reorder `allPaths` assembly + place the embedded check between project-scoped and ambient tiers; today embedded lives outside `resolveLibraryFromFilesystem`, so this means threading the embedded lookup into the priority list or splitting the ambient tier out — note this for the implementer).                           |

### Option C — Explicit `--library-path` CLI flag

Add a `--library-path DIR` flag (repeatable) to the `l4` CLI that mirrors
`JL4_LIBRARY_PATH`, so overriding library resolution from the command line is always
a conscious act (and scriptable in tests without mutating the environment).

|            |                                                                                                                                   |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------- |
| **Pros**   | Makes override explicit and per-invocation; good for reproducible tests and CI; complements B/B′'s "overrides are opt-in" stance. |
| **Cons**   | New surface area; must agree on precedence between flag and env var (suggest: flag > env var > everything).                       |
| **Effort** | Low-medium.                                                                                                                       |

### Option D — De-duplicate the two resolvers

Factor the VFS-candidate construction, filesystem resolution, and embedded-fallback
into **one** shared helper used by both `GetMixfixRegistry` and `GetImports`, so
parser-hint resolution and typecheck resolution can never pick different sources.

|            |                                                                                                                                                                              |
| ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Pros**   | Eliminates the drift hazard in §3.3 permanently; single place to apply A/B/B′/E; removes copy-paste.                                                                         |
| **Cons**   | Touches both rules; needs care that the mixfix path (which only needs a URI) and the imports path (which needs range + searched-paths for diagnostics) share a return shape. |
| **Effort** | Medium.                                                                                                                                                                      |

### Option E — Ambiguity diagnostic (defense in depth)

When **more than one** resolution source for the same module name exists (e.g. an
XDG copy _and_ a root copy _and_ the embedded copy), emit a **warning** naming all
candidates and the one chosen. Cheap once A/D exist (the ordered candidate list is
already in hand).

|            |                                                                                                                                                                                                           |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Pros**   | Turns "silently picked one of several" into an explicit, actionable warning; the true root-cause signal for the incident class.                                                                           |
| **Cons**   | Could be noisy in normal dev where an XDG symlink legitimately coexists with the embed — gate to "sources resolve to **different real paths** after canonicalization," and consider warn-once-per-module. |
| **Effort** | Low (given A + D).                                                                                                                                                                                        |

---

## 5. Recommended path

Stage the work; ship value early.

- **Stage 1 (do now, independent of any precedence decision): Option A + Option D.**
  Add visible, canonicalized, both-resolver logging of the winning source and the
  ordered candidate list, and de-duplicate the two resolvers so there is one place
  to reason about. This alone would have surfaced both incidents in seconds and
  carries essentially no behavioral risk.

- **Stage 2 (the actual fix): Option B′** — the surgical precedence flip — **plus
  Option E** (ambiguity warning). B′ preserves every intentional override while
  removing the ambient-global shadow, which is the precise failure mode. Fold in
  **Option C** (`--library-path`) if the CLI-override ergonomics are wanted; it is
  additive and can land separately.

- **Leave the B-vs-B′ call to Meng.** If the project decides it wants
  _fully hermetic-by-default_ resolution (nothing off-binary without an explicit
  env var/flag), go to **Option B** and resolve the bundle question in §6. B′ is the
  recommended default because it keeps the project-local override working, which is
  a real dev affordance, not just an ambient accident.

**Always ship (not optional):** the §3.4 TH-staleness caveat as a short note in
developer docs (e.g. a `libraries/README` or the contributing guide) and inline near
`EmbeddedLibraries/TH.hs` — because whichever option lands, a dev editing the stdlib
must know worktree edits don't auto-refresh the embed.

---

## 6. Open question for the implementer: is the bundled `libraries/` dir still needed?

The VSCode bundle ships `libraries/*.l4` (step 2.v) **and** the binary already embeds
the full stdlib at build time. Investigate whether the bundle can drop the on-disk
`libraries/` dir entirely and rely on the embed:

- If **yes**, step 2.v disappears, the VSCode deployment simplifies, and Option B
  collapses toward "embedded + explicit override only."
- If **no** (e.g. the bundle intentionally ships a _newer_ stdlib than the embedded
  binary, or ships extra non-embedded libraries), then 2.v must stay — and that is
  an argument for keeping it **above** embedded for the bundle case specifically,
  which B′ would need to special-case or accept.

Resolve this before committing to B vs B′, because it determines whether the
ambient tier is one path or two.

---

## 7. Non-goals

- Changing VFS (web/editor in-memory) resolution — that layer is orthogonal and
  correct; the shadow is entirely in the filesystem tier.
- Supporting relative/absolute import paths (still bare module names only, per the
  `GetImports` NOTE at `Rules.hs:402`).
- Redesigning the embedded-library mechanism or the TH embed. §3.4 is a
  documentation item, not a rework.
- A package manager / versioned library store. Out of scope; if it ever lands it
  supersedes this.

---

## 8. Acceptance criteria

1. For any `IMPORT`, the binary logs — at a level a dev sees on the CLI check path
   and in the LSP without opening a rarely-used channel — the **module name**, the
   **ordered list of candidate sources tried**, the **index that won**, and the
   **canonicalized real path** of the winner. Verified: a symlinked XDG entry prints
   its real target checkout, not the symlink path.
2. The `GetMixfixRegistry` resolver and the `GetImports` resolver produce identical
   resolution logs for the same import (ideally because they now share one code
   path — Option D). No import can parse against source A while typechecking against
   source B.
3. With `JL4_LIBRARY_PATH` **unset** and no project-local/sibling copy, a bare
   `IMPORT prelude` resolves to the **embedded** stdlib (Option B′), **not** to a
   machine-global XDG/bundle file. Regression: reproduce the §3.1 incident (edited
   worktree `prelude.l4` + un-annotated main-checkout XDG symlink) and confirm the
   annotated worktree copy is used **when it is the project-local/root/sibling
   source**, and the embedded copy (not the symlink) is used otherwise — in both
   cases the log names the real winner.
4. Project-scoped overrides still work: a `prelude.l4` in the project root or beside
   the importing file **wins** over the embedded copy (Option B′ preserves 2.ii/2.iii
   above embedded).
5. When two candidates resolve to **different real paths**, a warning names all
   candidates and the chosen one (Option E).
6. (If Option C lands) `l4 check --library-path DIR …` resolves libraries from `DIR`
   with clearly-specified precedence over `JL4_LIBRARY_PATH`, exercised by a CLI
   test that does not mutate the process environment.
7. The §3.4 TH-staleness caveat is documented where a stdlib-editing dev will
   encounter it.
8. Existing import/typecheck behavior for deployed binaries (no checkout) is
   unchanged: an installed/bundled binary with no filesystem stdlib still resolves
   the stdlib (now from the embed, or from the bundle if §6 keeps it).

---

## 9. Test sketch

- **Unit (resolver):** table-drive `resolveLibraryFromFilesystem` (and the unified
  helper) over synthetic dirs: env-set vs unset × {root has copy, sibling has copy,
  only XDG symlink, nothing on disk}. Assert the winning index and that
  canonicalization dereferences the symlink.
- **Regression (`.l4` corpus):** an `ok/` fixture that `IMPORT`s a library whose
  **only** on-disk copy is a symlink to a _different_ content than the embed, run
  with `JL4_LIBRARY_PATH` unset; assert it typechecks against the embedded copy and
  the log names the embed. A companion fixture with a root-local override asserts the
  override wins.
- **Two-resolver parity:** a fixture using cross-module **mixfix** _and_ a normal
  typecheck dependency on the same imported module; assert both resolvers log the
  same real path (guards §3.3).

---

## 10. Rulings recorded from a bench

The service's shorter ladder (`LibraryScope` / `EmbeddedStdlibOnly`, `jl4-service`'s
`bundleScope`; `doc/reference/libraries/resolution.md`, "the resolution order") was
built before it was ruled, and is now ruled.

- **R5 = A**, bench "Main Wave Rulings", no note, 2026-10-12,
  https://claude.ai/artifact/Lpj7TuD6CMHQ5v63yxSGnb. A deployment resolves its own files and
  the built-in stdlib, nothing from the host. Conditions: (1) a `WARN` naming the
  deployment and the module whenever a compile or a restart meets an unresolved `IMPORT`
  (a warning now, a refusal only by a later ruling; the deploy API is unchanged);
  (2) `resolution.md` says the service reads neither `JL4_LIBRARY_PATH`, the working
  directory nor the XDG store; (3) an operator note in the main PR's Operators section,
  no code: before a host is upgraded, its operator checks `/var/lib/jl4-service/.env` and
  the XDG store for libraries a deployment needs.
- **R3 = A**, bench "Main Wave Rulings", no note, 2026-10-12,
  https://claude.ai/artifact/Lpj7TuD6CMHQ5v63yxSGnb. Deployments run on the service's
  built-in stdlib; `ts-apps/vscode/src/sidebar-provider.ts` keeps skipping `jl4-embedded:`
  imports when it zips a deployment. Condition: a later, non-blocking PR has the extension
  warn at deploy time when its stdlib differs from the service's, the service reporting a
  stdlib hash. Recorded only; that warning is not built.

---

## 11. The case rule for module names (smucclaw/l4-ide#1080)

> **Status (2026-11-21): built on branch `fix/import-case-1080`; not on `main`.**
> Every ruling in §11.3 was made by GM on Meng's behalf while he was away, and each is labelled "assumed (GM, 2026-11-21), for Meng's review"; none is ANSWERED by Meng.
> `jl4-core/src/L4/Import/ModuleNameCase.hs` cites this section by number, so renumbering it is a breaking change.

### 11.1 The defect, measured

A module is named by its file's name, and an `IMPORT` names a module.
The embedded tier, the in-memory tier (a map keyed by URI), the API/WASM resolver (`apiModuleLookup`, `jl4-core/src/L4/API/VirtualFS.hs`) and `jl4-service`'s bundles always compared that name exactly.
The folder tiers of `resolveLibrary` (1, 2, 3, 5 and 6 in the table under "The resolution order" in `doc/reference/libraries/resolution.md`; §2.1 above predates that order) asked `doesFileExist` (`git show 536c95336:jl4-lsp/src/LSP/L4/Rules.hs`, line 501), which a case-insensitive disk, the macOS and Windows default, answers yes for any capitalisation; the file was then loaded under the spelling the `IMPORT` used.
So one source line meant different things on different machines: `jl4/experiments/carInsurance.l4:2` wrote `IMPORT dayDate`, which a Mac with `JL4_LIBRARY_PATH` set resolved and Linux, the web playground and `jl4-service` did not.

Measured with two `l4` binaries: the base, built from `unstable` at `536c95336` plus only this branch's first commit, "fix(experiments): carInsurance.l4 imports `daydate`, the library's own spelling", which changes nothing but `jl4/experiments/carInsurance.l4`; and the branch, built at the commit "feat(import): the web playground and jl4-service name the spelling too (#1080)", the last before this section's commit that changes what the code does (this section's commit changes one comment).
The table was first measured before the review of 2026-11-21, and re-run on 2026-11-21 UTC after GM's revision of finding A, on the binary built at "feat(import): the web playground and jl4-service name the spelling too (#1080)" as it then stood: the outputs of all 17 runs are byte-identical to the first run's.
Both ran on nye, in folders on an HFS+ volume (case-insensitive), `HOME` an empty folder unless stated, `JL4_LIBRARY_PATH` unset unless stated, `JL4_FIXED_NOW` pinned, under `sandbox-exec` with the network denied; each run's exit code and output size were checked before its text was compared.

| probe | the file                                                                                                         | base                                                                                                                                                                     | branch                                                                                                           |
| ----- | ---------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| P1    | `IMPORT dayDate` (`carInsurance.l4`), no library files                                                           | exit 1, not found, no hint                                                                                                                                               | exit 1, not found, the hint names `daydate`                                                                      |
| P2    | P1 with `JL4_LIBRARY_PATH` at `jl4-core/libraries`                                                               | exit 0: `daydate.l4` loaded as `dayDate`                                                                                                                                 | exit 1, not found, the hint                                                                                      |
| P4    | `IMPORT daydate` and `IMPORT dayDate`, `JL4_LIBRARY_PATH` set                                                    | exit 1: one file loaded twice, `Date` has "multiple definitions"                                                                                                         | exit 1, one not-found with the hint, no double load                                                              |
| P6    | `IMPORT Helper` beside `helper.l4`                                                                               | exit 0                                                                                                                                                                   | exit 1, the hint names `helper`                                                                                  |
| P7    | `IMPORT Helper` and `IMPORT helper` beside `helper.l4`                                                           | exit 1, "multiple definitions"                                                                                                                                           | exit 1, one not-found with the hint                                                                              |
| P8    | `main` imports `Shapes`, its import `mid` imports `shapes`                                                       | exit 1, "multiple definitions"                                                                                                                                           | exit 1, one not-found with the hint naming `shapes`                                                              |
| P9    | `l4 export dmn` on a copy of `jl4/examples/dmn/gst-rate.l4` that writes `IMPORT dayDate`, `JL4_LIBRARY_PATH` set | exit 0, 9 blocking findings against 3 for the `daydate` spelling: the exporter recognises the library by the basename `daydate.l4` (`jl4-core/src/L4/Dmn/Lower.hs:1074`) | exit 1, not found, the hint; the `daydate` spelling's output byte-identical                                      |
| P10   | `IMPORT dayDate`, `daydate.l4` in the XDG store                                                                  | `l4 run` gives 7, from the XDG copy: the embedded tier, compared exactly, missed, so nothing shadowed and no warning was printed                                         | exit 1, not found, the hint; `IMPORT daydate` byte-identical (the shadow warning, as before)                     |
| P11   | `` IMPORT `café` `` beside `café.l4`, which HFS+ lists decomposed                                                | `l4 run` gives 5                                                                                                                                                         | byte-identical: the disk's answer is kept (§11.2)                                                                |
| P12   | `IMPORT math` beside `Math.l4`                                                                                   | `l4 run` gives 11 from `Math.l4`, with the shadow warning                                                                                                                | exit 1 (`siblingMarker` undefined): the embedded `math` is used, and the skipped-variant warning names `Math.l4` |

P9 on the branch also reports three `__GEQ__` "multiple definitions": with `daydate` missing, a date comparison has nothing to resolve to, so that is a consequence of the refusal, not a double load.

### 11.2 The rule, and how each host applies it

**Capitals count on every tier.**
A tier holds `<mod>` only when its folder has an entry spelled exactly `<mod>.l4`.
`L4.Import.ModuleNameCase` (jl4-core) states it once: `classifyEntry` sorts a folder's listing into an exact entry, entries equal to it under full case folding (`Text.toCaseFold`), or neither; `caseVariantHint` is the sentence.
Full folding equates more than capitals: `ß` with `ss`, `ς` with `σ`.
The default Mac disk does too (measured 2026-11-21 on nye: on APFS a folder holding `straße.l4` answers yes for `strasse.l4`, `STRASSE.l4` and `STRAẞE.l4`, and one holding `οδος.l4` yes for `οδοσ.l4` and `ΟΔΟΣ.l4`; on HFS+ all five answer no), so those files are refused and offered like any variant.
But `strasse` and `straße` do not differ in capitals, so `differsOnlyInCapitals` decides the wording: "Capital letters count in a module name" only when it is true, and otherwise "Module names must match exactly, letter for letter".
`resolveLibrary` is `resolveLibraryWith realLibraryProbe` (`jl4-lsp/src/LSP/L4/Rules.hs`), and the probe is injectable, so a test can stand in a case-insensitive or a case-sensitive disk on any OS.
Pass 1 refuses a file the disk reports only when the folder lists it under other capitals; a folder that cannot be listed keeps the disk's answer and logs one Debug line.
Pass 2 lists the folder of every folder tier above the winner (every tier when nothing won), whatever the disk said, so the near misses, and the hint and the warning built on them, are the same on Linux as on a Mac; each folder is listed at most once per resolution.
The importing file is never a near miss of its own `IMPORT`: it is refused like any variant, but `Foo.l4` writing `IMPORT foo` is not told to import `Foo` or to rename itself, either of which would make it import itself (§5's trap in `CLAUDE.md`). It is set apart instead (`importerCaseVariant`), and when it is the only near match the error and the warning say so, and that a module cannot import itself (`ModuleNameCase.selfImportHint`; §11.4). It is recognised by canonical path, because from `l4 check Foo.l4` the importer is the relative `Foo.l4` and the folder's entry `./Foo.l4`.
The API/WASM resolver and `jl4-service` always looked up exactly, and gain only the sentence: `typecheckWithDependenciesKnowing` takes the names the host can see and the name of the module being checked, and the service's `Bundle IMPORT resolves to nothing` `WARN` gains a `hint` field.
Neither offers the importing module: the service leaves the importing file out of the names, and the API resolver leaves out every module whose resolution was in progress (`ModuleNotFound`'s third field) and the module being checked. Both give `selfImportHint`'s line when the importing module is the only near match, except, in the API resolver, for a module below the one being checked, whose error names no file.

A name listed in another Unicode normal form is "neither", not a variant, so for it the disk's yes stands (P11), and that is the accepted limit of C5 below.

### 11.3 Rulings

- **C1 = exact case on every tier, plus a hint in the not-found error**, and fix `jl4/experiments/carInsurance.l4:2` in the same branch: option C of the #1080 design, which is not this spec's Option C (the `--library-path` flag of §4). Assumed (GM, 2026-11-21), for Meng's review.
  Measured: P1, P2, P4, P6 to P10 above, and the sweep in §11.5, which finds `carInsurance.l4` the only tracked file the rule changes.
  The hint is one line, second in the message, only when a module of nearly that name is visible:
  ``Capital letters count in a module name: `dayDate` and `daydate` are different names. Did you mean `daydate`?``
  With several: ``Capital letters count in a module name: `dayDate` is a different name from each of these. Did you mean one of: `DayDate`, `daydate`?``
  When a name offered differs by more than capitals (§11.2): ``Module names must match exactly, letter for letter: `strasse` and `straße` are different names. Did you mean `straße`?``
- **C2 = the hint on every surface**: the CLI and the language server, the web playground (its in-browser checker, `l4Check`, through `checkWithImports`) and `jl4-service`. Assumed (GM, 2026-11-21), for Meng's review.
  The core owns the comparison and the sentence (`ModuleNameCase`), and each host supplies only the names it can see.
- **C3 = warn when a variant above the winner is skipped**, even when the import resolves (P12), once per configuration per session, like the shadow warning, naming the skipped file. Assumed (GM, 2026-11-21), for Meng's review.
  Its text, for P12:
  ``Warning | [Import Resolution] `IMPORT math` did not use `Math.l4` beside the importing file, because capital letters count in a module name: `Math` and `math` are different names.``
  ``It used the standard library's `math` instead.``
  ``To use that file, change the IMPORT to `Math`, or rename the file to `math.l4`.``
  Its other wordings, for a file whose name differs by more than capitals or in its extension, are in §11.4.
- **C4 = no warn-first release**: the refusal is immediate. Assumed (GM, 2026-11-21), for Meng's review.
- **C5 = accept the Unicode residual and document it; no new dependency.** Assumed (GM, 2026-11-21), for Meng's review.
  A non-ASCII name that differs from its file in both normal form and capitals (`` IMPORT `CAFÉ` `` for a decomposed `café.l4` on HFS+) is still accepted on such a disk; `ModuleNameCaseSpec` pins that answer, so closing it later is a visible change.
- **C6 = this section is the owning record**, and `specs/as-built/import-resolution.md` says where the rule stands relative to `main`. Assumed (GM, 2026-11-21), for Meng's review.
- **C7 = the skipped-variant warning in the editor**: published as a Warning diagnostic on the `IMPORT` line, with the log line's text. Assumed (GM, 2026-11-21), for Meng's review; its own commit, which reverts alone.
  `GetImports` publishes it on every check, from `ImportOutcome.skippedCaseVariantWarning`, so it is never given for an `IMPORT` inside the embedded library (§11.4), and it is pinned by `jl4-lsp/test/SkippedVariantDiagnosticSpec.hs` (P12's text and range, the text for `Math.l4` writing `IMPORT math`, and two controls).
  Because the command line runs the same rule and prints every diagnostic, `l4 check` prints it too, after the log line, and `--json` carries one more `diagnostics` entry (measured on P12); keeping it out of the command line would need the rule to know its host (assumed, not ruled).
  The log line is kept, once per session (assumed, not ruled), because `jl4-repl` by default shows log lines and not diagnostics; the cost is that `l4 check` prints the warning more than once (§11.7).

### 11.4 Choices made in building, assumed, not ruled

- The hint names only `.l4` variants: a `daydate.L4` is refused, but not suggested.
- The language server's hint does not name a variant held only in an unsaved editor buffer (tier 0); reading those would need an untracked read of the VFS, and the web playground checks one buffer.
- No embedded name is suggested when `JL4_LIBRARY_PATH` is set, because then the embedded tier is not searched and the suggestion would not resolve.
- Near misses are collected only above the winner; a variant below it could not have won under any rule, and is not mentioned.
- The skipped-variant warning is printed whether or not `JL4_LIBRARY_PATH` is set, unlike the shadow warning, because the file passed over is the user's own and not ambient machine state; it names files by name and their tier in words, never by path, so it is the same on every machine and cannot make a golden machine-dependent.
- In `jl4-service` the names offered are the stdlib's and the bundle's `.l4` files in the two folders the resolver probes for that importer: its own, and the session root (the folder of the bundle's first path).
- Full case folding for the comparison, with the capitals wording only where the names differ in capitals alone (review finding D; §11.2).
- The skipped-variant warning's reason and fix follow the file in hand (review finding C):
  ``because module names must match exactly, letter for letter: `straße` and `strasse` are different names`` for a difference beyond capitals;
  ``because a module's file name must end in `.l4`, in small letters`` and only ``To use that file, rename it to `prelude.l4`.`` for `prelude.L4`, since an `IMPORT` names no extension and so no spelling of it reaches the file;
  ``because a module's file must be named exactly `math.l4`, and capitals count`` and only the rename for `Math.L4`.
  With several files, the capitals wording only when every one differs in capitals alone and ends in `.l4`, and "change the IMPORT" offered only for the files it can reach.
- The importing file is never offered by the hint, and the warning never tells it to change the `IMPORT` or to rename itself (review finding A, as revised by GM on 2026-11-21; §11.2). When it is the only near match, both say what is true instead. The not-found line, for `Foo.l4` writing `IMPORT foo` with no other `foo`:
  ```foo` differs from `Foo`, the name of this file's own module, only in its capitals. If you meant this file, remove the IMPORT: a module cannot import itself, and a file's own definitions need no IMPORT.``
  The warning, for `Math.l4` writing `IMPORT math`:
  ``Warning | [Import Resolution] `IMPORT math` did not use `Math.l4`, which is the importing file itself: `math` differs from `Math`, the name of this file's own module, only in its capitals.``
  ``It used the standard library's `math` instead.``
  ``If you meant this file, remove the IMPORT: a module cannot import itself, and a file's own definitions need no IMPORT. If you meant the standard library's `math`, nothing needs to change.``
  For a difference beyond capitals the clause is `only in how its letters are written`. When other files are near too, only they are named. Neither line is given for an importing file whose name differs from the `IMPORT` only in its extension's capitals (`math.L4`), nor, in the API resolver, for a module below the one being checked, whose error names no file.
  In the API resolver every module whose resolution is in progress is left out, not only the importing one, because it keeps them as a set and importing any of them is a cycle; the CLI, the editor and the service leave out only the importing file.
- The skipped-variant warning is not given for an `IMPORT` written inside the embedded library, recognised by its `jl4-embedded:` URI (review finding B): `currency` writes `IMPORT jurisdiction`, and a user's `Jurisdiction.l4` in the project root drew a warning about an `IMPORT` the user did not write. The case rule still keeps that file from the library's import.

### 11.5 Evidence

- Tests: `jl4-core/test/ModuleNameCaseSpec.hs` (pure); "the case rule (#1080)" in `jl4-lsp/test/LibraryResolutionSpec.hs` (stand-in disks of both kinds, so the refusal is visible on Linux and listing-whatever-the-disk-said is visible on a Mac); `skippedCaseVariantMessage` and `selfCaseVariantMessage` in `jl4-lsp/test/ImportDiagnosticSpec.hs`; "l4 IMPORT: capitals count in a module name (#1080)" in `jl4/tests-cli/Main.hs` (temporary folders, so no case-pair file is tracked); `jl4-core/test/ImportResolutionSpec.hs`; `jl4-service/test/UnresolvedImportSpec.hs`.
- Mutation checks, one line each, against `jl4-lsp-test` and the CLI groups "#1080", "library resolution" and "#971", measured before the review of 2026-11-21 on the tests as they then stood: refusal turned off fails 6 `jl4-lsp-test` examples (3 on the case-insensitive stand-in, which fail on Linux too, and 3 on the real disk, which fail only on a case-insensitive one) and 3 CLI examples (real disk, so on a case-insensitive one only); near misses taken only after the disk says yes fails 2 (the case-sensitive stand-in); the hint dropped fails 4 CLI examples; the skipped-variant warning dropped fails 1, and warned on every resolution instead of once fails 1.
  Review added examples, and those counts were not re-taken.
  Two mutations were measured after it: the embedded-importer check switched off fails 1 CLI example (the standard-library one), and the session root taken out of the service's hint fails 1 `jl4-service-test` example (the root one), each the only failure.
  Two more were measured on 2026-11-21 UTC, after GM's revision of finding A, against `jl4-lsp-test` (262 examples) and the three CLI groups (28): `selfImportHint` taken out of the not-found line fails 1 CLI example (`Foo.l4` writing `IMPORT foo`), and the guard of the importing-file warning inverted fails 1 CLI example (`Math.l4` writing `IMPORT math`), each the only failure.

- The sweep: `l4 check` on every tracked `.l4` file that has an `IMPORT` line (666 files, `git grep -l -E '^[[:space:]]*IMPORT[[:space:]]' -- '*.l4'`), run from each file's own folder with the base binary of §11.1 and the branch binary built before the review, once with `JL4_LIBRARY_PATH` unset and once set to `jl4-core/libraries`, sandboxed as in §11.1. All 2,664 runs started (exit 0 or 1, none empty, none timed out), and each file's output is byte-identical on the two binaries in both regimes. So with `carInsurance.l4` corrected by this branch's first commit, no tracked file depends on a capitalisation the disk forgave; that file's old line is P1 and P2.
  The review's changes alter only the hint and the skipped-variant warning, and no run of the sweep printed either: `Did you mean`, `did not use`, `Capital letters count` and `letter for letter` occur in none of the 1,332 branch-side outputs, and occur in all 3 of the review's own outputs used as a positive control.
  GM's revision of finding A (2026-11-21) adds a line only for a file whose `IMPORT` names its own module under other capitals, and no tracked file does: comparing every `IMPORT` in the 1,600 tracked `.l4` files with its file's own name under full case folding finds none (the one exact self-import, `jl4/tests-cli/fixtures/selfimport/solo.l4`, is not a near match and is unaffected). So the sweep was not re-run.

### 11.6 What review changed

- A first draft of the tests used only the real disk and a case-insensitive stand-in, and a review pointed out that a resolver which lists a folder only after the disk says yes would pass all of them on a Mac and silently lose the hint on Linux. The case-sensitive stand-in (`caseSensitiveDisk`) and its two examples were added for that; the mutation check above shows they catch it.
- The review of 2026-11-21 found that the importing file could be offered to itself (A), that the warning fired for an `IMPORT` inside the standard library (B), that the advice for a `.L4` file named a spelling that does not resolve (C), that full case folding made the "capital letters" sentence false for `ß` and `ς` (D), that no `jl4-service` test failed with the session root taken out of the hint (I), and that this section did not record the cost of listing folders (J, §11.7). Each fix is in the commit that introduced the code, and each commit message says which finding it answers.
- GM revised two findings on 2026-11-21. A: instead of leaving the importing file out silently, say what is true, that the `IMPORT` is the file's own module name under other capitals and that a module cannot import itself (§11.4). E: no commit of this branch is cited by its hash, in a commit message or in the tree; a commit is cited by its subject, and a tree by what it was (§11.1).

### 11.7 Known limits

- **The cost of listing folders.** Pass 2 lists the folder of every tier above the winner on every resolution, the project root included, and two rules resolve every `IMPORT`. Measured by the review on 2026-11-21, `l4 check` of a file with 11 stdlib `IMPORT`s: 2.06 s with 2 entries in the root, 2.45 s with 5,000, about 8.2 s with 100,000, and within noise at 350. The largest folder of this tree that holds `.l4` files, `jl4/examples/ok`, has 344 entries (`ls -A | wc -l`, 2026-11-21 UTC; the review counted 346). There is no cache across resolutions (review finding J; assumed, not ruled); one would have to be invalidated when a file is added or renamed.
- **A folder that cannot be listed** keeps the disk's answer, so on a case-insensitive disk it still accepts any capitalisation; the only sign is a Debug line, which the CLI does not print.
- **`.L4` files** are refused, but the not-found hint does not suggest them, because no `IMPORT` reaches one; the skipped-variant warning names one and says to rename it.
- **A file that imports its own name under other capitals and means the library** (`Math.l4` writing `IMPORT math` for the standard library's `math`) is warned on every check, and nothing silences it short of renaming the file to a name that is not `math` in any capitals.
- **An importing file whose name differs from its `IMPORT` only in its extension's capitals** (`math.L4` writing `IMPORT math`) gets neither the not-found line nor the warning about itself. Measured 2026-11-21 UTC on HFS+ with an `l4` built from this branch: `math.L4` writing `IMPORT math` checks with no warning, and `foo.L4` writing `IMPORT foo` gets the not-found error with no line about itself. No test pins it.
- **In the REPL, an expression typed for a file that imports its own name under other capitals gets the advice meant for another file.** `jl4-repl` evaluates each expression in a new in-memory file beside the loaded one (`.repl_eval_1.l4`, `.repl_trace_1.l4` and so on) that holds a copy of the loaded file's text, and from there the loaded file is not the importing file. So for `Math.l4` writing `IMPORT math`, loading the file gives the warning about itself, and the first expression then adds the warning for a file beside the importing file, ending ``To use that file, change the IMPORT to `Math`, or rename the file to `math.l4`.``, either of which would make `Math.l4` import itself. Measured 2026-11-21 UTC on HFS+ with a `jl4-repl` built from this branch: `1 PLUS 1` gave that second warning and `:trace 1 PLUS 1` nothing more, since each warning is given once per session. No test pins it.
- **The editor's hint ignores unsaved buffers** (§11.4).
- **A library loaded from a folder tier** (the XDG store, the editor bundle) has a `file:` URI, so its own `IMPORT`s are not recognised as the library's, and a variant above the winner is still reported for them (finding B covers only the embedded library).
- **In the editor, the shadow warning reaches only the log** (the review of 2026-11-21): the shadow warning (Option E) is a log line, which an editor shows in its output channel, not in its list of problems, so an editor user sees an error such as "could not find a definition" first. C7 closes that gap for the skipped-variant warning only; the shadow warning is left as it is.
- **`l4 check` and `l4 run` print the skipped-variant warning more than once**: once as the log line, and once in each block of diagnostics the command line prints, a block each time the file's diagnostics change. Measured 2026-11-21 UTC on HFS+ with an `l4` built from this branch: P12 prints it 3 times (the log line, then both blocks, the second added by the checker's error), and `l4 check --json` has 3 `diagnostics` entries, all carrying it; with nothing else wrong (`IMPORT math` and `#EVAL 1 PLUS 1` beside `Math.l4`), `l4 check` prints it twice and `l4 run` 3 times, the `#EVAL` result adding a block. Printing a diagnostic again in each block that holds it is the command line's existing behaviour, not this rule's. The log line is kept (assumed, not ruled) because the REPL shows nothing else: `jl4-repl` shows only log lines at Warning and above unless started with `--verbose` (`jl4-repl/app/Main.hs`, its recorder's filter), and a host with no editor prints its diagnostics as a log line at Info (`LogDiagsDiffButNoLspEnv`, `jl4-lsp/src/LSP/Core/Shake.hs`); measured the same day, for P12 and for `Math.l4` writing `IMPORT math`, the REPL printed the log line and no diagnostic. The editor shows the diagnostic in its list of problems and the log line only in its output channel, since the server logs to stderr (`jl4-lsp/app/Server.hs`; read, not measured). `l4 batch` shows neither for a file that checks: the row's `diagnostics` is empty and nothing else is printed (measured).
- **The Unicode residual** of C5.
