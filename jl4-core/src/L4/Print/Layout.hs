-- | The layout behind 'L4.Print.docText': the same output as
-- @layoutPretty (LayoutOptions Unbounded)@, in time linear in the output
-- for a document whose groups all fit (smucclaw/l4-ide#1075).
--
-- See Note [Why L4.Print does not use the library's Unbounded layout].
module L4.Print.Layout (layoutUnboundedLocal) where

import Prettyprinter.Internal (Doc (..), PageWidth (..), SimpleDocStream (..))

{- Note [Why L4.Print does not use the library's Unbounded layout]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
'group' turns a document into a choice between its flattened form (A) and
itself (B). Under an unbounded page, prettyprinter 1.7.1 takes A unless
A's output fails before its first line break ('layoutUnbounded',
Prettyprinter/Internal.hs:1953-1971). A fails only where 'flatten' turned
a 'hardline' into 'Fail': a hardline inside a 'Column', 'Nesting' or
'WithPageWidth' function (so inside 'align', 'hang' and 'indent'), where
'group' cannot see it in advance, or in the flat alternative of a
'flatAlt'.

The library checks A by scanning the laid-out stream of A FOLLOWED BY THE
REST OF THE DOCUMENT, up to the next line break. When the rest of the
line is long, every group on it scans to its end: a residual printed as
one line of 284,667 characters at #1075's WAIT UNTIL 26 spends its time
there, quadratic in the number of groups on the line (measured
2026-11-20: 22 s of mutator time at WAIT UNTIL 30, nearly all of it in
'layoutPretty').

The part after A can never fail, so this layout checks A's own output and
stops at its end. Why the rest cannot fail, given a document built
without an explicit 'Fail':

  * A 'Fail' only ever comes from 'flatten', and 'flatten' only runs
    inside 'group', to build a choice's A ('changesUponFlattening').
  * A contains no line break and no choice. 'changesUponFlattening'
    turns every 'Line' into 'Fail' or a flat alternative, applies
    'flatten' to every function, and keeps only the A of a choice nested
    inside it, which is free of both by the same argument one level
    down. So the library's scan always reaches the end of A, and stops
    early only at a 'Fail' inside A.
  * What follows A is laid out exactly as it would be at top level: each
    choice in it takes its A only when that A does not fail, and its B
    otherwise. A B is the document as written; any 'Fail' in it sits in
    the A of a choice nested inside it, which is resolved the same way,
    so laying out a B never emits one.

So the library's verdict is decided inside A, and this layout reaches the
same one without reading past it. The output is byte-identical, which
@PrintLayoutSpec@ checks against the library on random documents.

The one assumption is "no explicit 'Fail'". It carries weight: a 'Fail'
in the text after a group, chosen by a 'column' function, is what the
library's longer look-ahead would catch and this layout would not (it
would emit the 'Fail', and rendering would stop with an error). The
combinators in "Prettyprinter" never build one, but the constructor is
exported by "Prettyprinter.Internal", "Prettyprinter.Internal.Type" and
their two @Data.Text.Prettyprint.Doc@ aliases, and 'Doc' has a 'Generic'
instance that can build any constructor. Nothing in this repository uses
any of those to build a document (checked 2026-11-20 with
@git grep 'Prettyprinter.Internal\|Data.Text.Prettyprint.Doc'@, which
finds only this module, and no Haskell source names 'flatAlt').

On a document with no end this layout is the more defined of the two:
the library's look-ahead reads on to the next line break and never
returns on a document whose last line is infinite, where this one emits
it as it goes.

The cost that remains: a group whose A fails is laid out again as B,
and each choice inside B is checked in turn, so nested groups that keep
failing cost the size of each one's content, as in the library. A
group whose A fits costs twice the size of A, once to check and once to
emit it.
-}

-- | What remains to lay out: each document with its nesting level, and
-- the annotation pops owed. The library's own pipeline type is not
-- exported, so this mirrors it.
data Pipeline ann
  = Done
  | Item !Int (Doc ann) (Pipeline ann)
  | PopAnn (Pipeline ann)

-- | The same output as @layoutPretty (LayoutOptions Unbounded)@ from
-- prettyprinter 1.7.1, for any document built without an explicit
-- 'Fail', in time proportional to the content each group check reads.
-- See Note [Why L4.Print does not use the library's Unbounded layout].
layoutUnboundedLocal :: Doc ann -> SimpleDocStream ann
layoutUnboundedLocal doc = best 0 (Item 0 doc Done)
  where
    -- The library's 'layoutWadlerLeijen' for 'Unbounded', clause for
    -- clause, without the nesting-level argument that only its fitting
    -- predicate reads, and with 'Union' decided by 'failsAlone'.
    best :: Int -> Pipeline ann -> SimpleDocStream ann
    best !_ Done = SEmpty
    best cc (PopAnn ds) = SAnnPop (best cc ds)
    best cc (Item i d ds) = case d of
      Fail -> SFail
      Empty -> best cc ds
      Char c -> let !cc' = cc + 1 in SChar c (best cc' ds)
      Text l t -> let !cc' = cc + l in SText l t (best cc' ds)
      Line ->
        let x = best i ds
            -- No indentation on a line with no text after it, as the
            -- library does, so no trailing whitespace.
            i' = case x of
              SEmpty -> 0
              SLine {} -> 0
              _ -> i
         in SLine i' x
      FlatAlt x _ -> best cc (Item i x ds)
      Cat x y -> best cc (Item i x (Item i y ds))
      Nest j x -> let !ij = i + j in best cc (Item ij x ds)
      Union x y
        | failsAlone (best cc (Item i x Done)) -> best cc (Item i y ds)
        | otherwise -> best cc (Item i x ds)
      Column f -> best cc (Item i (f cc) ds)
      WithPageWidth f -> best cc (Item i (f Unbounded) ds)
      Nesting f -> best cc (Item i (f i) ds)
      Annotated ann x -> SAnnPush ann (best cc (Item i x (PopAnn ds)))

    -- The library's 'failsOnFirstLine', applied to A's output alone.
    failsAlone :: SimpleDocStream ann -> Bool
    failsAlone = \case
      SFail -> True
      SEmpty -> False
      SLine _ _ -> False
      SChar _ s -> failsAlone s
      SText _ _ s -> failsAlone s
      SAnnPush _ s -> failsAlone s
      SAnnPop s -> failsAlone s
