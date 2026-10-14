# @ref attachment to AST nodes (as built)

As built on `main` by the ref-annotation change.
Source spec: `specs/done/REF-ANNOTATION-SPEC.md`, moved from `specs/todo/` by this change; its status table now reads "Attachment ✅", and its closing "Amendment 2026-10-13" records the rule below.
The change came from `unstable`: #48 (branch `tier2/ref-annotation`, carried in batch #77 as `b6e413accd`), the linear-time fix of #622 (`dcf517ae7`), and the attachment rule of #633 (`565775d26` through `828813085`); this page describes only what `main` has.
Line numbers are in this PR's tree, on `main` at `c6532c1d7`.

Differences from the source spec: its first example does not parse; its trailing-`@ref` example (`DECIDE foo IS TRUE @ref legal-opinion.pdf`) showed a ref after code, which under the rule below is attached to nothing, so this change moves it to the line above; `@ref-src`, marked removed, is still accepted silently; the parser discards `@desc` warnings (`_descS`) where the spec's snippet appends them; the three test files it names do not exist; its line citations were stale.

**Ruled 2026-10-12:** a `@ref` written after code on its line attaches to nothing and warns; in a stack, exporters show the nearest ref.

## What it does

A `@ref` annotation, in the line form `@ref <text>` or the inline form `<<text>>`, is held by the node that starts after it: a rule, a type, a section heading, an input, a field, a branch, an expression.
A node holds every ref between it and the node before it, in source order, so a stack of refs above a rule is kept whole.
`annRefs` reads them all and `annRef` reads the nearest, the last, which is the one a reader that shows one citation per node should use.

A ref written after code on its line, with nothing after it there, is held by no node and warns: it cannot cite the code it trails, because a ref refers to what follows it, and it is not given to the next construct either, whose citation it would silently become.
A ref with nothing after it at all, at the end of the file, warns with its own message.
A `<<…>>` in the middle of a line keeps attaching to what follows it (assumed, not ruled: the ruling is about a ref at the end of a code line).

Nothing else on `main` reads the stored ref: `l4 ast` prints it, the type checker and the exporters on `main` do not use it, and the link an editor shows on hover comes from the citation token (`jl4-core/src/L4/Citations.hs`), not from the syntax tree.

## Where it lives

- Storage: `Extension.ref :: Refs` (`jl4-core/src/L4/Syntax.hs:579`), a newtype over `[Ref]` whose `Show` prints `Nothing` when empty (`:589-605`); the lens `annRefs` (`:641-647`), the getter `annRef` (`:649-654`), `addRefs` (`:662-664`); `data Ref = MkRef Anno Text`, `getRef` (`:891-896`) and `refCitation`, the citation without its herald and delimiters (`:898-910`).
- Collection, older than the change: `PState.refs` (`jl4-core/src/L4/Parser.hs:80`), `addRef` (`:89-90`), `refP` (`:112-115`).
- Attachment, all in `jl4-core/src/L4/Parser/ResolveAnnotation.hs`: `RefWarning` and `RefS` (`:936-954`), `renderRefWarning` (`:956-963`), the message functions `refWarningMessage`, `refUnattachedMessage`, `refTrailingMessage`, `refNoLocationMessage` and `quotedCitation` (`:965-994`), `addRefCommentsToAst` (`:996-1043`), `TrailingRefs` and `trailingRefsOf` (`:1045-1117`), `preprocessRefs` (`:1119-1125`), `takeMatchingRefs` (`:1127-1147`), `refPrecedesNode` (`:1149-1158`), `attachRef` (`:1160-1170`), `class HasRef` (`:1176-1181`) and its 28 instances (`:1183-1520`).
- Warning constructors on the shared parser `Warning` type: `RefUnattached`, `RefTrailing`, `RefNoLocation` (`ResolveAnnotation.hs:71-80`).
- Wiring: `execParserForTokensWithHints` passes the token stream to `trailingRefsOf` (`Parser.hs:2810`).
- LSP rendering: messages at `jl4-lsp/src/LSP/L4/Rules.hs:843-848`, ranges at `:864-869`.
- The user reference is `doc/reference/syntax/README.md`, section `@ref`; `jl4/GRAMMAR.md` and `jl4/README.md` say the same in short.

## Behaviour and rules (read in code)

Order of passes after parsing: `@nlg`, then `@desc`, then `@ref`; each only adds data to `Anno.extra` and leaves the exact-print tokens alone.
Refs without a source range are set aside as `RefMissingLocation`.
The rest are sorted by the position where they end, and the ones that trail code are left out of the list (see below).
The pass walks the AST in pre-order; the code's comment (`ResolveAnnotation.hs:1004-1008`) assumes this visits nodes in non-decreasing start position.
At each node it takes every pending ref that ends at or before the node's start (earlier line, or same line and end column at most the start column).
Because the list is sorted by end, those refs are a prefix of it, and `List.span` takes them without looking at the rest (`takeMatchingRefs`, `:1127-1147`).
Sorting by start would let a ref that encloses another hide it; none does, since each ref is one lexer token.
The node holds all of them, in source order (`attachRef`).
So a ref is held by the outermost node that starts after it: a ref above a declaration lands on its `TopDecl` wrapper rather than the inner `Decide`, and a ref above a body expression lands on that expression's outermost node.
`Module` and `Section` never claim a ref; they only recurse, so a leading `@ref` reaches the first declaration rather than the module, whose start it shares (the `MkSection` container).
All seven `TopDecl` forms, `Declare`, `Decide`, `Assume`, the directives, `Event`, `Import`, type declarations, fields, signatures, types, names and every expression constructor call `attachRef`.
`Deonton` only passes the ref to its children: the `Regulative` expression that holds a `Deonton` (`Syntax.hs`) starts where it does and has already taken the refs before it.
`RAction` passes them to its children as well, but that reason does not cover it: a ref between the party and `MUST`, `MAY` or `SHANT` is not taken by anything before the action, so the action's expression holds it and the action does not (measured with `l4 ast`: `PARTY S`, then a `@ref`, then `MUST delivery` puts the ref on `delivery`).
In the same way a ref just inside a parenthesis before `PARTY` is held by the party expression and not by the nested obligation, while a ref directly above `PARTY` is held by the `Regulative`.
Whether those two should land on the action and on the obligation is not decided here; `unstable` has the same instances.
An infix (mixfix) call has a source range that is its keyword and no more, so an operand to the LEFT of the keyword starts before the call does.
The `App` arm first lets the call claim the refs that end before its first left operand starts, because the call starts where that operand does: a ref above `(1 + 2) `plus` 3` is held by the call.
It then visits the operands (`ResolveAnnotation.hs:1382-1400`), so a ref inside `(1 + <<cite>> 2) `plus` 3` is held by `2` and not by the whole call.
That is the narrower of two repairs (the other widens the range the parser gives an infix call, as unstable does); it touches only ref attachment, and other nodes whose range is narrower than their children have not been audited.
A rule written as clauses is compiled to one definition: a CONSIDER on the first clause, inside a `LET` whose local definition holds the clauses after it.
That local definition is generated and marked (`annPmSynthetic`), and its range is the next clause's body, which the checker needs to tell functions apart.
The `LET` binds the later clauses in its declarations and the first clause in its body, so the usual order, declarations before body, would meet the later clauses first.
The `LetIn` arm therefore visits the body first when `bindsLaterClauses` holds, as the `@nlg` and `@desc` passes do (`ResolveAnnotation.hs:1430-1443`), and the `Decide` arm does not let a marked definition claim refs (`:1217-1228`), because its range would otherwise reach every ref still pending before the next clause's body.
So a ref inside the first clause, or above a later one, is held by the first node written after it, and never by a generated one: in the test's rule, the refs above the rule, inside the first clause, above the second and above the third land on lines 4, 4, 6 and 8.

A ref that trails code is found in the token stream, because by the time a ref is a `Ref` it has a range and no memory of its neighbours (`trailingRefsOf`, `:1074-1117`).
A line-form `@ref` runs to the end of its line, so any code token before it on that line is enough.
An inline `<<…>>` counts only when no code follows it on the line it ends on.
Whitespace, comments and other annotations are not code, so a ref after another ref, or after a comment, on a line of its own is on a line of its own.
Such a ref is not offered to any node, and the warning names the code before it on its line.

Refs still pending after the walk, such as one after the last node, become `RefNotAttached`, reported in source order with the others.

## Diagnostics

All are warnings from source `parser`, so `l4 check` still succeeds.
The texts are built in one place (`ResolveAnnotation.hs:965-994`), from the citation without its herald, its delimiters, its trailing spaces or a carriage return, and the reference page quotes them:

- "This @ref (`<citation>`) follows code on its line, but a @ref refers to what follows it, so this one is attached to nothing. Put it on the line above `<code>`.", ranged on the ref.
- "This @ref (`<citation>`) is at the end of the file, so there is nothing after it to attach to.", ranged on the ref.
- "This @ref (`<citation>`) has no source location. This might be an internal compiler error.", with no range.

Where they appear (measured with this build on a file with a stack, a trailing ref and an end-of-file ref):

- on standard error for `l4 check`, `l4 run`, `l4 render`, `l4 trace` and `l4 ast`; `l4 ast` also prints the stored refs, so its output is longer;
- in the diagnostics of `l4 check --json` and `l4 run --json`;
- under the name of an imported file when the ref is in that file;
- as warnings in the editor (`jl4-lsp/src/LSP/L4/Rules.hs:843-869`), including on files that already had a ref after code or at the end of the file.
  The browser-based editor built from the WebAssembly target shows neither new warning: its check (`l4Check`) discards the parser's warnings, the `@nlg` ones included (`jl4-core/src/L4/Import/Resolution.hs:202` and `:287`).

They do not appear in `l4 format`, in `l4 batch` (its output is identical with and without the change) or in the jl4-service responses, and the exit status is unchanged.

## Tests and fixtures that pin it

- `jl4-core/test/RefAnnotationSpec.hs` (27 cases in `jl4-core-test`):
  - the four cases of #48: a ref above a body expression attaches to it; two DECIDEs get their own refs; no ref leaves the body's ref empty; a leading ref attaches to the first declaration and not the module;
  - a node holds every ref before it, in source order, and the nearest is the last;
  - the end-of-file and after-code messages, with a carriage return and an inline citation; a mid-line `<<…>>`; own-line refs across a blank line and a comment; a section heading holding a stack;
  - where a ref lands for an operand, for the left operand of an infix call, a type, a field and a branch, and in a rule written as clauses (below);
  - a timing guard that parses 1,000 and 8,000 definitions, each with a ref, and fails if the larger takes more than 30 times as long (linear is 8; the quadratic scan took 44 to 45). It does not depend on the clock's resolution: it parses the small file over and over until the stretch spans half a second, which is 32 steps of a 15.625 ms clock such as Windows' (so one step of error is a thirty-second of the reading), and measures the small file again with each retry. The search for such a stretch gives up after 4 s of wall-clock time or 4,096 parses, and the test is then pending, not failed.
    Three more cases pin that: a linear parse is judged linear on a clock that reads in 15.625 ms steps, a made-up quadratic parse is still failed on that clock, and a clock that never ticks gives no ratio within seconds, so the guard goes pending.
- `jl4/tests-cli/Main.hs` (one case under `l4 check`) with `jl4/tests-cli/fixtures/ref-trailing.l4`: a ref after code and a ref at the end of the file give the two warnings, with their text and ranges as the editor renders them, and the check still exits 0.
  `unstable` has no such case; it is added here because the text and ranges in `jl4-lsp/src/LSP/L4/Rules.hs:843-869` were otherwise covered by no test.
- `jl4/examples/ok/ref-annotation.l4` with its four goldens: refs on two declarations and their body expressions.
  The goldens pin only that the file parses, checks and evaluates (42, TRUE); they do not show where the refs landed.
- `jl4/examples/ok/ref.l4` and `jl4/examples/lsp/semantic-tokens/annotations.l4`, with their goldens, have each ref on the line above what it cites.
- Assumed, not ruled: the timing guard forces the warning count as well as the definitions, so that the whole attachment pass has run when the clock stops.

## Limits and known defects (verified)

- The stored ref is not kept by the service. `Serialise Anno` (`jl4-core/src/L4/Syntax.hs:1099-1111`) keeps only `pmSynthetic`, the mark on the nodes a multi-clause rule is compiled to, and none of the other fields, so a deployment's `bundle.cbor` is the same with and without the change and operators need do nothing, but a service that restarts from its stored bundles has no ref on its syntax tree until the module is compiled again.
- A `<<…>>` in the middle of a line attaches to what follows it, which is not what the ruling covers (see above).
- The spec's first example (`DECIDE` followed by an indented `GIVEN`) fails to parse with "unexpected GIVEN"; that is the example's syntax, not the ref rail.
- `@ref-src` is still lexed (`jl4-core/src/L4/Lexer.hs:75, 386-387, 538`) and consumed with no diagnostic by `refAdditionalP` (`Parser.hs:238-244`, older than the change); a file starting `@ref-src citations.csv` checks and evaluates normally.
  `@ref-map` is consumed the same way by the parser; `L4.Citations` in jl4-core reads it from the token stream instead (`Citations.hs:31-40`).
- Only the infix call is known to have a range narrower than its children; the other nodes have not been audited for it.
- Not on `main`: the `\>` escape inside an inline citation (#418), the exporters and lowerers that read the stored ref, and the later AST nodes that `unstable` adds `HasRef` arms for.
- Cost is linear in the number of refs. `l4 check` user CPU time on a file of N pairs of lines, `@ref https://example.com/s<i>` then `f<i> x MEANS <i>`, with the same file without the `@ref` lines in brackets: N = 1,000 takes 0.17 s (0.16 s), N = 4,000 takes 0.67 s (0.58 s) and N = 16,000 takes 3.07 s (2.75 s), measured 2026-10-13 on this tree. Before #622's fix the same files took 0.19 s (0.12 s), 2.10 s (0.48 s) and 30.4 s (1.96 s), because every node scanned every pending ref.
