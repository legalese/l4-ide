# @ref attachment to AST nodes (as built)

As built on `main` by the ref-annotation change.
Source spec: `specs/done/REF-ANNOTATION-SPEC.md`, moved from `specs/todo/` by this change; its status table now reads "Attachment ✅", and its closing "Amendment 2026-10-13" records the rule below.
The change came from `unstable`: #48 (branch `tier2/ref-annotation`, carried in batch #77 as `b6e413accd`), the linear-time fix of #622 (`dcf517ae7`), and the attachment rule of #633 (`565775d26` through `828813085`); this page describes only what `main` has.
Line numbers are in this PR's tree, on `main` at `00298eb60`.

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

- Storage: `Extension.ref :: Refs` (`jl4-core/src/L4/Syntax.hs:428`), a newtype over `[Ref]` whose `Show` prints `Nothing` when empty (`:435-446`); the lens `annRefs` (`:486-492`), the getter `annRef` (`:494-499`), `addRefs` (`:507-509`); `data Ref = MkRef Anno Text`, `getRef` (`:724-729`) and `refCitation`, the citation without its herald and delimiters (`:731-743`).
- Collection, older than the change: `PState.refs` (`jl4-core/src/L4/Parser.hs:73`), `addRef` (`:82-83`), `refP` (`:105-108`).
- Attachment, all in `jl4-core/src/L4/Parser/ResolveAnnotation.hs`: `RefWarning` and `RefS` (`:797-815`), `renderRefWarning` (`:817-824`), the message functions `refWarningMessage`, `refUnattachedMessage`, `refTrailingMessage`, `refNoLocationMessage` and `quotedCitation` (`:826-855`), `addRefCommentsToAst` (`:857-904`), `TrailingRefs` and `trailingRefsOf` (`:906-978`), `preprocessRefs` (`:980-986`), `takeMatchingRefs` (`:988-1008`), `refPrecedesNode` (`:1010-1019`), `attachRef` (`:1021-1031`), `class HasRef` (`:1037-1042`) and its 28 instances (`:1044-1361`).
- Warning constructors on the shared parser `Warning` type: `RefUnattached`, `RefTrailing`, `RefNoLocation` (`ResolveAnnotation.hs:70-79`).
- Wiring: `execParserForTokensWithHints` passes the token stream to `trailingRefsOf` (`Parser.hs:2146`).
- LSP rendering: messages at `jl4-lsp/src/LSP/L4/Rules.hs:843-848`, ranges at `:864-869`.
- The user reference is `doc/reference/syntax/README.md`, section `@ref`; `jl4/GRAMMAR.md` and `jl4/README.md` say the same in short.

## Behaviour and rules (read in code)

Order of passes after parsing: `@nlg`, then `@desc`, then `@ref`; each only adds data to `Anno.extra` and leaves the exact-print tokens alone.
Refs without a source range are set aside as `RefMissingLocation`.
The rest are sorted by the position where they end, and the ones that trail code are left out of the list (see below).
The pass walks the AST in pre-order; the code's comment (`ResolveAnnotation.hs:865-869`) assumes this visits nodes in non-decreasing start position.
At each node it takes every pending ref that ends at or before the node's start (earlier line, or same line and end column at most the start column).
Because the list is sorted by end, those refs are a prefix of it, and `List.span` takes them without looking at the rest (`takeMatchingRefs`, `:988-1008`).
Sorting by start would let a ref that encloses another hide it; none does, since each ref is one lexer token.
The node holds all of them, in source order (`attachRef`).
So a ref is held by the outermost node that starts after it: a ref above a declaration lands on its `TopDecl` wrapper rather than the inner `Decide`, and a ref above a body expression lands on that expression's outermost node.
`Module` and `Section` never claim a ref; they only recurse, so a leading `@ref` reaches the first declaration rather than the module, whose start it shares (the `MkSection` container).
All seven `TopDecl` forms, `Declare`, `Decide`, `Assume`, the directives, `Event`, `Import`, type declarations, fields, signatures, types, names and every expression constructor call `attachRef`.
`Deonton` and `RAction` only pass the ref to their children: the `Regulative` expression that holds a `Deonton` (`Syntax.hs`) starts where it does and has already taken the refs before it.
An infix (mixfix) call has a source range that is its keyword and no more, so an operand to the LEFT of the keyword starts before the call does.
The `App` arm visits those operands first (`ResolveAnnotation.hs:1238-1250`), so a ref inside `(1 + <<cite>> 2) `plus` 3` is held by `2` and not by the whole call.
That is the narrower of two repairs (the other widens the range the parser gives an infix call, as unstable does); it touches only ref attachment, and other nodes whose range is narrower than their children have not been audited.

A ref that trails code is found in the token stream, because by the time a ref is a `Ref` it has a range and no memory of its neighbours (`trailingRefsOf`, `:935-978`).
A line-form `@ref` runs to the end of its line, so any code token before it on that line is enough.
An inline `<<…>>` counts only when no code follows it on the line it ends on.
Whitespace, comments and other annotations are not code, so a ref after another ref, or after a comment, on a line of its own is on a line of its own.
Such a ref is not offered to any node, and the warning names the code before it on its line.

Refs still pending after the walk, such as one after the last node, become `RefNotAttached`, reported in source order with the others.

## Diagnostics

All are warnings from source `parser`, so `l4 check` still succeeds.
The texts are built in one place (`ResolveAnnotation.hs:826-855`), from the citation without its herald, its delimiters, its trailing spaces or a carriage return, and the reference page quotes them:

- "This @ref (`<citation>`) follows code on its line, but a @ref refers to what follows it, so this one is attached to nothing. Put it on the line above `<code>`.", ranged on the ref.
- "This @ref (`<citation>`) is at the end of the file, so there is nothing after it to attach to.", ranged on the ref.
- "This @ref (`<citation>`) has no source location. This might be an internal compiler error.", with no range.

Where they appear (measured with this build on a file with a stack, a trailing ref and an end-of-file ref):

- on standard error for `l4 check`, `l4 run`, `l4 render`, `l4 trace` and `l4 ast`; `l4 ast` also prints the stored refs, so its output is longer;
- in the diagnostics of `l4 check --json` and `l4 run --json`;
- under the name of an imported file when the ref is in that file;
- as warnings in the editor (`jl4-lsp/src/LSP/L4/Rules.hs:843-869`), including on files that already had a ref after code or at the end of the file.

They do not appear in `l4 format`, in `l4 batch` (its output is identical with and without the change) or in the jl4-service responses, and the exit status is unchanged.

## Tests and fixtures that pin it

- `jl4-core/test/RefAnnotationSpec.hs` (22 cases in `jl4-core-test`):
  - the four cases of #48: a ref above a body expression attaches to it; two DECIDEs get their own refs; no ref leaves the body's ref empty; a leading ref attaches to the first declaration and not the module;
  - a node holds every ref before it, in source order, and the nearest is the last;
  - the end-of-file and after-code messages, with a carriage return and an inline citation; a mid-line `<<…>>`; own-line refs across a blank line and a comment; a section heading holding a stack;
  - where a ref lands for an operand, for the left operand of an infix call, a type, a field and a branch;
  - a timing guard that parses 1,000 and 8,000 definitions, each with a ref, and fails if the larger takes more than 16 times as long.
- `jl4/examples/ok/ref-annotation.l4` with its four goldens: refs on two declarations and their body expressions.
  The goldens pin only that the file parses, checks and evaluates (42, TRUE); they do not show where the refs landed.
- `jl4/examples/ok/ref.l4` and `jl4/examples/lsp/semantic-tokens/annotations.l4`, with their goldens, have each ref on the line above what it cites.
- Assumed, not ruled: the timing guard forces the warning count as well as the definitions, so that the whole attachment pass has run when the clock stops.

## Limits and known defects (verified)

- The stored ref is not kept by the service. `Serialise (Anno_ t e)` writes only the unit (`jl4-core/src/L4/Instances/Serialise.hs:22-24`), so a deployment's `bundle.cbor` is the same with and without the change and operators need do nothing, but a service that restarts from its stored bundles has no ref on its syntax tree until the module is compiled again.
- A `<<…>>` in the middle of a line attaches to what follows it, which is not what the ruling covers (see above).
- The spec's first example (`DECIDE` followed by an indented `GIVEN`) fails to parse with "unexpected GIVEN"; that is the example's syntax, not the ref rail.
- `@ref-src` is still lexed (`jl4-core/src/L4/Lexer.hs:75, 386-387, 538`) and consumed with no diagnostic by `refAdditionalP` (`Parser.hs:231-237`, older than the change); a file starting `@ref-src citations.csv` checks and evaluates normally.
  `@ref-map` is consumed the same way by the parser; `L4.Citations` in jl4-core reads it from the token stream instead (`Citations.hs:31-40`).
- Only the infix call is known to have a range narrower than its children; the other nodes have not been audited for it.
- Not on `main`: the `\>` escape inside an inline citation (#418), the exporters and lowerers that read the stored ref, and the later AST nodes that `unstable` adds `HasRef` arms for.
- Cost is linear in the number of refs. `l4 check` user CPU time on a file of N pairs of lines, `@ref https://example.com/s<i>` then `f<i> x MEANS <i>`, with the same file without the `@ref` lines in brackets: N = 1,000 takes 0.17 s (0.16 s), N = 4,000 takes 0.67 s (0.58 s) and N = 16,000 takes 3.07 s (2.75 s), measured 2026-10-13 on this tree. Before #622's fix the same files took 0.19 s (0.12 s), 2.10 s (0.48 s) and 30.4 s (1.96 s), because every node scanned every pending ref.
