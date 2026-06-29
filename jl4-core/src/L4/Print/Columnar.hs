-- | Column-aligned \"ditto\" (@^@) grid emitter.
--
-- This is a standalone, AST-agnostic primitive that mirrors the ditto-grid
-- algorithm specified in the @dmnmd@ DMN→L4 backend (BUILD-SPEC §3). It is the
-- reusable building block a future DMN-import-in-IDE feature, or a
-- \"render a decision table back to aligned L4\" feature, would call.
--
-- Ditto is purely an emission-layer, column-positional concern: the lexer
-- ('L4.Lexer') resolves @^@ by /exact start-column match against the previous
-- non-whitespace line/, and a @^@-over-@^@ resolves transitively to the original
-- token. Column alignment is therefore load-bearing — an off-by-one column
-- silently copies the wrong token (or fails to resolve). This module guarantees
-- the lexer's precondition by laying out every cell left-aligned and padded to a
-- per-column width, separated by a fixed gutter, so logical column @j@ begins at
-- the identical absolute column on every line.
--
-- Deliberately NOT an AST node: the parser never produces ditto (it is expanded
-- in the lexer), so a @Ditto@ constructor could never round-trip. Ditto stays a
-- layout concern, kept here in an emission helper.
module L4.Print.Columnar
  ( Cell
  , Grid
  , DittoOpts(..)
  , defaultDittoOpts
  , renderDittoGrid
  ) where

import Data.Char (isSpace, ord)
import Data.Text (Text)
import qualified Data.Text as Text

-- | One logical cell. @Just tok@ is a real, resolvable token (field / operator /
-- value / connector); @Nothing@ is an absent token (a @-@ column, or a row with
-- fewer conjuncts). An absent token is rendered as blanks and is never replaced
-- by a caret — you cannot ditto-copy a token that is not there, and the lexer
-- would fail to find a token at that start column on the previous line.
type Cell = Maybe Text

-- | A grid is a list of rows, each a list of cells. Every row is expected to use
-- the same column layout (so column index = logical slot across all rows);
-- ragged rows are tolerated by right-padding with absent ('Nothing') cells.
type Grid = [[Cell]]

-- | Emission options.
data DittoOpts = DittoOpts
  { gutter      :: Int   -- ^ number of spaces between adjacent columns (>= 0)
  , enableDitto :: Bool  -- ^ when 'False', skip the caret pass entirely and emit
                         --   fully spelled-out, still column-aligned rows (the
                         --   safe \"oracle\" mode for round-trip equivalence)
  }

-- | The ditto-friendly default: single-space gutter, carets enabled.
defaultDittoOpts :: DittoOpts
defaultDittoOpts = DittoOpts { gutter = 1, enableDitto = True }

-- | Render a 'Grid' to column-aligned text implementing BUILD-SPEC §3.
--
-- Rows are joined by newlines. Lines are NOT right-stripped: every line is padded
-- to the same total width so a caller appending a suffix (e.g. @THEN \<result\>@)
-- keeps that suffix column-aligned. Trailing whitespace is layout-inert (the
-- lexer skips it) and acceptable under the spec's semantic-equivalence gate.
--
-- Algorithm:
--
--   1. Normalise rows to a common column count (pad short rows with 'Nothing').
--   2. @colWidth[j]@ = max display length of column @j@ (absent cells count 0).
--   3. Lay out each line left-aligned, padding each cell to @colWidth[j]@ and
--      separating columns by the gutter — guaranteeing identical start columns.
--   4. Ditto pass: for row @i>0@, column @j@, if the cell equals the cell
--      directly above /and/ both are real tokens, emit @^@; if the cell is
--      absent, emit blanks (copy nothing); otherwise emit the token verbatim.
--
-- The comparison is against the previous row's /original/ value (not its rendered
-- @^@), which is exactly what the lexer resolves transitively.
renderDittoGrid :: DittoOpts -> Grid -> Text
renderDittoGrid opts grid =
    Text.intercalate "\n" (zipWith renderRow [0 ..] normRows)
  where
    ncols :: Int
    ncols = maximum (0 : map length grid)

    normRows :: [[Cell]]
    normRows = map (\r -> take ncols (r ++ repeat Nothing)) grid

    cellLen :: Cell -> Int
    cellLen Nothing  = 0
    cellLen (Just t) = displayWidth t   -- lexer columns are DISPLAY width, not code points

    colWidth :: Int -> Int
    colWidth j = maximum (0 : [ cellLen (row !! j) | row <- normRows ])

    gut :: Text
    gut = Text.replicate (max 0 opts.gutter) " "

    pad :: Int -> Text -> Text
    pad w t = t <> Text.replicate (max 0 (w - displayWidth t)) " "

    renderRow :: Int -> [Cell] -> Text
    renderRow i row =
      Text.intercalate gut
        [ pad (colWidth j) (display i j (row !! j)) | j <- [0 .. ncols - 1] ]

    -- The token (or caret, or blank) to show before padding.
    display :: Int -> Int -> Cell -> Text
    display _ _ Nothing = ""
    display i j (Just t)
      | opts.enableDitto
      , i > 0
      , not (Text.any isSpace t)               -- a ^ copies exactly ONE lexical token,
                                               -- so a multi-token cell (e.g. "AT MOST")
                                               -- must be spelled out, never dittoed
      , (normRows !! (i - 1)) !! j == Just t
      = "^"
      | otherwise
      = t

-- | Display width of a token in L4-lexer columns. The lexer advances source
-- columns by DISPLAY width, not code points — verified empirically against the
-- real lexer: @中@ / @가@ / @Ａ@ / @😀@ each advance TWO columns, while ASCII,
-- half-width kana and combining marks advance one (it is not true @wcwidth@:
-- combining marks count 1, and there is no grapheme clustering). Column
-- alignment is load-bearing for @^@ resolution, so the grid MUST measure with
-- this, never 'Text.length'.
--
-- The range table approximates the Unicode East_Asian_Width W/F classes. It is
-- based on dmnmd's @DMN.Translate.L4.displayWidth@ but ADDS the wide-emoji blocks
-- (U+1F300–1F64F, 1F900–1F9FF, 1FA70–1FAFF) that the lexer also treats as width 2
-- and that dmnmd's table currently misses — dmnmd should adopt the same table.
-- Once @l4-lint@ is extracted this becomes the single shared implementation,
-- pinned to the lexer by a golden test.
displayWidth :: Text -> Int
displayWidth = Text.foldl' (\ acc c -> acc + if isWide c then 2 else 1) 0

isWide :: Char -> Bool
isWide c = any (\ (lo, hi) -> n >= lo && n <= hi) wideRanges
  where
    n = ord c
    wideRanges =
      [ (0x1100,  0x115F)   -- Hangul Jamo
      , (0x2329,  0x232A)   -- angle brackets
      , (0x2E80,  0x303E)   -- CJK radicals, Kangxi, CJK symbols/punctuation
      , (0x3041,  0x33FF)   -- Hiragana, Katakana, CJK symbols
      , (0x3400,  0x4DBF)   -- CJK Unified Ideographs Extension A
      , (0x4E00,  0x9FFF)   -- CJK Unified Ideographs
      , (0xA000,  0xA4CF)   -- Yi
      , (0xA960,  0xA97F)   -- Hangul Jamo Extended-A
      , (0xAC00,  0xD7A3)   -- Hangul Syllables
      , (0xF900,  0xFAFF)   -- CJK Compatibility Ideographs
      , (0xFE10,  0xFE19)   -- Vertical forms
      , (0xFE30,  0xFE6F)   -- CJK Compatibility / Small Form Variants
      , (0xFF00,  0xFF60)   -- Fullwidth Forms
      , (0xFFE0,  0xFFE6)   -- Fullwidth signs
      , (0x1B000, 0x1B16F)  -- Kana Supplement / Extended
      , (0x1F200, 0x1F251)  -- Enclosed Ideographic Supplement
      , (0x1F300, 0x1F64F)  -- Misc Symbols & Pictographs, Emoticons (wide emoji)
      , (0x1F900, 0x1F9FF)  -- Supplemental Symbols & Pictographs
      , (0x1FA70, 0x1FAFF)  -- Symbols & Pictographs Extended-A
      , (0x20000, 0x3FFFD)  -- CJK Unified Ideographs Extensions B–G
      ]
