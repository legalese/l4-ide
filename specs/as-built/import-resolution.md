# Import resolution (as built)

As built on `main` by this PR.
Source spec: `specs/todo/LIBRARY-RESOLUTION-SHADOW-SPEC.md`, which is on `unstable` and not on `main`; this page stands in for it here.
The work came from `unstable`; this page describes only what `main` has.
Line numbers hold at the head of this PR, which is `main` at `2541e4366` plus this PR's commits.

Differences from the source spec: its §2 and §2.1 describe the code before #134 (embedded copy last, a `resolveLibraryFromFilesystem`, two resolvers); it covers #134 only, not #64, #148, #167, #87, #102, #93, #630 or #627; its §8 acceptance 1 (the winning copy is visible) is not met on the CLI; its §7 calls the in-memory layer "orthogonal and correct", but the API/WASM resolver ranks the embedded copy above it.

Units: PRs #87, #102, #134, #148, #167 and #93; #64 (inside #77, branch commit `17dee68a4`, fix `b54d4d403`, both on unstable); and the three follow-ups that came out of reviewing them, #630 (the service's ladder, one warning per mistake and per file, the staleness wording), #627 (opening the stdlib from VS Code) and #642 (a `WARN` for an `IMPORT` that resolves to nothing, and the two rulings of 2026-10-12 below).
#143 is not carried: its one import-resolution hunk (the `entityInfo` union in `Resolution.hs`) is subsumed by `unionImportedCheckEnv` (#543, already on `main`), and the rest of it is the DMN exporter, which is not part of this change.
#134's diff also carries 22 unrelated `paper/` files, which are not part of this feature.
#451 (an unresolved `IMPORT` is an error at its line; percent-escaped basenames resolve) is a separate change on unstable and is not on `main`.

## Labels the code comments use

Comments in `Rules.hs`, `Shake.hs`, `EmbeddedLibraries/TH.hs`, `Cli/Common.hs`, the tests and the fixtures cite the source spec's labels; in this PR they cite this page with the same labels.

- Option B′: the ladder below, with the embedded stdlib at tier 4, beneath every project-scoped copy and above the machine-global ones.
- Option E: the shadow warning (Behaviour, and Diagnostics).
- §3.1: the incident the ordering guards against, a machine-global XDG symlink silently shadowing the stdlib the binary was built with.
- §3.3: one module name resolves to one source per build, for parsing and type checking alike.
- §3.4: the embedded stdlib is read when GHC compiles `L4.API.EmbeddedLibraries`, which Cabal does not trigger by itself when only a library changes.
- §6: an open question, whether the VS Code bundle's `libraries/` directory is still needed now that the binary embeds the stdlib.

## What it does

`IMPORT <name>` finds one source for `<name>` by a fixed ladder, and the same source serves every importer in a build.
A project's own copy of a library beats the stdlib compiled into the binary, and the compiled-in stdlib beats machine-global copies (XDG store, VS Code bundle).
When several differing copies are visible, a warning names them all, each file once: on stderr from the CLI, in the language server's log from the editor.
An `IMPORT` that resolves to nothing is announced once, as a Warning.
Diamond imports (A imports B and C, both import D) type-check C against D's exports, not against an empty environment.
A build that would ship an `l4` with no embedded stdlib fails at compile time, and CI checks the sdist carries the libraries.
Editor hover shows inferred types with stable names (`a`, `b`) instead of raw inference variables such as `x10`.
`jl4-service` resolves a deployment's `IMPORT`s against the deployment's own files and the stdlib built into the service, and nothing from the machine it runs on.
In VS Code, go-to-definition into the stdlib opens a read-only tab with the embedded text.

## What users and operators will notice

Each of these is a change in output or behaviour that a reader of this PR would not see in the diff of a single file.
Measured on 2026-10-13 with the `l4`, `jl4-lsp` and `jl4-service` built from plain `main` and from this PR, with `JL4_LIBRARY_PATH` unset and an empty XDG store.

- **`--json` diagnostics gain Warning entries.** `l4 check --json` and `l4 run --json` carry the resolver's Warning lines in `diagnostics`. For `main.l4` beside a project-local `prelude.l4`, `diagnostics` goes from `[]` on `main` to one entry, `Warning | [Import Resolution] Multiple differing copies of module `prelude` are visible: …`.
- **`l4 render --format json` reports stdlib blocks at a `jl4-embedded:` URI.** For a file that writes `IMPORT prelude`, the 107 prelude blocks have `"sourceModule":"jl4-embedded:/prelude.l4"`; on `main` they say `"file://prelude.l4"`. A program that reads `sourceModule` as a path must be told.
- **Go-to-definition into the stdlib returns a `jl4-embedded:/prelude.l4` URI.** With the VS Code extension's bundled `libraries/` directory beside the binary, `main` answered a real file URI, `file:///…/libraries/prelude.l4`, which the editor could open. This PR ranks the embedded copy above that tier, so it answers `jl4-embedded:/prelude.l4`, and VS Code opens that read-only through this PR's content provider, which asks the server with `l4/embeddedLibrary`. With no libraries on disk, `main` answered `file://prelude.l4`, which names no file. Another editor receives the same `jl4-embedded:` URI and has to make that request to show it. With `JL4_LIBRARY_PATH` set the answer is still a real file.
- **The CLI prints new Warning lines on stderr:** the shadow warning when two differing copies of a module are visible, and `Module not found: <mod>` once for an unresolved import.
- **`jl4-service` logs three new `WARN` lines.** At start-up, `JL4_LIBRARY_PATH is set and ignored` with the path, when the variable is set. At every compile of a bundle that ships a file named like a stdlib module with different text, `Bundle file stands in for a standard library module`, naming the deployment, the file and the module. For every `IMPORT` of a bundle that resolves to nothing, `Bundle IMPORT resolves to nothing`, naming the deployment, the importing file and the module, when the bundle is compiled, which a restart does again from the stored sources (#642, #666).
- **VS Code deploys no longer zip the stdlib (ruled 2026-10-12).** The extension zips the open file with the imports that `l4/getExportedFunctions` lists. With the extension's bundled `libraries/` directory beside the binary, `main` listed `file:///…/libraries/prelude.l4` and `…/daydate.l4`, so the bundle carried the editor's copy of the stdlib; here the list is `jl4-embedded:/prelude.l4` and `jl4-embedded:/daydate.l4`, which `sidebar-provider.ts:1284` (the third commit of #627) skips. A deployment therefore runs on the service's built-in stdlib, not the one the editor checked against, and a version skew between the extension and the service can change answers. That is ruled (see Rulings). With no libraries on disk `main` listed `file://prelude.l4`.
- **A library that sits only on the service's host is no longer found.** A bundle with `IMPORT sitelib`, where `sitelib.l4` is in the service's working directory, deployed "applied" and answered 200 on `main`. Here it deploys "applied" and every call answers 422 "Internal error: `site bonus` is not in scope. Please report this as a bug.", and the service logs one `WARN`, `Bundle IMPORT resolves to nothing`, naming the deployment, `main.l4` and `sitelib`, at the deploy and again after a restart (#642). "Applied" and then a 422 is `main`'s own for an import that is missing everywhere (measured on `main` with `sitelib.l4` nowhere, where nothing is logged). A file shipped in the bundle is still found (the own-`prelude.l4` case of `StdlibResolutionSpec`).
- **Before a host is upgraded to this build,** its operator should check `/var/lib/jl4-service/.env` and the XDG store (`~/.local/share/jl4/libraries/`) for any library or `JL4_LIBRARY_PATH` a deployment relies on, because the service no longer reads either; any such library has to be shipped inside the bundle, beside the file that imports it.
- **A store that holds a `bundle.cbor` written by an older build is not read and not changed** (#666: a restart compiles the stored sources and keeps no cache). Such a cache holds the prelude at `file://prelude.l4` and never at `jl4-embedded:`, so a build that started from it would pair it with a library environment at the new address and answer `sum is not in scope` (HTTP 422) at call time. Measured with the fixture planted in a store, by a reviewer: at `50df1abb8`, an earlier head that read the cache, the log said `Rebuilt functions from CBOR cache`, the call answered 422 `Internal error: sum is not in scope`, and the file was untouched; at `31cee57e5`, the head the second review was on, the log said `Corrupt bundle.cbor, will recompile` (the fixture was written before #545 was merged), the call answered 6, and the file was rewritten, which a rollback cannot use. The test `serves a function that calls sum from a store whose cache holds the standard library at its old address` (`jl4-service/test/IntegrationSpec.hs:874`, fixture `jl4-service/test/fixtures/old-prelude-cache/`, a `bundle.cbor` written by `main` at `00298eb60` for a function that calls `sum`) restarts the service on that store and expects the answer 6 and the file byte for byte unchanged (it pins "answers 6, file left as it was"), so that a rollback finds the cache it wrote.
- **`l4 deploy` no longer uploads the standard libraries.** A built-in library now has the address `jl4-embedded:/<name>.l4`, which is not a file's, so the CLI's list of files to upload no longer holds it; the lookup in `jl4/app/L4/Cli/Deploy.hs` that put the built-in copy in the upload is deleted, and the tutorial says so. Assumed, not ruled: that the ruling of 2026-10-12 (a deployment resolves its own files and the built-in stdlib) covers the CLI as it covers the extension's upload. Measured with the real `l4` and `jl4-service` binaries, `l4` run with `HOME` and `XDG_DATA_HOME` in empty directories and `JL4_LIBRARY_PATH` unset: a module with `IMPORT prelude` is uploaded as `imp.l4` and `prelude.l4` on `main`, and as `imp.l4` alone here. A library file that `l4` finds in the project directory or through `JL4_LIBRARY_PATH` is still uploaded like any imported file, because those two come before the built-in copy on the ladder; the per-user library store never reaches the upload, because the built-in copy comes before it (a reviewer measured this; the ladder says why). Measured with `l4` run in the test environment, where `JL4_LIBRARY_PATH` is pinned to the checkout's libraries and a per-user library store exists, `imp.l4` and `prelude.l4` on both, which by the ladder is the `JL4_LIBRARY_PATH` copy. **Changed 2026-10-26: `l4 deploy` keeps folders now, so the sentences above about what is "still uploaded", and the flat names `imp.l4` and `prelude.l4`, describe the flat upload of 2026-10-13 and are no longer true.** A library file found through `JL4_LIBRARY_PATH`, the project directory or the per-user library store (when the built-in set does not carry the module) is uploaded under its path below the folder that all the uploaded files share, and `l4 deploy` stops before any request when that file is outside the project folder, or is in a folder that is neither the importing file's nor the top of the upload, the only two places the service looks for an `IMPORT`. Every `IMPORT` line is judged, a name written with a slash included: this version reads `` IMPORT `lib/shared` `` as the bare name `shared`, in `l4` (measured 2026-10-26: `l4 check` answers "I could not find a module with this name: helper" for `` IMPORT `sub/helper` `` with `sub/helper.l4` in place) and in the service (measured 2026-10-26 with a hand-built bundle: the log says "Resolving import: zdefs" for `` IMPORT `lib/zdefs` ``, and the module is found at the top of the bundle and not in `lib/`). **Changed 2026-10-26, a second time: a library file that is exactly the copy built into `l4` is not uploaded.** `Deploy.hs` compares the file's bytes with the built-in text of the module of its name (`L4.API.EmbeddedLibraries`, the comparison `jl4-service`'s `logStdlibStandIns` makes), leaves a file that is equal out of the upload, does not judge where it sits, does not count it as outside the project folder, and prints `Not uploaded, the deployed service has it built in: <module>` for it. A file of the same name whose bytes differ is a project file like any other. So in the test environment above (`JL4_LIBRARY_PATH` pinned to the checkout's libraries) a project outside that checkout deploys with the project alone when the checkout's libraries are the ones built into the `l4` that runs, which they are for a binary built from that checkout; a checkout whose libraries differ from the built-in ones (newer, or edited) stops with "outside the project folder", and unsetting `JL4_LIBRARY_PATH` uploads the project alone. Pinned by `jl4/tests-cli/CliTest/Deploy.hs`, whose black-box cases write the copies from the built-in text of the build under test; the rules are in `jl4/app/L4/Cli/DeployPlan.hs` and the user's account is "What gets uploaded" in `doc/tutorials/getting-started/l4-cli.md`. When an uploaded copy of a standard library module differs from the built-in one, the service logs one `WARN`, `Bundle file stands in for a standard library module`.
  **The service does not find a file beside its importer when the first folder of the file's path has a space, a letter outside A to Z, or one of `# ' + ( ) % , = @ & ! $ ; [ ]` in its name, so `l4 deploy` and the extension's deploy refuse such a folder, and the refusal is there because of the service.**
  The cause is in `resolveImportQuietly` (`jl4-lsp/src/LSP/L4/Rules.hs`), which the service shares with the language server: the candidate beside the importer is the relative path of the importer's folder plus the module name, and `roundTrippingFileUri` cannot spell a relative path whose first part needs a percent-escape in a `file:` URI that reads back (the part before the first `/` becomes the URI's authority, which is read back without un-escaping).
  That is a residual of the fix for smucclaw/l4-ide#971, which is closed (2026-09-22).
  The fix is `roundTrippingFileUri`, which is on `unstable` and covers a module whose own basename needs a percent-escape (the comment above it in `jl4-lsp/src/LSP/L4/Rules.hs` says so).
  No issue tracks the residual yet.
  It falls back to the absolute spelling, which is not the key `jl4-service/src/Backend/Jl4.hs` registered the file under (`normalizedFilePathToUri (toNormalizedFilePath ("./" <> path))`), so the module is never found.
  Measured 2026-10-26 with hand-built bundles on the service of this branch, run through the harness of `jl4-service/test/BundleRootSpec.hs` with throwaway cases (the committed cases are the pending one for `my dir`, the passing one for a module at the top from `my dir/x.l4`, and `root-siblings` for the ASCII folder `a`): `{a/x.l4, a/helper.l4}` answers 105 on both call paths, and so do the folders `my-dir_2.x`, `v1.2`, `a~b` and `ok/my dir`; the folders `my dir`, `a b/c`, `dossier é`, a Hebrew name, and names with `+ @ , = ( ) # % ' & ! $ ; [ ]` in the first part answer "zmark is not in scope", and the deploy says "ready" for all of them.
  A reviewer measured on 2026-10-26 against the real service that `ok/my dir` and `ok/dossier é` are found, `my dir` and `a b/c` are not, and `a#b` and `a'b`, built by hand, are not; only the first segment of a file's name decides.
  Read in the source, not measured: `filePathToUri` (lsp-types 2.3.0.1, `isUnescapedInUriPath`, which uses `isUnreserved` of network-uri 2.6.4.2) leaves unescaped only ASCII letters, digits, `-`, `_`, `.` and `~`, and percent-escapes every other character of a folder name.
  That agrees with each case above, and it would make a character that is not on the measured list, such as `*` or `:`, fail too; no bundle with one was built.
  A module at the top of the bundle is found from an importer in `my dir/`.
  The same cause makes a module at the top whose own name has a space or such a letter (`my mod.l4` for `` IMPORT `my mod` ``, `café.l4`) unfindable, flat or not, while `a/my mod.l4` is found; that was so before folders were kept, and `l4 deploy` does not refuse it.
  The refusal is `UnsafeFolder` in `jl4/app/L4/Cli/DeployPlan.hs` and `collectBundle` in `ts-apps/vscode/src/deploy-bundle.ts`.
  It judges every folder of the path and stops at every character other than ASCII letters, digits, `.`, `-` and `_`, so it also stops a few names that the service finds: `ok/my dir` and `ok/dossier é`, because only the first part decides there, and `a~b`, because `~` is fine.
  For that reason the refusal says the service "may not find" the file, and not that it would not.
  The pending case in `BundleRootSpec` ("finds a sibling in a folder whose name has a space") is the test that passes when the resolver is fixed; the refusals go when it does.
  **The extension's deploy cannot judge where an `IMPORT` is found.**
  `l4/getExportedFunctions` returns the imported files and not the `IMPORT` lines, so `deploy-bundle.ts` has no line to check and uploads a library in a folder that is neither its importer's nor the top; the service reports the deployment as ready and a call that needs the library fails.
  It does refuse an imported file in a folder with such a name, because every file but the main one is one an import brought in.
  Judging the lines would need the language server to return them, which is not built.
- **A service built before `bundleRoot` (`jl4-service/src/Backend/Jl4.hs`, the commit "the service resolves bare names from the bundle root, not the first file's folder") does not find a library at the top of an upload that keeps folders.**
  Such a service looks a bare `IMPORT` up from the folder of the first file of the upload in alphabetical order, not at the top.
  That is how it compiles the bundle and answers a call on the direct path.
  A call on the wrapper path, which a request with a `{}` in an input takes, looks from the folder of the function's own file instead (`jl4-service/test/BundleRootSpec.hs`, header; the comment on `bundleRoot` in `jl4-service/src/Backend/Jl4.hs`; read in the code of `977691b36`, where `evaluateModule` passes the function's file to a session whose root is that file's folder).
  A project that the old flat `l4 deploy` deployed and that worked, `a/main.l4` importing `defs` with `defs.l4` at the top and found through `JL4_LIBRARY_PATH`, is uploaded now as `a/main.l4` and `defs.l4`.
  A reviewer measured on 2026-10-26 against the real service that such an old service reports that deployment as ready and that every call then answers "zmark is not in scope".
  The default target of `l4 deploy` is Legalese Cloud (`jl4/app/L4/Cli/Cloud.hs`: "No --server given, so this goes to Legalese Cloud").
  Neither `l4 deploy` nor the extension's deploy checks the version of the service.
  Whether the service has to be released before `l4 deploy` and the extension are is not decided.
  What the files read on 2026-10-26 show about how the service change would reach Legalese Cloud follows.
  The Cloud runbook `runbooks/binary-rollout.md` of `legalese/jl4-auth-proxy` takes the URL and SHA256 of the service binary, `jl4-service-linux-x64`, from a release of `smucclaw/l4-ide` (its steps 1 and 2), and applies it by hand.
  `.github/workflows/rollout-jl4-service.yml` of the same repository is a `workflow_dispatch` workflow that reads the release with `-R smucclaw/l4-ide`.
  Both were read in a local clone of that repository at `94f60af`, committed 2026-03-30, whose remote could not be reached on 2026-10-26, so a later change to them is not excluded.
  `.github/workflows/main-tag.yml` of this repository is `workflow_dispatch` only and publishes `jl4-service-linux-x64` with each `l4-ide-build-<run_number>` release.
  Those releases are in `legalese/l4-ide` (the newest, `l4-ide-build-100`, is of 2026-10-25), and none of the 100 newest releases of `smucclaw/l4-ide` has that name (its newest is `vscode-wasm-build-117`, of 2026-04-21), both read with `gh release list` on 2026-10-26.
  So which repository's release Cloud takes its binary from today is not established by these files.
  If it is a release made by `main-tag.yml`, the service change reaches Cloud after a carry to `main` (`CLAUDE.md` §1: the extension and `jl4-service` come from `main` via `main-tag.yml`), a `main-tag.yml` cut and a rollout by hand.
  Nothing in this branch names who carries, cuts or rolls out.
  Path imports (Stage 1 of the relative-imports work, PR #748, open against `unstable` and not merged when checked with `gh pr view` on 2026-10-26) need a service that has that change as well.
  A service without it reads `` IMPORT `../b/mod` `` as the bare name `mod` (measured above for `` IMPORT `lib/zdefs` ``), so a project that uses a path import to a file beside neither its importer nor the top of the upload still deploys as "ready" and fails its calls.
  The hazard is not limited to Cloud: any service built before `bundleRoot` that `l4 deploy --server` (`jl4/app/L4/Cli/Cloud.hs`) or the extension's `jl4.serviceUrl` setting (`ts-apps/vscode/package.json`; `getApiBaseUrl` in `ts-apps/vscode/src/auth.ts`) reaches behaves the same.
  The extension already requests `/health`: `verifyConnection` in `ts-apps/vscode/src/auth.ts` fetches it and looks only at the status code.
  For a Legalese Cloud session that request goes to `https://legalese.cloud/service/health?org=<slug>`, a URL of the proxy, and not to the service.
  `getHealth` in `ts-apps/vscode/src/service-client.ts` returns a `ServiceHealth`, which has `status` and `instances` and no version field, and no other file under `ts-apps/` or `ts-shared/` calls `getHealth` (grep of 2026-10-26).
  `GET /health` on `jl4-service` reports its version as `version` (`hrVersion`, `jl4-service/src/Application.hs:294`, `jl4-service/src/Types.hs:723`), but a build made without `JL4_SERVICE_VERSION` reports `0.0.0-dev` (`jl4-service/src/Version.hs`).
  The release workflow sets that variable (`.github/workflows/main-tag.yml:219`), and `Version.hs` says a local build with it unset falls back to `0.0.0-dev`.
  So a development build that has the change reports `0.0.0-dev` unless the variable was set when it was built, and a comparison of the reported version with a minimum is not a safe gate by itself.
  The proxy's own answer at `/service/health`, which is what the extension gets on Cloud, is built in `handleHealth` (`src/admin/routes.ts` of `legalese/jl4-auth-proxy`, in the clone at `94f60af` named above) from the instances' status and the organisation's configuration, and does not copy the service's `version`.
  A restart compiles every stored deployment again from its sources (`jl4-service/src/Compiler.hs`: "A deploy and a restart both come through here"), and an unresolved `IMPORT` is only a `WARN` there (`logUnresolvedImports` in the same file, which cites ruling R5 of 2026-10-12).
  So a stored bundle that this change stops resolving, for example `{a/helper.l4, b/x.l4}` with `x.l4` importing `helper`, comes back from a restart as ready and fails its calls.
  `jl4-service --check-store` (#747, merged 2026-10-25 as `72093818a`; it is on `unstable` and not in this branch) marks a deployment `failed` for the reasons a restart would register it as failed (`jl4-service/README.md` on `unstable`, "Checking a store before a rollout"), and an unresolved `IMPORT` is not among them, so it reports such a bundle as `ok`, with the `WARN` only in its log on stderr (read in `jl4-service/src/CheckStore.hs` and `DeploymentLoader.hs` at `origin/unstable`; not run).
  The same README section says "The check compiles; it does not evaluate."
  No count of stored deployments that this change stops resolving is recorded in this branch or in the `--check-store` section of `jl4-service/README.md` on `unstable`.
  Status on 2026-10-26: that commit is proposed, not landed (it is on `fix/deploy-keeps-paths` and not an ancestor of `origin/unstable`, checked with `git merge-base --is-ancestor`).
- **The service README's list of wrapper-path limits loses two lines**, "a name the module gets by `IMPORT` is not found" and "a function with a `BOOLEAN` input fails the same way". Measured as a deployed service (the real `jl4-service` started from an empty directory outside the repository, `JL4_LIBRARY_PATH` unset, `HOME` and `XDG_DATA_HOME` in empty directories, modules deployed with `l4 deploy --server`, then called with a `{}` in an input so the request takes the wrapper, and checked against a string for a NUMBER input, which only the wrapper refuses with `Expected JSON number`): here the module with `IMPORT prelude` (uploaded without a `prelude.l4`) and the function with a `BOOLEAN` input both answer 200 on both paths. On `main` the `BOOLEAN` function answers 200 on the direct path and 422 on the wrapper path (the body begins `Info | [Import Resolution] Resolving import: prelude from file://boo.l4 ...`); the module with `IMPORT prelude` answers 200 there only because `main`'s `l4 deploy` puts `prelude.l4` in the upload, so the `IMPORT` half cannot be shown failing on `main` with `l4 deploy`; it no longer arises here, because the upload no longer carries the prelude and the service answers 200 without it. Handed a bundle that holds only the module (no `prelude.l4`) directly, as the integration-test harness does, `main` at `df9d37a4b` answered 422 on the wrapper path for the module with `IMPORT prelude` as well, and this PR answers 200. The scope change is what removes the limit.
- **An unresolved `IMPORT` still checks "succeeded" on `main`.** `l4 check` prints the diagnostic and exits 0; this PR does not change that (#451 does, on unstable).

### What the new tool refuses that the old tool deployed (2026-10-26; assumed, not ruled)

Assumed, not ruled: that these refusals are the right price for keeping folders, and not a reason to go on flattening them.
The old `l4 deploy` uploaded every file at the top of the zip, and a reviewer reports that each project below deployed with it and answered calls.
This version stops each one before any request, and mending it is work for the project's owner, as the refusal says.
Checked 2026-10-26 with the `l4` built from the head of this branch, run with `--server http://127.0.0.1:9`, where nothing listens: each case below exits 1 with the refusal and not with "Could not reach", while a flat control project and a project whose folder is `a-b_c.d` get as far as "Could not reach".
The fix named for each was run too and got as far as "Could not reach".

- **A library found through `JL4_LIBRARY_PATH` or the per-user library folder, in a subfolder of the project that is neither the importer's folder nor the top.**
  For example `lib/shared.l4` with `JL4_LIBRARY_PATH` naming `lib`, or `data/jl4/libraries/x.l4` with `XDG_DATA_HOME` naming `data` inside the project.
  It is refused as `UnreachableImport`: the file would be uploaded as `lib/shared.l4`, a place the service does not look in.
  Fix: put the library beside the file that imports it, or at the top of the project.
  With `JL4_LIBRARY_PATH` naming the old folder, move the file and do not copy it: a copy beside the importer was still refused while the variable was set, and went through with it unset.
  The per-user library folder is read after the importer's folder, so a copy beside the importer is enough there.
- **`` IMPORT `sub/helper` `` with the library found in `sub/` through `JL4_LIBRARY_PATH`.**
  This version reads that name as `helper`, finds `sub/helper.l4` through the variable, and would upload it as `sub/helper.l4`; it is refused as `UnreachableImport`.
  Fix: move `helper.l4` beside the importing file or to the top of the project.
  The line can stay as it is.
- **An importing file together with a file it imports, in a folder named `my dir`, `é`, a Hebrew name, `a%b`, `a#b`, `a+b`, `a(b` or `a'b`.**
  The old tool flattened the folder away, so the service found the file at the top and the call answered.
  This version keeps the folder, and when the upload also holds a file outside that folder the service may not find the file beside its importer, so it is refused as `UnsafeFolder`.
  When all the files sit in one folder the upload holds plain names and nothing is refused.
  Fix: rename the folder to use only letters, digits, `.`, `-` and `_`.
- **A library, or any other imported file, that lies outside the project folder and differs from the copy built into `l4`.**
  For example a shared library kept in a folder beside the project, found through `JL4_LIBRARY_PATH` naming that folder, or a library in a per-user library folder (`XDG_DATA_HOME`) that is outside the project.
  The project folder is the folder `l4` is run from when the file being deployed is inside it (and it is not the top of a drive), and otherwise the folder of the file being deployed.
  The old tool had no project folder and no check of where a file lies: it read every file it was given an absolute path for and uploaded it at the top of the zip under its plain name, which is a place where the service looks for a bare `IMPORT` (read in `977691b36:jl4/app/L4/Cli/Deploy.hs`; the old tool was not run against a service for this case).
  This version refuses it as `OutsideRoot`, which names the file and the project folder, and sends nothing.
  The refusal is the same for any imported file outside the project folder, however `l4` found it: `planBundle` in `jl4/app/L4/Cli/DeployPlan.hs` checks every collected file, and `jl4/tests-cli/CliTest/Deploy.hs` has a unit case for an import in a sibling folder; only the two library routes above were run against the binary.
  A file that is exactly the copy built into `l4` is not refused, because it is not uploaded.
  Fix: put the library inside the project folder, beside the file that imports it.
  With `JL4_LIBRARY_PATH` naming the old folder, move the file and do not copy it: a copy beside the importer was still refused while the variable was set, and went through with it unset.
  The per-user library folder is read after the importer's folder, so a copy beside the importer is enough there.
  Checked 2026-10-26 as for the three above, with the `l4` built from this branch's code: a project folder holding `main.l4` with `IMPORT shared` and a folder beside it holding `shared.l4`, with `JL4_LIBRARY_PATH` naming that folder, exits 1 with "This file lies outside the project folder" and names the file; so does the same project with `XDG_DATA_HOME` naming a folder whose `jl4/libraries/` holds `shared.l4` and `JL4_LIBRARY_PATH` unset.
  With `shared.l4` copied beside `main.l4` the first still exits 1 while the variable is set, and gets as far as "Could not reach" with the variable unset or with the file moved; the second gets as far as "Could not reach" with the copy beside `main.l4`.

## Where it lives

- `jl4-lsp/src/LSP/L4/Rules.hs:238-259`: `LibraryScope`, `AmbientLibraries` (the whole ladder) or `EmbeddedStdlibOnly` (the stdlib built into the binary and nothing else).
- `jl4-lsp/src/LSP/L4/Rules.hs:295-366`: `resolveLibrary` takes a scope; the `EmbeddedStdlibOnly` clause (l.318-328) is the embedded copy alone, and the ambient clause builds the ladder (`cands`, l.346-348), probes it, and returns every existing candidate in order.
- `jl4-lsp/src/LSP/L4/Rules.hs:385-405`: `distinctCopies` keeps each file once, by canonical path, at the rank of its first appearance.
- `jl4-lsp/src/LSP/L4/Rules.hs:449-489`: `resolveImportShared` calls `resolveImportQuietly` and announces an unresolved import once per (importing module, module name), clearing the key when it resolves.
- `jl4-lsp/src/LSP/L4/Rules.hs:491-610`: `resolveImportQuietly` is the in-memory tier (l.504-539), then `resolveLibrary`, the log lines, the shadow warning (`warnOnLibraryShadow`, l.617-638) and the returned `ImportOutcome`.
- `jl4-lsp/src/LSP/L4/Rules.hs:668-681`: `jl4Rules` is `jl4RulesIn AmbientLibraries`; `jl4RulesIn` creates the session's two warn-once sets and binds `resolveImport`, which both `GetMixfixRegistry` (l.731) and `GetImports` (l.764) call.
- `jl4-lsp/src/LSP/L4/Rules.hs:407-447`: `ImportOutcome`, `EmbedStatus` (`EmbedSkipped`, `EmbedEmpty`, `EmbedMissing n`) and `renderEmbedStatus` (from #167).
- `jl4-lsp/src/LSP/L4/Rules.hs:640-666`: `unresolvedImports`, the imports `GetImports` could not resolve (it gives each the importing file's own URI as a placeholder, `mkImportUri` at l.767-787); `jl4-service/src/Backend/Jl4.hs:155-182` and `:239-243` return them from `typecheckAndEvalBundle` as (importing file, module) pairs (#642).
- `jl4-lsp/src/LSP/L4/Oneshot.hs:31-107`: `oneshotL4ActionAndErrorsIn`, `oneshotL4ActionAndDiagnosticsIn` and `oneshotL4ActionIn` run a one-shot session under a chosen scope, all through `oneshotL4ActionWithDiagsIn`; the old names are the same with `AmbientLibraries`.
- `jl4-lsp/src/LSP/Core/Shake.hs:338-403`: `embeddedLibraryUriScheme` (`"jl4-embedded"`), `embeddedLibraryUri`, `embeddedLibraryVfs`, `embeddedLibraryText`, and `getVirtualFile`'s fallback to it; `addVirtualFileUri` at l.422.
- `jl4-lsp/src/LSP/L4/EmbeddedLibrary.hs`: the `l4/embeddedLibrary` request, `{uri}` to `{text}`, served from the same map the build graph reads; `jl4-lsp/app/LSP/L4/Handlers.hs:820-833` registers it.
- `ts-apps/vscode/src/embedded-library.ts`: the document selector that forwards `jl4-embedded:` documents to the server and the content provider that serves their text; `ts-apps/vscode/src/extension.mts:306` and `:395-406` wire them in, `ts-apps/vscode/src/sidebar-provider.ts:1284` keeps embedded modules out of deploy zips, and `ts-shared/jl4-client-rpc/custom-protocol.ts:253` defines the request type.
- `jl4-core/src/L4/Import/Resolution.hs:180-252`: `resolveImports`, the API/WASM resolver; the already-resolved branch at l.190-191 is #102's fix.
- `jl4-core/src/L4/TypeCheck/Types.hs:470-492`: `unionImportedCheckEnv` (#543, already on `main`): `entityInfo` is unioned left-biased (l.492), and the comment above it (l.470-474) gives the rationale that #143 wrote into `combineResolvedImports` (`jl4-core/src/L4/Import/Resolution.hs:347`).
- `jl4-core/src/L4/API/EmbeddedLibraries.hs:44-95`: the TH splice that embeds `jl4-core/libraries/*.l4`; its `fail` at l.79 is #167's.
- `jl4-core/jl4-core.cabal:21`: `data-files: libraries/*.l4`, above every section, with the reason in l.7-20 (l.7 begins "KEEP THIS ABOVE THE `flag` STANZAS").
- `jl4/app/L4/Cli/Common.hs:185-194`: `isProgressChatter` drops Info/Debug `[Import Resolution]` lines and keeps Warning/Error ones.
- `jl4-service/src/Backend/Jl4.hs:134-153`: `bundleScope = Rules.EmbeddedStdlibOnly`, which every session the service opens runs under (l.218, l.1133, l.1386, l.1406); l.187-230 registers each embedded library at `embeddedLibraryUri`, unless the bundle ships a file of the same basename.
- `jl4-service/src/Compiler.hs:40-60` and `:105`: `logStdlibStandIns`, the `WARN` for a bundle file that stands in for a stdlib module; `:62-80` and its call (`:112`): `logUnresolvedImports`, the `WARN` for an `IMPORT` that resolves to nothing, called from `compileBundle`, which a restart reaches through `DeploymentLoader.loadAndRegister`; `jl4-service/src/Application.hs:108-115` logs the ignored `JL4_LIBRARY_PATH`.
- `jl4-lsp/src/LSP/L4/Actions.hs:407-419`: hover renders a type through `prettyTypeForDisplay` (`jl4-core/src/L4/Print.hs:119`).
- `jl4-lsp/jl4-lsp.cabal:156-179`: the `jl4-lsp-test` suite, created by #93.
- User docs: `doc/reference/libraries/resolution.md` (the ladder table at l.26-34) and `jl4-core/libraries/README.md`, both from #134, and `doc/reference/libraries/IMPORT.md`, whose resolution rule this PR corrects.
  `doc/reference/libraries/README.md`, `doc/reference/README.md` and `prelude-example.l4` no longer say the prelude is imported automatically, which `main` measured as false (a file that calls `sum` without `IMPORT prelude` gets "could not find a definition"); the wording is unstable's (`ec899dc95`).
  `doc/reference/libraries/resolution.md` names the XDG store on Windows, `%APPDATA%\jl4\libraries\` unless `XDG_DATA_HOME` is set, taken from the `directory` package's source (`getXdgDirectory XdgData`) and not run on Windows.
  `jl4-service/README.md` has a "Libraries and `IMPORT`" section with the three `WARN` lines.

## Behaviour and rules

In-memory tier (tier 0), probed first through the memoising `GetFileContents` rule: `project:/<mod>.l4`, then the importing file's directory, then the root directory (`Rules.hs:504-539`).
Then the ladder, first existing copy wins (`Rules.hs:339-348`):

1. `$JL4_LIBRARY_PATH/<mod>.l4`, only when the variable is set;
2. `<root>/<mod>.l4`;
3. `<dir of importing file>/<mod>.l4`, omitted when the importer has no file path;
4. the embedded stdlib;
5. `<XDG data>/jl4/libraries/<mod>.l4`;
6. `<exeDir>/../../libraries/<mod>.l4`.

Under `EmbeddedStdlibOnly` the ladder is tier 4 alone, whatever the environment and the working directory hold; `JL4_LIBRARY_PATH` is not read, so `hasExplicitPath` is `False` (`Rules.hs:318-328`).
`jl4-service` runs every session under that scope.
Before this PR it registered the stdlib up front at `./<name>.l4`, a key the in-memory tier hits first, so the host's files could not stand in for the stdlib; registering it at `jl4-embedded:` made the host's `prelude.l4` (in the working directory, or in a directory named by `JL4_LIBRARY_PATH`) win silently, and the scope is what keeps `main`'s deployments immune.
Measured: with the scope removed, a deployment of `IMPORT prelude` and `sum xs` deploys ("applied") and every call answers 422 `sum is not in scope`; with it, 200.
A file in the bundle with the stdlib module's name still wins, as any project copy does (it is in the in-memory tier), and the service warns.
The CLI's root directory is the entry file's own directory (`jl4-lsp/src/LSP/L4/Oneshot.hs:98-101`), so tiers 2 and 3 coincide for the entry file.
When `JL4_LIBRARY_PATH` is set, tier 4 is removed from the probe list, and the candidate table and the shadow warning are not produced (`Rules.hs:560`), so goldens that pin the variable stay machine-independent.
Parser-hint resolution and type-check resolution share this one code path, so an import cannot parse against one source and type-check against another; each import is therefore resolved, and its Info lines logged, twice in a run, while its Warning lines are announced once.
An embedded winner resolves to `jl4-embedded:/<mod>.l4`, and no VFS write happens (`Rules.hs:594-608`).
`getVirtualFile` falls back to `embeddedLibraryVfs`, so an embedded module is readable from the start of the build and a probe cannot memoise it as missing (smucclaw/l4-ide#906).
The URI is not a `file:` URI, so no speculative in-memory probe can name it.
`main` registered the embedded fallback at `./<mod>.l4` instead, a VFS key, and with the entry file named bare (root `"."`) that key collides: measured on plain `main`, `cd project && l4 run total.l4` for a file that writes `IMPORT prelude` and uses `sum` fails with "I could not find a definition for the identifier `sum`" and exits 1, while `l4 run project/total.l4` works; this PR makes both work.
An embedded importer has no directory (`uriToNormalizedFilePath` is `Nothing`), so its own imports are ranked by the same ladder as everyone else's, and one module name stays bound to one source per build.
Shadow warning: when two or more distinct files exist and at least two contents differ (byte comparison), it lists every distinct copy, marks the winner `[chosen]` and the rest `[shadowed]`, and shows each symlink's real target; identical copies stay silent; each (module, list) pair warns once per session (`Rules.hs:617-638`).
Two tiers that name one file, as the root and importer-relative tiers do from the CLI, are one copy (`distinctCopies`), so the file is not listed as shadowing itself.
Winner logging, only when the variable is unset: Info "Found on filesystem (candidate i of n): <path>[ -> <real path>]" or "Found in embedded libraries (candidate i of n): <mod>", and a Debug candidate table with `(hit)`/`(miss)` per entry (`Rules.hs:560-604`).
Core resolver (API/WASM): `resolved` maps each module name to its type-checked record, and a module met again hands back that record, so a diamond's second sibling sees the shared module's exports (#102, smucclaw/l4-ide#904).
Merging imported environments keeps the first `entityInfo` entry on a key collision; a collision is the same entity reached by two paths, so the values agree.
Build: if the TH splice finds no `prelude.l4` in the Cabal datadir, `./libraries` or `./jl4-core/libraries`, compilation fails (`jl4-core/src/L4/API/EmbeddedLibraries/TH.hs:41-51`).
The embed is read when GHC compiles `L4.API.EmbeddedLibraries`; editing a library alone leaves nothing for Cabal to rebuild, so `cabal build` prints `Up to date` and the binary keeps the old stdlib (measured, `doc/reference/libraries/resolution.md`, "The embed-staleness gotcha").
CI step "The sdist must carry the standard library" (`.github/workflows/pr-checks.yml:174-190`, job `haskell`) fails on a `cabal check` parser warning or an sdist without `libraries/prelude.l4`.

## Diagnostics

- Shadow warning (Warning, printed to stderr by the CLI): "Multiple differing copies of module `<mod>` are visible:", one row per copy, then "The [chosen] copy is used wherever this module is imported. To use a" / "different copy, set JL4_LIBRARY_PATH or place <mod>.l4 in the project root or beside the importing file." (`Rules.hs:632-638`).
- Not found (Warning): "Module not found: <mod>", or "Module not found (JL4_LIBRARY_PATH is set, embedded libs skipped): <mod>", once per (importing module, module name) until the import resolves (`Rules.hs:449-489`).
- Not-found diagnostic, embedded entry (#167): "the stdlib embedded in this binary (skipped: JL4_LIBRARY_PATH is set)", "... (<n> modules, not among them)", or the multi-line "... -- WHICH IS EMPTY." build-defect text (`Rules.hs:437-447`); `EmbedEmpty` cannot occur in an `l4` that compiled, because the splice fails the build first.
- The diagnostic itself reads "I could not find a module with this name: <mod>" / "I have tried the following locations:", then the tried URIs and paths with exact duplicates removed, then the embedded entry last (`Rules.hs:774-787`); `doc/reference/errors/README.md` quotes it.
- Build failure: "L4.API.EmbeddedLibraries: found no standard library to embed.", followed by the three probed paths and the cwd (`EmbeddedLibraries.hs:79-93`).
- Core API: "Module not found: <mod> (searched: embedded libraries, project VFS)" (`Resolution.hs:305`).
- Service: "JL4_LIBRARY_PATH is set and ignored: deployments resolve IMPORTs against their own files and the standard library built into this binary" (`Application.hs:112-115`), "Bundle file stands in for a standard library module" (`Compiler.hs:54-59`), and "Bundle IMPORT resolves to nothing: no bundle file and no built-in standard library module has this name" with the deployment, the file and the module (`Compiler.hs:73-80`).
- `l4/embeddedLibrary`: "Not an embedded library: <uri>" for a URI that is not a `jl4-embedded:` module this binary carries, such as a `file:` URI (`Handlers.hs:820-833`).

## Rulings

Two rulings of 2026-10-12 cover this feature; the source spec records them as its §10, which is on `unstable` and not on `main`, so they are recorded here.

- **The service's ladder.** Ruled 2026-10-12: a deployment resolves its own files and the built-in stdlib, nothing from the host. Its conditions: (1) the service logs a `WARN` naming the deployment and the module whenever a compile or a restart meets an `IMPORT` that resolves to nothing, a warning now and a refusal only by a later ruling, with the deploy API unchanged; (2) `doc/reference/libraries/resolution.md` says the service reads neither `JL4_LIBRARY_PATH`, nor its working directory, nor the XDG store; (3) the PR's Operators section tells an operator to check `/var/lib/jl4-service/.env` and the XDG store for libraries a deployment needs before a host is upgraded. The code comments on `LibraryScope` (`Rules.hs:238-259`) and `bundleScope` (`Backend/Jl4.hs:134-153`) state it.
- **The extension's stdlib.** Ruled 2026-10-12: deployments run on the service's built-in stdlib, and the VS Code extension keeps skipping `jl4-embedded:` imports when it zips a deployment (`sidebar-provider.ts:1277-1285`). A later, non-blocking change would have the extension warn at deploy time when its stdlib differs from the service's, with the service reporting a stdlib hash; that warning is not built.

## Tests and fixtures that pin it

- `jl4-lsp/test/LibraryResolutionSpec.hs`: table-driven `resolveLibrary` cases over environment variable, root, sibling, XDG and symlink sandboxes (#134), two for `EmbeddedStdlibOnly` (it ignores the variable, the root, the sibling and the XDG store; it finds nothing the embed lacks) and three for `distinctCopies` (#630).
- `jl4-lsp/test/EmbeddedLibrarySpec.hs`: `l4/embeddedLibrary` serves exactly the embedded text for every module, refuses a `file:` URI, an unknown module and a path-shaped URI, and speaks `{uri}` to `{text}` (#627).
- `jl4-service/test/UnresolvedImportSpec.hs` (#642): a bundle that imports a module nobody supplies compiles, and the log has exactly one `WARN` naming the deployment, the importing file and the module; with several `IMPORT`s, the missing ones are named and `prelude`, `daydate` and a bundle file are not; loading the deployment from a store through `loadAndRegister`, as a restart does, says it again on its own log; and a bundle whose `IMPORT`s all resolve logs nothing on either path (the positive control). With the call to `logUnresolvedImports` in `compileBundle`, the only one left since #666 deleted the cache rebuild that had the other, made to log nothing, the first three fail and the control passes.
- Black-box, on the built `jl4-service` (2026-10-13): a bundle that imports `zznope` deploys "applied", answers 200 with 42, and logs one `WARN` at the deploy and one after a restart (measured before #666, when a restart read `bundle.cbor`; since, the restart case of `UnresolvedImportSpec` pins it through `loadAndRegister`), each naming `d1`, `main.l4` and `zznope`.
- `jl4-service/test/StdlibResolutionSpec.hs`: with a stray `prelude.l4` in the service's working directory, and with `JL4_LIBRARY_PATH` naming a directory that holds one, a deployment answers 200 from the real stdlib; a bundle's own `prelude.l4` wins and is warned about; a byte-for-byte copy of the stdlib's is not (#630). The first two fail on this PR's first commit with 422, and the warning case with no log line.
- `jl4/tests-cli/Main.hs:1436-1451`: embedded-only diamond (#87), with fixture `jl4/tests-cli/fixtures/embedded-diamond/main.l4`.
- `jl4/tests-cli/Main.hs:1458-1549`: black-box cases for the shadow order and warning, with fixtures `jl4/tests-cli/fixtures/library-shadow/{embedded-wins,sibling-wins,xdg-extra}/` (#134). The poisoned-XDG case asserts the two rows whole, `[chosen]   embedded stdlib` and `[shadowed] XDG data dir`.
- `jl4/tests-cli/Main.hs:1558-1694`: entry-path spelling and embedded importers: a bare entry path (#148) for the project override and for the embedded stdlib; the stdlib's names in scope under a bare entry path (measured failing on `main`); the two embedded-importer cases of #148, adapted (below); one row per copy in the shadow warning; one `Module not found` warning per mistake in stderr, `check --json`, `run --json` and `ast` (#630).
- `jl4-core/test/ImportResolutionSpec.hs:88`: both diamond siblings type-check clean (#102).
- `jl4-lsp/test/HoverDisplaySpec.hs:63-64`: hover shows `a`, never `x10` (#93).
- `ts-apps/vscode/src/unit-tests/embedded-library.test.ts`: the document selector forwards `jl4-embedded:` documents, and the content provider asks for exactly the URI it is given, waits for the client, passes the text through untouched, and names the document when the server errors (#627).
- No golden changed with this PR. The two goldens that #134 re-blessed on unstable, `section-scoping-import-collision` and `set-equals-ambiguous`, are not on `main`.

Run against the `l4` built from plain `main`, eight of the CLI cases fail: the embedded diamond, the poisoned XDG copy, the symlink naming, the differing copies, both embedded-importer cases, one row per copy, and one warning per mistake.

## Adapted from unstable

The two "an embedded library sees the project-local override" cases of #148 assert that `l4 check` exits non-zero on an error inside an imported module, which needs `hasBlockingError` from unstable's #52, not on `main`.
On `main` that error is printed and `l4 check` still exits 0, so here the cases keep their three stderr assertions (the arity error names `actus-schedule`; the shadow warning names `daydate`; `[chosen]   project root`) and drop the exit code.
Measured: they fail against `main`'s `l4`, where the embedded `actus-schedule` keeps the embedded `daydate` and `l4 check` prints no diagnostic, and pass against this PR's.
The fixture-existence pre-check in the suite's `main` (`jl4/tests-cli/Main.hs:447-459`) is not extended for the new fixtures.

## Limits and known defects (verified by reading the code)

- The two resolvers disagree: the ladder puts a project copy above the embedded one, but `apiModuleLookup` tries embedded first (`jl4-core/src/L4/API/VirtualFS.hs:99-101`); this is latent because every non-test caller passes `emptyVFS` (eight sites in `jl4-core/src/L4/API.hs`, and `jl4-wasm/app/QueryPlanWasm.hs:40`).
- That API path also has no filesystem tiers and no shadow warning, and its not-found list is hard-coded (`Resolution.hs:200`).
- Spec §8 acceptance 1 is not met on the CLI: winner lines are Info (`Rules.hs:592`, `:595`) and the CLI drops Info resolution lines, so the chosen copy is shown only when a shadow warning fires; the language server's log has them, because no `l4` command has a verbose mode (`runOneshotVerbose` has no caller).
- The `jl4-service` restart probe from unstable (`etc/probe-service-restart.mjs`, `2e54070e9`) is not in this tree or on `main`; a reader of this branch has to take the script from unstable. It is run as `node etc/probe-service-restart.mjs [--perturb] <jl4-service binary>` and needs `zip`. A reviewer ran it on `0f004353d`, with the script's check that the store holds a `bundle.cbor` (it exits 2 without one) disabled, since #666 keeps none: 5 of 5 identical, the query plan answering 200 on both sides of the restart, and its `--perturb` run, which changes one answer on purpose, failing 1 of 5. Measured on 2026-10-13, before #666, the probe failed on `main` and on this PR alike (200 before a restart, 400 after).
- A bundle that ships its own `prelude.l4` is honoured and warned about; nothing stops it from defining a `sum` of another type, which is the right of a bundle and the reason for the warning.
- The embed-staleness measurement is of a checkout built with `cabal build`; `cabal install` from an sdist and a Nix build were not measured.
- The `ts-apps/vscode` part is checked by its unit tests, the type check and lint, not by opening a tab in VS Code; the claim that a read-only `prelude.l4` tab opens rests on the content provider and the selector, which the unit tests pin.

## Later changes

- #451, a separate change on unstable that is not on `main`, adds `tiersInOrder` and `roundTrippingFileUri` (smucclaw/l4-ide#971), lists the not-found locations in ladder order deduplicated by file, adds the line "Nothing it defines is in scope here; ...", stops an unresolved import from producing the importer's own URI (the source of "Your module depends on itself"), and adds `ImportDiagnosticSpec` and `ImportUriSpec` to `jl4-lsp-test`.
- On unstable the CLI runner `runL4EmbeddedOnly` (added by #87) later moved to a `CliTest/Common.hs`; `main` has no such file, and the runner is in `jl4/tests-cli/Main.hs:208-209`.
