-- | The query syntax of @search_text@, the same as Legalese AI's file search
-- (@ts-shared/legalese-agent/src/search-patterns.ts@):
--
-- * Spaces separate patterns, and a line matches when any pattern does.
--   Spaces inside @()@, @[]@, @{}@, backticks or double quotes don't
--   separate.
-- * Double quotes around a pattern are dropped: @"the greater of"@ is a
--   phrase.
-- * Each pattern is a case-insensitive regular expression. regex-tdfa runs
--   it in linear time, so no pattern can stall the server. Perl's @\\s \\d
--   \\w@ and their negations become POSIX classes, @(?:@ a plain group, and a
--   lazy quantifier the greedy one, which finds the same lines.
-- * A pattern that isn't a valid regular expression is matched as plain
--   text, and the result says so.
module SearchPattern
  ( Pattern (..)
  , splitPatterns
  , compilePatterns
  , matchesAny
  , invalidPatternNote
  , noMatchHint
  , patternSyntax
  , identifierSyntax
  , rulesQuerySyntax
  , toPosix
  ) where

import Data.Char (isSpace)
import Data.List (isPrefixOf)
import Data.Text (Text)
import qualified Data.Text as Text
import Text.Regex.TDFA (CompOption (..), ExecOption (..), defaultCompOpt, defaultExecOpt, matchTest)
import qualified Text.Regex.TDFA.Text as TDFA

-- | One pattern of a query.
data Pattern = Pattern
  { patSource  :: !Text
    -- ^ As written, without surrounding double quotes.
  , patMatches :: Text -> Bool
  , patInvalid :: !(Maybe Text)
    -- ^ Why the pattern isn't a valid regular expression, when it is
    -- matched as plain text.
  }

-- | The syntax, for tool descriptions and empty results.
patternSyntax :: Text
patternSyntax =
  "Each space-separated pattern is a case-insensitive regular expression \
  \(`^ $ . * + ? | ( ) [ ] {n,m}`, `\\s \\d \\w \\b`), and a line matches \
  \if any one does. Spaces inside `()`, `[]`, `{}`, backticks or double \
  \quotes stay in one pattern, and double quotes make a phrase: \
  \`\"the greater of\"`."

-- | How @search_identifier@ reads its argument, and what to use instead.
identifierSyntax :: Text
identifierSyntax =
  "The identifier is one whole L4 name, matched case-sensitively, with or \
  \without backticks: `the greater of`. For part of a name, other \
  \spellings or a pattern, use search_text."

-- | How the WebMCP rule search (@search_rules@) reads its query: words, not
-- patterns, as Legalese AI's own @search_rules@ does.
rulesQuerySyntax :: Text
rulesQuerySyntax =
  "Plain words, case-insensitive. A rule matches if any word does, and \
  \rules matching more words rank first. Punctuation and regex syntax are \
  \ignored: `^(tax|levy)` searches \"tax\" and \"levy\"."

-- | Split a query into patterns at the spaces outside @()@, @[]@, @{}@,
-- backticks and double quotes, and drop double quotes around a pattern. A
-- backslash escapes the next character; inside @[...]@ only @]@ closes.
splitPatterns :: Text -> [Text]
splitPatterns =
  filter (not . Text.null) . map unquote . go [] [] (0 :: Int) False False False . Text.unpack
 where
  -- finished patterns and the current one, both reversed; group depth;
  -- inside a bracket expression, backticks, double quotes
  go acc cur _ _ _ _ [] = reverse (flush cur acc)
  go acc cur d cls bt q ('\\' : c : rest) = go acc (c : '\\' : cur) d cls bt q rest
  go acc cur d True bt q (c : rest) = go acc (c : cur) d (c /= ']') bt q rest
  go acc cur d cls bt q (c : rest)
    | isSpace c && d == 0 && not bt && not q = go (flush cur acc) [] d cls bt q rest
    | c == '`' && not q = go acc (c : cur) d cls (not bt) q rest
    | c == '"' && not bt = go acc (c : cur) d cls bt (not q) rest
    | bt || q = go acc (c : cur) d cls bt q rest
    | c == '[' = go acc (c : cur) d True bt q rest
    | c == '(' || c == '{' = go acc (c : cur) (d + 1) cls bt q rest
    | (c == ')' || c == '}') && d > 0 = go acc (c : cur) (d - 1) cls bt q rest
    | otherwise = go acc (c : cur) d cls bt q rest
  flush [] acc = acc
  flush cur acc = Text.pack (reverse cur) : acc
  unquote t
    | Text.length t >= 2, Text.head t == '"', Text.last t == '"' = Text.init (Text.tail t)
    | otherwise = t

-- | A pattern in the POSIX syntax regex-tdfa reads: Perl's @\\s \\d \\w@
-- (and @\\S \\D \\W@ outside brackets) as classes, @(?:@ as @(@, and a lazy
-- quantifier as the greedy one. Everything else is left as it is.
toPosix :: Text -> Text
toPosix = Text.pack . outside . Text.unpack
 where
  outside [] = []
  outside ('\\' : c : rest)
    | Just cls <- perlClass c = cls ++ outside rest
    | otherwise = '\\' : c : outside rest
  outside ('[' : rest) = '[' : opening rest
  outside ('(' : '?' : ':' : rest) = '(' : outside rest
  outside (q : '?' : rest) | q `elem` ("*+?}" :: String) = q : outside rest
  outside (c : rest) = c : outside rest
  -- a leading ^ negates and a leading ] is literal
  opening ('^' : ']' : rest) = "^]" ++ inside rest
  opening ('^' : rest) = '^' : inside rest
  opening (']' : rest) = ']' : inside rest
  opening rest = inside rest
  inside [] = []
  inside ('\\' : c : rest) | Just set <- perlSet c = set ++ inside rest
  inside (']' : rest) = ']' : outside rest
  inside (c : rest) = c : inside rest
  perlClass c = case c of
    's' -> Just "[[:space:]]"
    'S' -> Just "[^[:space:]]"
    'd' -> Just "[0-9]"
    'D' -> Just "[^0-9]"
    'w' -> Just "[[:alnum:]_]"
    'W' -> Just "[^[:alnum:]_]"
    _ -> Nothing
  perlSet c = case c of
    's' -> Just "[:space:]"
    'd' -> Just "0-9"
    'w' -> Just "[:alnum:]_"
    _ -> Nothing

-- | The query's patterns, compiled. Empty for a blank query.
compilePatterns :: Text -> [Pattern]
compilePatterns = map compileOne . splitPatterns

compileOne :: Text -> Pattern
compileOne src =
  case TDFA.compile compOpt execOpt (toPosix src) of
    Right re -> Pattern src (matchTest re) Nothing
    Left err -> Pattern src plain (Just (shortError err))
 where
  compOpt = defaultCompOpt {caseSensitive = False}
  execOpt = defaultExecOpt {captureGroups = False}
  needle = Text.toLower src
  plain line = needle `Text.isInfixOf` Text.toLower line

-- | regex-tdfa's parse error, cut to what went wrong.
shortError :: String -> Text
shortError err =
  case filter ("unexpected" `isPrefixOf`) (lines err) of
    l : _ -> Text.pack l
    [] -> case filter (not . all isSpace) (drop 1 (lines err)) of
      l : _ -> Text.pack l
      [] -> "not supported"

-- | True when a line matches any pattern.
matchesAny :: [Pattern] -> Text -> Bool
matchesAny pats line = any (\p -> p.patMatches line) pats

-- | One line per pattern matched as plain text, if any was.
invalidPatternNote :: [Pattern] -> Maybe Text
invalidPatternNote pats =
  case [note p reason | p <- pats, Just reason <- [p.patInvalid]] of
    [] -> Nothing
    notes -> Just (Text.intercalate "\n" notes)
 where
  note p reason =
    "Note: \"" <> p.patSource <> "\" is not a valid regular expression ("
      <> reason <> "), so it was matched as plain text."

-- | What to say when a search found nothing. Never repeats the query.
-- @scope@ says where else to look.
noMatchHint :: Text -> Text
noMatchHint scope =
  "No matches. " <> patternSyntax
    <> " To find more: use fewer or shorter patterns, alternatives such as \
       \`(total|sum)`, `\\s` for a space, or " <> scope <> "."
