-- | What the type checker says about a module's cycles (smucclaw/l4-ide#1075):
-- the warnings, the note each @\@ends-because@ leaves, and the words they are
-- made of.
--
-- The cycles are found and judged in "L4.Cycles", which imports the checker's
-- types; the checker's types import this module, so what a warning carries,
-- and the vocabulary it needs ('Doubt', 'Stall', 'Multiplication'), lives
-- here, below both.
--
-- Which cycle draws which warning is 'L4.Cycles.alarms'; which warnings an
-- @\@ends-because@ silences, and where it must be written to do so, is
-- 'L4.Cycles.cycleNotices'. The rulings behind both are recorded in
-- @specs\/todo\/GLOBAL-DEPENDENCY-GRAPH-SPEC.md@, "Cycles of rules: rulings
-- L3, L4 and the scope ruling": recursion-limit rulings L3 and L4, and
-- the scope ruling (ii).
module L4.Cycles.Warning
  ( -- * What a warning carries
    CycleWarning (..)
  , CycleTrouble (..)
    -- * What a mark's note carries
  , MarkNote (..)
  , MarkOutcome (..)
  , Ending (..)
    -- * Why a cycle is not shown to end
  , Doubt (..)
  , Stall (..)
    -- * What multiplies
  , Multiplication (..)
  , Continuation (..)
    -- * The text
  , cycleWarningText
  , cycleNoteText
  ) where

import Base
import qualified Base.Text as Text
import Data.Ratio (denominator, numerator)

import L4.Parser.SrcSpan (SrcRange)
import L4.Syntax (DeonticModal (..))

-- | One warning about one cycle, or about one @\@ends-because@ that is on no
-- cycle.
data CycleWarning = MkCycleWarning
  { rule    :: Text
    -- ^ the definition it is shown on and names: for "could not check" and
    -- "no time", the cycle's first in source order (decided by Claude
    -- 2026-11-22, pending Meng's review: ruling L4 says only "the definition the warning is reported on"); for
    -- "multiplies", the one whose continuation multiplies; for a stray mark,
    -- the one the mark is above
  , at      :: Maybe SrcRange
    -- ^ where: that definition's name; the continuation that multiplies; the
    -- mark, for a stray mark
  , through :: [Text]
    -- ^ the cycle's other definitions, in source order
  , trouble :: CycleTrouble
  , marks   :: [(Text, Text)]
    -- ^ the @\@ends-because@ marks on the cycle's definitions, each with its
    -- reason, in source order
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass NFData

data CycleTrouble
  = CouldNotCheckThat Doubt
    -- ^ an obligation cycle not shown to end
  | GivesNoTime [Rational]
    -- ^ an obligation cycle with a lap that passes only deadlines that give no
    -- time: each one's distance after the arming, never above 0
  | StartsCopies Multiplication
    -- ^ a continuation that starts two or more copies of the cycle at once
  | NothingToExplain
    -- ^ an @\@ends-because@ above a definition that is on no cycle (decided by Claude
    -- 2026-11-22, pending Meng's review)
  deriving stock (Eq, Generic, Show)
  deriving anyclass NFData

-- | The note one @\@ends-because@ leaves, at the mark, carrying its reason:
-- ruling L4's "each use emits one information-level message carrying its
-- reason", read as every mark the checker accepts. This follows the printed
-- condition literally ('each use emits one information-level message'). The
-- narrow reading is the alternative, for Meng's review: a note only for a
-- mark that silences a warning. A mark
-- the checker refuses (no reason, or not above a definition) is an error and
-- leaves no note; nor does any mark in a module that does not check.
data MarkNote = MkMarkNote
  { rule    :: Text
    -- ^ the definition the mark is above
  , at      :: Maybe SrcRange
    -- ^ the mark
  , reason  :: Text
  , outcome :: MarkOutcome
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass NFData

-- | What the mark did.
data MarkOutcome
  = Silenced [Text] Doubt
    -- ^ it is on the definition a "could not check" is reported on, and
    -- silences it: the cycle's other definitions, in source order, and why
    -- it could not be checked
  | NotWhereReported Text Bool
    -- ^ it is on a cycle whose "could not check" is reported on that other
    -- definition, so it silences nothing; 'True' when that definition's own
    -- mark silences the warning, so that it is not shown
  | CannotSilence [Text]
    -- ^ it is on a cycle whose only warnings, shown on those definitions, are
    -- ones a mark does not silence ("no time", "multiplies")
  | NotChecked
    -- ^ it is on a cycle with no HENCE or LEST on it, which draws no warning
    -- (the scope ruling (ii))
  | ShownToEnd Ending
    -- ^ it is on a cycle whose HENCE or LEST leads back, shown to end, and how
  | OnNoCycle
    -- ^ its definition is on no cycle the checker can see
  deriving stock (Eq, Generic, Show)
  deriving anyclass NFData

-- | How a cycle shown to end comes to an end, in words a reader can check.
data Ending
  = WaitsForTime
    -- ^ every lap waits, for an event or for time to pass ('WaitsEachLap')
  | InputGetsSmaller
    -- ^ an input gets smaller every lap, towards a stop ('Structural',
    -- 'Countdown')
  deriving stock (Eq, Generic, Show)
  deriving anyclass NFData

data Doubt
  = NoMeasure [Text]
    -- ^ self-recursion, and neither function check applies: the members whose
    -- direct uses of themselves neither check proves, never empty. A cycle's
    -- warning is shown on its first member, which need not be one of them.
  | Mutual
    -- ^ definitions that call each other with no continuation between: v1
    -- does not try
  | Stalled [Stall]
    -- ^ some lap passes only continuations that need not wait; these are why
  | Untraced
    -- ^ a member uses a function no edge follows (Note [What the graph
    -- cannot see] in "L4.Cycles"), so the cycle the graph shows may not be
    -- the only one
  deriving stock (Eq, Generic, Show)
  deriving anyclass NFData

-- | Why a continuation on a lap cannot be shown to wait.
data Stall
  = NotAfterArming Rational
    -- ^ the deadline falls this long after the arming, which is not after it:
    -- @WITHIN 0@ or less, an @AFTER@ below 0 beside a bare @WITHIN@, or @OF
    -- THE DEADLINE@ of such a deadline. It does not move
  | WithinNotLiteral
    -- ^ a @WITHIN@ that is not a number written out: it may shrink (a Zeno
    -- chain) or be zero
  | AnchoredAtInstant
    -- ^ @WITHIN d OF e@: counted from a fixed instant, so already past once
    -- the trace has passed it
  | AnchoredAtJoin
    -- ^ @WITHIN d OF THE JOIN@: not shown either way
  | AnchoredAtDeadline
    -- ^ @OF THE DEADLINE@ where the obligation that will hand this one on is
    -- not the one written around it: the deadline is the hand-off's, read
    -- when it hands on (see Note [What makes a lap wait] in "L4.Cycles")
  | OpensNotLiteral
    -- ^ @AFTER@ a date, or a number not written out, beside a bare @WITHIN@:
    -- the window may open at a fixed instant
  | OpensAtInstant
    -- ^ @AFTER d OF e@ beside a bare @WITHIN@: the window opens at a fixed
    -- instant, so the deadline is fixed too
  | OpensAtJoin
    -- ^ @AFTER d OF THE JOIN@ beside a bare @WITHIN@: not shown either way
  | BeforeDate
    -- ^ @BEFORE date@: an instant, already past once the trace has passed it
  | RecordHence
    -- ^ a @RECORD@'s @HENCE@ runs at once
  | BarrierMayBeEmpty
    -- ^ an @EVERY … ONCE ALL HAVE@ @HENCE@ whose roll is not shown to have a
    -- member: a list written out (or a name for one) holding a member built
    -- by the cast's constructor, with no @WHO@ or @WHOSE@ filter. Over an
    -- empty roll it runs at once
  | OwnTrace
    -- ^ the module may run a contract inside an @EVALTRACE@, which runs it on
    -- a trace of its own from that trace's start: no wait, on either trace,
    -- bounds how deep the runs nest (Note [What makes a lap wait] in
    -- "L4.Cycles")
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass NFData

-- | A @HENCE@, @LEST@ or @RECORD … HENCE@ whose expression joins two or more
-- direct calls of the cycle's members with @RAND@ or @ROR@.
data Multiplication = MkMultiplication
  { rule      :: Text
    -- ^ the member whose body holds the continuation
  , at        :: Maybe SrcRange
    -- ^ the continuation's expression
  , operator  :: Text
    -- ^ @RAND@, @ROR@, or @RAND and ROR@
  , copies    :: Int
    -- ^ how many calls of members the expression joins
  , via       :: Continuation
  , stepsDown :: Maybe (Text, Rational)
    -- ^ when every copy is the rule itself, passed one parameter less a
    -- number written out: that parameter and the number. As written, not a
    -- proof that the parameter reaches a stop
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass NFData

-- | Which continuation, with the modal of the obligation it belongs to.
data Continuation = HenceOf DeonticModal | LestOf DeonticModal | AfterRecord
  deriving stock (Eq, Generic, Show)
  deriving anyclass NFData

------------------------------------------------------------------------
-- The text
------------------------------------------------------------------------

-- | The warning, a line per element. Written for a reader who has never met
-- the words cycle or recursion (@doc\/STYLE.md@): a rule that "starts itself
-- again". It names no limit or flag of a run-time stop: ruling L2's counts are
-- not on this branch.
cycleWarningText :: CycleWarning -> [Text]
cycleWarningText w = case w.trouble of
  CouldNotCheckThat d ->
    -- The opening sentence ('startsItself') assumes a cycle of obligations:
    -- "a HENCE or LEST in it leads back". Under the scope ruling (ii) a cycle of
    -- functions never reaches here, because 'L4.Cycles.alarms' gives a
    -- 'FunctionCycle' no alarm. If cycles of functions are ever given alarms
    -- again, this sentence must first branch on the cycle's kind, which
    -- 'CycleWarning' does not carry today: with that gate removed, it tells
    -- the reader of @ok/fib.l4@ that a HENCE or LEST leads back to
    -- @fibNaive@, which has none (measured 2026-11-21).
    [startsItself w.rule w.through <> "."]
    <> couldNotCheck "I could not check that this comes to an end" d
    <> [ ""
       , "If it does come to an end, say why on a line of its own above " <> quoted w.rule <> ", like this:"
       , ""
       , "  @ends-because <your reason>"
       , ""
       , "A reader can then check your reason, and L4 stops warning about it."
       ]
    <> elsewhere
  GivesNoTime rs ->
    [ quoted w.rule <> " starts itself again with no time passing" <> byWayOf w.through <> ": " <> noTime rs <> "."
    , "So the time of each copy is up the moment it starts, and the next copy starts straight away."
    , "Waiting does not help, because no time passes between one copy and the next, so it does not stop by itself."
    , ""
    , "To give each copy time, make its deadline fall after the moment it starts."
    ]
    <> cannotSilence "no time passes"
  StartsCopies m ->
    [ quoted m.rule <> " starts " <> Text.textShow m.copies <> " copies " <> copiesOf <> " at once: "
        <> continuation m.via <> " joins them with " <> m.operator <> "."
    ]
    <> loop
    <> [ "So " <> occasion m.via <> ", the number of copies open " <> grows m.copies <> "." ]
    <> bound m
    <> [ ""
       , "If one copy is what you meant, start it once."
       ]
    <> cannotSilence "the copies multiply"
  NothingToExplain ->
    [ "@ends-because is above " <> quoted w.rule <> ", but I find no way for " <> quoted w.rule
        <> " to lead back to itself, so I see nothing for the mark to explain."
    , "The mark goes above a rule that uses itself again, directly or through other rules, or whose HENCE or LEST starts it again."
    , "I cannot see a loop that goes through a rule kept in a record or passed in as an input: if "
        <> quoted w.rule <> " leads back to itself that way, the mark is where it belongs, and if not, move it to the rule it explains."
    ]
 where
  copiesOf
    | null w.through = "of itself"
    | otherwise = "of rules that lead back to it"
  -- the rules on the loop, named on a line of their own, so that the list is
  -- not read as the copies
  loop
    | null w.through = []
    | otherwise = ["The rules that lead back to each other are " <> quotedList (w.rule : w.through) <> "."]
  -- the marks on the cycle that are not on the definition the warning is
  -- reported on, which ruling L4 says is where the mark is written
  elsewhere = case [d | (d, _) <- w.marks, d /= w.rule] of
    [] -> []
    ds ->
      [ ""
      , "The @ends-because above " <> quotedList ds <> " does not count here: it goes above "
          <> quoted w.rule <> ", the rule this warning is shown on"
          <> (if null w.through then "." else ", which comes first of the rules that lead back to each other.")
      ]
  -- said only when a definition on the cycle carries a mark, so that a reader
  -- who has never heard of the mark is not told about it
  cannotSilence what
    | null w.marks = []
    | otherwise =
        [ ""
        , "@ends-because does not silence this warning: L4 has checked that " <> what
            <> ", and the mark answers only the warning that L4 could not check that a rule comes to an end."
        ]
  bound m = case m.stepsDown of
    Nothing -> ["Nothing written limits how many times round it goes."]
    Just (p, r) ->
      [ "Each copy is given " <> quoted p <> " less " <> numberText r <> ", so if " <> quoted p
          <> " reaches a stop, this comes to an end, but only after the number open has "
          <> multiplied m.copies <> " at every step down: as many as " <> Text.textShow m.copies
          <> " to the power of " <> (if r == 1 then quoted p else "(" <> quoted p <> " divided by " <> numberText r <> ")") <> "."
      ]

-- | The note a mark leaves, an information-level message carrying its reason
-- (ruling L4). Where it silences a warning, the note says what was silenced
-- first; everywhere else it gives the reason first, then what the mark did.
cycleNoteText :: MarkNote -> [Text]
cycleNoteText n = case n.outcome of
  Silenced through d ->
    couldNotCheck (startsItself n.rule through <> ", and I could not check that this comes to an end") d
    <> [ "Its author says why it does, with the @ends-because above " <> quoted n.rule <> ":"
       , ""
       , "  " <> n.reason
       , ""
       , "So L4 does not warn about it. That reason is what a reader should check."
       ]
  NotWhereReported r answered ->
    said
    <> [ if answered
           then "It does not count here: the warning it would answer, that L4 could not check that this comes to an end, would be shown on "
             <> quoted r <> ", and the @ends-because above " <> quoted r <> " answers it."
           else "It does not count here: the warning it would answer, that L4 could not check that this comes to an end, is shown on "
             <> quoted r <> ", and the mark goes above " <> quoted r <> "."
       ]
  CannotSilence rs ->
    said
    <> [ "It silences nothing: " <> shownOn rs
           <> " about something L4 has checked, and the mark answers only the warning that L4 could not check that a rule comes to an end."
       ]
  NotChecked ->
    said
    <> [ quoted n.rule <> " uses itself again, directly or through other rules, but not through a HENCE or LEST, and L4 gives no warning about whether a rule like that comes to an end."
       , "So the mark changes nothing. That reason is what a reader should check."
       ]
  ShownToEnd e ->
    said
    <> [ quoted n.rule <> " can start itself again, but I could check that it comes to an end: " <> ending e <> "."
       , "So the mark changes nothing."
       ]
  OnNoCycle ->
    said
    <> [ "I find no way for " <> quoted n.rule <> " to lead back to itself, so the mark changes nothing."
       , "I cannot see a loop that goes through a rule kept in a record or passed in as an input."
       ]
 where
  shownOn = \ case
    [r] -> "the warning shown on " <> quoted r <> " is"
    rs -> "the warnings shown on " <> quotedList rs <> " are"
  ending = \ case
    WaitsForTime -> "each new copy waits, for an event or for time to pass, so a run over a list of events reaches an answer"
    InputGetsSmaller -> "each time round, one of its inputs gets smaller, towards a stop"
  said =
    [ "The @ends-because above " <> quoted n.rule <> " says why it comes to an end:"
    , ""
    , "  " <> n.reason
    , ""
    ]

-- | The opening of a "could not check" and of its note.
startsItself :: Text -> [Text] -> Text
startsItself rule through
  | null through = quoted rule <> " can start itself again: a HENCE or LEST in it leads back to " <> quoted rule
  | otherwise = quoted rule <> " can start itself again: " <> quotedList (rule : through)
      <> " lead back to each other, and a HENCE or LEST in one of them starts one of them again"

byWayOf :: [Text] -> Text
byWayOf = \ case
  [] -> ""
  ds -> ", by way of " <> quotedList ds

-- | The sentence that says it could not be checked, ending with why: on one
-- line for one reason, one line each for several.
couldNotCheck :: Text -> Doubt -> [Text]
couldNotCheck opening = \ case
  Stalled [s] -> [opening <> ", because " <> stallReason s <> "."]
  Stalled ss -> (opening <> ", because:") : ["  - " <> stallReason s | s <- ss]
  -- Reached only when no lap through a HENCE or LEST stalls (the verdict's
  -- guards in "L4.Cycles" report a stall first), so the doubt is about the
  -- direct uses alone, and each reason's second line says so (decided by Claude
  -- 2026-11-21, pending Meng's review).
  Mutual ->
    [ opening <> ", because two or more of them also use each other directly, with no duty in between, and I do not check that kind of loop."
    , "The doubt is about those direct uses of each other, not about a HENCE or LEST."
    ]
  -- The rules that use themselves are named, never "it": the warning is
  -- shown on the cycle's first rule, which may only hand on to them by a
  -- HENCE or LEST.
  NoMeasure [r] ->
    [ opening <> ", because " <> quoted r <> " also uses itself directly, with no duty in between, and there I could not find an input that gets smaller each time, towards a stop."
    , "The doubt is about that direct use of itself, not about a HENCE or LEST."
    ]
  NoMeasure rs ->
    [ opening <> ", because " <> quotedList rs <> " also use themselves directly, with no duty in between, and there I could not find an input that gets smaller each time, towards a stop."
    , "The doubt is about those direct uses, not about a HENCE or LEST."
    ]
  Untraced -> [opening <> ", because it uses a rule kept in a record field or passed in as an input, which I cannot follow, so there may be another way round that I cannot see."]

stallReason :: Stall -> Text
stallReason = \ case
  NotAfterArming r
    | r == 0 -> "one of its deadlines falls at the very moment its duty starts, so it gives no time to act"
    | otherwise -> "one of its deadlines falls " <> numberText (negate r) <> " before its duty starts, so it gives no time to act"
  WithinNotLiteral -> "the time one of its duties allows (its WITHIN) is not a number written out, and I read only a number written out there, so I cannot tell how long that time is, or whether it is more than 0 each time round"
  AnchoredAtInstant -> "one of its deadlines is counted from a fixed moment (WITHIN … OF …), and once that moment is past, each new copy is already late"
  AnchoredAtJoin -> "one of its deadlines is counted from THE JOIN (WITHIN … OF THE JOIN), and I cannot tell when that is"
  AnchoredAtDeadline -> "one of its deadlines is another duty's deadline (OF THE DEADLINE), taken when that duty hands on, and it may already be past"
  OpensNotLiteral -> "one of its duties opens at a moment that is not a number written out (AFTER …), which may be a fixed moment already past"
  OpensAtInstant -> "one of its duties opens at a time counted from a fixed moment (AFTER … OF …), so its deadline is fixed too, and once that is past, each new copy is already late"
  OpensAtJoin -> "one of its duties opens at a time counted from THE JOIN (AFTER … OF THE JOIN), and I cannot tell when that is"
  BeforeDate -> "one of its deadlines is a date (BEFORE …), and once that date is past, each new copy is already late"
  RecordHence -> "the HENCE after a RECORD goes on straight away, without waiting for anything"
  BarrierMayBeEmpty -> "it waits for everyone in a list to act (EVERY … ONCE ALL HAVE), the list may be empty, and over an empty list it goes on straight away"
  OwnTrace -> "this file may run a contract on a trace of its own (EVALTRACE), and on a trace that starts again, no wait limits how many times it can start"

noTime :: [Rational] -> Text
noTime rs
  | all (== 0) rs = "its deadline falls at the very moment each copy starts"
  | all (< 0) rs = "its deadline falls before the moment each copy starts"
  | otherwise = "its deadline falls at the moment each copy starts, or before it"

continuation :: Continuation -> Text
continuation = \ case
  HenceOf _ -> "its HENCE"
  LestOf _ -> "its LEST"
  AfterRecord -> "the HENCE after its RECORD"

-- | When the continuation goes on.
occasion :: Continuation -> Text
occasion = \ case
  LestOf DMustNot -> "every time the duty is broken"
  LestOf DMay -> "every time the chance passes unused"
  LestOf _ -> "every time a deadline is missed"
  HenceOf DMustNot -> "every time the time passes and the duty is kept"
  HenceOf DMay -> "every time the permission is used"
  HenceOf _ -> "every time the duty is done"
  AfterRecord -> "every time the RECORD is made"

grows :: Int -> Text
grows = \ case
  2 -> "doubles"
  n -> "grows " <> Text.textShow n <> " times over"

multiplied :: Int -> Text
multiplied = \ case
  2 -> "doubled"
  n -> "grown " <> Text.textShow n <> " times over"

quoted :: Text -> Text
quoted n = "`" <> n <> "`"

-- | @`a`@, @`a` and `b`@, @`a`, `b` and `c`@.
quotedList :: [Text] -> Text
quotedList ns = case reverse (map quoted ns) of
  [] -> ""
  [n] -> n
  (l : rest) -> Text.intercalate ", " (reverse rest) <> " and " <> l

-- | A number as a reader writes it: @3@, @0.001@, @-2.5@, and @1/3@ for one
-- with no decimal that ends.
numberText :: Rational -> Text
numberText r
  | r < 0 = "-" <> numberText (negate r)
  | denominator r == 1 = Text.textShow (numerator r)
  | Just places <- decimalPlaces (denominator r) =
      let scaled = numerator (r * 10 ^ places)
          (whole, frac) = scaled `divMod` (10 ^ places)
      in Text.textShow whole <> "." <> Text.justifyRight places '0' (Text.textShow frac)
  | otherwise = Text.textShow (numerator r) <> "/" <> Text.textShow (denominator r)
 where
  -- how many decimal places a denominator needs, when its only prime factors
  -- are 2 and 5
  decimalPlaces :: Integer -> Maybe Int
  decimalPlaces d = go d 0 0
   where
    go n twos fives
      | n == 1 = Just (max twos fives)
      | n `mod` 2 == 0 = go (n `div` 2) (twos + 1) fives
      | n `mod` 5 == 0 = go (n `div` 5) twos (fives + 1)
      | otherwise = Nothing
