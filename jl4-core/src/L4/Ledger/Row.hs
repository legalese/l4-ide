-- | The instance ledger's row, and the pure arithmetic around it
-- (OPERATIONAL-LOWERING-SPEC §3.1, §3.4): the row type, how a row's two
-- times are set, and a row as one line of a @#TRACE@ and back.
--
-- A row is the persisted form of one line of the instance's @#TRACE@, and
-- the instance's rows in 'seqNo' order /are/ that @#TRACE@. There are three
-- kinds of line, and so three kinds of row:
--
-- * the opening, @#TRACE c AT t WITH@: row 1 of every instance, written when
--   the instance is created. The dinner fixture opens the arrangement in its
--   own text (@COMMIT `dinner status record` IS opened@ before the first
--   act), not by an act, so the trace header is the only line the opening
--   can be;
-- * an act, @PARTY p DOES a AT t@;
-- * a tick, @(`WAIT UNTIL` t)@: the clock passing a deadline with nothing
--   done, which has no party.
--
-- Nothing here evaluates L4. "L4.Ledger.Replay" turns rows into a module and
-- runs it; this module only says what a row is and how it is spelled.
module L4.Ledger.Row
  ( -- * Rows
    SeqNo
  , InstanceKey (..)
  , RowEvent (..)
  , RowVerdict (..)
  , Row (..)
  , rowEventAt
  , withVerdict
    -- * The two times of a row (§3.4)
  , nextTxTime
  , clampReported
    -- * A row as a @#TRACE@ line, and back
  , canonicalExpr
  , eventLine
  , parseEventLine
  , traceBlock
  , renderStamp
  , parseStamp
  ) where

import Base
import qualified Base.Text as Text
import Data.Char (isDigit, isSpace)
import Data.Ratio (denominator, numerator, (%))

-- | A row's position in its instance: 1 is the opening.
type SeqNo = Int

-- | Which instance a row belongs to. The deployment is part of the key
-- because the service's routes are per deployment (§3.1, skeptic O5): an
-- instance keyed without it could be replayed against another contract.
data InstanceKey = MkInstanceKey
  { deployment   :: !Text
  , instanceName :: !Text
  }
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass NFData

-- | What a row records. The texts are L4 source, in the form
-- 'canonicalExpr' gives them.
data RowEvent
  = OpeningEvent !Text
    -- ^ the contract expression the instance runs, as the @#TRACE@ names it
  | ActEvent !Text !Text
    -- ^ the party, and the action, as @PARTY party DOES action@ spells them
  | TickEvent
    -- ^ the clock passed a deadline with nothing done
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | What the evaluator said of the row's event when it was appended
-- (R-O2: every event that evaluates is appended, with its verdict). An
-- event the evaluator could not decide is never a row.
data RowVerdict
  = VDischarging
    -- ^ the contract ended fulfilled
  | VBreaching !(Maybe Text)
    -- ^ the contract ended in breach; the party blamed, when one is
  | VAdvancing
    -- ^ the contract moved to another position
  | VPassedOver !Text
    -- ^ no obligation took the event; why, in the what-if's words
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | One row of an instance ledger (§3.1). The instance it belongs to is the
-- store's key, not a field.
data Row = MkRow
  { seqNo          :: !SeqNo
  , event          :: !RowEvent
  , at             :: !Rational
    -- ^ the event's contract time: the @AT@ of its @#TRACE@ line
  , txTime         :: !Rational
    -- ^ the ledger's clock when the row was appended; never decreases
  , verdict        :: !RowVerdict
  , decidedAgainst :: !(Maybe SeqNo)
    -- ^ the head the proposer saw: provenance, not the guard (R-O4)
  , idempotencyKey :: !(Maybe Text)
    -- ^ the proposer's retry key; openings and ticks have none
  , ruleVersion    :: !Text
    -- ^ the deployment version the row was appended under
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | The row as a @#TRACE@ line's two parts.
rowEventAt :: Row -> (RowEvent, Rational)
rowEventAt r = (r.event, r.at)

-- | The same row with another verdict.
withVerdict :: RowVerdict -> Row -> Row
withVerdict v r = r {verdict = v}

----------------------------------------------------------------------------
-- Times
----------------------------------------------------------------------------

-- | The next row's transaction time: the ledger's clock, or the previous
-- row's transaction time if the clock has stepped back (§3.4). The
-- evaluator re-sorts a trace by @AT@, so a clock that stepped back would
-- reorder the replay against the ledger, with no error (skeptic O1).
nextTxTime :: Maybe Rational -> Rational -> Rational
nextTxTime previous now = maybe now (max now) previous

-- | The contract time of an act a party reports having done in the world:
-- the time claimed, clamped to @[previous row's at, txTime]@ (§3.4, R-O1).
-- A report can never be placed before what the ledger already holds, nor
-- after the moment it is recorded.
clampReported :: Rational -> Rational -> Rational -> Rational
clampReported previousAt tx claimed = max previousAt (min tx claimed)

----------------------------------------------------------------------------
-- Lines
----------------------------------------------------------------------------

-- | One top-level segment of a line: its text, and where it starts and ends.
data Segment = MkSegment
  { segText  :: !Text
  , segStart :: !Int
  , segEnd   :: !Int
  }

-- | Split L4 source into its top-level segments: runs separated by
-- whitespace outside any parenthesis, backtick name or string. The splits a
-- line needs are made only between top-level segments, so a @DOES@ or an
-- @AT@ inside a name, a string or a parenthesis is never taken for the
-- keyword.
--
-- Refused, because each would make the generated line say something other
-- than the row: a line break or tab (a second line of the @#TRACE@); a
-- comment opener, @--@ or @{-@, or closer, @-}@ (the rest of the line would
-- vanish); a @^@ (L4's ditto, which copies a token from the line above, and
-- resolves silently when it resolves to the wrong one); an unbalanced
-- parenthesis; an unterminated name or string.
segments :: Text -> Either Text [Segment]
segments src = go 0 (0 :: Int) Nothing [] (Text.unpack src)
  where
    go _ depth current acc [] = case current of
      _ | depth /= 0 -> Left "a parenthesis is not closed"
      Nothing -> Right (reverse acc)
      Just s  -> Right (reverse (close s (Text.length src) : acc))
    go i depth current acc (c : rest)
      | c == '\n' || c == '\r' || c == '\t' = Left "the text holds a line break or a tab"
      | c == '^' = Left "the text holds a ^, which L4 reads as a ditto of the line above"
      | c == '-', ('-' : _) <- rest = Left "the text holds --, which starts a comment"
      | c == '{', ('-' : _) <- rest = Left "the text holds {-, which starts a comment"
      | c == '-', ('}' : _) <- rest = Left "the text holds -}, which ends a comment"
      | c == '`' = quoted '`' i depth current acc rest
      | c == '"' = quoted '"' i depth current acc rest
      | c == '(' = go (i + 1) (depth + 1) (Just (fromMaybe i current)) acc rest
      | c == ')' = if depth == 0
          then Left "a parenthesis is closed that was never opened"
          else go (i + 1) (depth - 1) (Just (fromMaybe i current)) acc rest
      | isSpace c, depth == 0 = case current of
          Nothing -> go (i + 1) depth Nothing acc rest
          Just s  -> go (i + 1) depth Nothing (close s i : acc) rest
      | otherwise = go (i + 1) depth (Just (fromMaybe i current)) acc rest
    -- a backtick name or a string: runs to its closing delimiter; a string
    -- may escape its quote with a backslash
    quoted delim i depth current acc rest =
      case scan (i + 1) rest of
        Nothing -> Left (if delim == '`' then "a backtick name is not closed" else "a string is not closed")
        Just (j, rest') -> go j depth (Just (fromMaybe i current)) acc rest'
      where
        scan _ [] = Nothing
        scan j ('\\' : _ : more) | delim == '"' = scan (j + 2) more
        scan j (x : more)
          | x == delim = Just (j + 1, more)
          | x == '\n' || x == '\r' = Nothing
          | otherwise = scan (j + 1) more
    close s e = MkSegment {segText = slice s e, segStart = s, segEnd = e}
    slice s e = Text.take (e - s) (Text.drop s src)

-- | The form a party, an action or a contract expression is stored in: the
-- text trimmed, and wrapped in one pair of parentheses when it is more than
-- one top-level segment, so that it is one operand wherever a line puts it.
-- Idempotent. 'Left' says why the text cannot stand in a line at all.
canonicalExpr :: Text -> Either Text Text
canonicalExpr raw = do
  let t = Text.strip raw
  segs <- segments t
  case segs of
    []  -> Left "the text is empty"
    [_] -> Right t
    _   -> Right ("(" <> t <> ")")

-- | The row's event as a @#TRACE@ line, without indentation.
eventLine :: RowEvent -> Rational -> Either Text Text
eventLine ev t = do
  stamp <- renderStamp t
  case ev of
    OpeningEvent c -> do
      c' <- canonicalExpr c
      pure ("#TRACE " <> c' <> " AT " <> stamp <> " WITH")
    ActEvent p a -> do
      p' <- canonicalExpr p
      a' <- canonicalExpr a
      pure ("PARTY " <> p' <> " DOES " <> a' <> " AT " <> stamp)
    TickEvent -> pure ("(`WAIT UNTIL` " <> stamp <> ")")

-- | A @#TRACE@ line read back as a row's event and time: the inverse of
-- 'eventLine' on canonical texts, and a reader of the hand-written forms
-- the corpus uses (an unparenthesised action, a bare @`WAIT UNTIL` t@).
-- The texts come back canonical.
parseEventLine :: Text -> Either Text (RowEvent, Rational)
parseEventLine line = do
  segs <- segments (Text.strip line)
  let src = Text.strip line
      word s = s.segText
      between a b = Text.strip (Text.take (b - a) (Text.drop a src))
  case segs of
    (h : rest)
      | word h == "#TRACE" -> case reverse rest of
          (w : s : a : revContract@(_ : _))
            | word w == "WITH", word a == "AT" -> do
                let cs = reverse revContract
                t <- parseStamp (word s)
                c <- canonicalExpr (between (head1 cs).segStart (last1 cs).segEnd)
                pure (OpeningEvent c, t)
          _ -> Left "an opening line reads #TRACE contract AT time WITH"
      | word h == "PARTY" -> case break ((== "DOES") . word) rest of
          (ps@(_ : _), _ : afterDoes) -> case reverse afterDoes of
            (s : a : revAction@(_ : _)) | word a == "AT" -> do
              let as = reverse revAction
              t <- parseStamp (word s)
              p <- canonicalExpr (between (head1 ps).segStart (last1 ps).segEnd)
              act <- canonicalExpr (between (head1 as).segStart (last1 as).segEnd)
              pure (ActEvent p act, t)
            _ -> Left "an act line ends AT time"
          _ -> Left "an act line reads PARTY party DOES action AT time"
    [w, s] | word w == "`WAIT UNTIL`" -> (TickEvent,) <$> parseStamp (word s)
    [g] | Just inner <- Text.stripPrefix "(" (word g) >>= Text.stripSuffix ")" ->
      case parseEventLine inner of
        Right (TickEvent, t) -> Right (TickEvent, t)
        _ -> Left "a parenthesised line is a tick, (`WAIT UNTIL` time)"
    _ -> Left "a #TRACE line is an opening, an act or a tick"
  where
    head1 xs = case xs of (x : _) -> x; [] -> MkSegment "" 0 0
    last1 xs = head1 (reverse xs)

-- | The whole @#TRACE@ directive for a sequence of rows' events: the first
-- must be the opening, and no other may be. Each event line is indented
-- four spaces under the header, as the corpus writes them.
traceBlock :: [(RowEvent, Rational)] -> Either Text Text
traceBlock = \ case
  ((o@(OpeningEvent _), t) : evs) -> do
    header <- eventLine o t
    ls <- for evs \ (ev, s) -> case ev of
      OpeningEvent _ -> Left "an instance has one opening, and it is row 1"
      _ -> ("    " <>) <$> eventLine ev s
    pure (Text.unlines (header : ls))
  _ -> Left "row 1 of an instance is its opening"

-- | A time as an L4 numeric literal: an exact decimal, with no exponent.
-- 'Left' for a negative time, and for one with no finite decimal (a third),
-- which no literal spells exactly.
renderStamp :: Rational -> Either Text Text
renderStamp r
  | r < 0 = Left "a time on the contract clock is never negative"
  | otherwise = case decimalPlaces (denominator r) of
      Nothing -> Left ("the time " <> Text.pack (show r) <> " has no exact decimal form")
      Just k ->
        let scaled = numerator r * (10 ^ k) `div` denominator r
            digits = Text.pack (show scaled)
            padded = Text.replicate (k + 1 - Text.length digits) "0" <> digits
            (whole, frac) = Text.splitAt (Text.length padded - k) padded
        in Right (if k == 0 then whole else whole <> "." <> frac)
  where
    -- the decimal places a denominator needs: the larger of its powers of 2 and 5
    decimalPlaces d = strip 0 0 d
    strip :: Int -> Int -> Integer -> Maybe Int
    strip twos fives d
      | d == 1 = Just (max twos fives)
      | d `mod` 2 == 0 = strip (twos + 1) fives (d `div` 2)
      | d `mod` 5 == 0 = strip twos (fives + 1) (d `div` 5)
      | otherwise = Nothing

-- | An L4 numeric literal as a time: digits, perhaps a point and more
-- digits. The inverse of 'renderStamp'.
parseStamp :: Text -> Either Text Rational
parseStamp t = case Text.splitOn "." t of
  [whole] | digitsOnly whole -> Right (fromInteger (read (Text.unpack whole)))
  [whole, frac] | digitsOnly whole, digitsOnly frac ->
    Right (read (Text.unpack whole) % 1 + read (Text.unpack frac) % (10 ^ Text.length frac))
  _ -> Left ("the time " <> t <> " is not a numeric literal")
  where
    digitsOnly s = not (Text.null s) && Text.all isDigit s
