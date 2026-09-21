# Library Resolution: How `IMPORT` Finds Files, and How to Work with Dev vs Prod Preludes

When an L4 file says `IMPORT prelude`, the toolchain has to find _a_ file
called `prelude` — but on a developer's machine there may be **several**: one
compiled into the binary, one in each git worktree, one in a machine-global
store, one shipped inside the VSCode extension. This page explains, in order:

1. [the resolution order and why each tier exists](#the-resolution-order)
2. [the dev/prod playbook — what to set in each situation](#the-devprod-playbook)
3. [how to read the resolver's logs and warnings](#reading-the-resolvers-output)
4. [what happens when nothing resolves](#when-nothing-resolves), and which
   module names are allowed
5. [the embed-staleness gotcha](#the-embed-staleness-gotcha) (why `cabal build`
   doesn't pick up your prelude edit)
6. [the shadow saga](#the-shadow-saga-how-we-got-here) — the two incidents that
   forced this design, preserved so future devs understand _why_ the rules are
   what they are

The design analysis behind all of this lives in
`specs/todo/LIBRARY-RESOLUTION-SHADOW-SPEC.md` in the repository.

---

## The resolution order

For a bare module name `<mod>`, resolution tries, **first match wins**:

| #   | Tier                  | Location                                                       | Who it serves                                            |
| --- | --------------------- | -------------------------------------------------------------- | -------------------------------------------------------- |
| 0   | VFS                   | in-memory files (`project:/<mod>.l4`, importer-relative, root) | web IDE / Monaco / unsaved editor buffers                |
| 1   | **env override**      | `$JL4_LIBRARY_PATH/<mod>.l4`                                   | operators and stdlib developers taking explicit control  |
| 2   | **project root**      | `<root>/<mod>.l4`                                              | a project that ships its own copy of a library           |
| 3   | **importer-relative** | `<dir of importing file>/<mod>.l4`                             | multi-file projects; local overrides beside the code     |
| 4   | **embedded**          | compiled into the binary at build time                         | everyone else — this is the default stdlib               |
| 5   | XDG store             | `~/.local/share/jl4/libraries/<mod>.l4`                        | machine-global _extra_ libraries the embed doesn't carry |
| 6   | VSCode bundle         | `<exeDir>/../../libraries/<mod>.l4`                            | the packaged extension, for non-embedded extras          |

Three rules of thumb fall out of the table:

- **Project-scoped beats embedded.** If you put a `prelude.l4` in your project
  root or beside the importing file, you get it. Overriding the stdlib is a
  conscious, visible act — the file is _in your project_.
- **Embedded beats ambient.** A machine-global file (XDG, bundle) can never
  silently replace the stdlib your binary was built with. Ambient tiers only
  serve modules the embed does not carry.
- **`JL4_LIBRARY_PATH` is absolute.** When it is set, the embedded copy is not
  consulted _at all_ — the operator has taken full control of the library
  store. (The ambient tiers are still searched after it, for extras.)

This ordering is pinned by tests: `jl4-lsp/test/LibraryResolutionSpec.hs`
(unit, table-driven) and the `l4 library resolution shadow (B′)` group in
`jl4/tests-cli/Main.hs` (black-box CLI).

---

## The dev/prod playbook

### I'm writing L4 programs (consuming the stdlib)

Do nothing. The embedded copy serves `IMPORT prelude` and friends, and it is
guaranteed to match the binary you're running. This is the **prod** regime:
an installed `l4`, the VSCode extension, `jl4-service` — none of them need any
environment setup or files on disk.

### I'm developing the standard library itself (editing `jl4-core/libraries/*.l4`)

Pin the resolver at your worktree, in the shell where you build and test:

```sh
export JL4_LIBRARY_PATH="$PWD/jl4-core/libraries"
```

This is **the** reliable way to see your stdlib edits take effect, because of
the [embed-staleness gotcha](#the-embed-staleness-gotcha) below: a plain
`cabal build` does _not_ refresh the embedded copy, so without the pin your
freshly-edited prelude loses to the stale embed on every bare `IMPORT`.

Do **not** try to accomplish this with symlinks in
`~/.local/share/jl4/libraries/` pointing into a checkout. That was the old
convenience and it is exactly what caused the incidents below: with several
worktrees, a machine-global symlink points at _one_ of them and silently lies
to all the others. Since the B′ reordering it also no longer works for stdlib
modules (the embed outranks it) — the env var is both safer and the only
supported mechanism.

### I'm running the test suites

- **CI** exports `JL4_LIBRARY_PATH` already.
- **`jl4-test` (the golden suite)** sets it for you if unset (pointing at the
  jl4-core datadir), so a bare `cabal test jl4-test` works. Locally you still
  want the worktree pin from the previous section so the goldens run against
  the sources you're editing.
- **`l4-cli-test`** manufactures its own hermetic environments per test
  (fabricated `XDG_DATA_HOME`, env var dropped) — nothing to set.

### I'm packaging / deploying

The embedded copy is the source of truth for a deployed binary. The VSCode
extension additionally ships `libraries/*.l4` next to the bundled binary
(tier 6); since the embed already carries the full stdlib, that directory only
matters for libraries _not_ in the embed. (Whether it can be dropped entirely
is an open question — see §6 of the spec.)

### I want machine-global extra libraries

`~/.local/share/jl4/libraries/` is still searched — _below_ the embed. Use it
for third-party or personal libraries that are not part of the stdlib. Do not
use it to shadow stdlib modules; it can't anymore, and if a differing copy of
any module sits there you'll get a warning (next section).

---

## Reading the resolver's output

All of the following appears only when `JL4_LIBRARY_PATH` is **unset** (in the
env-pinned regime you have explicitly chosen your store, and the logs keep the
historical one-line form).

**The winner**, at Info priority, with its position in the candidate order and
— when the path is a symlink — its real target:

```
Info | [Import Resolution] Found in embedded libraries (candidate 3 of 5): prelude
Info | [Import Resolution] Found on filesystem (candidate 2 of 5): ./prelude.l4
```

**The full candidate table**, at Debug priority:

```
Debug | [Import Resolution] Candidate order for prelude: [1] project root: /work/prelude.l4 (miss); [2] importer-relative: /work/sub/prelude.l4 (miss); [3] embedded stdlib (compiled into this binary) (hit); [4] XDG data dir: /home/dev/.local/share/jl4/libraries/prelude.l4 (miss); [5] VSCode bundle: … (miss)
```

**The shadow warning**, at Warning priority — the one you must never ignore.
It fires (once per session per configuration) when more than one copy of a
module is visible **and their contents differ**; byte-identical copies stay
silent. Symlinks are dereferenced so you can see _which checkout_ an entry
really points at:

```
Warning | [Import Resolution] Multiple differing copies of module `prelude` are visible:
  [chosen]   embedded stdlib (compiled into this binary)
  [shadowed] XDG data dir: /home/dev/.local/share/jl4/libraries/prelude.l4 -> /home/dev/src/other-checkout/jl4-core/libraries/prelude.l4
The [chosen] copy is used wherever this module is imported. To use a
different copy, set JL4_LIBRARY_PATH or place prelude.l4 in the project root or beside the importing file.
```

The CLI (`l4 check`, `l4 run`, …) prints Warning-level resolution lines to
stderr; Info/Debug lines are visible in the LSP log channel and in verbose
runs.

**Debugging "my edit didn't take effect":**

1. Run `l4 check` on the importing file and read stderr. A shadow warning
   tells you immediately that two differing copies exist and which one won.
2. No warning? Then only one copy is visible — check the winner line to see
   _which_ one, and remember the embed-staleness gotcha: the embedded copy may
   be older than your checkout.
3. When in doubt, `export JL4_LIBRARY_PATH="$PWD/jl4-core/libraries"` and
   re-run. If behaviour changes, you were not loading the file you thought.

---

## When nothing resolves

An `IMPORT` whose module cannot be found is an **error**, not a warning, and it is reported even when nothing in your file reads anything from that import.

```
I could not find a module with this name: myhelpers
Nothing it defines is in scope here; names you expected from it are reported as undefined.
I have tried the following locations:
project:/myhelpers.l4,
/work/proj/myhelpers.l4,
the stdlib embedded in this binary (22 modules, not among them),
/home/dev/.local/share/jl4/libraries/myhelpers.l4,
/opt/l4/bin/../../libraries/myhelpers.l4
```

The list is every candidate from [the table above](#the-resolution-order), in that same tier order, so a typo shows up as a name you do not recognise and a mis-set store shows up as a path you do not recognise.
Each location is listed **once**, however many tiers name it — the in-memory tier keys a file by URI and the filesystem tiers key it by path, so for a project whose root is the importing file's own directory (which is what the CLI uses) the same file arrives twice — and it is printed as the plain path, at the rank of the tier that spells it that way.
The embedded stdlib sits at its own rank too — tier 4 in the table above — rather than at the end, which is where it used to be printed whatever its rank.

The second line of the message is there because this is usually not the first error you see.
A failed import produces one `I could not find a definition for the identifier` for every name it was supposed to supply, and those read like broken source rather than like a failed import.
So if you are looking at a screen full of undefined identifiers, read the top of it.

### Which commands fail on it

**`l4 check` and `l4 run` exit non-zero** — and so does the bare `l4 <file>` form, which is `run`.
Those two are the commands to gate a build or a pipeline on.

**Nine commands print the same error and still exit 0.**
Measured on this tree, on a module that is otherwise fine: `render`, `nlg`, `trace`, `verify`, `openfisca`, `catala`, `docassemble`, and `export --to=dmn` / `--to=dmn-md`.

**Five do not mention it at all.**
`l4 format` and `l4 ast` never typecheck.
`l4 lts` and `l4 state-graph` print diagnostics only when the typecheck itself fails.
`l4 batch` reports diagnostics per input row, and this one is not among them — it streams results for a module with an unresolved import and exits 0, which is worth knowing if a pipeline reads its output.

Two commands do exit non-zero here, and it is not because of the import: `l4 blawx` and `l4 export --to=bpmn` refuse this module identically with the `IMPORT` line deleted.

The reason is that only `check` and `run` weigh the whole set of diagnostics; every other command takes a successful typecheck as its verdict, and an unresolvable `IMPORT` does not stop a module from typechecking — which is the same blindness the repository's own corpus suite had until it was taught to fail on any structural error (`checkFile` in `jl4/tests/Main.hs`), so a corpus fixture can no longer go green with an unresolvable import.

### Module names that are not plain ASCII

A module's basename may contain spaces, non-ASCII letters, or a percent sign.
Write the name in backticks in the `IMPORT` line, exactly as you would for a hyphen:

```l4
IMPORT `my helpers`
IMPORT `hvac-law-he`
```

This is worth knowing about if you are on an older build, because it used to fail, and fail quietly.
On a build predating the fix for [smucclaw/l4-ide#971](https://github.com/smucclaw/l4-ide/issues/971), such an import resolved to nothing whenever the entry file was named without a directory component — `l4 check main.l4` rather than `l4 check sub/main.l4` — and no import error was reported at all.
The symptom was a module full of undefined identifiers, or, when nothing read from the import, no symptom whatsoever.
The file itself was fine: a module with such a name checks and runs perfectly well on its own, and can import others; it was only as an import _target_ that it was lost.

---

## The embed-staleness gotcha

The embedded stdlib is captured at **build** time by a Template Haskell splice
(`L4.API.EmbeddedLibraries`). The splice asks Cabal for the `jl4-core` datadir
_at compile time_ and reads `libraries/*.l4` from there — commonly a path like
`~/.cabal/share/…/jl4-core-*/libraries`, **not** your checkout. The
`addDependentFile` recompilation hook tracks that same build-time path.

Consequences:

- Editing `jl4-core/libraries/prelude.l4` in a worktree does **not**
  invalidate the splice. `cabal build` rebuilds nothing, and the binary keeps
  serving the old prelude.
- To force a re-embed: make a real content change to
  `L4.API.EmbeddedLibraries` or its TH module, or clean-rebuild `jl4-core`.
- Which is why the supported dev workflow is the `JL4_LIBRARY_PATH` pin, not
  "rebuild and hope". The pin outranks the embed deterministically.

This is documented at the code site too
(`jl4-core/src/L4/API/EmbeddedLibraries/TH.hs`) and in
`jl4-core/libraries/README.md`.

---

## The shadow saga (how we got here)

Preserved so the next generation understands why the ordering is the way it
is, and why the warning exists.

**The setup (early 2026).** Two well-intentioned commits gave a deployed
binary ways to find the stdlib without a checkout: the VSCode bundle path
(`8c796c24`, 2026-01-10) and the XDG + env-var search (`7d763367`,
2026-02-05). Both filesystem tiers were placed _above_ the embedded copy,
which became the last resort. Separately, on dev machines it became customary
to symlink `~/.local/share/jl4/libraries/*.l4` into a checkout so an installed
binary would "just work" against the working tree.

**The trap.** This repository's development convention uses many parallel git
worktrees. A machine-global symlink points into exactly _one_ of them. In
every other worktree, a bare `IMPORT prelude` (no project-local copy — the
normal case for corpus files) fell through root and importer-relative tiers
and landed on the XDG symlink: the resolver loaded **another checkout's
prelude**, resolved successfully, and said nothing. The log line that did
exist printed the symlink path, not its target, was emitted at a priority the
CLI filtered out — and the parser-hints resolver (mixfix) logged nothing at
all.

**Incident 1 (2026-07).** During the CONSIDER-exhaustiveness work, library
changes appeared to have no effect; the XDG store was found to be shadowing
the worktree and was _moved aside by hand_ (`libraries.stale-2026-07-03`). A
hand-move fixes one machine once; the next worktree recreates the hazard.

**Incident 2 (2026-07-18).** A session added `@infixl` fixity annotations to
its worktree's `prelude.l4`. With `JL4_LIBRARY_PATH` unset, `IMPORT prelude`
resolved via the XDG symlink to the main checkout's un-annotated prelude. The
annotations "didn't take effect" — hours went into debugging the parser and
the fixity machinery, which were both fine. The binary had simply never
loaded the file containing the annotations.

**The diagnosis.** Three compounding failures:

1. **Ordering** — ambient machine-global paths outranked the binary's own
   hermetic embedded copy, so global state could silently override it.
2. **Silence** — one of the two resolvers logged nothing, the other logged at
   a filtered priority, and neither dereferenced symlinks.
3. **Duplication** — parser-hint resolution and import resolution were
   copy-pasted twins that could drift into loading _different_ files for the
   same import.

**The fix (2026-07-19).** Implemented in `jl4-lsp/src/LSP/L4/Rules.hs`:

- **One resolver** (`resolveImportShared`) shared by both rules — parse and
  typecheck can never disagree about which file a module is.
- **The B′ reorder** — embedded moved above XDG/bundle; project-scoped tiers
  and the env override kept above embedded, so every _intentional_ override
  still works. (The fully-hermetic alternative — nothing off-binary without
  an env var — was rejected because project-local overrides are a real
  affordance, not an accident.)
- **The shadow warning** — differing copies are named, symlinks dereferenced,
  the winner marked, once per session. Identical copies stay silent, so a
  benign mirror doesn't nag.
- **Visible logging** — winner + candidate table as shown above; the CLI
  passes Warning-level resolution lines through to stderr.

**The moral.** If a resolver consults global state, the global state _will_
eventually be wrong, and the failure will be attributed to whatever code the
victim happened to be editing. Hermetic-by-default with conscious, visible
overrides — and a loud message when two sources disagree — is the only
configuration that fails debuggably.
