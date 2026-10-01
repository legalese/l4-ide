# Import resolution (as built)

As built on `main` by this PR.
Source spec: `specs/todo/LIBRARY-RESOLUTION-SHADOW-SPEC.md`, which is on `unstable` and not on `main`; this page stands in for it here.
Differences from the source spec: its §2 and §2.1 describe the code before #134 (embedded copy last, a `resolveLibraryFromFilesystem`, two resolvers); it covers #134 only, not #64, #148, #167, #87, #102 or #93; its §8 acceptance 1 (the winning copy is visible) is not met on the CLI; its §7 calls the in-memory layer "orthogonal and correct", but the API/WASM resolver ranks the embedded copy above it; the shadow warning can list one file twice (details under Limits).
The work came from `unstable`; this page describes only what `main` has.
Line numbers are in this PR's tree, on `main` at `00298eb60`.

Units: PRs #87, #102, #134, #148, #167 and #93; #64 (inside #77, branch commit `17dee68a4`, fix `b54d4d403`, both on unstable); and the one import-resolution hunk of #143.
The rest of #143 is the DMN exporter, which is not part of this change, and #134's diff also carries 22 unrelated `paper/` files, which are not part of this feature.
#451 (an unresolved `IMPORT` is an error at its line; percent-escaped basenames resolve) is a separate change on unstable and is not on `main`.

## Labels the code comments use

Comments in `Rules.hs`, `Shake.hs`, `EmbeddedLibraries/TH.hs`, `Cli/Common.hs`, the tests and the fixtures cite the source spec's labels; in this PR they cite this page with the same labels.

- Option B′: the ladder below, with the embedded stdlib at tier 4, beneath every project-scoped copy and above the machine-global ones.
- Option E: the shadow warning (Behaviour, and Diagnostics).
- §3.1: the incident the ordering guards against, a machine-global XDG symlink silently shadowing the stdlib the binary was built with.
- §3.3: one module name resolves to one source per build, for parsing and type checking alike.
- §3.4: the embedded stdlib is frozen at build time by a Template Haskell splice.
- §6: an open question, whether the VS Code bundle's `libraries/` directory is still needed now that the binary embeds the stdlib.

## What it does

`IMPORT <name>` finds one source for `<name>` by a fixed ladder, and the same source serves every importer in a build.
A project's own copy of a library beats the stdlib compiled into the binary, and the compiled-in stdlib beats machine-global copies (XDG store, VS Code bundle).
When several differing copies are visible, a warning names them all: on stderr from the CLI, in the language server's log from the editor.
Diamond imports (A imports B and C, both import D) type-check C against D's exports, not against an empty environment.
A build that would ship an `l4` with no embedded stdlib fails at compile time, and CI checks the sdist carries the libraries.
Editor hover shows inferred types with stable names (`a`, `b`) instead of raw inference variables such as `x10`.

## Where it lives

- `jl4-lsp/src/LSP/L4/Rules.hs:287-325`: `resolveLibrary` builds the ladder (`cands`, l.305-307), probes it, and returns every existing candidate in order.
- `jl4-lsp/src/LSP/L4/Rules.hs:395-545`: `resolveImportShared` is the in-memory tier, then `resolveLibrary`, the log lines, the shadow warning (`warnOnLibraryShadow`, l.527-545), and the returned `ImportOutcome`.
- `jl4-lsp/src/LSP/L4/Rules.hs:547-553`: `jl4Rules` creates the session's warn-once set (l.551) and binds `resolveImport`, which both `GetMixfixRegistry` (l.603) and `GetImports` (l.636) call.
- `jl4-lsp/src/LSP/L4/Rules.hs:346-384`: `ImportOutcome`, `EmbedStatus` (`EmbedSkipped`, `EmbedEmpty`, `EmbedMissing n`) and `renderEmbedStatus` (from #167).
- `jl4-lsp/src/LSP/Core/Shake.hs:363-404`: `embeddedLibraryUriScheme` (`"jl4-embedded"`), `embeddedLibraryUri`, `embeddedLibraryVfs` and `getVirtualFile`'s fallback to it; `addVirtualFileUri` at l.410.
- `jl4-core/src/L4/Import/Resolution.hs:180-252`: `resolveImports`, the API/WASM resolver; the already-resolved branch at l.190-191 is #102's fix.
- `jl4-core/src/L4/TypeCheck/Types.hs:395-417`: `unionImportedCheckEnv` (#543, already on `main`): `entityInfo` is unioned left-biased (l.417), and the comment above it (l.395-399) gives the same rationale #143 wrote into `combineResolvedImports` (`jl4-core/src/L4/Import/Resolution.hs:347`; see Later changes).
- `jl4-core/src/L4/API/EmbeddedLibraries.hs:44-95`: the TH splice that embeds `jl4-core/libraries/*.l4`; its `fail` at l.79 is #167's.
- `jl4-core/jl4-core.cabal:21`: `data-files: libraries/*.l4`, above every section, with the reason in l.7-20 (l.7 begins "KEEP THIS ABOVE THE `flag` STANZAS").
- `jl4/app/L4/Cli/Common.hs:185-194`: `isProgressChatter` drops Info/Debug `[Import Resolution]` lines and keeps Warning/Error ones.
- `jl4-service/src/Backend/Jl4.hs:157-199`: a bundle registers each embedded library at `embeddedLibraryUri`, unless the bundle ships a file of the same basename.
- `jl4-lsp/src/LSP/L4/Actions.hs:385-397`: hover renders a type through `prettyTypeForDisplay` (`jl4-core/src/L4/Print.hs:119`).
- `jl4-lsp/jl4-lsp.cabal:155-172`: the `jl4-lsp-test` suite, created by #93.
- User docs: `doc/reference/libraries/resolution.md` (the ladder table at l.26-34) and `jl4-core/libraries/README.md` (l.18-65), both from #134.

## Behaviour and rules

In-memory tier (tier 0), probed first through the memoising `GetFileContents` rule: `project:/<mod>.l4`, then the importing file's directory, then the root directory (`Rules.hs:416-444`).
Then the ladder, first existing copy wins (`Rules.hs:298-307`):

1. `$JL4_LIBRARY_PATH/<mod>.l4`, only when the variable is set;
2. `<root>/<mod>.l4`;
3. `<dir of importing file>/<mod>.l4`, omitted when the importer has no file path;
4. the embedded stdlib;
5. `<XDG data>/jl4/libraries/<mod>.l4`;
6. `<exeDir>/../../libraries/<mod>.l4`.

The CLI's root directory is the entry file's own directory (`jl4-lsp/src/LSP/L4/Oneshot.hs:38-41`), so tiers 2 and 3 coincide for the entry file.
When `JL4_LIBRARY_PATH` is set, tier 4 is removed from the probe list, and the candidate table and the shadow warning are not produced (`Rules.hs:463`), so goldens that pin the variable stay machine-independent.
Parser-hint resolution and type-check resolution share this one code path, so an import cannot parse against one source and type-check against another; each import is therefore logged twice in a run.
An embedded winner resolves to `jl4-embedded:/<mod>.l4`, and no VFS write happens (`Rules.hs:497-507`).
`getVirtualFile` falls back to `embeddedLibraryVfs`, so an embedded module is readable from the start of the build and a probe cannot memoise it as missing (smucclaw/l4-ide#906).
The URI is not a `file:` URI, so no speculative in-memory probe can name it; on unstable, with #64's original `./<mod>.l4` key, `l4 check main.l4` (root `"."`) let the embedded prelude beat the project's own `prelude.l4` until #148 (per #148's commit message); `main` never had that key, and `l4 check main.l4` run from that fixture's directory (the case at `jl4/tests-cli/Main.hs:633`) passes on plain `main` too (measured).
An embedded importer has no directory (`uriToNormalizedFilePath` is `Nothing`), so its own imports are ranked by the same ladder as everyone else's, and one module name stays bound to one source per build.
Shadow warning: when two or more candidates exist and at least two contents differ (byte comparison), it lists every existing candidate, marks the winner `[chosen]` and the rest `[shadowed]`, and shows each symlink's real target; identical copies stay silent; each (module, list) pair warns once per session (`Rules.hs:527-545`).
Winner logging, only when the variable is unset: Info "Found on filesystem (candidate i of n): <path>[ -> <real path>]" or "Found in embedded libraries (candidate i of n): <mod>", and a Debug candidate table with `(hit)`/`(miss)` per entry (`Rules.hs:464-500`).
Core resolver (API/WASM): `resolved` maps each module name to its type-checked record, and a module met again hands back that record, so a diamond's second sibling sees the shared module's exports (#102, smucclaw/l4-ide#904).
Merging imported environments keeps the first `entityInfo` entry on a key collision; a collision is the same entity reached by two paths, so the values agree.
Build: if the TH splice finds no `prelude.l4` in the Cabal datadir, `./libraries` or `./jl4-core/libraries`, compilation fails; the embed is frozen at build time, so a plain `cabal build` does not pick up edits to a checkout's libraries (`jl4-core/src/L4/API/EmbeddedLibraries/TH.hs:41-51`), a gotcha that is documented rather than fixed.
CI step "The sdist must carry the standard library" (`.github/workflows/pr-checks.yml:171-187`, job `haskell`) fails on a `cabal check` parser warning or an sdist without `libraries/prelude.l4`.

## Diagnostics

- Shadow warning (Warning, printed to stderr by the CLI): "Multiple differing copies of module `<mod>` are visible:", one row per copy, then "The [chosen] copy is used wherever this module is imported. To use a" / "different copy, set JL4_LIBRARY_PATH or place <mod>.l4 in the project root or beside the importing file." (`Rules.hs:539-545`).
- Not found (Warning log): "Module not found: <mod>", or "Module not found (JL4_LIBRARY_PATH is set, embedded libs skipped): <mod>" (`Rules.hs:512-520`).
- Not-found diagnostic, embedded entry (#167): "the stdlib embedded in this binary (skipped: JL4_LIBRARY_PATH is set)", "... (<n> modules, not among them)", or the multi-line "... -- WHICH IS EMPTY." build-defect text (`Rules.hs:374-384`); `EmbedEmpty` cannot occur in an `l4` that compiled, because the splice fails the build first.
- The diagnostic itself reads "I could not find a module with this name: <mod>" / "I have tried the following locations:", then the tried URIs and paths with exact duplicates removed, then the embedded entry last (`Rules.hs:640-659`).
- Build failure: "L4.API.EmbeddedLibraries: found no standard library to embed.", followed by the three probed paths and the cwd (`EmbeddedLibraries.hs:79-93`).
- Core API: "Module not found: <mod> (searched: embedded libraries, project VFS)" (`Resolution.hs:305`).

## Tests and fixtures that pin it

- `jl4-lsp/test/LibraryResolutionSpec.hs:103-171`: nine table-driven `resolveLibrary` cases over environment variable, root, sibling, XDG and symlink sandboxes (#134).
- `jl4/tests-cli/Main.hs:546-619`: five black-box cases for the shadow order and warning, with fixtures `jl4/tests-cli/fixtures/library-shadow/{embedded-wins,sibling-wins,xdg-extra}/` (#134).
- `jl4/tests-cli/Main.hs:520-544`: embedded-only diamond (#87), with fixture `jl4/tests-cli/fixtures/embedded-diamond/main.l4`.
- `jl4/tests-cli/Main.hs:621-661`: bare entry path (#148), two cases that run `l4 check main.l4` from inside the `sibling-wins` and `embedded-wins` fixture directories.
- `jl4-core/test/ImportResolutionSpec.hs:88`: both diamond siblings type-check clean (#102).
- `jl4-lsp/test/HoverDisplaySpec.hs:63-64`: hover shows `a`, never `x10` (#93).
- No golden changed with this PR. The two goldens that #134 re-blessed on unstable, `section-scoping-import-collision` and `set-equals-ambiguous`, are not on `main`.

## What this PR leaves out

The two "an embedded library sees the project-local override" cases of #148 are not here.
They expect `l4 check` to fail on an error inside an imported module, which needs `hasBlockingError` from unstable's #52, and that is not on `main`.
Measured on this PR's build: `l4 check main.l4`, run from inside the fixture directory with `JL4_LIBRARY_PATH` unset, prints the arity mismatch in `actus-schedule` as a diagnostic on `jl4-embedded:/actus-schedule.l4`, which shows the embedded importer bound to the project's `daydate`, and then prints "Check succeeded." and exits 0, so a case that expects a non-zero exit fails here.
Their fixture (`jl4/tests-cli/fixtures/library-shadow/embedded-importer/`) and its constants (`shadowImporterDir`, `shadowImporterEntry`, `jl4/tests-cli/Main.hs:266-273`) are here, but no case in the suite runs the fixture.
The fixture-existence pre-check in the suite's `main` (`jl4/tests-cli/Main.hs:283-290`) is not extended for any of the new fixtures.
Nothing of #143 is carried: its one in-scope hunk is subsumed by `unionImportedCheckEnv`.

## Limits and known defects (verified by reading the code)

- The two resolvers disagree: the ladder puts a project copy above the embedded one, but `apiModuleLookup` tries embedded first (`jl4-core/src/L4/API/VirtualFS.hs:99-101`); this is latent because every non-test caller passes `emptyVFS` (eight sites in `jl4-core/src/L4/API.hs`, and `jl4-wasm/app/QueryPlanWasm.hs:40`).
- That API path also has no filesystem tiers and no shadow warning, and its not-found list is hard-coded (`Resolution.hs:200`).
- The shadow warning does not deduplicate by real path: from the CLI, where root and importer directory coincide, one file is listed as both "[chosen] project root" and "[shadowed] importer-relative"; no CLI case on `main` asserts the rows.
- Spec §8 acceptance 1 is not met on the CLI: winner lines are Info (`Rules.hs:495`, `:498`) and the CLI drops Info resolution lines, so the chosen copy is shown only when a shadow warning fires; `resolution.md:145-146` says the Info/Debug lines are in the language server's log only, because no `l4` command has a verbose mode (`runOneshotVerbose` has no caller).
- Stale comments: `Rules.hs:393-394` says an embedded winner "is registered as a Shake virtual file", contradicted by l.502-507; `jl4-service/src/Backend/Jl4.hs:1089-1091`, `:1342-1344` and `:1361-1363` say embedded libraries resolve "via JL4_LIBRARY_PATH or Paths_jl4_core data-dir".
- `Backend/Jl4.hs:159` says registering the libraries makes `IMPORT prelude` resolve "via the VFS"; the in-memory tier never probes a `jl4-embedded:` URI, so read in code the import resolves at tier 4 and the registration duplicates `embeddedLibraryVfs` (not run).
- `doc/reference/libraries/IMPORT.md:61-62` (older text, not from these units) says library names resolve to `jl4-core/libraries/` and relative names to the current directory.

## Later changes

- #451, a separate change on unstable that is not on `main`, adds `tiersInOrder` and `roundTrippingFileUri` (smucclaw/l4-ide#971), lists the not-found locations in ladder order deduplicated by file, and adds the line "Nothing it defines is in scope here; ...".
  It also stops an unresolved import from producing the importer's own URI (the source of "Your module depends on itself"), and adds `ImportDiagnosticSpec` and `ImportUriSpec` to `jl4-lsp-test`.
- #543 moved the import-boundary merge into `unionImportedCheckEnv` before this PR, so #143's rewritten `Map.union` line and comment in `combineResolvedImports` do not apply on `main`.
- On unstable the CLI runner `runL4EmbeddedOnly` (added by #87) later moved to a `CliTest/Common.hs`; `main` has no such file, and the runner is in `jl4/tests-cli/Main.hs:182`.
