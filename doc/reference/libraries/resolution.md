# How IMPORT finds libraries

This page is for people who run L4 tooling or develop the standard library. For how to write an `IMPORT`, see [IMPORT](README.md#import).

When an L4 file says `IMPORT prelude`, the toolchain has to find _a_ file
called `prelude` — but on a developer's machine there may be **several**: one
compiled into the binary, one in each git worktree, one in a machine-global
store, one shipped inside the VSCode extension. This page explains, in order:

1. [the resolution order and why each tier exists](#the-resolution-order)
   (and [path imports](#path-imports), which skip it)
2. [the dev/prod playbook — what to set in each situation](#the-devprod-playbook)
3. [how to read the resolver's logs and warnings](#reading-the-resolvers-output)
4. [what happens when nothing resolves](#when-nothing-resolves), and which
   module names are allowed
5. [the embed-staleness gotcha](#the-embed-staleness-gotcha) (why `cabal build`
   doesn't pick up your prelude edit)
6. [the shadow saga](#the-shadow-saga-how-we-got-here) — the two incidents that
   forced this design, preserved so future devs understand _why_ the rules are
   what they are

An as-built description of the code behind all of this lives in
`specs/as-built/import-resolution.md` in the repository, and the design
analysis in `specs/todo/LIBRARY-RESOLUTION-SHADOW-SPEC.md`.

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

The XDG store is the `jl4/libraries` folder of the user's data directory.
It is `$XDG_DATA_HOME/jl4/libraries/` when that variable is set to an absolute path.
Otherwise it is `~/.local/share/jl4/libraries/` on macOS and Linux, and `%APPDATA%\jl4\libraries\` on Windows, which is usually `C:\Users\<you>\AppData\Roaming\jl4\libraries\`.
Every other mention of `~/.local/share/jl4/libraries/` on this page means this folder.

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

**`jl4-service` uses a shorter ladder.** A service that runs bundles other
people uploaded cannot let its own machine stand in for the standard library.
So a deployment's `IMPORT`s are resolved against the bundle's own files (tier 0)
and then the standard library built into the service binary (tier 4), and
nothing else. **The service reads neither `JL4_LIBRARY_PATH`, nor its working
directory, nor the XDG store (`~/.local/share/jl4/libraries/`)**, and not the
extension bundle either: tiers 1, 2, 3, 5 and 6 are not consulted. A
`prelude.l4` in the service's working directory, or a library directory exported
into its environment, has no effect on any deployment. (Without this rule it
would: the deploy reports "applied" and every call then answers 422 `sum is not
in scope`.) The service says at start-up, at `WARN`, when `JL4_LIBRARY_PATH` is
set and therefore ignored.

A consequence for anyone moving a deployment onto the service: a library you
used to supply from the host's filesystem has to be a file in the bundle, in the
same directory as the file that imports it. A file elsewhere in the bundle is
found only when its directory happens to be the one the service treats as the
bundle's root, the directory of the first file in the bundle's sort order, so
do not rely on it.

A bundle that ships a file with the name of a standard library module, such as
its own `prelude.l4`, is still honoured, as any project copy is: the importers
that can see that file — those in the same directory — get it instead of the
library's. The service says so, at `WARN`, each time it compiles such a bundle
(`Bundle file stands in for a standard library module`, naming the file and the
module), unless the file is exactly the library's own text.

An `IMPORT` that finds nothing — no file in the bundle, no module in the built-in
library — does not stop the deploy, which still reports "applied": the file
typechecks, and only a call that reaches something the missing module should have
defined fails. The service logs a `WARN` for each one, naming the deployment, the
importing file and the module (`Bundle IMPORT resolves to nothing`), when the
bundle is compiled, which a restart does again from the stored sources. A refusal at
deploy time is not made; it would need a ruling of its own.

This ordering is pinned by tests: `jl4-lsp/test/LibraryResolutionSpec.hs`
(unit, table-driven), the `l4 library resolution shadow (B′)` group in
`jl4/tests-cli/Main.hs` (black-box CLI), and, for the service's shorter ladder,
`jl4-service/test/StdlibResolutionSpec.hs` and
`jl4-service/test/UnresolvedImportSpec.hs`.

---

## Path imports

A backticked name with a slash, such as ``IMPORT `../shared/definitions` ``, is a **path import**. It does not use the ladder above. [How to write one](README.md#importing-a-file-from-another-folder) is in the `IMPORT` reference; this section is how it is resolved.

A name is a path import if, and only if, it contains a `/`. Every other name is resolved by the ladder above, exactly as before. That includes a name with a dot or an extension (`IMPORT foo.l4`, `IMPORT a.b`), which the ladder still reduces to `foo` and `a`; a warning now says so.

To resolve a path import from the file `F`:

1. Take the path as written, drop one trailing `.l4` if there is one, and append `.l4`.
2. Join it to the folder that holds `F`.
3. Collapse every `.` and every `x/..` in the result, without touching the disk. `sub/../core.l4` becomes `core.l4`. Two spellings of one path therefore become one module, and a shared module reached from two places is checked once. This is done on the words of the path alone: a symbolic link, or a different capitalisation on a system that ignores capitals, still reaches one file as two modules, as it does for a bare name.
4. If the runtime is **confined** (below) and the collapsed path still starts with `..`, stop: [the import leaves the root](../errors/README.md#this-import-leaves-the-root-of-this-deployment).
5. Look for that one file among the files the editor or the service holds in memory. If the runtime is not confined, then look on disk.
6. Found: that is the module. Not found: [I could not find a module at this path](../errors/README.md#i-could-not-find-a-module-at-this-path), naming the collapsed path.

No other tier is consulted: not `$JL4_LIBRARY_PATH`, not the project root, not the embedded standard library, not the per-user store, not the extension's bundle. A path import names one file, and the point of writing one is that no ladder decides it. It follows that `JL4_LIBRARY_PATH` has no effect on a path import, and that a file called `prelude.l4` in a folder is never mistaken for the standard library by ``IMPORT `sub/prelude` ``.

**Confined and not confined.** The runtime's library scope decides, the same one that gives `jl4-service` its shorter ladder:

| runtime                                                   | step 4, a path that climbs above where it started | step 5, the disk |
| --------------------------------------------------------- | ------------------------------------------------- | ---------------- |
| `l4` (every command), the REPL, MLIR, the language server | allowed                                           | looked at        |
| `jl4-service`                                             | refused, before anything is looked up             | never looked at  |

On your own machine a `..` may leave the folder you started from, because the commons rows that keep their cases in a sub-folder need exactly that. A service that runs files somebody else uploaded must not read its own disk for them, so it resolves a path against the uploaded files only, and refuses one that would leave them. Tests plant a real file where such a path would land and check that it is not taken.

**A leading `/`** is refused everywhere, with the same message as a path that leaves the root. It is reserved for a form that does not exist yet.

**Only the written name changes.** A module reached by a path import is an ordinary module. Its own `IMPORT prelude` and `IMPORT helper` are resolved by the ladder from its own folder, as they would be anywhere.

**What a path import cannot do yet.** These are limits, not oversights:

- The browser editor holds one document and has no way to add a second file, so a path import there still finds nothing. The WASM module underneath can resolve one once a page hands it files ([In the browser](#in-the-browser)); nothing in the editor does yet.
- `l4 deploy` and the VS Code deploy action upload every file at the top level, so a project that uses path imports fails after it is deployed that way ([what a deployment contains](README.md#what-a-deployment-contains)).
- A deployed bundle that cannot resolve a path import is accepted, and the only trace is a warning in the service's log.
- The service does not find a file at the top of an upload whose own name has a space or a non-ASCII letter, nor a file inside a top-level folder whose name has a space, a non-ASCII letter or punctuation such as `#` `'` `+` `(` `%` (a deployment says `ready` and every call then answers 422, and the service's log says the import resolves to nothing). This was measured for a bare import; a path import into such a folder was seen to fail the same way in review. A file inside a plain top-level folder is found whatever its own name or deeper folders are called. `l4` on your machine is not affected.
- The REPL looks every import up from the folder it was started in, not from the loaded file's.
- The editor's "find all references" on a module only searches the project root and the folder of the module being searched, so a file that imports it by path from another folder is not listed.
- `l4 export dmn` finds the files that call a decision by looking for `IMPORT <name>` among the files in the same folder; a file that imports by path is not recognised, and a decision it calls may be left out.
- `l4 render` (HTML and Akoma Ntoso) numbers the definitions of an imported module by the module's file name, so two modules with one file name in different folders can produce duplicate anchors.

### In the browser

L4 also runs in a web page, as a WebAssembly module (the browser editor's "WASM mode").
It has no disk, so it resolves an `IMPORT` among two things only: the standard library built into the module, and the files the page hands it as a table from path to source text.
A path import is **confined** in the sense of the table above.
It can reach those files and nothing else, and a path that climbs above the start of them is refused before anything is looked up.
Tests put a file where such a path would land and check that it is not taken.

How it differs from `l4` on your machine:

- **The page says where the document is.**
  With the document's path set to `rows/a/main.l4`, ``IMPORT `../b/mod` `` looks for `rows/b/mod.l4`.
  Until a path is set, the document is at the top of the files, so ``IMPORT `./helper` `` looks for `helper.l4` and a path that starts with `..` is refused.
  The open document is the module at that path, whatever the files hold there.
  A file that imports the document back makes a cycle (`Cyclic import detected: a/x -> b/y -> a/x`), as it does under `l4`, and a copy of the document among the files is never read in its place.
  That holds for the default path too: with the document at the top of the files, a file that says `IMPORT main` imports the document, and the program is refused as a cycle even if the files hold a `main.l4`.
- **A file is found by its path, with or without `.l4`**, however the page spelt it (`./rows/b/mod.l4`, `rows/a/../b/mod`).
  Two spellings of one path are one module.
  So are a path and a bare name that reach the same file at the top of the files: ``IMPORT `sub/../core` `` and `IMPORT core` load `core.l4` once.
- **A key is a path from the top of the files, with no leading `/`.**
  The module refuses a table that has a key like `/rows/b/mod.l4`, and the message names the key, because no import could find it.
  It also refuses a table in which two keys are one path (`core.l4` and `./core.l4`, or `core` and `core.l4`) and names both, so that neither is taken in place of the other without a word.
  A refused table changes nothing: the module keeps the files it had.
  The document's path is the one place where a leading `/` is allowed, and it is ignored there.
  A key that climbs above the top of the files, such as `../x.l4`, is accepted and never found.
- **A bare name is not shortened at its last dot.**
  Under `l4`, `IMPORT foo.l4` and `IMPORT a.b` are read as `foo` and `a`, with a warning.
  In the browser they are looked up as written: `IMPORT a.b` looks for a module called `a.b` and does not find `a.l4`, and `IMPORT foo.l4` finds the file `foo.l4` as a module of its own, so that it and ``IMPORT `./foo` `` load one file twice and the program is refused with `There are multiple definitions`.
  Write a module's name without an extension.
- **A path never finds the standard library.**
  ``IMPORT `lib/prelude` `` is the page's `lib/prelude.l4` or nothing, and `IMPORT prelude` in the same program is still the library.
- **A bare name is looked up by name, among the files at the top first and then in the standard library.**
  That is the order `l4` uses, where a project's file comes before the standard library.
  An earlier browser module tried the standard library first ([smucclaw/l4-ide#989](https://github.com/smucclaw/l4-ide/issues/989)).
  Two things follow that you may not expect:
  - A file of the page's called `prelude.l4` stands in for `IMPORT prelude`, and for the `IMPORT prelude` inside each library that has one, such as `hierarchy`.
    A library is then checked against your file, and one that uses something your file does not define stops checking, as it does under `l4`.
    Such a file cannot import the library's own `prelude` in turn: `IMPORT prelude` inside it finds itself, and the program is refused as a cycle.
    Unlike `l4`, the browser does not warn that a file stands in for a library, and does not show the library's errors.
    To leave the library alone, put your file in a folder, where only a path finds it, or give it another name.
  - A bare name inside one of the page's files is looked up among the files at the top, not beside the file that writes it.
    In `rows/b/mod.l4`, `IMPORT neighbour` needs `neighbour.l4` at the top of the files, and `rows/b/neighbour.l4` is not found by it.
    `l4` finds the second.
    Write ``IMPORT `./neighbour` `` to mean the file beside.
- **One address, two files.**
  A page's file at the top of the files that has the name of a standard library module, such as `prelude.l4`, is the module of that name, however it is reached: ``IMPORT `./prelude` `` and `IMPORT prelude` load it once.
  One spelling of the key is the exception, because a bare name takes the key as the page wrote it: a file keyed `./prelude.l4` is found by ``IMPORT `./prelude` `` and not by `IMPORT prelude`.
  A program that reaches that file and the library module of the same name, directly or through another library, is refused, because the two would be one module: `Two different modules are both called prelude`.
  Key the file `prelude.l4`, put it in a folder, or give it another name.
- **An error inside an imported file is not shown.**
  The browser reports the open document's errors only, whichever way a file was imported.
  Two things reach you anyway.
  A file that cannot be parsed stops the import, and the browser then shows the parser's message at the top of the document, headed `Parse error in` and the file's module name.
  A file that parses and does not type-check leaves the document's own errors as they were, and the browser adds an error at the top of the document for each such module: `The imported module`, its name and `has errors`, without saying what they are.
  A document with that error is not evaluated, whether or not it uses the part of the module that is wrong, and `l4` is more lenient: it prints the module's errors where they are and still evaluates the importing file.
  To read the errors, check the imported file as the document on its own.

The page hands over files with the bridge's `setFiles` (a table from path to source) and `setDocumentPath` (`ts-apps/jl4-web/src/lib/wasm/wasm-bridge.ts`), which call the module's `l4_set_files` and `l4_set_document_path`.
The editor itself does not call them, because it has no second file to give.
Until it does, a document in the browser editor can import the standard library and nothing else.
When the module refuses a table, the bridge says so once in the browser console and goes on with the files the module had.
The module analyses one document at a time under one path: let an analysis finish before you change the path, because a call that has been issued runs under the path that is set when it starts, and `WasmLspHandler` checks every open document under the one path.

---

## The dev/prod playbook

### I'm writing L4 programs (consuming the stdlib)

Do nothing. The embedded copy serves `IMPORT prelude` and friends, and it is
guaranteed to match the binary you're running. This is the **prod** regime:
an installed `l4`, the VSCode extension, `jl4-service` — none of them need any
environment setup or files on disk.

**Reading the stdlib from your editor.** Go-to-definition on a stdlib name (say
`sum`, after `IMPORT prelude`) opens a **read-only** tab named `prelude.l4`.
It is not a file on disk: its address is `jl4-embedded:/prelude.l4`, and the
language server supplies the text — the exact copy compiled into the binary, so
what you read is what your program runs. Hover and go-to-definition work inside
it. To change the stdlib, edit `jl4-core/libraries/` and see the next section.

The limits: this works in the VSCode extension, which asks the server for the
text with a custom request, `l4/embeddedLibrary` (params `{"uri": …}`, reply
`{"text": …}`). Another editor connected to `jl4-lsp` receives the same
`jl4-embedded:` address and has to make the same request to show it. When
`JL4_LIBRARY_PATH` is set, the embedded copy is not consulted and
go-to-definition lands on a real file instead.

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
convenience and it is exactly what caused the
[incidents below](#the-shadow-saga-how-we-got-here): with several
worktrees, a machine-global symlink points at _one_ of them and silently lies
to all the others. It also no longer works for stdlib modules, because the
embedded copy outranks the XDG store; the env var is both safer and the only
supported mechanism.

### I'm running the test suites

- **CI** exports `JL4_LIBRARY_PATH` already.
- **`jl4-test` (the golden suite)** sets it for you if unset (pointing at the
  jl4-core datadir), so a bare `cabal test jl4-test` works. Locally you still
  want the worktree pin from the previous section so the goldens run against
  the sources you're editing.
- **`l4-cli-test`**: the library-resolution cases manufacture their own
  environment per case (a fabricated `XDG_DATA_HOME`, the variable dropped), so
  they need nothing set. The rest of the suite runs in the environment it is
  given.

### I'm packaging / deploying

The embedded copy is the source of truth for a deployed binary. The VSCode
extension additionally ships `libraries/*.l4` next to the bundled binary
(tier 6); since the embed already carries the full stdlib, that directory only
matters for libraries _not_ in the embed. (Whether it can be dropped entirely
is an open question — see §6 in `specs/as-built/import-resolution.md`.)
`jl4-service` consults neither: see
[the shorter ladder above](#the-resolution-order).

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
Info | [Import Resolution] Found on filesystem (candidate 1 of 5): /work/prelude.l4
```

(The first when nothing in the project shadows the stdlib, the second when the
project root holds its own `prelude.l4`.)

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
stderr; Info/Debug lines are visible in the LSP log channel only.
`l4 check --json` and `l4 run --json` carry the same Warning lines in the
`diagnostics` array of their output, so a program that reads that array sees a
shadow warning there too.

An `IMPORT` that resolves to nothing is an error, not a shadow warning: see [When nothing resolves](#when-nothing-resolves).

When two tiers name the same file — the CLI sets the project root to the
importing file's own directory, so the root tier and the importer-relative tier
probe one path — the shadow warning lists that file once, not as both
`[chosen]` and `[shadowed]`.

**Debugging "my edit didn't take effect":**

1. Run `l4 check` on the importing file and read stderr. A shadow warning
   tells you immediately that two differing copies exist and which one won.
2. No warning? Then only one copy is visible — check the winner line in the
   language server's log to see
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

The error is also listed with the other messages under [Module not found](../errors/README.md#module-not-found).

The list is every candidate from [the table above](#the-resolution-order), in that same tier order, so a typo shows up as a name you do not recognise and a mis-set store shows up as a path you do not recognise.
Each location is listed **once**, however many tiers name it — the in-memory tier keys a file by URI and the filesystem tiers key it by path, so for a project whose root is the importing file's own directory (which is what the CLI uses) the same file arrives twice — and it is printed as the plain path, at the rank of the tier that spells it that way.
The embedded stdlib sits at its own rank too — tier 4 in the table above — rather than at the end, which is where it used to be printed whatever its rank.

The same mistake is also announced once, at Warning priority, as `Module not found: myhelpers`: once for each importing file, however many of the toolchain's rules go looking for the import. (`l4 ast`, which never typechecks, prints that one line on stderr and exits 0.)

The second line of the message is there because this is usually not the first error you see.
A failed import produces one `I could not find a definition for the identifier` for every name it was supposed to supply, and those read like broken source rather than like a failed import.
So if you are looking at a screen full of undefined identifiers, read the top of it.

### Which commands fail on it

**`l4 check` and `l4 run` exit non-zero** — and so does the bare `l4 <file>` form, which is `run`.
Those two are the commands to gate a build or a pipeline on.

**Nine commands print the same error and still exit 0** (ten when `l4 export blawx` is given a module it can lower).
Measured on this tree, on a module that is otherwise fine: `render`, `nlg`, `trace`, `verify`, `export openfisca`, `export catala`, `export docassemble`, and `export dmn` / `export dmn-md`.

**Five do not mention it at all.**
`l4 format` and `l4 ast` never typecheck.
`l4 lts` and `l4 state-graph` print diagnostics only when the typecheck itself fails.
`l4 batch` reports diagnostics per input row, and this one is not among them — it streams results for a module with an unresolved import and exits 0, which is worth knowing if a pipeline reads its output.

Three commands do exit non-zero here, and it is not because of the import: `l4 export blawx`, `l4 state-graph` and `l4 export bpmn` refuse this module identically with the `IMPORT` line deleted; `l4 export blawx` refuses only a module it cannot lower, so on one it can lower it joins the exit-0 group above.

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
(`L4.API.EmbeddedLibraries`), which reads `libraries/*.l4` while GHC compiles
that module. For a checkout it reads the checkout's own `jl4-core/libraries/`
(the dependency GHC records is `<checkout>/jl4-core/libraries/prelude.l4`, with
a content hash), so GHC itself would re-embed a library that changed. The catch
is that Cabal does not ask it to.

Measured on 2026-10-13, a checkout built with `cabal build` (GHC 9.10.3,
Cabal 3.16):

- Appending a definition to `jl4-core/libraries/prelude.l4` and running
  `cabal build` prints `Up to date`. Nothing is rebuilt, and the binary keeps
  serving the old prelude. `touch`-ing `L4.API.EmbeddedLibraries` changes
  nothing either: Cabal compares content, not modification times.
- The same edit plus any real change to a `jl4-core` source file (the test was a
  comment on an unrelated module) makes Cabal call GHC. GHC sees the new content
  hash, recompiles `L4.API.EmbeddedLibraries`, and the rebuilt binary serves the
  new prelude.

Consequences:

- Editing `jl4-core/libraries/prelude.l4` in a worktree and running a plain
  `cabal build` leaves the binary on the old prelude.
- To force a re-embed without the pin: make a real content change to a
  `jl4-core` source file, or clean-rebuild `jl4-core`.
- Which is why the supported dev workflow is the `JL4_LIBRARY_PATH` pin, not
  "rebuild and hope". The pin outranks the embed deterministically.

This was measured for a checkout. A build from somewhere else — `cabal install`
from an sdist, a Nix build — reads the `libraries/` of the directory it is built
in; this page does not claim to have measured those.

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
