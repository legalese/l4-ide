-- | Recognising and repairing "smart" punctuation — the curly quotes, en/em
-- dashes and ellipsis characters that Word, Pages and Google Docs silently
-- substitute for their plain ASCII lookalikes as you type, and that survive a
-- copy-paste into an L4 source file.
--
-- __Deliberately does not touch the lexer grammar.__ 'TGenitive' (the @\'s@
-- dereference) has no payload and always prints @\'s@ (exactprint), so
-- teaching the lexer to also accept @’s@ would break the
-- @exactprint identity@ law in @jl4\/tests\/Main.hs@ — the file on disk is
-- repaired instead, either by the author's editor (a per-character quick fix)
-- or by the whole-document action ('L4.Lexer.straightenDocument').
--
-- __Why this module does not call the real lexer.__ The natural reading of
-- "the whole-document repair, with the real lexer as oracle" is a single
-- function here that calls 'L4.Lexer.execLexer' in a loop. That would make
-- this module import "L4.Lexer" — and "L4.Lexer" already needs
-- 'lookupConfusable' and 'confusableMessage' from /here/, to word its own
-- lexer diagnostic. Haskell modules cannot import each other, so one of the
-- two directions has to give. This module stays the leaf: it holds the
-- table, the message, the dash heuristic and the NBSP scan — all pure
-- functions of 'Char'\/'Text', none of them naming a lexer type — plus
-- 'straightenWith', a fixed-point engine parameterised over an abstract lex
-- oracle. The concrete, real-lexer-backed 'L4.Lexer.straightenDocument' is
-- built from 'straightenWith' in "L4.Lexer", right next to 'execLexer', and
-- is what callers (the LSP code action, the test suite) actually use.
module L4.SmartPunctuation
  ( -- * The confusables table
    Confusable (..)
  , confusables
  , lookupConfusable
  , confusableMessage
  , codePointText

    -- * The dash heuristic
  , dashReplacementFor
  , applyConfusableAt
  , pairedQuoteCloser
  , applyConfusableFixAt

    -- * Straightening identifiers (the did-you-mean helper)
  , straightenChars

    -- * The whole-document fixed-point engine
  , straightenWith
  , defaultStraightenIterationCap
  , offsetOfSrcPos

    -- * The NBSP lint
  , nbspHitsInToken
  ) where

import Base
import qualified Base.Map as Map
import qualified Base.Text as Text

import Data.Char (ord, toUpper)
import Numeric (showHex)

import L4.Parser.SrcSpan (SrcPos (..), SrcRange (..))

-- ----------------------------------------------------------------------------
-- The confusables table
-- ----------------------------------------------------------------------------

-- | One "smart" character: a glyph that a word processor substitutes for a
-- plain ASCII one, plus what to tell a reader about it and what to replace it
-- with.
data Confusable = MkConfusable
  { glyph          :: !Char
  , unicodeName    :: !Text
    -- ^ e.g. "Right Single Quotation Mark" — the wording rustc and swiftc
    -- both use, so this table's messages read the same way.
  , replacement    :: !Text
    -- ^ The default straightened spelling.
  , altReplacement :: !(Maybe (Text, Text))
    -- ^ Dashes only: an alternative spelling, and the title of the quick fix
    -- that offers it (see 'dashReplacementFor').
  }
  deriving stock (Eq, Show)

confusables :: [Confusable]
confusables =
  [ mk '\x2018' "Left Single Quotation Mark"            "'"   Nothing
  , mk '\x2019' "Right Single Quotation Mark"            "'"   Nothing
  , mk '\x201A' "Single Low-9 Quotation Mark"            "'"   Nothing
  , mk '\x201B' "Single High-Reversed-9 Quotation Mark"  "'"   Nothing
  , mk '\x201C' "Left Double Quotation Mark"             "\""  Nothing
  , mk '\x201D' "Right Double Quotation Mark"            "\""  Nothing
  , mk '\x201E' "Double Low-9 Quotation Mark"            "\""  Nothing
  , mk '\x201F' "Double High-Reversed-9 Quotation Mark"  "\""  Nothing
  , mk '\x2013' "En Dash"                                "-"   (Just ("--", "Replace with `--` (start a comment)"))
  , mk '\x2014' "Em Dash"                                "-"   (Just ("--", "Replace with `--` (start a comment)"))
  , mk '\x2011' "Non-Breaking Hyphen"                    "-"   Nothing
  , mk '\x2026' "Horizontal Ellipsis"                    "..." Nothing
  , mk '\x00A0' "No-Break Space"                         " "   Nothing
  ]
  where
    mk glyph unicodeName replacement altReplacement =
      MkConfusable { glyph, unicodeName, replacement, altReplacement }

-- | 'confusables', indexed by glyph, for O(log n) lookup.
confusableTable :: Map Char Confusable
confusableTable = Map.fromList [ (c.glyph, c) | c <- confusables ]

lookupConfusable :: Char -> Maybe Confusable
lookupConfusable c = Map.lookup c confusableTable

-- ----------------------------------------------------------------------------
-- The message
-- ----------------------------------------------------------------------------

-- | The lexer diagnostic for a confusable character, written for a
-- non-technical first-time reader (doc/STYLE.md): SHOW the glyph itself
-- (the way rustc and swiftc both do — rustc's own wording is "Unicode
-- character '“' (Left Double Quotation Mark) looks like '"' (Quotation
-- Mark), but it is not"), name its code point and Unicode name, the ASCII
-- character it looks like, say plainly that this usually means the text was
-- edited in a word processor, and say what to replace it with. No
-- "expecting" list — that list is for a reader who already knows the
-- grammar, and the whole point here is that they do not need to.
confusableMessage :: Text -> Confusable -> Text
confusableMessage lineBefore c =
  Text.unlines
    [ "This is " <> Text.singleton c.glyph <> " (" <> c.unicodeName <> ", "
        <> codePointText c.glyph <> "). It looks like " <> quoted c.replacement
        <> ", but L4 only understands the plain one."
    , ""
    , "Word processors such as Word, Pages and Google Docs swap plain"
        <> " punctuation for curly lookalikes as you type, so this usually"
        <> " means the text was pasted in from one."
    , ""
    , advice
    ]
  where
    quoted t = "`" <> t <> "`"
    -- A dash leads with whichever spelling 'dashReplacementFor' picks for
    -- this position, so the message agrees with the preferred quick fix and
    -- with the whole-document straighten.
    advice = case c.altReplacement of
      Nothing -> "Replace it with " <> quoted c.replacement <> "."
      Just (alt, _)
        | dashReplacementFor lineBefore c == alt ->
            "Replace it with " <> quoted alt <> " if it starts a comment, as it"
              <> " seems to here; if it was meant as a minus sign, use "
              <> quoted c.replacement <> "."
        | otherwise ->
            "Replace it with " <> quoted c.replacement <> "; if it was meant to"
              <> " start a comment, use " <> quoted alt <> "."

-- | @U+2019@, four hex digits, upper case, as rustc and swiftc both write it.
codePointText :: Char -> Text
codePointText ch =
  "U+" <> Text.justifyRight 4 '0' (Text.pack (map toUpper (showHex (ord ch) "")))

-- ----------------------------------------------------------------------------
-- The dash heuristic
-- ----------------------------------------------------------------------------

-- | Which spelling to use for a confusable in the whole-document straighten
-- pass. Every confusable but the dashes has one answer regardless of
-- context. A dash is ambiguous — Word turns both @ - @ and @ -- @ into
-- @ – @ — so the ruling (2026-09-21) is positional: use the two-hyphen,
-- comment-starting spelling when the dash is the first non-blank character
-- on its line, or is preceded by two or more spaces (comment-shaped);
-- otherwise the single-hyphen arithmetic spelling. The caller supplies the
-- text of the line strictly before the confusable.
dashReplacementFor :: Text -> Confusable -> Text
dashReplacementFor beforeOnLine c = case c.altReplacement of
  Nothing -> c.replacement
  Just (alt, _)
    | isCommentShaped -> alt
    | otherwise        -> c.replacement
  where
    isCommentShaped =
      Text.all (== ' ') beforeOnLine
        || "  " `Text.isSuffixOf` beforeOnLine

-- | Replace ONE confusable character at the given 0-based character offset
-- in @t@, applying 'dashReplacementFor' with the line's own text as context.
applyConfusableAt :: Int -> Confusable -> Text -> Text
applyConfusableAt offset c t =
  before <> repl <> after
  where
    (before, afterWithChar) = Text.splitAt offset t
    after = Text.drop 1 afterWithChar
    lineBefore = Text.takeWhileEnd (/= '\n') before
    repl = dashReplacementFor lineBefore c

-- | The two curly-quote pairs a word processor actually emits (Word, Pages
-- and Google Docs AutoFormat both use this pairing): an OPENING curly quote
-- maps to its matching CLOSING one. Mirrored by
-- 'L4.Lexer.confusableLexError''s @pairedQuoteFix@, which offers the same
-- pairing as a single quick fix — the two are kept in step by both reading
-- this table rather than each keeping their own copy of it.
pairedQuoteCloser :: Char -> Maybe Char
pairedQuoteCloser = \case
  '\x2018' -> Just '\x2019'
  '\x201C' -> Just '\x201D'
  _        -> Nothing

-- | Resolve ONE lexer failure at a confusable character: for an ordinary
-- confusable, 'applyConfusableAt' as above (one replacement). For an
-- OPENING curly quote, first look ahead on the REST OF THE LINE for its
-- matching CLOSING curly quote (via 'pairedQuoteCloser') and, when found,
-- replace BOTH at once.
--
-- __Why this matters, and isn't just a cosmetic pairing.__ Straightening
-- only the opener and leaving the closer curly does not lex clean on the
-- next pass: 'L4.Lexer.stringLiteral' now sees a well-formed OPENING @\"@
-- and reads everything after it — including the still-curly closer, which
-- is an ordinary printable character as far as a string body is concerned
-- — as string content, hunting for a straight @\"@ that is not there. The
-- next failure this produces is nowhere near the actual problem (typically
-- end of file, "unexpected end of input"), which is not a confusable
-- character, so a naive one-character-at-a-time fixed point stops right
-- there with the string still broken. Fixing both quotes in the same step
-- is what keeps the fixed point converging.
--
-- Both replacements are applied at their ORIGINAL offsets in @t@ — safe
-- without re-splitting between them because every curly quote replaces
-- 1-for-1 with its straight spelling (never the dash's two-character
-- alternative), so fixing the opener first cannot shift the closer's
-- offset. Returns how many replacements were made (1, or 2 for a resolved
-- pair) alongside the updated text.
applyConfusableFixAt :: Int -> Confusable -> Text -> (Int, Text)
applyConfusableFixAt offset c t = fromMaybe (1, applyConfusableAt offset c t) $ do
  closeCh <- pairedQuoteCloser c.glyph
  let restOfLine = Text.takeWhile (/= '\n') (Text.drop (offset + 1) t)
  relIdx  <- Text.findIndex (== closeCh) restOfLine
  closeC  <- lookupConfusable closeCh
  let closeOffset = offset + 1 + relIdx
      t1 = applyConfusableAt offset c t        -- same length, closeOffset still valid
      t2 = applyConfusableAt closeOffset closeC t1
  pure (2, t2)

-- ----------------------------------------------------------------------------
-- Straightening identifiers (the did-you-mean helper)
-- ----------------------------------------------------------------------------

-- | Replace every confusable character in @t@ with its ASCII spelling,
-- leaving every other character untouched. Used both directions by the
-- out-of-scope did-you-mean quick fix: the reference may carry a curly
-- character where the declaration has the straight one, or the other way
-- round, and straightening both sides before comparing catches either.
straightenChars :: Text -> Text
straightenChars =
  Text.concatMap (\c -> maybe (Text.singleton c) (.replacement) (lookupConfusable c))

-- ----------------------------------------------------------------------------
-- The whole-document fixed-point engine
-- ----------------------------------------------------------------------------

-- | Generous enough to straighten any real file (the largest corpus modules
-- run to a few hundred lines) many times over, without risking a runaway
-- loop on a pathological input.
defaultStraightenIterationCap :: Int
defaultStraightenIterationCap = 2000

-- | The 0-based character offset in @t@ corresponding to a 1-based
-- (line, column) source position, the convention 'L4.Parser.SrcSpan.SrcPos'
-- uses. Assumes @\\n@-terminated lines, which is what the lexer's own
-- position tracking assumes too.
offsetOfSrcPos :: Text -> SrcPos -> Int
offsetOfSrcPos t pos =
  sum (map lineLen before) + (pos.column - 1)
  where
    before = take (pos.line - 1) (Text.lines t)
    lineLen l = Text.length l + 1

-- | The fixed-point repair loop, parameterised over an abstract lex oracle
-- (so this module never has to import "L4.Lexer" — see the module header):
-- given the CURRENT text, the oracle reports 'Nothing' when it lexes clean,
-- or 'Just' the source position of its first failure.
--
-- Lex; if the failure sits on a confusable character, replace it (the dash
-- heuristic decides which spelling) and lex again; stop when the oracle
-- succeeds, the failure is not a confusable (a genuine, unrelated error —
-- straightening never touches those), or the iteration cap is reached.
-- Returns the number of replacements made and the final text.
straightenWith :: Int -> (Text -> Maybe SrcPos) -> Text -> (Int, Text)
straightenWith cap oracle = go cap 0
  where
    go 0 !n t = (n, t)
    go budget !n t = case oracle t of
      Nothing -> (n, t)
      Just pos ->
        let off = offsetOfSrcPos t pos
        in case Text.uncons (Text.drop off t) of
             Just (ch, _)
               | Just c <- lookupConfusable ch ->
                   let (k, t') = applyConfusableFixAt off c t
                   in go (budget - 1) (n + k) t'
             _ -> (n, t)

-- ----------------------------------------------------------------------------
-- The NBSP lint
-- ----------------------------------------------------------------------------

-- | Positions of a no-break space (U+00A0) within one whitespace token's
-- text, each reported at its OWN length-1 range rather than the whole
-- token's, so a quick fix touches exactly the offending character.
--
-- Takes the token's start position and text rather than a
-- 'L4.Lexer.PosToken' directly, again to keep this module free of any
-- import of "L4.Lexer" (see the module header); the caller — the
-- 'jl4-lsp' rule that already has the token stream — supplies those two
-- fields for every @TSpace@ token.
nbspHitsInToken :: NormalizedUri -> SrcPos -> Text -> [SrcRange]
nbspHitsInToken uri = go
  where
    go pos t = case Text.uncons t of
      Nothing -> []
      Just (ch, rest)
        | ch == '\x00A0' -> MkSrcRange pos (advance pos ch) 1 uri : go (advance pos ch) rest
        | otherwise      -> go (advance pos ch) rest

    advance :: SrcPos -> Char -> SrcPos
    advance pos ch
      | ch == '\n' = MkSrcPos (pos.line + 1) 1
      | otherwise  = MkSrcPos pos.line (pos.column + 1)
