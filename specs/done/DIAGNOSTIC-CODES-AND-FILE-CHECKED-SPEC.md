# Diagnostic Codes and l4/fileChecked

**Status:** Done.

Two gaps between `jl4-lsp` and the tools that drive it, the Legalese AI harness above all.

## l4/fileChecked

### Problem

`updateFileDiagnostics` publishes only when a file's diagnostics changed, and through a debouncer that waits 100 ms when the list is empty. So a client cannot tell "nothing changed" from "still compiling". One client waited out a 20 second timeout on that, and VS Code used a fixed 400 ms delay and sometimes read stale results.

### Behaviour

After every `didOpen`, `didChange` and `didSave` of a document, once its checking and evaluation have finished, the server sends:

```json
{
  "method": "l4/fileChecked",
  "params": {
    "uri": "file:///project/rules.l4",
    "version": 7,
    "diagnostics": []
  }
}
```

- It is sent whatever the check found: when nothing changed, when the text is identical, when the file does not parse or type-check.
- `uri` is the URI the client sent. For an importer (below) it is the URI as `textDocument/publishDiagnostics` gives it.
- `version` is the version the check covered, read from the diagnostic store with the diagnostics. It is `null` only if the store has no version for the file.
- `diagnostics` is the full list for the file, from every source, in the shape and order of a publish, so a client need not wait for the debounced publish.
- If `l4/directiveResultsUpdated` is sent for the same check, it comes first. It is not sent for a file that fails to type-check.

### Versions and bursts of edits

An edit cancels the check in progress, and every notification still pending then reports the check that finishes next. So:

- a version that was superseded may never be reported;
- a burst of edits may report its last version several times;
- versions for one file never go backwards, and a reported version matches what was checked, but see the known limits below.

To wait for an edit, wait for `version >= sent`.

### Importers

`kick` already re-checks every open file on every session, so the published diagnostics of an importer did follow an edit to a module it imports. What did not follow was any notification: no directive results, and so no signal that the file was checked again.

After reporting the edited document, the server now finds the open files that reach it through `IMPORT`, directly or not, and reports each of them the same way: directive results, then `l4/fileChecked`. Their `version` is their own, unchanged.

### Rules that outlive their session

Cancelling a session does not always stop all of its rules. Under load, a rule was still running when the next session started, though nothing waited for it. Its result came from the old document, but hls-graph stored it as built in the new session, and it was reported under the new version. After a burst of edits the server could show the diagnostics of an old version as those of the last one, until the next edit. This was in the published diagnostics as well, and is one way a client read stale results. With `l4/fileChecked` it showed as `version: 20` with the results of version 16, in 21 of 1,162 stress runs with 16 servers running at once.

The cause is in hls-graph, which is a dependency, so the fix is at the point where a rule's result is committed, in `defineEarlyCutoff'`:

- `sessionGeneration` moves at the start of a restart, and again when `newSession` swaps the VFS. It is odd in between, when nothing may be stored.
- `stillInSession` abandons a rule whose session has ended, before it writes diagnostics and in the transaction that stores its result. The key stays unfinished, so the session computes it again.
- A verdict that a rule's dependencies are unchanged may come from the session before, so a stored result of another file version is recomputed, not replayed.

The check runs in the transaction that writes the diagnostics, and in the one that stores the result. Checked before a separate write, a rule could be held up between the two and overwrite what the new session wrote, and since a write of another version replaces everything stored for the file, nothing would put it right.

`shakeRestart` marks what changed before the new VFS can be read, and passes the session no keys, so a restart walks the keys once. The walk is on the path the reactor waits on: a server that dirties every key, because its client does not watch files, does a full pass there.

### Known limits

- **The stored version check covers one file.** A verdict from the old session that a rule's dependencies are unchanged, about a dependency in another file, can still be accepted: the rule's own file has not moved, so nothing tells. Closing this needs a change in hls-graph.
- **The root cause is not fixed.** It is likely in hls-graph's `cleanupAsync`, which cancels one snapshot of the list of asyncs, so one added after that is not cancelled. This was not proved. Everything above works around it where results are committed.
- **Reports are not coalesced.** Each edit in a burst sends its own reports, per file and per importer, with no merging by URI.
- **A timeout is still needed.** A client should keep one behind `version >= sent`, for the limits above and for an `#EVAL` that never finishes, which sends nothing until the next edit.

### Rings of imports

With two files of a ring open, the server used to hang: it reported nothing for them, on any edit, and no `l4/fileChecked` could be sent. hls-graph stops a key that waits on itself in one chain of calls, but not two threads that enter a ring at different files, and the server runs several at once. A service that checks a whole bundle at once does the same.

No rule follows an import that leads back to its file any more (`importsThatDoNotLeadBack`), so a ring of imports never becomes a ring of keys. A file on a ring, or a file that imports itself, has no typecheck: `CheckModule` returns no result, with the error on the `IMPORT` in words (`import/cycle`, `import/self-import`). Every consumer takes the branch it has for a file that does not parse. It must not get a result with the import left out: a name from that module would read as undefined, and `jl4-service` takes an undefined name in an `@export` for an input the caller supplies, so the deployment would serve a wrong schema.

A file that only imports a ring is checked without it, as a file that imports a broken module is, and the `import/cycle` on its `IMPORT` blocks it. The engine's `StackException` is gone, with the rule-name message that came with it. `isBlockingDiagnostic` goes by the code `import/module-has-errors` now, not the source `import`, since a ring is reported from that source too. `unresolvedImports` tells a self-import from an `IMPORT` that found nothing by its edge in `GetImportEdges`.

### Not noticed

An edit to a file that is not open and only changed on disk is still not noticed: the server has no `workspace/didChangeWatchedFiles` handler. A client has to keep such files open.

### Implementation

- `LSP.L4.Inspector`: `FileCheckedMethodName`, `FileCheckedParams`.
- `LSP.L4.Handlers`: `scheduleFileChecked` replaces `scheduleDirectiveResultsNotification`.
- `LSP.Core.Shake`: `getFileDiagnostics` reads one file's diagnostics and version together.
- `LSP.L4.Rules`: `importClosure`, moved here from `LSP.L4.BlockingErrors` so that rules can use it, and `importsThatDoNotLeadBack` and `onImportRing` over it.

Everything for one file happens inside one `Action`: waiting for `EvaluateLazy`, sending directive results, reading the store, and sending `l4/fileChecked`. A session cannot start while an action of the session before it runs, so the store cannot yet hold anything of a newer version. Reading it after `runAction` returned could pair a newer version with a partial list. An action interrupted by a restart runs again in the next session, which is why a client may hear of a version twice but always hears.

Exceptions other than cancellation on the way to the directive results are caught and logged, so that they cannot cost the client its `l4/fileChecked`. Directive results are rendered inside the action, not when the message is encoded, for the same reason.

## Diagnostic codes

### Problem

Every diagnostic had `code = null`, so tooling had to match on message text.

### Behaviour

Every diagnostic has a stable string `code`, and a `codeDescription` with this `href`, from one formula with no per-code table:

```text
https://legalese.com/l4/reference/errors#<code with / replaced by ->
```

[`jl4-lsp/DIAGNOSTIC-CODES.md`](../../jl4-lsp/DIAGNOSTIC-CODES.md) lists them all, with what a code promises and how to read one from the CLI.

- Type errors: `checkErrorCode`, in `L4.TypeCheck.Types`, is an exhaustive match with no wildcard, so a new `CheckError` stops the build until it has a code. Checker warnings are `lint/` codes.
- Parse errors: `parseErrorCode`, in `L4.Lexer`, reads Megaparsec's structured error and never the rendered text. `ErrorIndentation` gives `parse/indentation`. An unexpected token gives `parse/unexpected-<kind>`, where `tokenKindSlug` is exhaustive over `TokenType`: a keyword is its own kind, and everything else is a fixed word, so no identifier or literal can reach a code. A `Label`, an `ErrorFail` message and every lexer error about a character give `parse/syntax-error`.
- Evaluation: `evalDirectiveCode` and `evalExceptionCode`. An `#ASSERT` that raises has the code of what it raised, since that is neither a pass nor a failed verdict.
- Annotations: `annotationWarningCode`.
- Imports, files and internal errors: set where each diagnostic is built.

CLI output prints the code on its `Code:` line, which printed `<none>` before.

### Not covered

- The web editor's `L4.API.l4Check` builds its own JSON, not an LSP diagnostic, and carries no codes.
- The custom messages of the parser, such as the clause written like a mixfix rule, are `parse/syntax-error`. Giving them a code of their own needs them to be structured errors first.

## Testing

- `jl4-lsp/test/DiagnosticCodesSpec.hs` runs the real rules over small sources for each kind of diagnostic, checks that every diagnostic has a code and the link the formula gives, that a code never contains what the user wrote, and that `DIAGNOSTIC-CODES.md` matches the source.
- `jl4-lsp/test/FileCheckedSpec.hs` starts a real `jl4-lsp` and speaks the protocol over stdio.
- `jl4-service/test/ImportRingSpec.hs` and `jl4/tests-cli/Main.hs` check that a ring and a self-import are refused by the compile path of the service, by `l4 batch` and by `jl4-schema`.
- The goldens of `jl4/examples/not-ok/` show each code on its `Code:` line.
