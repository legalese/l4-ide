{-# LANGUAGE PatternSynonyms #-}
-- | The enabled set and its discharging \/ breaching partition, in the
-- REPLAY form.
--
-- This is P2c of @specs/todo/lexipedia-superset/LTS-VISUALISER.md@, under
-- §2.4's ruling: anything counterfactual — what an event WOULD do — is
-- obtained by running the evaluator on the hypothetical, never by walking
-- the residual and re-deriving the machine's modal routing. So this module
-- contains no rule of the form "a @SHANT@ inverts polarity" or "a @MAY@
-- expiry routes to @LEST@"; it contains a way to append an event to a
-- @#TRACE@ and read what came back. It is @STATEFUL-CONTRACT-DEPLOYMENT@
-- §6.5's endpoints 22 (@what_if@) and 24 (@what_if_tick@), driven from
-- §6.4's endpoint 18 (the shapes to try), with 19\/20 as a classification
-- of 22's result rather than a projection of their own.
--
-- == What a candidate is
--
-- A candidate is read from the position's residual, which is data the
-- evaluator already computed:
--
-- * for every obligation in force, the act that is its own @(party, action)@
--   shape, stamped at the position's clock — the party as the machine
--   forced it, the action pattern instantiated ('patternExpr'); and
-- * for every distinct live deadline, a clock tick to just past it — a
--   @WAIT UNTIL@, the machine's own no-party event, stamped by 'tickPast'
--   so that no other live deadline lies between.
--
-- A shape the what-if cannot instantiate — an action pattern that BINDS a
-- variable (@pay amount@ with no @EXACTLY@), or one that NAMES a local the
-- residual holds unforced and the replay cannot resolve (@Receipt … amount@
-- in a @HENCE@ under @UPON EACH@, the member's @amount@ never having been
-- compared; a rule @GIVEN@ nothing has read yet), a party the machine
-- never forced and whose expression mentions a local it cannot read — is
-- still listed, as 'Left' with the reason. It is not silently dropped: an
-- enabled set that omitted it would say "nothing else can happen". The
-- second of those is told from a module-level name STATICALLY
-- ('openLocals'), before any replay: the replay evaluates the
-- hypothetical in the module's top-level environment, whose keys
-- 'position' records ('posReplayScope'), so a name the obligation closed
-- over that is not among them can only fail there — and until 2026-09-19
-- it did, surfacing the evaluator's own "Internal error: amount is not in
-- scope" as the reason (LTS-VISUALISER §7.3, every-each round 2 O2).
--
-- == Cost
--
-- One full replay per candidate: the module's top-level heap is rebuilt and
-- every prior event re-scrutinised before the hypothetical is. For a trace
-- of /n/ events and /k/ live obligations with /d/ distinct deadlines that
-- is /k + d/ evaluations of /n + 1/ events each. Nothing is cached across
-- candidates. This is what §2.4 accepts in exchange for having no second
-- semantics; R11 records what it says about @STATEFUL@ §6.4's promise.
module L4.Lts.WhatIf
  ( -- * The rig: a checked module and a @#TRACE@ in it
    Rig (..)
  , Trace (..)
  , tracesOf
    -- * The position: the trace as written, replayed
  , Position (..)
  , position
    -- * Hypotheticals
  , Hypothetical (..)
  , hypotheticalExpr
  , Candidate (..)
  , CandidateKind (..)
  , candidatesOf
  , tickPast
    -- * The replay
  , whatIf
  , tryCandidate
  , confirmTick
  , confirmAct
  , Verdict (..)
  , PassOver (..)
  , Outcome (..)
  , EnabledSet (..)
  , enabledSet
  , discharging
  , breaching
  , advancing
  , passedOver
  , untried
    -- * Instantiating a shape
  , patternExpr
  , closedAction
  , openLocals
  , reifyExpr
  , reifyNF
  ) where

import Base
import qualified Base.Map as Map
import qualified Base.Set as Set
import qualified Base.Text as Text
import qualified Optics

import L4.Annotation (emptyAnno)
import L4.Evaluate.ValueLazy hiding (Blame)
import L4.EvaluateLazy
  ( EvalConfig
  , EvalDirectiveResult (..)
  , EvalDirectiveValue (..)
  , EntityInfo
  , ReductionOutcome (..)
  , execEvalModuleWithDeonticLog
  , prettyEvalException
  , prettyRefusal
  )
import L4.EvaluateLazy.DeonticStep (DeonticStep (..), NormKey (..), StepOutcome (..))
import L4.EvaluateLazy.ContractFrame (Lifecycle (..))
import L4.EvaluateLazy.Machine (pattern ValFulfilled, anchorInstant, lifecycleOf)
import L4.Lts.Marking
import L4.Syntax
import qualified L4.TypeCheck as TypeCheck
import L4.Utils.Ratio (prettyRatio)

-- | Everything one replay needs.
data Rig = MkRig
  { rigConfig     :: !EvalConfig
  , rigEntityInfo :: !EntityInfo
  , rigEnv        :: !Environment
    -- ^ the base environment, as 'execEvalModuleWithEnv' takes it
  , rigModule     :: !(Module Resolved)
  }

-- | A @#TRACE c AT t WITH evs@ directive, as the module carries it.
data Trace = MkTrace
  { trDirective :: !(Directive Resolved)
    -- ^ the directive itself, which is how the replay finds it again
  , trContract  :: !(Expr Resolved)
  , trStart     :: !(Expr Resolved)
  , trEvents    :: ![Expr Resolved]
  }
  deriving stock (Eq, Show)

-- | Every @#TRACE@ in the module, in source order.
tracesOf :: Module Resolved -> [Trace]
tracesOf (MkModule _ _ section) = sectionTraces section
  where
    sectionTraces (MkSection _ _ _ _ decls) = concatMap declTraces decls
    declTraces = \ case
      Directive _ d@(Contract _ c t evs) ->
        [MkTrace {trDirective = d, trContract = c, trStart = t, trEvents = evs}]
      Section _ s -> sectionTraces s
      _ -> []

-- | The trace as written, replayed: the residual and its marking, the steps
-- the run logged, and the contract clock the residual is relative to.
data Position = MkPosition
  { posResult   :: !EvalDirectiveResult
  , posSteps    :: ![DeonticStep]
  , posResidual :: !(Maybe (Value NF))
    -- ^ 'Nothing' when the directive errored or refused
  , posContext  :: !MarkingContext
  , posMarking  :: ![NormPlacement]
  , posClock    :: !Rational
    -- ^ the stamp of the last event scrutinised (else the @AT@): the clock
    -- every 'Remaining' countdown in the marking counts from
  , posReplayScope :: !(Set Unique)
    -- ^ the names the replay resolves when it evaluates a hypothetical: the
    -- module's own top-level bindings, as the replay's own pass built them
    -- ('replay' returns that heap; only its keys are kept), and the
    -- imports' ('rigEnv'). Builtins are known by their sort and are not
    -- listed. A local an obligation closed over — a pattern-bound or
    -- @GIVEN@-bound name — is not among them, which is how 'openLocals'
    -- tells the two apart without a second resolver.
  }

-- | Replay the trace as written.
position :: Rig -> Trace -> IO (Maybe Position)
position rig tr = replay rig tr [] >>= pure . \ (topLevel, mres) -> flip fmap mres \ (res, steps) ->
  let ctx = contextOf steps
      residual = case res.result of
        Reduction (Reduced (MkNF v)) -> Just v
        _                            -> Nothing
      literalStamps = mapMaybe literalStamp (tr.trStart : tr.trEvents)
      loggedClocks  = mapMaybe (.dsClock) steps
  in MkPosition
      { posResult   = res
      , posSteps    = steps
      , posResidual = residual
      , posContext  = ctx
      , posMarking  = maybe [] (markingOf ctx) residual
      , posClock    = maximum (0 : literalStamps <> loggedClocks)
      , posReplayScope = Map.keysSet topLevel <> Map.keysSet rig.rigEnv
      }

-- | The stamp an authored event carries, when it is a literal: the @AT@ of
-- a @PARTY … DOES … AT n@, the argument of a @WAIT UNTIL n@, or a bare
-- number (the @AT@ itself).
literalStamp :: Expr Resolved -> Maybe Rational
literalStamp = \ case
  Lit _ (NumericLit _ r) -> Just r
  Event _ (MkEvent _ _ _ at _) -> literalStamp at
  App _ f [at] | getUnique f == TypeCheck.waitUntilUnique -> literalStamp at
  _ -> Nothing

-- | An event that has not happened.
data Hypothetical
  = Act
      { hyParty  :: !(Expr Resolved)
      , hyAction :: !(Expr Resolved)
      , hyAt     :: !Rational
      }
    -- ^ endpoint 22: @PARTY p DOES a AT t@
  | Tick { hyAt :: !Rational }
    -- ^ endpoint 24: nothing happens until @t@ — a @WAIT UNTIL t@
  deriving stock (Eq, Show)

-- | The hypothetical as an authored event would be, ready to append.
hypotheticalExpr :: Hypothetical -> Expr Resolved
hypotheticalExpr = \ case
  Act p a t -> Event emptyAnno (MkEvent emptyAnno p a (stamp t) False)
  Tick t    -> App emptyAnno TypeCheck.waitUntilRef [stamp t]
  where
    stamp t = Lit emptyAnno (NumericLit emptyAnno t)

-- | Where a candidate came from.
data CandidateKind
  = ActBy !LiveNorm
    -- ^ the act that is this obligation's own @(party, action)@ shape
  | TickPast !Rational ![LiveNorm]
    -- ^ a tick past this deadline (absolute, on the contract clock), and the
    -- obligations whose countdown ends there
  | NoTick !LiveNorm
    -- ^ this obligation's deadline could not be read — its @WITHIN@ was
    -- never evaluated and is not a literal — so no tick is offered for it;
    -- listed rather than dropped
  deriving stock (Eq, Show)

data Candidate = MkCandidate
  { cdKind         :: !CandidateKind
  , cdHypothetical :: !(Either Text Hypothetical)
    -- ^ 'Left' names why the shape could not be instantiated
  , cdShape        :: !(Maybe (Expr Resolved))
    -- ^ for an act, the action as far as the residual could instantiate it
    -- ('patternExpr' then 'reifyExpr'), kept for NAMING the candidate even
    -- when 'cdHypothetical' is 'Left' because a local in it is still open
    -- ('closedAction'): a refused @Receipt theLandlord t amount@ under a
    -- fork still says which member @t@ is. 'Nothing' when the pattern has no
    -- expression form at all (it binds, or is a list pattern), and for a
    -- tick.
  }
  deriving stock (Eq, Show)

-- | Read the candidates off the position. In 'IO' because instantiating an
-- @EXACTLY e@ reads the residual's heap ('reifyExpr').
--
-- Each candidate's 'LiveNorm' is rendered ('renderLive') from the very
-- 'RawObligation' its act is built from, so the label and the act cannot
-- come apart; the position's 'posMarking' is not consulted here.
candidatesOf :: Position -> IO [Candidate]
candidatesOf pos = case pos.posResidual of
  Nothing -> pure []
  Just residual -> do
    let raws   = liveObligations residual
        paired = [ (raw, renderLive pos.posContext raw) | raw <- raws ]
    acts <- for paired \ (raw, live) -> do
      party <- either (fmap Just . reifyExpr raw.roEnv) (reifyValue reifyNF) raw.roParty
      shape <- patternExpr raw.roEnv raw.roAction.action
      let hyp = do
            p <- maybe (Left "the party was never forced and could not be read back") Right party
            a <- shape >>= closedAction pos.posReplayScope raw.roEnv
            pure Act {hyParty = p, hyAction = a, hyAt = pos.posClock}
      pure MkCandidate {cdKind = ActBy live, cdHypothetical = hyp, cdShape = either (const Nothing) Just shape}
    dues <- for paired \ (raw, live) -> (live,) <$> deadlineOf pos.posClock raw
    let deadlines =
          Map.fromListWith (<>) [ (d, [live]) | (live, Right d) <- dues ]
        ticks =
          [ MkCandidate
              { cdKind = TickPast d (reverse ns)
              , cdHypothetical = Right (Tick (tickPast (Map.keys deadlines) d))
              , cdShape = Nothing }
          | (d, ns) <- Map.toList deadlines ]
        noTicks =
          [ MkCandidate {cdKind = NoTick live, cdHypothetical = Left why, cdShape = Nothing}
          | (live, Left why) <- dues ]
    pure (acts <> ticks <> noTicks)

-- | The absolute deadline of an obligation in force, on the contract clock.
--
-- A residual @WITHIN@ is a number once the obligation has scrutinised an
-- event (@Contract5@ rewrites it as @deadline - stamp@, relative to that
-- event, which is then the position's clock). One that has seen NO event
-- still holds its expression, anchored at its arming time — which is the
-- position's clock too: an obligation is armed either at the trace's @AT@
-- (and then there were no events, so the clock is the @AT@) or by the match
-- of an event (and an obligation armed by any event but the last would
-- have scrutinised the later ones). So both cases add to 'posClock'. That
-- is reasoning from the machine, checked on the fixtures (an unforced
-- @WITHIN@ appeared only in a fresh position and in a fork continuation
-- armed by the last event), not a proof. If it is wrong the tick lands
-- short of the real deadline by the gap and reveals nothing — which
-- 'confirmTick' turns into an 'Untried' naming this function, so the
-- failure is loud. The expression is read after 'reifyExpr'; if it is
-- still not a literal, the deadline is not known here and the reason says
-- so.
--
-- An ANCHORED unforced @WITHIN d OF …@ (R-Q7B\/C) is absolute: the anchor's
-- instant plus @d@, not the clock plus @d@. The anchor is read the way the
-- machine resolves it at @Contract4@, without re-deriving it (§2.4): a
-- lifecycle anchor is the binding the enclosing obligation's hand-off left
-- in this environment ('lifecycleOf', from the machine), THE ARMING with no
-- enclosing obligation being this obligation's own arming — the clock, by
-- the reasoning above; an @OF e@ is the value @e@ names; and either is
-- lowered by the machine's own 'anchorInstant'. An anchor that is not yet
-- forced, or a lifecycle position this hand-off does not have, leaves the
-- deadline unknown, and the reason says which.
--
-- The window's OPENING edge (@AFTER@, EVERY-EACH-QUANTIFIER-SPEC §5.1.2,
-- read here since 2026-09-17) moves the origin in two ways, both the
-- machine's: a residual due is REMAINING from the instant the @WITHIN@
-- runs from, which while the window has still to open is the opening, not
-- the clock (@relativeDue@ at @Contract5@; the residual's 'roOpens' then
-- holds the time still to run until it) — so the opening is added back
-- first, exactly as @Contract4@ does at the next scrutiny; and a bare
-- unforced @WITHIN@ beside an @AFTER@ re-anchors on the opening (§5.1.2.2,
-- R-X5 as amended), so its origin is the opening's instant — the
-- @AFTER@'s anchor (or the clock) plus its offset, read the same way the
-- closing edge's anchor is. An @AFTER@ whose offset is not a literal (a
-- date) leaves the deadline unknown, as an unforced @BEFORE@ does.
deadlineOf :: Rational -> RawObligation NF -> IO (Either Text Rational)
deadlineOf clock raw = case raw.roDue of
  Right (ValNumber r) -> pure $ case raw.roOpens of
    Right (Just (ValNumber untilOpen)) -> Right (clock + untilOpen + r)
    Right (Just other) -> Left ("the residual opening is not a number: " <> Text.pack (show other))
    _ -> Right (clock + r)
  Right other         -> pure (Left ("the residual deadline is not a number: " <> Text.pack (show other)))
  Left Nothing        -> pure (Left "no WITHIN: the obligation has no deadline to tick past")
  Left (Just (MkDeadline _ e anchor)) -> do
    duration <- reifyExpr raw.roEnv e >>= pure . \ case
      Lit _ (NumericLit _ r) -> Right r
      _ -> Left "the WITHIN was never evaluated and is not a literal, so its deadline is not known here"
    origin <- case anchor of
      Nothing -> openingInstant
      Just a  -> anchorOf a
    pure ((+) <$> origin <*> duration)
  -- a BEFORE date (EVERY-EACH-QUANTIFIER-SPEC §5.1.2, R-X5) is lowered by
  -- the machine at Contract5, from an application (@YMD …@), not a literal;
  -- an unforced one is not known here
  Left (Just (MkBefore _ _)) ->
    pure (Left "the BEFORE date was never evaluated, so its deadline is not known here")
  where
    lifecycle = lifecycleOf raw.roEnv
    -- what a bare WITHIN counts from: the window's opening when the act
    -- has one that is still to open, the clock otherwise
    openingInstant = case raw.roOpens of
      Left Nothing  -> pure (Right clock)
      Right Nothing -> pure (Right clock)
      Right (Just (ValNumber untilOpen)) -> pure (Right (clock + untilOpen))
      Right (Just other) -> pure (Left ("the residual opening is not a number: " <> Text.pack (show other)))
      Left (Just (MkOpening _ offset mAnchor)) -> do
        off <- reifyExpr raw.roEnv offset >>= pure . \ case
          Lit _ (NumericLit _ r) -> Right r
          _ -> Left "the AFTER was never evaluated and is not a literal (a date, or a computed offset), so its deadline is not known here"
        base <- maybe (pure (Right clock)) anchorOf mAnchor
        pure ((+) <$> base <*> off)
    anchorOf = \ case
      AnchorJoin _     -> lifecyclePosition "THE JOIN" (lifecycle >>= (.join))
      AnchorDeadline _ -> lifecyclePosition "THE DEADLINE" (lifecycle >>= (.deadline))
      AnchorArming _   -> maybe (pure (Right clock)) (lifecyclePosition "THE ARMING" . Just) ((.armed) <$> lifecycle)
      AnchorAt _ e     -> case e of
        Var _ r | Just rf <- Map.lookup (getUnique r) raw.roEnv -> instantOf "the anchor" rf
        _ -> reifyExpr raw.roEnv e >>= pure . \ case
          Lit _ (NumericLit _ r) -> Right r
          _ -> Left "the anchor of the WITHIN is not a literal, so its deadline is not known here"
    lifecyclePosition name = \ case
      Nothing -> pure (Left (name <> " names a position the enclosing obligation's hand-off did not have, so the deadline is not known here"))
      Just rf -> instantOf name rf
    instantOf name rf = readIORef rf.pointer >>= pure . \ case
      WHNF v           -> anchorInstant v
      WHNFWhen _ v _ _ -> anchorInstant v
      Unevaluated{}    -> Left (name <> " was never forced, so the deadline is not known here")

-- | The stamp that reveals the expiry of deadline @d@ and of no later one:
-- the machine expires on @stamp > deadline@, so a tick AT @d@ shows
-- nothing. One unit past @d@ (the corpus clock counts days), or half-way to
-- the next live deadline when that is nearer.
tickPast :: [Rational] -> Rational -> Rational
tickPast deadlines d = d + minimum (1 : [ (d' - d) / 2 | d' <- deadlines, d' > d ])

-- | What the evaluator said the hypothetical does. Only the machine's own
-- terminals are read: @FULFILLED@ discharges, @BREACHED@ breaches, and
-- anything else is the next position, with its marking — unless the
-- machine's own steps say no obligation took the act ('PassedOver').
data Verdict
  = Discharging
  | Breaching !Blame
  | Advancing ![NormPlacement]
  | PassedOver !PassOver
    -- ^ the replay reduced to a position, but the steps it caused are all
    -- pass-overs: nothing matched, expired or concluded a join. The
    -- position is the one we started from. See 'confirmAct'.
  | Untried !Text
    -- ^ the candidate could not be instantiated, or the replay errored or
    -- refused; the text says which
  deriving stock (Eq, Show)

-- | Why an act was passed over, as the machine's step for the candidate's
-- own obligation recorded it ('StepOutcome').
data PassOver
  = GuardFalse     -- ^ the act matched but its @PROVIDED@ came out false
  | TooEarly !Rational
    -- ^ the act matched but came before the window opened (@AFTER@,
    -- EVERY-EACH-QUANTIFIER-SPEC §5.1.2, R-X6): a nullity, the obligation
    -- stands; carries the instant the window opens
  | WrongAct       -- ^ not the act awaited
  | WrongParty     -- ^ not this party's to do
  | NoTaker
    -- ^ no step carried a pass-over reason at all: the log records no
    -- obligation matching, expiring or passing over this act. Listed, so
    -- that an act nobody took never reads as moving things along.
  deriving stock (Eq, Show)

data Outcome = MkOutcome
  { ocCandidate :: !Candidate
  , ocVerdict   :: !Verdict
  , ocSteps     :: ![DeonticStep]
    -- ^ the steps the hypothetical caused: those past the longest prefix
    -- the replay shares with the position's log ('afterCommonPrefix')
  }

-- | Endpoint 22 \/ 24: append the hypothetical and run.
whatIf :: Rig -> Trace -> Position -> Hypothetical -> IO (Verdict, [DeonticStep])
whatIf rig tr pos hyp = replay rig tr [hypotheticalExpr hyp] >>= pure . \ case
  (_, Nothing) -> (Untried "the replay produced no result", [])
  (_, Just (res, steps)) -> (classify (contextOf steps) res, afterCommonPrefix pos.posSteps steps)

-- | One candidate, tried: 'whatIf' on its hypothetical, with the tick's
-- stamp checked against what the machine did with it.
--
-- A 'TickPast' candidate's stamp is derived HERE ('deadlineOf', 'tickPast')
-- from the machine's timing rule — anchor plus @WITHIN@, expiry on a stamp
-- strictly past it — and §2.4 forbids trusting a derivation the evaluator
-- has not confirmed. So a tick is held to reveal an expiry: the steps it
-- caused must contain an 'Expired' or a 'JoinExpired'. If they do not, the
-- arithmetic disagreed with the machine (an anchor read from the wrong
-- clock would land the tick short by the gap) and the outcome is 'Untried'
-- saying so, rather than an 'Advancing' that looks like a genuine advance
-- and lets 'breaching' return @[]@ for a deadline that does breach.
tryCandidate :: Rig -> Trace -> Position -> Candidate -> IO Outcome
tryCandidate rig tr pos cand = case cand.cdHypothetical of
  Left why -> pure MkOutcome {ocCandidate = cand, ocVerdict = Untried why, ocSteps = []}
  Right hyp -> do
    (verdict, steps) <- whatIf rig tr pos hyp
    let verdict' = confirmAct cand.cdKind steps (confirmTick cand.cdKind hyp steps verdict)
    pure MkOutcome {ocCandidate = cand, ocVerdict = verdict', ocSteps = steps}

-- | The act's self-check; see 'tryCandidate'. The candidate set is read off
-- the residual before the guard is asked (spec §1.1b, G9: the shapes are an
-- over-approximation of what the contract accepts), so an act whose
-- @PROVIDED@ comes out false is a candidate, and the replay reports it as
-- 'Advancing' to a marking that is the position's own. That would read as
-- moving things along. So an 'ActBy' outcome is held to the steps it
-- caused: if none of them is a match, an expiry, a breach or a join
-- terminal — if every one is a pass-over — the verdict is 'PassedOver'
-- with the reason, read from the machine's steps rather than decided here.
--
-- Which step's reason: the candidate's own obligation is the one at the
-- candidate's site ('LiveNorm.lnSite' against 'NormKey.nkSite') with the
-- candidate's bearer ('LiveNorm.lnBearer' against 'NormKey.nkBearerName',
-- which the machine records in the same rendering where the party
-- comparison has forced the party's fields). The name is known on the
-- candidate's own pass-over step for a narrower reason than "the
-- comparison ran": the hypothetical act is BY the candidate's bearer, so
-- its own obligation's party comparison MATCHED, and a match forces every
-- field. A mismatch does not: the equality stops at the first field that
-- differs, so another member whose party differs from the actor's in an
-- earlier field is logged with no name on that step (measured,
-- @LtsListSpec@ case 7) — but that step is not the candidate's, and the
-- filter here only needs the candidate's own to be named.
-- Under an @RAND@\/@ROR@ the other side's obligation scrutinises the same
-- event and logs its own pass-over first, in the machine's order, so the
-- first reason in the log is the wrong norm's; the site tells them apart.
-- Under an @EVERY@ the members share a site and differ in bearer; the
-- bearer tells them apart. (Until the name was recorded, the members were
-- told apart by ranking the reasons at the site by specificity — a guard
-- that came out false could only be the candidate's own — which was a
-- heuristic standing in for a comparison the log could not make.)
--
-- A candidate whose party the residual holds unforced ('UnforcedParty')
-- has no rendered name to compare, and every step at its site is taken to
-- be its own: such an obligation is not an @EVERY@ member (the roll call
-- forces every member), so its site has one bearer. No step with the
-- bearer's name at the site falls back to the site's first reason in the
-- machine's order (not expected to happen: the name is recorded before
-- any pass-over that is not a party mismatch); no step at the site at all
-- falls back to the first reason in the log; no reason anywhere is
-- 'NoTaker'.
--
-- A 'Joined' step does not count as the act being taken: it is the
-- compound reporting where it stands after both sides looked, and under an
-- @ROR@ with nothing matched it says "still open" — which is exactly the
-- pass-over case. The join terminals ('JoinReleased', 'JoinExpired',
-- 'JoinFailed', 'JoinStalled') do count: they are the @EVERY@ join
-- concluding.
confirmAct :: CandidateKind -> [DeonticStep] -> Verdict -> Verdict
confirmAct kind steps verdict = case (kind, verdict) of
  (ActBy n, Advancing _) | not (any took steps) -> PassedOver (reasonFor n)
  _ -> verdict
  where
    took s = case s.dsOutcome of
      Matched _       -> True
      Expired _ _     -> True
      Breached _      -> True
      JoinReleased    -> True
      JoinExpired _ _ -> True
      JoinFailed _    -> True
      JoinStalled     -> True
      Joined _ _      -> False
      Waiting         -> False
      PartyMismatch   -> False
      ActionMismatch  -> False
      GuardFailed     -> False
      EarlyAct _      -> False
    reasonFor n =
      let atSite = [ (k, s) | s <- steps, Just k <- [s.dsNorm], k.nkSite == n.lnSite ]
          own = case n.lnBearer of
            KnownParty name -> [ s | (k, s) <- atSite, k.nkBearerName == Just name ]
            UnforcedParty _ -> map snd atSite
      in fromMaybe NoTaker (listToMaybe (mapMaybe reason own <> mapMaybe reason (map snd atSite) <> mapMaybe reason steps))
    reason s = case s.dsOutcome of
      GuardFailed    -> Just GuardFalse
      EarlyAct open  -> Just (TooEarly open)
      ActionMismatch -> Just WrongAct
      PartyMismatch  -> Just WrongParty
      _              -> Nothing

-- | The tick's self-check; see 'tryCandidate'. Only a 'TickPast' is held to
-- it; an act is the machine's to route however it likes.
confirmTick :: CandidateKind -> Hypothetical -> [DeonticStep] -> Verdict -> Verdict
confirmTick kind hyp steps verdict = case (kind, hyp) of
  (TickPast _ _, Tick _) | Untried _ <- verdict -> verdict   -- the replay already said why
  (TickPast d _, Tick t)
    | not (any revealsExpiry steps) -> Untried $
        "the tick to " <> prettyRatio t <> " past the deadline computed as " <> prettyRatio d
        <> " revealed no expiry: deadlineOf's arithmetic did not agree with the machine"
  _ -> verdict
  where
    revealsExpiry s = case s.dsOutcome of
      Expired _ _     -> True
      JoinExpired _ _ -> True
      Waiting         -> False
      PartyMismatch   -> False
      ActionMismatch  -> False
      GuardFailed     -> False
      EarlyAct _      -> False
      Matched _       -> False
      Breached _      -> False
      Joined _ _      -> False
      JoinReleased    -> False
      JoinFailed _    -> False
      JoinStalled     -> False

-- | The replay's steps past the position's: the two logs agree up to the
-- point where the hypothetical changes what the machine sees, and diverge
-- there (a @Waiting@ in the position becomes a match in the replay, say).
-- The replay is deterministic, so a prefix comparison finds that point.
afterCommonPrefix :: [DeonticStep] -> [DeonticStep] -> [DeonticStep]
afterCommonPrefix before after = drop (length (takeWhile id (zipWith (==) before after))) after

classify :: MarkingContext -> EvalDirectiveResult -> Verdict
classify ctx res = case res.result of
  Reduction (Reduced (MkNF v)) -> case v of
    ValFulfilled  -> Discharging
    ValBreached r -> Breaching (blameOf r)
    _             -> Advancing (markingOf ctx v)
  Reduction (Reduced Omitted)      -> Untried "the residual was omitted"
  Reduction (ReducedRefused ref)   -> Untried (Text.unlines (prettyRefusal ref))
  Reduction (ReducedErrored exc)   -> Untried (Text.unlines (prettyEvalException exc))
  Assertion _                      -> Untried "not a #TRACE"

-- | The enabled set: every candidate, tried.
data EnabledSet = MkEnabledSet
  { esPosition :: !Position
  , esOutcomes :: ![Outcome]
  }

enabledSet :: Rig -> Trace -> IO (Maybe EnabledSet)
enabledSet rig tr = position rig tr >>= \ case
  Nothing -> pure Nothing
  Just pos -> do
    cands <- candidatesOf pos
    outcomes <- for cands (tryCandidate rig tr pos)
    pure (Just MkEnabledSet {esPosition = pos, esOutcomes = outcomes})

-- | Endpoint 19: the candidates that lead to @FULFILLED@.
discharging :: EnabledSet -> [Outcome]
discharging es = [ o | o <- es.esOutcomes, Discharging <- [o.ocVerdict] ]

-- | Endpoint 20: the candidates that lead to @BREACHED@.
breaching :: EnabledSet -> [Outcome]
breaching es = [ o | o <- es.esOutcomes, Breaching _ <- [o.ocVerdict] ]

-- | The rest of endpoint 18: the candidates that lead to another position.
-- An act the steps say nobody took is not among them ('confirmAct'); it is
-- 'passedOver'.
advancing :: EnabledSet -> [Outcome]
advancing es = [ o | o <- es.esOutcomes, Advancing _ <- [o.ocVerdict] ]

-- | The acts the contract would not take: listed, tried, and passed over by
-- every obligation in force. The position does not change.
passedOver :: EnabledSet -> [Outcome]
passedOver es = [ o | o <- es.esOutcomes, PassedOver _ <- [o.ocVerdict] ]

-- | The shapes that were listed but could not be run.
untried :: EnabledSet -> [Outcome]
untried es = [ o | o <- es.esOutcomes, Untried _ <- [o.ocVerdict] ]

-- | Run the module with every directive dropped except this trace, which
-- gets the extra events appended. The directive is found by equality with
-- the one the module carries. Beside the result, the module's own top-level
-- heap as this run built it — the environment the hypothetical was
-- evaluated in, over 'rigEnv' and the builtins ('posReplayScope').
replay :: Rig -> Trace -> [Expr Resolved] -> IO (Environment, Maybe (EvalDirectiveResult, [DeonticStep]))
replay rig tr extra = do
  let MkModule a uri section = rig.rigModule
      m' = MkModule a uri (rewrite section)
  (topLevel, results) <- execEvalModuleWithDeonticLog rig.rigConfig rig.rigEntityInfo rig.rigEnv m'
  pure (topLevel, listToMaybe results)
  where
    rewrite (MkSection a n aka given decls) = MkSection a n aka given (mapMaybe keep decls)
    keep = \ case
      Directive a d
        | d == tr.trDirective, Contract ca c t evs <- d ->
            Just (Directive a (Contract ca c t (evs <> extra)))
        | otherwise -> Nothing
      Section a s -> Just (Section a (rewrite s))
      other -> Just other

-- | An action pattern as an event's action, if the pattern determines one.
-- A pattern that BINDS ('PatVar') does not: the what-if has no basis for
-- choosing the value, so the shape is reported and not tried. An
-- expression operand is read through the residual's heap ('reifyExpr');
-- whether what is left still names a local the replay cannot resolve is
-- 'closedAction''s question, asked by 'candidatesOf' on the whole
-- instantiated action, since a constructor pattern's operands are each
-- read here on their own.
patternExpr :: Environment -> Pattern Resolved -> IO (Either Text (Expr Resolved))
patternExpr env = \ case
  PatVar _ v -> pure (Left (cannotChoose (getOriginal v)))
  PatLit _ l -> pure (Right (Lit emptyAnno l))
  PatExpr _ e -> Right <$> reifyExpr env e
  PatApp _ con ps -> do
    args <- traverse (patternExpr env) ps
    pure (App emptyAnno con <$> sequence args)
  PatCons _ _ _ -> pure (Left "the action is a list pattern, which the what-if does not instantiate")

-- | The one refusal wording for a name the what-if would have to supply
-- and cannot: the pattern's own variable ('PatVar'), or a local the
-- residual holds unforced ('openLocals'). The same sentence for both,
-- because to the reader they are the same fact — the event must carry the
-- value and the list has no basis for picking one — and because the list's
-- consumers key on it (`etc/lts-reader-proxy/RESULTS.md` §3.1).
--
-- The name is spelled as the rule wrote it, without its section. A local
-- declared under a @§@ — a @WHERE@'s @y@ — resolves to a section-qualified
-- name, and until 2026-09-19 the refusal printed that (\`inner.y\`) beside
-- an action printed by 'prettyLayout' as @pay OF (y PLUS 1)@, so the two
-- halves of one line spelled one name two ways.
cannotChoose :: Name -> Text
cannotChoose v = "the action binds `" <> unqualifiedNameToText v <> "`, which the what-if cannot choose"

-- | An instantiated action the replay can evaluate, or the reason it
-- cannot: the first local it still names that the residual holds unforced
-- and the replay's scope does not resolve. Asked BEFORE the replay, so the
-- refusal is the what-if's own sentence and never the evaluator's
-- "Internal error: amount is not in scope" (which is what a replay of such
-- an action produced until 2026-09-19).
closedAction :: Set Unique -> Environment -> Expr Resolved -> Either Text (Expr Resolved)
closedAction scope env e = case openLocals scope env e of
  (v : _) -> Left (cannotChoose v)
  []      -> Right e

-- | The names in an expression that the replay cannot resolve and the
-- residual cannot supply: each @Var@ whose unique the obligation's
-- environment holds — a local it closed over, still there after
-- 'reifyExpr' because it is unforced or unspellable — and that is neither
-- a module top-level name nor an import (the replay's scope,
-- 'posReplayScope') nor a builtin (sort @\'b\'@, minted by
-- "L4.TypeCheck.Environment.TH"). In source order, once per occurrence.
--
-- A @Var@ the environment does NOT hold is left alone: it is bound inside
-- the expression itself (a @WHERE@ local, a lambda's input), or it is
-- genuinely broken — and a genuinely broken one must reach the replay and
-- fail there, loudly, as 'Untried' with the evaluator's own message. This
-- function narrows only the case it can name with confidence.
openLocals :: Set Unique -> Environment -> Expr Resolved -> [Name]
openLocals scope env e =
  [ getOriginal r
  | Var _ r <- Optics.toListOf (Optics.cosmosOf (Optics.gplate @(Expr Resolved))) e
  , let u = getUnique r
  , Map.member u env
  , u.sort /= 'b'
  , not (Set.member u scope)
  ]

-- | Substitute what the residual's heap has already forced. A @Var@ bound
-- in the obligation's environment to a forced value becomes that value's
-- literal form ('reifyRef'), so an @EXACTLY t@ under an @EVERY@ names the
-- member; anything unforced, or not a value this can spell, is left as
-- written and resolves — or fails, loudly, as 'Untried' — when the replay
-- evaluates it in the module's environment ('closedAction' catches the
-- unforced-local case first). Every @Var@ in the expression is visited,
-- under any operator: until 2026-09-19 only the arguments of an @App@ were,
-- so @Deliver Tenant (p's landlord) what@ kept its @p@ under the projection
-- unread even when the residual had forced it, and the replay then failed
-- on a name it could have been handed as a literal (measured:
-- @ok/regulative-reference-expressions.l4@'s @projection operand@, one
-- mismatched event in, listed "Internal error: p is not in scope" before
-- and discharging after).
reifyExpr :: Environment -> Expr Resolved -> IO (Expr Resolved)
reifyExpr env = Optics.transformMOf (Optics.gplate @(Expr Resolved)) \ case
  Var a r -> case Map.lookup (getUnique r) env of
    Just rf -> fromMaybe (Var a r) <$> reifyRef rf
    Nothing -> pure (Var a r)
  other -> pure other

-- | A forced reference, spelled as an expression; 'Nothing' if it is not
-- forced, or not spellable.
reifyRef :: Reference -> IO (Maybe (Expr Resolved))
reifyRef rf = readIORef rf.pointer >>= \ case
  WHNF v           -> reifyValue reifyRef v
  WHNFWhen _ v _ _ -> reifyValue reifyRef v
  Unevaluated{}    -> pure Nothing

-- | A normal form, spelled as an expression.
reifyNF :: NF -> IO (Maybe (Expr Resolved))
reifyNF = \ case
  Omitted -> pure Nothing
  MkNF v  -> reifyValue reifyNF v

-- | The value shapes an event can carry: numbers, strings, constructors
-- (nullary ones as @App c []@, the machine's own spelling for a sentinel
-- party) and lists. A closure, a date or a builtin has no literal form.
reifyValue :: (a -> IO (Maybe (Expr Resolved))) -> Value a -> IO (Maybe (Expr Resolved))
reifyValue sub = \ case
  ValNumber r -> pure (Just (Lit emptyAnno (NumericLit emptyAnno r)))
  ValString s -> pure (Just (Lit emptyAnno (StringLit emptyAnno s)))
  ValNil -> pure (Just (List emptyAnno []))
  ValCons x xs -> do
    mx  <- sub x
    mxs <- sub xs
    pure do
      x'  <- mx
      xs' <- mxs
      case xs' of
        List a es -> Just (List a (x' : es))
        _         -> Nothing
  ValConstructor r args -> fmap (App emptyAnno r) . sequence <$> traverse sub args
  ValUnappliedConstructor r -> pure (Just (App emptyAnno r []))
  _ -> pure Nothing
