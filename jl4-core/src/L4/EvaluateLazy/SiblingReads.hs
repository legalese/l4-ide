-- | The run-time check on compounds whose operands read each other's records
-- (smucclaw/l4-ide#1069; NORM-LOG-SPEC card N10, "a run-time check now,
-- lockstep operands as the goal", extended here to black ink).
--
-- A @RAND@ runs its operands in step (N10's goal, option A; Note [Operands in
-- step] in 'L4.EvaluateLazy.Machine'): event n of the @#TRACE@ is handed to
-- the left operand and then to the right before event n+1 is handed to
-- either. An @EVERY … UPON EACH@ and the distributive @EVERY@ fold their
-- members into the same right-nested @RAND@, so their members run in step
-- too. An @ROR@ still runs operand-major, the left operand over the whole
-- trace and then the right, and so does a @RAND@ evaluated under an
-- evaluation trace (@#EVALTRACE@, or every directive under the REPL's
-- policy), whose trace builder needs each operand's frames nested whole.
-- All operands share one ledger, whose entries carry no contract instant.
--
-- In Hvitved's contract specification language, which L4's contract evaluator
-- follows (@jl4/README.md@), a conjunct is a function of the trace alone
-- (thesis Def. 2.2.7, p. 35; Fig. 2.8, p. 49): CSL has no shared state, so an
-- operand reading its sibling's record is outside CSL. In step, a read sees
-- the sibling's records from earlier events and none from later ones, which
-- is the reading the shared ledger has when the trace is taken one event at a
-- time; what in step cannot order, this module refuses, and refusing keeps L4
-- inside CSL. For operands that do not read each other's records the check
-- observes and never fires, so verdicts, breach instants and blamed parties
-- are exactly what they were.
--
-- This module holds the check's state and its rules; the machine calls
-- 'checkRead' at every @RECALL@ and 'checkWrite' at every @RECORD@, @COMMIT@,
-- @ATTEST@ and @NOTIFY@ made inside a compound's operand, and turns a 'Left'
-- into an evaluation error. Two accesses are ordered by their contract
-- instants and, at one instant, by the number of events the compound where
-- their operands part had taken when each was made ('setTaken'; 'earlier'):
-- in step, that number is the event's position in the trace. The check
-- refuses a read that saw a sibling's record not 'earlier' than it, a read
-- that missed one 'earlier' than it, and a @RECALL ALL@ that saw sibling
-- records out of that order. The check changes no read, stores nothing in
-- the ledger, and forces nothing: a compound's time that is still a thunk is
-- logged as the compound's start ('StartOf') and filled in once the machine
-- has evaluated it for its own reasons.
--
-- What is refused in step, by design (assumed, not ruled): a read and a
-- sibling's record made while the two operands take the SAME event, when the
-- left operand's turn (which comes first) is not the earlier instant, as when
-- one event reveals a deadline missed some time before it and the right
-- operand's @LEST@ records the miss at that deadline; and any two such
-- accesses at the same instant, which the trace gives no order. An @ROR@ or a
-- barrier (@EVERY … ONCE ALL HAVE@) inside an operand goes over events the
-- compound has already taken (the @ROR@'s right operand, the barrier's later
-- members and its join), so an access inside one carries no event count for
-- the compounds outside it ('takenOn'), and is ordered against their other
-- operands by instant alone.
--
-- What it does not see, sorted by how it fails:
--
-- * Silent: when an @ROR@'s left operand is @FULFILLED@ the right operand is
--   never run, so a record it would have made is never compared with what
--   the left operand read. The check-time warning
--   ('L4.Lint.SiblingReads') names such a pair; the run-time check does not.
-- * Silent: two operands that write one cell with no read of it inside the
--   compound leave the ledger in the order the writes were made (in step,
--   event by event, left before right at one event). No read depended on
--   that order, so there is nothing to refuse.
-- * Silent: a read whose evaluation is deferred (a @RECALL@ inside a value
--   that is stored unevaluated and forced later) is checked where it is
--   forced, not where it is written; and a top-level rule with no inputs that
--   reads the ledger is forced once and its answer shared, so a second
--   operand that uses it makes no read of its own (a defect outside compounds
--   too: a later use in the same chain gets the stale answer).
-- * Over-refusal, by design (assumed, not ruled): @EVAL AS OF SYSTEM TIME@
--   and @EVAL UNDER VALID TIME@ bounds are not applied, so a write such a
--   bound would hide is still compared; a @RECALL ALL@ that sees two sibling
--   entries out of order is refused even when what the rule does with the
--   list would come out the same; and an access whose instant is never known
--   counts as simultaneous with every other.
module L4.EvaluateLazy.SiblingReads
  ( LedgerKey (..)
  , OperandPath
  , Scope (..)
  , Clock (..)
  , Access (..)
  , CellLog (..)
  , SiblingState (..)
  , emptySiblingState
  , inCompound
  , openScope
  , startKnown
  , setTaken
  , checkRead
  , checkWrite
  , siblingReadMarker
  , isSiblingReadRefusal
  , lineOf
  ) where

import Base
import Control.Applicative ((<|>))
import Data.Char (toUpper)
import qualified Base.Map as Map
import qualified Base.Text as Text
import qualified Data.IntMap.Strict as IntMap
import Data.IntMap.Strict (IntMap)
import Data.Sequence (Seq, (|>))
import qualified Data.Sequence as Seq
import L4.Parser.SrcSpan (SrcPos (..), SrcRange (..))
import L4.Utils.Ratio (prettyRatio)

-- | Which ledger a cell lives in: the shared official record (@COMMIT@,
-- @ATTEST@, @RECALL OFFICIAL's@) or one party's own (@RECORD@, @NOTIFY@,
-- @RECALL@, @RECALL p's@), keyed exactly as the machine keys it.
data LedgerKey = OfficialKey | OwnKey !Text
  deriving stock (Eq, Ord, Show)

-- | The compound operands an evaluation is inside, innermost first: each a
-- compound's scope (a fresh number per application of a compound to its
-- events) and the side, 0 for the left operand and 1 for the right.
type OperandPath = [(Int, Int)]

-- | What a message needs to know about one compound: its operator and how to
-- name each side.
data Scope = MkScope
  { scOp    :: !Text
  , scLeft  :: !Text
  , scRight :: !Text
  , scFork  :: !Bool
    -- ^ the compound looks like the members of an @EVERY@, folded into a
    -- @RAND@ (its left operand is an obligation value, not source); it
    -- only adds a sentence to the message, so a wrong guess costs nothing
  , scLockstep :: !Bool
    -- ^ the machine runs this compound's operands in step, one event at a
    -- time (a @RAND@, 'L4.EvaluateLazy.Machine'\'s @Lockstep@ frame), so the
    -- events its operands have taken order two of its accesses at one instant
  }
  deriving stock Show

-- | When an access happened, as the machine knew it at the time.
data Clock
  = At !Rational
    -- ^ an event's stamp, a hand-off's clock (the act's stamp under @HENCE@,
    -- the missed deadline under @LEST@), an obligation's arming, or a
    -- compound's own time when an operand starts
  | StartOf !Int
    -- ^ the start of the compound with this scope, whose time was still a
    -- thunk then: the check never forces it, and reads it once something
    -- else has ('startKnown')
  | Unclocked
  deriving stock (Eq, Show)

-- | One logged read or write.
data Access = MkAccess
  { acInstant :: !(Maybe Rational)
    -- ^ the contract instant, as far as it is known now: 'acClock' resolved
    -- against the compound start times known when the access is compared
  , acClock   :: !Clock
  , acPath    :: !OperandPath
  , acSite    :: !(Maybe SrcRange)
  , acVerb    :: !Text
    -- ^ @RECORD@, @COMMIT@ or @NOTIFY@ for a write; @RECALL@ or
    -- @RECALL ALL@ for a read
  , acTaken   :: !(IntMap Int)
    -- ^ for each in-step compound on 'acPath', how many events it had handed
    -- its operands when the access was made ('ssTaken')
  }
  deriving stock Show

-- | Every logged write to one cell, oldest first, and every logged read of it.
data CellLog = MkCellLog
  { clWrites :: !(Seq Access)
  , clReads  :: ![Access]
  }
  deriving stock Show

-- | The check's state for one directive. Reset with the ledger.
data SiblingState = MkSiblingState
  { ssPath   :: !OperandPath
  , ssClock  :: !Clock
  , ssStarts :: !(IntMap Rational)
    -- ^ the start times of compounds whose time was a thunk when they started,
    -- once the machine has evaluated it for some other reason
  , ssScopes :: !(IntMap Scope)
  , ssCells  :: !(Map (LedgerKey, Text) CellLog)
  , ssNext   :: !Int
    -- ^ the next scope number. Kept here rather than drawn from the
    -- machine's supply, so that the check moves no address or unique.
  , ssTaken  :: !(IntMap Int)
    -- ^ for each compound whose operands run in step, by scope, how many
    -- events of its stream it has handed them so far: the event they are
    -- all taking now. Two accesses made while taking different events are
    -- ordered by them even at one instant, as the trace orders the events.
  , ssBehind :: !Int
    -- ^ how many of the outermost entries of 'ssPath' belong to compounds
    -- whose events are being taken again: inside a barrier ('startBarrier'
    -- in "L4.EvaluateLazy.Machine"), the members after the first and the
    -- join take events the compounds around it have already taken, so an
    -- access in there is not ordered by those compounds' counts. 0 outside.
  }
  deriving stock Show

emptySiblingState :: SiblingState
emptySiblingState = MkSiblingState [] Unclocked IntMap.empty IntMap.empty Map.empty 0 IntMap.empty 0

-- | The in-step compound with this scope has handed its operands @n@ events.
setTaken :: Int -> Int -> SiblingState -> SiblingState
setTaken s n st = st {ssTaken = IntMap.insert s n st.ssTaken}

-- | What 'acTaken' records for an access made now on @path@: the counts of
-- the in-step compounds the access is taking its event from at the head of
-- their streams. Walking out from the innermost compound, that stops at the
-- first compound that is not in step (an @ROR@, whose right operand takes
-- again the events its left one took) and at the compounds a barrier is
-- taking events again from ('ssBehind'). An access with no count for the
-- compound where it parts from another is ordered by instant alone, and at
-- one instant not at all ('earlier').
takenOn :: OperandPath -> SiblingState -> IntMap Int
takenOn path st = IntMap.fromList
  [ (s, n)
  | (s, _) <- takeWhile inStep (take (length path - st.ssBehind) path)
  , Just n <- [IntMap.lookup s st.ssTaken] ]
  where
    inStep (s, _) = maybe False (.scLockstep) (IntMap.lookup s st.ssScopes)

-- | A compound meets its events at @clock@ ('Nothing' while its time is a
-- thunk): a fresh scope, and the left operand's path into it.
openScope :: Scope -> Maybe Rational -> SiblingState -> (Int, SiblingState)
openScope sc clock st =
  ( st.ssNext
  , st { ssPath = (st.ssNext, 0) : st.ssPath
       , ssClock = maybe (StartOf st.ssNext) At clock
       , ssScopes = IntMap.insert st.ssNext sc st.ssScopes
       , ssNext = st.ssNext + 1
       } )

-- | The start time of the compound with this scope, now that it is known.
startKnown :: Int -> Rational -> SiblingState -> SiblingState
startKnown s t st = st {ssStarts = IntMap.insert s t st.ssStarts}

-- | A clock as an instant, as far as it is known now.
instantOf :: SiblingState -> Clock -> Maybe Rational
instantOf st = \ case
  At t      -> Just t
  StartOf s -> IntMap.lookup s st.ssStarts
  Unclocked -> Nothing

-- | A cell's log with every instant resolved as far as it is known now.
resolved :: SiblingState -> CellLog -> CellLog
resolved st cl = MkCellLog (fmap fill cl.clWrites) (map fill cl.clReads)
  where fill a = a {acInstant = instantOf st a.acClock}

-- | Whether the evaluation is inside some compound's operand. Outside every
-- compound nothing is logged: such an access can never be a sibling's.
inCompound :: SiblingState -> Bool
inCompound s = not (null s.ssPath)

-- | The scope at which two paths take different sides, if they do: the
-- compound one access is on the left of and the other on the right of. The
-- scope numbers are unique per directive, so a shared number is a shared
-- compound.
divergence :: OperandPath -> OperandPath -> Maybe Int
divergence p q = listToMaybe [ s | (s, side) <- p, Just side' <- [lookup s q], side /= side' ]

-- | The words every refusal message contains, so that a front end can tell a
-- sibling-read refusal from other evaluation errors without parsing it.
siblingReadMarker :: Text
siblingReadMarker = "read each other's records"

isSiblingReadRefusal :: Text -> Bool
isSiblingReadRefusal = Text.isInfixOf siblingReadMarker

-- | Whether access @a@ happened strictly before access @b@ in the trace's
-- time, as far as the compound with scope @s@, where the two diverge, can
-- tell: at an earlier instant; or, at one instant, while the compound's
-- operands were taking an earlier event of its stream, which only an in-step
-- compound knows ('acTaken'), since the trace orders two events with one
-- stamp as they were written. An unknown instant is never earlier, so a
-- comparison involving one refuses.
earlier :: Int -> Access -> Access -> Bool
earlier s a b = case (a.acInstant, b.acInstant) of
  (Just x, Just y)
    | x < y     -> True
    | x > y     -> False
    | otherwise -> case (IntMap.lookup s a.acTaken, IntMap.lookup s b.acTaken) of
        (Just m, Just n) -> m < n
        _                -> False
  _ -> False

-- | A @RECALL@ of @cell@ in @key@'s ledger, made now. Rules 1 and 3; the read
-- is logged when nothing refuses.
--
-- 1. A record from the read's future: some entry the read sees was written by
--    a sibling at an instant at or after the read's.
-- 3. Records seen out of order: two entries the read sees, written by two
--    siblings of each other, stand in the ledger in an order other than the
--    order of their instants (or at one instant, where no order between them
--    is the trace's), and the read's answer depends on that order: the last
--    entry for @RECALL@, the whole list for @RECALL ALL@.
checkRead :: LedgerKey -> Text -> Bool -> Maybe SrcRange -> SiblingState -> Either Text SiblingState
checkRead key cell readAll site st
  | not (inCompound st) = Right st
  | otherwise =
      case future <|> outOfOrder of
        Just msg -> Left msg
        Nothing  -> Right st {ssCells = Map.insert (key, cell) cl {clReads = theRead : cl.clReads} st.ssCells}
  where
    cl = resolved st (Map.findWithDefault (MkCellLog Seq.empty []) (key, cell) st.ssCells)
    writes = toList cl.clWrites
    theRead = MkAccess (instantOf st st.ssClock) st.ssClock st.ssPath site (if readAll then "RECALL ALL" else "RECALL") (takenOn st.ssPath st)
    future = listToMaybe
      [ refusal st key cell (FutureSeen w) theRead w s
      | w <- writes, Just s <- [divergence theRead.acPath w.acPath]
      , not (earlier s w theRead) ]
    outOfOrder
      | readAll = listToMaybe
          [ refusal st key cell (OutOfOrder a) theRead b s
          | (i, a) <- zip [0 :: Int ..] writes, (j, b) <- zip [0 ..] writes, i < j
          , Just s <- [divergence a.acPath b.acPath]
          , not (earlier s a b) ]
      | otherwise = case reverse writes of
          -- the entry the read returns is the last in the ledger; the trace's
          -- order gives the same one only when it is later than every entry a
          -- sibling of it made, or the two have an order the trace knows
          lastW : _ -> listToMaybe
            [ refusal st key cell (OutOfOrder w) theRead lastW s
            | w <- writes, Just s <- [divergence w.acPath lastW.acPath]
            , not (earlier s w lastW) ]
          [] -> Nothing

-- | A @RECORD@, @COMMIT@, @ATTEST@ or @NOTIFY@ of @cell@ into @key@'s ledger,
-- made now. Rule 2; the write is logged when nothing refuses.
--
-- 2. A record the read missed: a sibling read of the cell, already made, at an
--    instant at or after this write's, could not see it.
checkWrite :: LedgerKey -> Text -> Text -> Maybe SrcRange -> SiblingState -> Either Text SiblingState
checkWrite key cell verb site st
  | not (inCompound st) = Right st
  | otherwise =
      case missed of
        Just msg -> Left msg
        Nothing  -> Right st {ssCells = Map.insert (key, cell) cl {clWrites = cl.clWrites |> theWrite} st.ssCells}
  where
    cl = resolved st (Map.findWithDefault (MkCellLog Seq.empty []) (key, cell) st.ssCells)
    theWrite = MkAccess (instantOf st st.ssClock) st.ssClock st.ssPath site verb (takenOn st.ssPath st)
    missed = listToMaybe
      [ refusal st key cell PastMissed r theWrite s
      | r <- reverse cl.clReads, Just s <- [divergence r.acPath theWrite.acPath]
      , not (earlier s r theWrite) ]

data Rule = FutureSeen Access | PastMissed | OutOfOrder Access

-- | The message: what stopped, the two places, the
-- instants, why it matters, and what to do.
refusal :: SiblingState -> LedgerKey -> Text -> Rule -> Access -> Access -> Int -> Text
refusal st key cell rule r w s = Text.unwords $
  [ "The two sides of " <> opName <> " " <> siblingReadMarker <> ","
  , "so the answer would depend on which side L4 runs first, and evaluation stops here."
  ]
  <> capitalised middle
  <>
  ( if lockstep
      then
        [ "L4 runs the sides of " <> opName <> " in step, one event of the trace at a time,"
        , "each event first on the left side and then on the right,"
        , "so a read and a record made while the sides take the same event,"
        , "or inside an ROR or an EVERY … ONCE ALL HAVE on one side, which go over events already taken,"
        , "come in an order that need not be the order of their instants; at one instant the trace gives them no order at all."
        ]
      else if op == "RAND"
        then
          [ "While it keeps an evaluation trace (#EVALTRACE), L4 runs one side of a RAND over the whole trace before it starts the other,"
          , "so a record made on one side is not in step with a read on the other;"
          , "without the evaluation trace the sides run in step, one event at a time."
          ]
        else
          [ "L4 runs one side of " <> opName <> " over the whole trace before it starts the other,"
          , "so a record made on one side is not in step with a read on the other."
          ] )
  <> [ "An EVERY runs its members as the sides of a RAND, so this holds between its members too." | fork ]
  <>
  [ "Rewrite the rule so that the side that reads the record also makes it,"
  , "or make the record before the " <> op <> " starts."
  , "(smucclaw/l4-ide#1069.)"
  ]
  where
    scope = IntMap.lookup s st.ssScopes
    op = maybe "RAND" (.scOp) scope
    fork = maybe False (.scFork) scope
    lockstep = maybe False (.scLockstep) scope
    -- only our own words are capitalised: a rule's name is always quoted, and
    -- a party's name is printed as it was declared
    capitalised = \ case
      t : ts | "the " `Text.isPrefixOf` t, Just (c, rest) <- Text.uncons t -> Text.cons (toUpper c) rest : ts
      ts -> ts
    opName = article op <> " " <> op
    article o = if o == "ROR" then "an" else "a"
    record = ledgerName key <> " `" <> cell <> "`"
    sideOf a = case (scope, lookup s a.acPath) of
      (Just sc, Just 0) -> sc.scLeft
      (Just sc, Just _) -> sc.scRight
      _                 -> "one side"
    whoAt a = innermost a <> describeSide a
    -- the operand closest to the access, then (when that is not the side of
    -- the diverging compound itself) which side of it the access is on
    innermost a = case a.acPath of
      (s', side) : _ | s' /= s, Just sc <- IntMap.lookup s' st.ssScopes ->
        if side == 0 then sc.scLeft else sc.scRight
      _ -> sideOf a
    -- between the members of one fold the member's own name is enough
    describeSide a = case a.acPath of
      (s', _) : _ | s' /= s, not (fork && maybe False (.scFork) (IntMap.lookup s' st.ssScopes)) -> ", inside " <> sideOf a <> ","
      _ -> ""
    middle = case rule of
      FutureSeen _ ->
        [ whoAt r <> " read " <> record <> at r <> site r <> ","
        , "and saw a record that " <> whoAt w <> ", on the other side of the " <> op <> ","
        , "made" <> at w <> site w <> ":"
        , "a record from the read's " <> (if w.acInstant == r.acInstant then "own instant, whose order with the read is unknown." else "future.")
        ]
      PastMissed ->
        [ whoAt r <> " read " <> record <> at r <> site r <> ","
        , "but " <> whoAt w <> ", on the other side of the " <> op <> ","
        , "makes that record" <> at w <> site w <> ","
        , "which the read " <> (if w.acInstant == r.acInstant then "may or may not have been meant to see, at the same instant." else "should have seen and did not.")
        ]
      OutOfOrder a ->
        [ whoAt r <> " read " <> record <> at r <> site r <> ","
        , "and saw two records in an order that is not the order they were made in:"
        , "one by " <> whoAt a <> at a <> site a <> ","
        , "then one by " <> whoAt w <> at w <> site w <> ","
        , "on the other side of the " <> op <> "."
        ]
    at a = maybe "" (\ t -> " at " <> prettyRatio t) a.acInstant
    site a = case a.acSite of
      Just rng -> " (" <> a.acVerb <> ", line " <> Text.pack (show (lineOf rng)) <> ")"
      Nothing  -> " (" <> a.acVerb <> ")"
    ledgerName = \ case
      OfficialKey -> "OFFICIAL's"
      OwnKey ""   -> "the anonymous ledger's"
      OwnKey p    -> p <> "'s"

-- | The line a range starts on, as a message names it.
lineOf :: SrcRange -> Int
lineOf MkSrcRange {start = MkSrcPos {line = n}} = n
