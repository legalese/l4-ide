# Library Resolution Shadow Specification

> **Status: TODO** — design sketch only, not yet implemented. Targets `unstable`
> per repo convention. Branch `docs/library-resolution-shadow`. No PR yet.
> This document specifies a **DX/infra fix** to L4's `IMPORT` library-resolution
> ordering; it does **not** contain the Haskell patch. A follow-up session should
> implement against the acceptance criteria in §8 and the anchors in §2.

**Status:** Proposed (2026-07)
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

| What | Location |
| --- | --- |
| `data LibraryResolution { resolvedPath, searchedPaths, hasExplicitPath }` | `Rules.hs:236-240` |
| `resolveLibraryFromFilesystem` (the single filesystem resolver) | `Rules.hs:252-289` |
| priority list assembly (`envPaths <> [rootPath, relPath] <> discoverPaths`) | `Rules.hs:277` |
| `discoverPaths = [xdgPath, bundledPath]` | `Rules.hs:266-275` |
| **Resolver #1** — inline `resolveImportUri` inside `GetMixfixRegistry` | `Rules.hs:336-374` |
| **Resolver #2** — `mkImportPath` inside `GetImports` | `Rules.hs:431-478` |
| `hasExplicitPath` gate on the embedded fallback | `Rules.hs:367`, `Rules.hs:462` |
| `LogImportResolution` log payload | `Rules.hs:218`, `Rules.hs:233` |
| Embedded-library lookup (TH-compiled stdlib) | `jl4-core/src/L4/API/EmbeddedLibraries.hs` |
| TH embed + `addDependentFile` (build-time datadir) | `jl4-core/src/L4/API/EmbeddedLibraries/TH.hs:34-46` |
| CLI check path (uses the same `jl4Rules`) | `jl4-lsp/src/LSP/L4/Oneshot.hs:56` |

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
ones — above the binary's own hermetic embedded copy.** For a *deployed* binary
with no checkout, that is fine. For *development with multiple checkouts or git
worktrees*, it inverts what you want:

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

| | |
| --- | --- |
| **Pros** | ~One-line-per-site; would have surfaced **both** incidents immediately; zero behavior change; unblocks diagnosis of any future shadow. |
| **Cons** | Does not prevent the wrong file from loading — only makes it observable. Noise if over-logged (mitigate: log winner at a visible level, full candidate list at `Debug`). |
| **Effort** | Low. |

### Option B — Full precedence flip (embedded wins unless overridden)

Make the embedded copy the **default** source. Consult filesystem locations only
when `JL4_LIBRARY_PATH` is explicitly set (ambient filesystem lookup becomes
opt-out-by-default).

| | |
| --- | --- |
| **Pros** | Hermetic by default: the binary always uses the stdlib it was built with; cross-checkout contamination impossible without an explicit opt-in. |
| **Cons** | Breaks the legitimate **project-local override** and **sibling file** cases (steps 2.ii/2.iii) that devs rely on — you would have to set `JL4_LIBRARY_PATH` to import a locally-modified `prelude`. Also, per §3.4, embedded may itself be stale, so this can mask worktree edits differently. **Deployment question to resolve:** does the VSCode bundle still need `<exeDir>/../../libraries` at all if the full stdlib is embedded? (Investigate: if the embed already carries the complete stdlib at build time, the bundled `libraries/` dir may be removable, collapsing step 2.v — see §6.) |
| **Effort** | Low-medium (reorder + settle the bundle question). |

### Option B′ — Surgical precedence flip (RECOMMENDED core; see §5)

Demote **only the two ambient/global locations** (XDG 2.iv, bundle 2.v) to **below**
the embedded copy. Keep the **project-scoped** locations (env 2.i, root 2.ii,
importer-relative 2.iii) **above** embedded.

Resulting order: `JL4_LIBRARY_PATH → root → importer-relative → EMBEDDED →
XDG → bundle`.

| | |
| --- | --- |
| **Pros** | Preserves every **intentional** override (explicit env var, project-root lib, sibling file) while making a machine-global symlink no longer able to shadow the binary's own stdlib. Directly kills the incident class: a bare `IMPORT prelude` with no local copy now gets the hermetic embedded copy, not a random other checkout. |
| **Cons** | A dev who *wants* the XDG symlink to win for a bare import must now set `JL4_LIBRARY_PATH` (this is arguably correct — it makes the override conscious). Slightly more nuanced than a blanket flip. |
| **Effort** | Low (reorder `allPaths` assembly + place the embedded check between project-scoped and ambient tiers; today embedded lives outside `resolveLibraryFromFilesystem`, so this means threading the embedded lookup into the priority list or splitting the ambient tier out — note this for the implementer). |

### Option C — Explicit `--library-path` CLI flag

Add a `--library-path DIR` flag (repeatable) to the `l4` CLI that mirrors
`JL4_LIBRARY_PATH`, so overriding library resolution from the command line is always
a conscious act (and scriptable in tests without mutating the environment).

| | |
| --- | --- |
| **Pros** | Makes override explicit and per-invocation; good for reproducible tests and CI; complements B/B′'s "overrides are opt-in" stance. |
| **Cons** | New surface area; must agree on precedence between flag and env var (suggest: flag > env var > everything). |
| **Effort** | Low-medium. |

### Option D — De-duplicate the two resolvers

Factor the VFS-candidate construction, filesystem resolution, and embedded-fallback
into **one** shared helper used by both `GetMixfixRegistry` and `GetImports`, so
parser-hint resolution and typecheck resolution can never pick different sources.

| | |
| --- | --- |
| **Pros** | Eliminates the drift hazard in §3.3 permanently; single place to apply A/B/B′/E; removes copy-paste. |
| **Cons** | Touches both rules; needs care that the mixfix path (which only needs a URI) and the imports path (which needs range + searched-paths for diagnostics) share a return shape. |
| **Effort** | Medium. |

### Option E — Ambiguity diagnostic (defense in depth)

When **more than one** resolution source for the same module name exists (e.g. an
XDG copy *and* a root copy *and* the embedded copy), emit a **warning** naming all
candidates and the one chosen. Cheap once A/D exist (the ordered candidate list is
already in hand).

| | |
| --- | --- |
| **Pros** | Turns "silently picked one of several" into an explicit, actionable warning; the true root-cause signal for the incident class. |
| **Cons** | Could be noisy in normal dev where an XDG symlink legitimately coexists with the embed — gate to "sources resolve to **different real paths** after canonicalization," and consider warn-once-per-module. |
| **Effort** | Low (given A + D). |

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
  *fully hermetic-by-default* resolution (nothing off-binary without an explicit
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
- If **no** (e.g. the bundle intentionally ships a *newer* stdlib than the embedded
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
  **only** on-disk copy is a symlink to a *different* content than the embed, run
  with `JL4_LIBRARY_PATH` unset; assert it typechecks against the embedded copy and
  the log names the embed. A companion fixture with a root-local override asserts the
  override wins.
- **Two-resolver parity:** a fixture using cross-module **mixfix** *and* a normal
  typecheck dependency on the same imported module; assert both resolvers log the
  same real path (guards §3.3).
