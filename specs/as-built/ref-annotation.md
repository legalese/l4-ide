# @ref attachment to AST nodes (as built)

As built on unstable at 73a953821. Line numbers are in this PR's tree (main plus this change) unless marked. Source spec: specs/todo/REF-ANNOTATION-SPEC.md (on unstable it is specs/done/REF-ANNOTATION-SPEC.md; this PR leaves main's copy where it is). Differences from the source spec: its status table still says "Attachment to AST" is TODO; its first example does not parse and its trailing-`@ref` example reads as annotating the declaration it follows, but by the spec's own rule, as in the code, it attaches to the next one; `@ref-src`, marked removed, is still accepted silently; the parser discards `@desc` warnings (`_descS`) where the spec's snippet appends them; the three test files it names do not exist; its line citations are stale except `Lexer.hs:77`.

This PR carries PR #48 (branch `tier2/ref-annotation`, carried in batch #77 as `b6e413accd`, commits `a39475183` and `f2acf5561`).
The `\>` escape inside an inline citation (#418, with #373) is a separate change on unstable, not on main, and is not part of this PR.

## What it does

A `@ref` annotation, in the line form `@ref <text>` or the inline form `<<text>>`, is stored on the AST node that immediately follows it.
Before #48 the parser collected refs into `PState.refs` and attached none of them.
A ref that no node claims becomes a parser warning.
Nothing on main reads the stored ref yet, apart from the new `RefAnnotationSpec`; the code that does read it is on unstable (see "Later changes").

## Where it lives

- Storage: `Extension.ref :: Maybe Ref` (`jl4-core/src/L4/Syntax.hs:427`), lens `annRef` (`:463-464`), setter `setRef` (`:472-473`); `data Ref = MkRef Anno Text` and `getRef` (`:688-693`, older than #48).
- Collection, older than #48: `PState.refs` (`jl4-core/src/L4/Parser.hs:73`), `addRef` (`:82-83`), `refP` (`:105-108`).
- Attachment, all in `jl4-core/src/L4/Parser/ResolveAnnotation.hs`: `RefWarning` and `RefS` (`:782-796`), `renderRefWarning` (`:801-804`), `addRefCommentsToAst` (`:820-833`), `preprocessRefs` (`:835-841`), `takeMatchingRefs` (`:843-848`), `refPrecedesNode` (`:855-862`), `attachRef` (`:868-878`), `class HasRef` (`:888-889`) and its 28 instances (`:891-1197`).
- Warning constructors on the shared parser `Warning` type: `RefUnattached`, `RefNoLocation` (`ResolveAnnotation.hs:62-65`).
- Wiring: `execParserForTokensWithHints`, `Parser.hs:2138-2149`.
  `execParser`, `execParserWithHints`, `execParserForTokens` and `parseFile` gain a `HasRef` constraint (`Parser.hs:2126, 2129, 2135, 2138, 2213`).
- LSP rendering: message at `jl4-lsp/src/LSP/L4/Rules.hs:843-846`, range at `:862-865`.

## Behaviour and rules (read in code)

Order of passes after parsing: `@nlg`, then `@desc`, then `@ref` (`Parser.hs:2144-2146`); each only adds data to `Anno.extra` and leaves the exact-print tokens alone.
Refs without a source range are set aside as `RefMissingLocation`; the rest are sorted by start position.
The pass walks the AST in pre-order; the code's comment (`ResolveAnnotation.hs:812-816`) assumes this visits nodes in non-decreasing start position (not tested here: an application visits its function name before its arguments).
At each node it takes every pending ref that ends at or before the node's start (earlier line, or same line and end column at most the start column).
The nearest of those, by start position, is set on the node's `Anno`; the others become `RefNotAttached` warnings, because an `Anno` holds one `Ref`.
So a ref is claimed by the outermost node that starts after it: a ref above a declaration lands on its `TopDecl` wrapper rather than the inner `Decide`, and a ref above a body expression lands on that expression's outermost node.
`Module` and `Section` never claim a ref; they only recurse, so a leading `@ref` reaches the first declaration rather than the module, whose start it shares.
All seven `TopDecl` forms, `Declare`, `Decide`, `Assume`, the directives, `Event`, `Import`, type declarations, fields, signatures, types, names and every expression constructor call `attachRef`; `Deonton` and `RAction` only pass it to their children (the code's comment at `:1146` says `Deonton` has no source-range handle there).
Refs still pending after the walk, such as one after the last node, become `RefNotAttached`.
The warnings are returned with the `@nlg` warnings through the parser's `[Warning]` result (`Parser.hs:2147, 2149`); `@desc` warnings are discarded (`_descS`).

## Diagnostics

Both are LSP warnings from source `parser` (`Rules.hs:843-846`):

- "@ref `<text>` could not be attached to any following syntax node.", ranged on the ref.
- "@ref `<text>` has no source location. This might be an internal compiler error.", with no range.

`<text>` is `getRef`'s payload, which keeps the herald, so the message doubles it: measured, `@ref ../docs/regulation-summary.md` as the last thing in a file yields "@ref `@ref ../docs/regulation-summary.md` could not be attached to any following syntax node."

## Tests and fixtures that pin it

- `jl4-core/test/RefAnnotationSpec.hs:61-115` (in `jl4-core-test`), four cases from #48: a ref above a body expression attaches to it; two DECIDEs get their own refs; no ref leaves the body's ref empty; a leading ref attaches to the first declaration and not the module.
  The file ends at `:115`; the escape tests that follow it on unstable (#415, #418) are not on main.
- `jl4/examples/ok/ref-annotation.l4` with its four goldens: refs on two declarations and their body expressions.
  The goldens pin only that the file parses, checks and evaluates (42, TRUE); they do not show where the refs landed.

## Limits and known defects (verified)

Probed 2026-10-12 with the `l4` built from this PR's tree.

- A trailing ref belongs to what follows, not to what precedes: in `DECIDE foo IS TRUE @ref a.pdf` followed by `DECIDE bar …`, the ref draws no warning, and `l4 ast` shows it on the `Decide` wrapper of `bar`; the same ref at the end of the file warns.
- The spec's first example (`DECIDE` followed by an indented `GIVEN`) fails to parse with "unexpected GIVEN"; that is the example's syntax, not the ref rail.
- `@ref-src` is still lexed (`jl4-core/src/L4/Lexer.hs:75, 387, 538`) and consumed with no diagnostic by `refAdditionalP` (`Parser.hs:231-237`, older than #48); a file starting `@ref-src citations.csv` checks and evaluates normally.
  `@ref-map` is consumed the same way by the parser; `L4.Citations` in jl4-core reads it from the token stream instead (`Citations.hs:31-40`).
- Cost grows faster than the file: `attachRef` calls `takeMatchingRefs` once per node, and that scans every ref still pending (`ResolveAnnotation.hs:843-848, 868-878`).
  Measured, `l4 check` CPU time on a file of N pairs of lines, `@ref https://example.com/s<i>` then `f<i> x MEANS <i>`, against the same file without the `@ref` lines: N = 1,000 takes 0.19 s (0.12 s without); N = 4,000 takes 2.10 s (0.48 s); N = 16,000 takes 30.4 s (1.96 s).
  Linear would multiply the time by 4 at each step; with refs it is multiplied by 11 and then 14.5, without them by 4.0 and 4.1.
  A file with a few hundred refs is unaffected; thousands of refs in one file are not.
- The user reference (`doc/reference/syntax/README.md:78-84`, `:352-355`) shows the inline `<<…>>` form and does not say which node a ref attaches to.

## Later changes (all on unstable, none on main)

- #92: `TYPICALLY` fields threaded through the `Assume`, `TypedName` and `OptionallyTypedName` instances.
- #128: a fixity pass runs between the `@desc` and `@ref` passes, and `Warning` gains fixity constructors.
- #333: `HasRef (Section n)` visits the section `GIVEN` before the declarations.
- Every later AST node adds its own `HasRef` arm; #360's regulative nodes `Join`, `Deadline`, `Opening`, `Filter`, `Anchor` and `Subject` only pass the ref to their children, as `Deonton` and `RAction` do here.
- Readers of the stored ref, none of them in #48: the deprecated-`ASSUME` warning in the type checker (#358), which asks whether a declaration is annotated, and the Relational, YScript, Catala, docassemble and DMN lowerings.
- #418: `refP` decodes `\>` and `\\` in the stored text while the tokens stay verbatim.
