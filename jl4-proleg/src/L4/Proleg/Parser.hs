-- | A small, dependency-free recursive-descent parser for canonical PROLEG.
--
-- Deliberately uses only @base@ + @text@ (a tiny backtracking parser monad over
-- 'String') so the PROLEG front end stays standalone and compiles without the
-- rest of the jl4 build. Covers the canonical dialect from
-- @docs/proleg-concrete-syntax.md@; the Modular-PROLEG/PIL extensions
-- (@#Country@ tags, @negation/1@, @solve/3@ phases) are out of scope.
module L4.Proleg.Parser
  ( parseProgram
  , parseClause
  , ParseError
  ) where

import Control.Applicative (Alternative (..), optional)
import Data.Char (isAlphaNum, isDigit, isLower, isSpace, isUpper)
import Data.Text (Text)
import qualified Data.Text as T

import L4.Proleg.Syntax

-- | A human-readable parse error message.
type ParseError = String

-- | A minimal backtracking parser over the remaining input.
newtype P a = P (String -> Either ParseError (a, String))

-- | Run a parser on its input. (A plain function rather than a record field,
-- since the package uses @NoFieldSelectors@.)
runP :: P a -> String -> Either ParseError (a, String)
runP (P g) = g

instance Functor P where
  fmap f (P g) = P \s -> case g s of
    Left e -> Left e
    Right (a, r) -> Right (f a, r)

instance Applicative P where
  pure x = P \s -> Right (x, s)
  P pf <*> P px = P \s -> case pf s of
    Left e -> Left e
    Right (g, r) -> case px r of
      Left e -> Left e
      Right (a, r2) -> Right (g a, r2)

instance Monad P where
  P px >>= f = P \s -> case px s of
    Left e -> Left e
    Right (a, r) -> runP (f a) r

-- | '<|>' fully backtracks: a failing left alternative discards any progress.
instance Alternative P where
  empty = P \_ -> Left "no parse"
  P a <|> P b = P \s -> case a s of
    Left _ -> b s
    Right ok -> Right ok

-- ---------------------------------------------------------------------------
-- Primitives
-- ---------------------------------------------------------------------------

anyChar :: P Char
anyChar = P \s -> case s of
  [] -> Left "unexpected end of input"
  (c : cs) -> Right (c, cs)

satisfy :: (Char -> Bool) -> P Char
satisfy p = P \s -> case s of
  (c : cs) | p c -> Right (c, cs)
  _ -> Left "unexpected character"

char :: Char -> P Char
char c = satisfy (== c)

string :: String -> P String
string = traverse char

peekC :: P (Maybe Char)
peekC = P \s -> Right (listToHead s, s)
  where
    listToHead [] = Nothing
    listToHead (c : _) = Just c

eof :: P ()
eof = P \s -> case s of
  [] -> Right ((), [])
  _ -> Left "expected end of input"

-- | Skip whitespace, @%@ line comments, and @\/* *\/@ block comments.
ws :: P ()
ws = P \s -> Right ((), go s)
  where
    go ('%' : rest) = go (dropWhile (/= '\n') rest)
    go ('/' : '*' : rest) = go (dropBlock rest)
    go (c : rest) | isSpace c = go rest
    go s' = s'
    dropBlock [] = []
    dropBlock ('*' : '/' : r) = r
    dropBlock (_ : r) = dropBlock r

lexeme :: P a -> P a
lexeme p = p <* ws

symbol :: String -> P String
symbol s = lexeme (string s)

sepBy1 :: P a -> P sep -> P [a]
sepBy1 p sep = (:) <$> p <*> many (sep *> p)

-- ---------------------------------------------------------------------------
-- Terms
-- ---------------------------------------------------------------------------

isIdentChar :: Char -> Bool
isIdentChar c = isAlphaNum c || c == '_'

-- | A primary term (no top-level operators). Consumes trailing layout.
term :: P Term
term = variable <|> integer <|> stringLit <|> listTerm <|> atomOrCompound

variable :: P Term
variable = lexeme do
  c <- satisfy (\ch -> isUpper ch || ch == '_')
  cs <- many (satisfy isIdentChar)
  pure (TVar (T.pack (c : cs)))

integer :: P Term
integer = lexeme do
  sign <- (char '-' >> pure "-") <|> pure ""
  ds <- some (satisfy isDigit)
  pure (TInt (read (sign ++ ds)))

stringLit :: P Term
stringLit = lexeme do
  _ <- char '"'
  cs <- many strChar
  _ <- char '"'
  pure (TStr (T.pack cs))
  where
    strChar = (char '\\' >> anyChar) <|> satisfy (/= '"')

plainAtomName :: P Text
plainAtomName = do
  c <- satisfy isLower
  cs <- many (satisfy isIdentChar)
  pure (T.pack (c : cs))

quotedAtomName :: P Text
quotedAtomName = do
  _ <- char '\''
  cs <- many quotedChar
  _ <- char '\''
  pure (T.pack cs)
  where
    quotedChar =
      (string "''" >> pure '\'')
        <|> (char '\\' >> anyChar)
        <|> satisfy (/= '\'')

-- | An atom, or a compound if @(@ immediately follows the functor (no layout).
atomOrCompound :: P Term
atomOrCompound = do
  name <- plainAtomName <|> quotedAtomName
  margs <- optional do
    _ <- char '(' -- must be adjacent to the functor
    ws
    args <- sepBy1 term (symbol ",")
    _ <- char ')'
    pure args
  ws
  pure case margs of
    Nothing -> TAtom name
    Just args -> TComp name args

listTerm :: P Term
listTerm = do
  _ <- char '['
  ws
  result <-
    (char ']' >> pure (TList [] Nothing))
      <|> do
        xs <- sepBy1 term (symbol ",")
        mtail <- optional (symbol "|" *> term)
        _ <- char ']'
        pure (TList xs mtail)
  ws
  pure result

-- ---------------------------------------------------------------------------
-- Clauses & program
-- ---------------------------------------------------------------------------

-- | A clause terminator: @.@ followed by layout or end of input.
clauseEnd :: P ()
clauseEnd = do
  _ <- char '.'
  mc <- peekC
  case mc of
    Nothing -> pure ()
    Just c | isSpace c -> pure ()
    Just _ -> P \_ -> Left "expected layout after clause-terminating '.'"
  ws

-- | Classify a parsed head + body into a clause by shape (see spec).
classify :: Term -> [Term] -> Clause
classify hd body = case hd of
  TComp "exception" [h, e] | noBody -> CException (Exception h e)
  TComp "allege" [t, p] | noBody -> CProc (Allege t (toParty p))
  TComp "provide_evidence" [t, p] | noBody -> CProc (ProvideEvidence t (toParty p))
  TComp "admission" [t, p] | noBody -> CProc (Admission t (toParty p))
  TComp "plausible" [t] | noBody -> CProc (Plausible t)
  _
    | noBody -> CFact (Fact hd)
    | otherwise -> CRule (Rule hd body)
  where
    noBody = null body

toParty :: Term -> Party
toParty (TAtom "plaintiff") = Plaintiff
toParty (TAtom "defendant") = Defendant
toParty t = PartyTerm t

clause :: P Clause
clause = do
  hd <- term
  body <- (symbol "<=" *> sepBy1 term (symbol ",")) <|> pure []
  clauseEnd
  pure (classify hd body)

program :: P Program
program = do
  ws
  cs <- many clause
  eof
  pure (Program cs)

-- | Parse a whole PROLEG program.
parseProgram :: Text -> Either ParseError Program
parseProgram t = case runP program (T.unpack t) of
  Left e -> Left e
  Right (p, _) -> Right p

-- | Parse a single PROLEG clause.
parseClause :: Text -> Either ParseError Clause
parseClause t = case runP (ws *> clause <* eof) (T.unpack t) of
  Left e -> Left e
  Right (c, _) -> Right c
