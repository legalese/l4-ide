{-# LANGUAGE PatternSynonyms #-}
-- | The norm-plane marking: what a regulative residual says is live, read
-- off the value the evaluator returned.
--
-- This is 'markingOf' of @specs/todo/lexipedia-superset/LTS-VISUALISER.md@
-- §4.2a (P2c), written against 'Threshold' as §4.9 "What follows for P2"
-- asks. It defines /no second semantics/ (§2.4): every placement here is a
-- reading of a value shape the machine has already decided on, and nothing
-- here predicts what an event would do. Predictions are "L4.Lts.WhatIf",
-- which gets them by running the evaluator.
--
-- == Provenance of the lifecycle vocabulary
--
-- * 'Created' and 'InEffect' are Symboleo's lifecycle states @Create@ and
--   @InEffect@ (Sharifi et al., RE 2020, Fig. 2; read 2026-09-16, R8), as
--   §2.3 borrows them — @Create@ past-participled to match its siblings.
--   'Created' is the F3 distinction drawn: a norm the machine has not
--   entered, as opposed to one it has discharged.
-- * 'Violated' is Anderson\/Meyer's violation atom (§2.2): the machine
--   concluded a breach. Symboleo's state for the same thing is @Violation@.
-- * 'Lapsed' is this spec's own coinage (§4.2a; R12 ANSWERED 2026-09-16):
--   an @ROR@ alternative that is definitively lost while the compound is
--   not violated. Symboleo has no compound obligations and so no such
--   state; its @Discharge@ and @Unsuccessful Termination@ are both
--   cancellations without breach and would erase the blame this carries.
-- * 'Awaiting' is the join state §4.9 asks for: a barrier's continuation,
--   marked but not enabled until its 'Threshold' is met. It has no
--   Symboleo name; it is the Petri-net "place with too few tokens".
--
-- == Loud and silent
--
-- The fold is total over 'Value' — a non-regulative value marks as @[]@ —
-- so its failures are silent by construction; the reader must know them:
--
-- * A barrier's members print as ordinary obligations whose @HENCE@ is the
--   machine's checkpoint sentinel; the residual carries neither the join
--   line nor the count ("phase-2 limit", @Machine.barrierFinish@). With a
--   'MarkingContext' read from the step log the 'Awaiting' place knows its
--   progress and its threshold; with 'noContext' it is still emitted —
--   recognised by the sentinel's name AND its lack of a source range (the
--   machine mints it with 'L4.Annotation.emptyAnno'; a drafter's own
--   @`the join`@ has a range and is not mistaken for it) — but its
--   'awProgress' is 'Nothing'. A missing @Awaiting@ therefore means "no
--   barrier"; an @Awaiting@ with no progress means "run it with the log on".
-- * A member's 'lnMember' is filled from the same context and is 'Nothing'
--   without it. It is the FAMILY ('Family': join, total, join site), not
--   the member's own record: the context is keyed by action site, which
--   every member of a cast shares, so a per-member field read through it
--   would be some other member's.
-- * The arm count ('mcDone') is folded over the steps IN ORDER: a
--   @MemberSatisfied n@ sets it to @n@, and the join's own terminal step
--   ('JoinReleased', 'JoinExpired', 'JoinFailed', 'JoinStalled') resets it
--   to zero, mirroring the machine's @registerCast@, which zeroes its
--   counter every time the @EVERY@ is entered. So a @HENCE@ that re-enters
--   its own barrier reads the second activation's count, not the first's
--   final one. Taking the maximum instead — which this module did at first
--   — reported @3 of 3@ for a re-entered barrier with one arm satisfied,
--   with 'thresholdMet' true while the 'Awaiting' was still pending.
-- * What that re-entry still collapses, silently, is the cast register
--   itself: a second cast from the same site overwrites the first in
--   'mcCasts'. Today the two casts are identical (same join, same total,
--   same join site), so nothing observable is lost; that is the cast
--   register's own limit (spec §4.3, "Not built"), inherited here.
module L4.Lts.Marking
  ( -- * The marking
    NormPlacement (..)
  , markingOf
  , placementText
    -- * The pieces
  , LiveNorm (..)
  , Bearer (..)
  , Countdown (..)
  , Blame (..)
  , Family (..)
  , Progress (..)
  , thresholdMet
  , blameOf
    -- * The raw walk
  , RawObligation (..)
  , liveObligations
  , renderLive
  , isCheckpoint
    -- * The context
  , MarkingContext (..)
  , noContext
  , contextOf
  ) where

import Base
import qualified Base.Map as Map
import qualified Base.Text as Text
import Base.Text (textShow)

import L4.Annotation (HasSrcRange (..))
import L4.Evaluate.ValueLazy
import L4.EvaluateLazy.DeonticStep
import L4.EvaluateLazy.Machine (joinCheckpointName, pattern ValFulfilled)
import L4.Parser.SrcSpan (SrcRange)
import L4.Print (LayoutPrinter, prettyLayout)
import L4.Syntax
import L4.Utils.Ratio (prettyRatio)

-- | One place on the norm plane, with its lifecycle state.
data NormPlacement
  = Created
      { crSite   :: !(Maybe SrcRange)
        -- ^ where the branch is written: @rangeOf@ the unforced expression,
        -- or of the whole @EVERY@ rule for an unarmed quantified obligation
      , crSource :: !Text
        -- ^ the branch as the residual prints it
      }
    -- ^ Symboleo's @Create@: a branch the machine has not entered. Two value
    -- shapes land here — a @Left rexpr@ operand of a 'ValROp' (§4.2a fact
    -- 4: "already present in the runtime type"), and a 'ValQuantified',
    -- an @EVERY@ that has not met its event stream and so has no cast yet.
  | InEffect !LiveNorm
    -- ^ Symboleo's @InEffect@: a 'ValObligation' the machine is holding
    -- against the event stream.
  | Violated !Blame
    -- ^ Anderson\/Meyer: a 'ValBreached' the machine concluded.
  | Lapsed !Blame
    -- ^ §4.2a's coinage (R12, ours): a breached operand of a surviving @ROR@. The
    -- alternative is gone; the compound is not violated. Drawing this red
    -- is the lie §3.1's counterexample exists to prevent.
  | Awaiting
      { awJoinSite :: !(Maybe SrcRange)
        -- ^ the join line's range when the context knows it; else the
        -- members' shared action site
      , awProgress :: !(Maybe Progress)
        -- ^ 'Nothing' when the residual was read without a context: the
        -- sentinel is visible but the count is not
      }
    -- ^ §4.9: a barrier's continuation — marked, not enabled. One per
    -- barrier, however many members are still pending.
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | An obligation in force, as the residual holds it.
data LiveNorm = MkLiveNorm
  { lnSite   :: !(Maybe SrcRange)
    -- ^ @rangeOf@ the 'RAction' — the static half of §3.4's key
  , lnBearer :: !Bearer
  , lnModal  :: !DeonticModal
  , lnAction :: !Text
    -- ^ the action pattern, pretty-printed
  , lnDue    :: !Countdown
  , lnHence  :: !Text
    -- ^ the @HENCE@ as the residual prints it; for a barrier member this is
    -- the machine's sentinel, @`the join`@
  , lnLest   :: !(Maybe Text)
  , lnMember :: !(Maybe Family)
    -- ^ which @EVERY@ family this belongs to, when the context knows
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | An @EVERY@ family, as every member of its cast shares it: the
-- 'MemberOf' fields that are the same for the whole cast, and nothing
-- per-member. 'MemberOf.moIndex' is deliberately not carried — through a
-- context keyed by action site it would be whichever member the log wrote
-- last, which is nobody's in particular.
data Family = MkFamily
  { faJoin     :: !JoinKind
  , faTotal    :: !Int
  , faJoinSite :: !(Maybe SrcRange)
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

familyOf :: MemberOf -> Family
familyOf m = MkFamily {faJoin = m.moJoin, faTotal = m.moTotal, faJoinSite = m.moJoinSite}

-- | The party, as far as the machine has forced it. A @PARTY p@ obligation
-- evaluates @p@ lazily, so a norm that never met an event may still hold
-- the expression.
data Bearer
  = KnownParty !Text       -- ^ the forced value, pretty-printed
  | UnforcedParty !Text    -- ^ the expression, pretty-printed
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | The residual @WITHIN@, on the contract clock (§4.1: a step counter, not
-- dense time). The machine decrements it per event scrutinised.
data Countdown
  = NoDeadline
  | UnforcedDeadline !Text   -- ^ the @WITHIN@ expression, never evaluated
  | Remaining !Rational      -- ^ what is left, relative to the last event seen
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | What a breach value blames, as the residual carries it
-- ('ReasonForBreach'). Everything is pretty-printed: the marking is a list.
data Blame = MkBlame
  { blParty    :: !(Maybe Text)
    -- ^ who breached; 'Nothing' for a bare @BREACH@
  , blAction   :: !(Maybe Text)
    -- ^ what they did (a @DeadlineMissed@ names the revealing act)
  , blStamp    :: !(Maybe Rational)
    -- ^ when; 'Nothing' for an @ExplicitBreach@, which carries no time
  , blObliged  :: !(Maybe Text)
    -- ^ the obligation missed, as @MUST …@
  , blSite     :: !(Maybe SrcRange)
    -- ^ @rangeOf@ the missed 'RAction'
  , blDeadline :: !(Maybe Rational)
  , blReason   :: !(Maybe Text)
    -- ^ the @BECAUSE@, when written
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | How far a barrier has come, against what it waits for.
data Progress = MkProgress
  { prDone      :: !Int
  , prTotal     :: !Int
  , prThreshold :: !(Threshold Resolved)
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | Is the threshold met? Phase 3's count and measure forms add arms here
-- and at 'placementText''s @thresholdText@ (and in the machine, at
-- @assembleQuantified@'s @threshold\@AllHave{}@); none of the three has a
-- wildcard, so a new 'Threshold' constructor is a compile error at each.
thresholdMet :: Progress -> Bool
thresholdMet p = case p.prThreshold of
  AllHave _ -> p.prDone >= p.prTotal

-- | What the step log knows that the residual does not: which action sites
-- belong to an @EVERY@ cast, and how many of a barrier's arms are satisfied.
-- Both are read back out of the steps ('contextOf'), so nothing new is
-- captured.
data MarkingContext = MkMarkingContext
  { mcCasts :: !(Map (Maybe SrcRange) Family)
    -- ^ per ACTION site, the family every member of the cast shares
  , mcDone  :: !(Map (Maybe SrcRange) Int)
    -- ^ per JOIN site, the arms satisfied so far in the CURRENT activation
    -- of that barrier: the last 'MemberSatisfied' the log recorded since
    -- the join's last terminal step, folded in log order
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | No context: a residual read without its run's log.
noContext :: MarkingContext
noContext = MkMarkingContext Map.empty Map.empty

-- | Read the context out of a directive's steps.
--
-- The arm count is a fold in step order, not a maximum: the machine zeroes
-- its own counter at every @registerCast@ (each time the @EVERY@ is
-- entered), so a barrier a @HENCE@ re-enters counts from one again, and the
-- context must forget the first activation's count when the second begins.
-- The step that marks the boundary is the join's own terminal — the one
-- logged with the join site as its 'nkSite' and no membership — since the
-- re-entry itself logs nothing.
contextOf :: [DeonticStep] -> MarkingContext
contextOf steps = MkMarkingContext
  { mcCasts = Map.fromList
      [ (k.nkSite, familyOf m) | s <- steps, Just k <- [s.dsNorm], Just m <- [k.nkMember] ]
  , mcDone = foldl' arm Map.empty steps
  }
  where
    arm done s = case s.dsNorm of
      Nothing -> done
      Just k -> case (k.nkMember, s.dsJoin) of
        (Just m, Just (MemberSatisfied n _)) -> Map.insert m.moJoinSite n done
        (Nothing, _) | joinTerminal s.dsOutcome -> Map.insert k.nkSite 0 done
        _ -> done
    -- the outcomes after which the barrier is gone and a re-entry starts
    -- over; every 'StepOutcome' is named, so a new join outcome must choose
    joinTerminal = \ case
      JoinReleased    -> True
      JoinExpired _ _ -> True
      JoinFailed _    -> True
      JoinStalled     -> True
      Waiting         -> False
      PartyMismatch   -> False
      ActionMismatch  -> False
      GuardFailed     -> False
      Matched _       -> False
      Expired _ _     -> False
      Breached _      -> False
      Joined _ _      -> False

-- | The marking of a residual: §4.2a's fold, total over 'Value'.
--
-- The shapes, in the spec's order: @FULFILLED@ marks nothing; a breach is
-- 'Violated'; an obligation is 'InEffect'; a compound is the union of its
-- operands' markings, except that an unentered operand is 'Created' and a
-- breached operand of an @ROR@ is 'Lapsed' (fact 1 in the spec: an @RAND@
-- never holds one, so the arm is @ROR@-only by construction). A quantified
-- obligation that has not been armed is 'Created'. Everything else is not
-- regulative and marks nothing.
--
-- Barrier members are recognised by the checkpoint sentinel in their
-- @HENCE@ ('L4.EvaluateLazy.Machine.joinCheckpointName') or by the context,
-- and contribute one 'Awaiting' per barrier, placed after the members.
markingOf :: LayoutPrinter a => MarkingContext -> Value a -> [NormPlacement]
markingOf ctx v0 = places <> joins
  where
    (places, barriers) = go v0

    -- the placements, and the join sites of every barrier member seen
    go :: LayoutPrinter a => Value a -> ([NormPlacement], [(Maybe SrcRange, Maybe Family)])
    go = \ case
      ValFulfilled -> ([], [])
      ValBreached r -> ([Violated (blameOf r)], [])
      ValObligation env party act due hence lest ->
        let raw = MkRawObligation {roEnv = env, roParty = party, roAction = act, roDue = due, roHence = hence, roLest = lest}
            live = renderLive ctx raw
            barrier
              | Just f <- live.lnMember, isBarrier f.faJoin = [(f.faJoinSite, live.lnMember)]
              | isCheckpoint hence                          = [(rangeOf act, Nothing)]
              | otherwise                                   = []
        in ([InEffect live], barrier)
      ValROp _ op l r -> operand op l <> operand op r
      ValQuantified _ deonton ->
        ([Created {crSite = rangeOf deonton, crSource = prettyLayout deonton}], [])
      _ -> ([], [])

    operand :: LayoutPrinter a => RBinOp -> Either RExpr (Value a) -> ([NormPlacement], [(Maybe SrcRange, Maybe Family)])
    operand _ (Left rexpr) = ([Created {crSite = rangeOf rexpr, crSource = prettyLayout rexpr}], [])
    operand ValROr (Right (ValBreached r)) = ([Lapsed (blameOf r)], [])
    operand _ (Right v) = go v

    -- one Awaiting per barrier, in first-seen order
    joins =
      [ Awaiting {awJoinSite = site, awProgress = progress member}
      | (site, member) <- nubOrdOn fst barriers ]
    -- exhaustive over 'JoinKind', as 'isBarrier' is: a new threshold-bearing
    -- join kind is a compile error here, not a silent 'Nothing' that prints
    -- as "progress unknown"
    progress family = do
      f <- family
      threshold <- case f.faJoin of
        Barrier th   -> Just th
        Fork         -> Nothing
        Distributive -> Nothing
      pure MkProgress
        { prDone = Map.findWithDefault 0 f.faJoinSite ctx.mcDone
        , prTotal = f.faTotal
        , prThreshold = threshold }

-- | The 'InEffect' reading of one obligation. 'markingOf' uses it for every
-- 'ValObligation' it meets, and "L4.Lts.WhatIf" uses it on the
-- 'RawObligation' a candidate is built from, so the 'LiveNorm' a candidate
-- carries is rendered from the same value the candidate's act is — not
-- paired up with the marking afterwards.
renderLive :: LayoutPrinter a => MarkingContext -> RawObligation a -> LiveNorm
renderLive ctx raw = MkLiveNorm
  { lnSite   = rangeOf raw.roAction
  , lnBearer = either (UnforcedParty . prettyLayout) (KnownParty . prettyLayout) raw.roParty
  , lnModal  = raw.roAction.modal
  , lnAction = prettyLayout raw.roAction.action
  , lnDue    = countdown raw.roDue
  , lnHence  = prettyLayout raw.roHence
  , lnLest   = prettyLayout <$> raw.roLest
  , lnMember = Map.lookup (rangeOf raw.roAction) ctx.mcCasts
  }
  where
    countdown = \ case
      Left Nothing         -> NoDeadline
      Left (Just e)        -> UnforcedDeadline (prettyLayout e)
      Right (ValNumber t)  -> Remaining t
      Right other          -> UnforcedDeadline (prettyLayout other)

-- | A 'ValObligation' as the residual holds it, unrendered, for a consumer
-- that needs the value and not its text — "L4.Lts.WhatIf" builds its
-- candidates from these. The walk is the same as 'markingOf''s: it yields
-- exactly the obligations that mark 'InEffect', in the same order.
data RawObligation a = MkRawObligation
  { roEnv    :: !Environment
  , roParty  :: !(Either RExpr (Value a))
  , roAction :: !(RAction Resolved)
  , roDue    :: !(Either (Maybe RExpr) (Value a))
  , roHence  :: !RExpr
  , roLest   :: !(Maybe RExpr)
  }

-- | The obligations in force, in marking order.
liveObligations :: Value a -> [RawObligation a]
liveObligations = \ case
  ValObligation env party act due hence lest ->
    [MkRawObligation {roEnv = env, roParty = party, roAction = act, roDue = due, roHence = hence, roLest = lest}]
  ValROp _ _ l r -> operand l <> operand r
  _ -> []
  where
    operand = either (const []) liveObligations

-- | The barrier checkpoint, as it stands in a member's @HENCE@ slot. The
-- machine mints it as a fresh name under 'L4.Annotation.emptyAnno'
-- (@startBarrier@, @barrierMember@), so it is the sentinel's name with NO
-- source range; a drafter's own @`the join`@ written as a @HENCE@ carries
-- the range it was parsed at, and is not one.
isCheckpoint :: RExpr -> Bool
isCheckpoint = \ case
  e@(Var _ r) -> rawName (getOriginal r) == NormalName joinCheckpointName && isNothing (rangeOf e)
  _           -> False

blameOf :: LayoutPrinter a => ReasonForBreach a -> Blame
blameOf = \ case
  DeadlineMissed evParty evAction stamp party act deadline -> MkBlame
    { blParty    = Just (prettyLayout party)
    , blAction   = Just (prettyLayout evAction)
    , blStamp    = Just stamp
    , blObliged  = Just (prettyLayout act)
    , blSite     = rangeOf act
    , blDeadline = Just deadline
    , blReason   = Just ("revealed by " <> prettyLayout evParty <> " doing " <> prettyLayout evAction)
    }
  ExplicitBreach mParty mReason -> MkBlame
    { blParty    = prettyLayout <$> mParty
    , blAction   = Nothing
    , blStamp    = Nothing
    , blObliged  = Nothing
    , blSite     = Nothing
    , blDeadline = Nothing
    , blReason   = prettyLayout <$> mReason
    }

-- | One line per place: the list §1.1a proposes as the picture's rival.
placementText :: NormPlacement -> Text
placementText = \ case
  Created {crSource} -> "created, not entered: " <> crSource
  InEffect n -> Text.unwords $
    [ "in effect:", bearerText n.lnBearer, modalText n.lnModal, n.lnAction ]
    <> dueText n.lnDue
    <> maybe [] (\ m -> ["(member of " <> familyText m <> ")"]) n.lnMember
  Violated b -> "violated: " <> blameText b
  Lapsed b -> "lapsed (alternative lost, compound stands): " <> blameText b
  Awaiting {awProgress} -> case awProgress of
    Nothing -> "continuation blocked at a barrier: progress unknown (run with the step log on)"
    Just p ->
      "continuation blocked: " <> textShow p.prDone <> " of " <> textShow p.prTotal
      <> " have acted" <> thresholdText p.prThreshold
  where
    bearerText = \ case
      KnownParty t    -> t
      UnforcedParty t -> t
    modalText = \ case
      DMust    -> "MUST"
      DMay     -> "MAY"
      DMustNot -> "SHANT"
      DDo      -> "DO"
    dueText = \ case
      NoDeadline         -> []
      UnforcedDeadline t -> ["WITHIN", t]
      Remaining r        -> ["WITHIN", prettyRatio r]
    familyText f = case f.faJoin of
      Barrier _    -> "a barrier of " <> textShow f.faTotal
      Fork         -> "a fork of " <> textShow f.faTotal
      Distributive -> "a cast of " <> textShow f.faTotal
    thresholdText = \ case
      AllHave _ -> " (ONCE ALL HAVE)"
    blameText b = Text.unwords $ catMaybes
      [ b.blParty
      , ("missed " <>) <$> b.blObliged
      , (\ d -> "due " <> prettyRatio d) <$> b.blDeadline
      , (\ t -> "at " <> prettyRatio t) <$> b.blStamp
      , ("because " <>) <$> b.blReason
      ]
