-- | SMT-LIB2 text for @l4 prove@ (VERIFICATION-BACKEND-LOWERING-SPEC R-V6).
--
-- Plain s-expressions, a printer and a reader, and nothing that knows about a
-- particular solver: R-V6 asks for portable text, with no z3-specific options
-- or tactics, so that cvc5 is a free second opinion on any @unsat@, and for an
-- emitter narrow enough that an @sbv@ backend is a swap of one module (D3).
--
-- __Identifiers.__ Every symbol that comes from an L4 name is a quoted symbol
-- with a namespace prefix ('userSymbol'). Quoting alone is not enough: in
-- SMT-LIB @|pi|@ and @pi@ are the same symbol, and Z3 5.1.0 rejects a user
-- declaration that clashes with a built-in name such as @pi@. A prefix that no
-- theory symbol starts with is what makes the clash impossible.
module L4.Prove.Smt
  ( SExpr (..)
  , renderSExpr
  , renderScript
  , userSymbol
  , realLit
  , readRational
  , parseSExprs
  , CheckSat (..)
  , readCheckSat
  ) where

import Base
import qualified Data.Char as Char
import Data.Ratio (denominator, numerator, (%))
import qualified Data.Text as Text

-- | An s-expression. An 'Atom' is printed exactly as it is held, so a quoted
-- symbol keeps its bars.
data SExpr
  = Atom !Text
  | SList ![SExpr]
  deriving stock (Eq, Ord, Show, Generic)

renderSExpr :: SExpr -> Text
renderSExpr = \case
  Atom t  -> t
  SList xs -> "(" <> Text.unwords (map renderSExpr xs) <> ")"

-- | One command per line.
renderScript :: [SExpr] -> Text
renderScript = Text.unlines . map renderSExpr

-- | A quoted symbol for an L4 name: @|<prefix><name>|@.
--
-- The two characters a quoted symbol cannot hold, @|@ and @\\@, become @_@.
userSymbol :: Text -> Text -> Text
userSymbol prefix name =
  "|" <> prefix <> Text.map (\c -> if c == '|' || c == '\\' then '_' else c) name <> "|"

-- | A rational as an SMT-LIB @Real@ term: @3.0@, @(/ 1.0 3.0)@, @(- 2.0)@.
realLit :: Rational -> SExpr
realLit r
  | r < 0     = SList [Atom "-", realLit (negate r)]
  | denominator r == 1 = Atom (dec (numerator r))
  | otherwise = SList [Atom "/", Atom (dec (numerator r)), Atom (dec (denominator r))]
 where
  dec n = Text.pack (show n) <> ".0"

-- | Read a model value of sort @Real@ back. Accepts what solvers print for a
-- rational: a numeral, a decimal, @(- x)@ and @(/ x y)@. Anything else (an
-- algebraic number from non-linear arithmetic, say) is 'Nothing', and the
-- caller must say so rather than guess.
readRational :: SExpr -> Maybe Rational
readRational = \case
  Atom t -> readDecimal t
  SList [Atom "-", x] -> negate <$> readRational x
  SList [Atom "/", x, y] -> do
    a <- readRational x
    b <- readRational y
    if b == 0 then Nothing else Just (a / b)
  _ -> Nothing
 where
  readDecimal t = case Text.splitOn "." t of
    [i] | isDigits i -> Just (fromInteger (read (Text.unpack i)))
    [i, f] | isDigits i, Text.all Char.isDigit f ->
      Just (fromInteger (read (Text.unpack i))
            + (if Text.null f then 0 else read (Text.unpack f) % (10 ^ Text.length f)))
    _ -> Nothing
  isDigits s = not (Text.null s) && Text.all Char.isDigit s

-- | Parse a solver's whole output into its top-level s-expressions.
parseSExprs :: Text -> Either Text [SExpr]
parseSExprs = go []
 where
  go acc s = case Text.uncons (skip s) of
    Nothing -> Right (reverse acc)
    Just _  -> do
      (e, rest) <- one (skip s)
      go (e : acc) rest

  skip s =
    let s' = Text.dropWhile Char.isSpace s
    in if ";" `Text.isPrefixOf` s'
         then skip (Text.dropWhile (/= '\n') s')
         else s'

  one s = case Text.uncons s of
    Just ('(', rest) -> list [] rest
    Just (')', _)    -> Left "unexpected ')'"
    Just ('|', rest) ->
      let (body, rest') = Text.breakOn "|" rest
      in if Text.null rest'
           then Left "unterminated quoted symbol"
           else Right (Atom ("|" <> body <> "|"), Text.drop 1 rest')
    Just ('"', rest) -> stringLit "" rest
    Just _ ->
      let (tok, rest) = Text.break (\c -> Char.isSpace c || c == '(' || c == ')') s
      in Right (Atom tok, rest)
    Nothing -> Left "unexpected end of input"

  list acc s = case Text.uncons (skip s) of
    Just (')', rest) -> Right (SList (reverse acc), rest)
    Just _ -> do
      (e, rest) <- one (skip s)
      list (e : acc) rest
    Nothing -> Left "unterminated list"

  -- SMT-LIB escapes a double quote inside a string literal by doubling it.
  stringLit acc s =
    let (body, rest) = Text.breakOn "\"" s
    in case Text.uncons (Text.drop 1 rest) of
         _ | Text.null rest -> Left "unterminated string literal"
         Just ('"', rest') -> stringLit (acc <> body <> "\"") rest'
         _ -> Right (Atom ("\"" <> acc <> body <> "\""), Text.drop 1 rest)

-- | The answer to a @(check-sat)@.
data CheckSat = CsSat | CsUnsat | CsUnknown
  deriving stock (Eq, Show)

readCheckSat :: SExpr -> Maybe CheckSat
readCheckSat = \case
  Atom "sat"     -> Just CsSat
  Atom "unsat"   -> Just CsUnsat
  Atom "unknown" -> Just CsUnknown
  _              -> Nothing
