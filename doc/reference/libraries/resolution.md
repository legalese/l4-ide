# How IMPORT finds libraries

This page is for people who run L4 tooling or develop the standard library. For how to write an `IMPORT`, see [IMPORT](README.md#import).

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

**Capitals count on every tier.**
A tier holds `<mod>` only when it has a file spelled exactly `<mod>.l4`, so `IMPORT dayDate` does not find `daydate.l4` in any folder, on any disk, in any host.
The embedded tier and the in-memory one always compared names exactly, and so did the web playground and `jl4-service`.
The folder tiers (1, 2, 3, 5 and 6) asked the operating system whether the file exists, and a case-insensitive disk, the default on macOS and Windows, answers yes for any capitals; the file was then loaded under the spelling the `IMPORT` used.
So on a Mac, `IMPORT dayDate` found `daydate.l4` through `JL4_LIBRARY_PATH`, or in the XDG store with no shadow warning (the built-in copy, compared exactly, did not match); and beside an `IMPORT daydate` it loaded the same file a second time, which made every name in it ambiguous.
Now each folder tier also reads the folder's list of files, and refuses a file the operating system reports when the list spells it only with other capitals.
The same goes for a few differences that are not capitals but that the default Mac disk also ignores, such as `ß` for `ss`: `IMPORT strasse` does not load `straße.l4`.

When nothing matches, the not-found error names any module whose name differs only in capitals ([When only the capitals differ](#when-only-the-capitals-differ)).
When something lower down matches, but a folder tier above it held the name in other capitals, the import uses the lower copy and a warning names the file it passed over ([Reading the resolver's output](#reading-the-resolvers-output)).
Both come from the folder's list, not from the operating system's answer, so they read the same on Linux as on a Mac.

What has been run, and what is reasoned: the rule was checked on a Mac, on an HFS+ volume (every example in the specification's probe table, and the test suites) and on the APFS internal disk (a file that imports a variant of its own name); which spellings each disk treats as one file, such as `straße` and `strasse`, was measured on both.
On Linux and Windows it is reasoned from the code, and from tests that stand in for each kind of disk; it has not been run on those systems by hand.
The web playground and Legalese Cloud compare names in memory, so no disk is involved there.

The limits of the rule, each accepted rather than fixed:

- **Unicode normal forms.**
  The comparison does not normalise Unicode.
  Mac OS Extended (HFS+) stores an accented letter taken apart, as a plain letter followed by a combining accent, while the `IMPORT` spells it as one character; the two spellings of `café` match neither exactly nor by capitals, so for such a name L4 keeps the operating system's answer, as before.
  A correctly spelled `` IMPORT `café` `` therefore still works on HFS+, and the cost is that `` IMPORT `CAFÉ` `` is also accepted there.
  Closing that would need a Unicode normalisation library, which L4 does not depend on.
- **A folder L4 cannot list.**
  When the operating system says the file exists but the folder's list of files cannot be read, L4 cannot check the capitals, so it uses the file under any capitals, as before.
  It notes this only in a Debug line, which the command line does not print.
- **A file ending in `.L4`.**
  A file such as `daydate.L4` is refused, because a module's file must end in `.l4`, but the not-found error does not suggest it: no spelling of the `IMPORT` would reach it.
  When it is passed over for a copy lower down, the warning names it and says to rename it.
- **Unsaved changes in the editor.**
  The not-found error in the editor names only modules saved on disk or built in; a module that exists only in an unsaved editor tab is not suggested.

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
When the module's name differs only in capitals from a standard library module, or from a bundle `.l4` file other than the importing one in a directory the importing file can import from (its own, or the bundle's root as above), that `WARN` also carries a `hint` field with the sentence the command line prints, such as ``Capital letters count in a module name: `dayDate` and `daydate` are different names. Did you mean `daydate`?``.
When the only near match is the importing file's own name (`Foo.l4` that writes `IMPORT foo`), the `hint` says that a module cannot import itself, as the command line does (see [When only the capitals differ](#when-only-the-capitals-differ)).

This ordering is pinned by tests: `jl4-lsp/test/LibraryResolutionSpec.hs`
(unit, table-driven), the `l4 library resolution shadow (B′)` group in
`jl4/tests-cli/Main.hs` (black-box CLI), and, for the service's shorter ladder,
`jl4-service/test/StdlibResolutionSpec.hs` and
`jl4-service/test/UnresolvedImportSpec.hs`.
The capitals rule is pinned by `jl4-core/test/ModuleNameCaseSpec.hs` (the comparison and the sentence), the "the case rule (#1080)" group of `LibraryResolutionSpec.hs`, the `l4 IMPORT: capitals count in a module name (#1080)` group in `jl4/tests-cli/Main.hs`, `jl4-core/test/ImportResolutionSpec.hs` (the library's checker) and `jl4-service/test/UnresolvedImportSpec.hs` (the `hint` field).

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

The winner's line in this form, the candidate table and the shadow warning
appear only when `JL4_LIBRARY_PATH` is **unset** (in the env-pinned regime you
have explicitly chosen your store, and the logs keep the historical one-line
form). The skipped-file warning, last below, appears in both.

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

**The skipped-file warning**, at Warning priority, when a folder tier ranked above the copy that was used holds the module's file only under other capitals.
Unlike the lines above, it is printed whether or not `JL4_LIBRARY_PATH` is set, because the file passed over is your own; it names files by name and their place in words, never by path:

```
Warning | [Import Resolution] `IMPORT math` did not use `Math.l4` beside the importing file, because capital letters count in a module name: `Math` and `math` are different names.
It used the standard library's `math` instead.
To use that file, change the IMPORT to `Math`, or rename the file to `math.l4`.
```

The reason and the fix depend on how the file's name differs:

- by more than capitals, such as `straße.l4` for `IMPORT strasse`: the reason is ``module names must match exactly, letter for letter: `straße` and `strasse` are different names``, and the fixes are the same two;
- in its ending, such as `prelude.L4` for `IMPORT prelude`: the reason is ``a module's file name must end in `.l4`, in small letters``, and the only fix is ``rename it to `prelude.l4` ``, because an `IMPORT` names no ending, so no spelling of it reaches that file.

When several files are passed over, the first line says `did not use these files`, and each follows on its own line.
A file with other capitals ranked _below_ the copy used is not mentioned: it could not have been chosen under any rule.
Nor is an `IMPORT` written inside the standard library: the library's `currency` writes `IMPORT jurisdiction`, and a `Jurisdiction.l4` of yours in the project root is not used for it, but you are not told to change an `IMPORT` you did not write.
With `JL4_LIBRARY_PATH` set, the folder it names ranks above the project, so a `math.l4` there is used and a `Math.l4` beside your file is not passed over, and nothing is printed.

The importing file itself is never offered either fix, because either one would make the file import itself.
When it is the file passed over, as for `Math.l4` that writes `IMPORT math`, the warning says what is true instead:

```
Warning | [Import Resolution] `IMPORT math` did not use `Math.l4`, which is the importing file itself: `math` differs from `Math`, the name of this file's own module, only in its capitals.
It used the standard library's `math` instead.
If you meant this file, remove the IMPORT: a module cannot import itself, and a file's own definitions need no IMPORT. If you meant the standard library's `math`, nothing needs to change.
```

If you meant the standard library's `math`, the warning appears on every check until the file has another name, one that is not `math` in any capitals.

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

The line `Nothing it defines is in scope here` is there because this is usually not the first error you see.
A failed import produces one `I could not find a definition for the identifier` for every name it was supposed to supply, and those read like broken source rather than like a failed import.
So if you are looking at a screen full of undefined identifiers, read the top of it.

### When only the capitals differ

Capital letters count in a module name ([the resolution order](#the-resolution-order) says why), so `IMPORT dayDate` does not find `daydate.l4`.
When a module's name differs from the one asked for only in its capitals, the message gains a second line that names it:

```
I could not find a module with this name: dayDate
Capital letters count in a module name: `dayDate` and `daydate` are different names. Did you mean `daydate`?
Nothing it defines is in scope here; names you expected from it are reported as undefined.
I have tried the following locations:
...
```

When several modules differ from it only in capitals, the line names them all: ``Did you mean one of: `DayDate`, `daydate`?``.
The names come from every folder tier that was tried, read from the folder's list of files, and from the built-in standard library when it was consulted (not when `JL4_LIBRARY_PATH` is set).
They are module names, never paths, so the line is the same on every computer.
The file that writes the `IMPORT` is never offered, since importing itself would fail.
When that file's own name is the only near match, as for `IMPORT foo` written in `Foo.l4`, the line says so instead:

```
`foo` differs from `Foo`, the name of this file's own module, only in its capitals. If you meant this file, remove the IMPORT: a module cannot import itself, and a file's own definitions need no IMPORT.
```

Everything a file defines can already be used in that file, so an `IMPORT` of its own name is never needed.
When the difference is more than capitals, the line says `only in how its letters are written` instead of `only in its capitals`.

A name can also differ by more than capitals in a way the default Mac disk ignores, such as `ß` for `ss`; that name is offered too, but the line says why without blaming capitals:

```
Module names must match exactly, letter for letter: `strasse` and `straße` are different names. Did you mean `straße`?
```

The web playground gives the same sentence.
Connected to a language server, it shows the message above.
Checking in the browser, it shows its own one-line message, `Module not found: dayDate (searched: embedded libraries, project VFS)`, with the sentence on a line of its own after it; so does the checker a program calls through the library (`checkWithImports`).
On Legalese Cloud the sentence is the `hint` field of the service's `WARN` (see [the resolution order](#the-resolution-order), under the service's shorter ladder).

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
