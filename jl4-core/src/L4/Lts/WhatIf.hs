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
-- variable (@pay amount@ with no @EXACTLY@), a party the machine never
-- forced and whose expression mentions a local it cannot read — is still
-- listed, as 'Left' with the reason. It is not silently dropped: an
-- enabled set that omitted it would say "nothing else can happen".
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
  , Verdict (..)
  , Outcome (..)
  , EnabledSet (..)
  , enabledSet
  , discharging
  , breaching
  , advancing
  , untried
    -- * Instantiating a shape
  , patternExpr
  , reifyExpr
  , reifyNF
  ) where

import Base
import qualified Base.Map as Map
import qualified Base.Text as Text

import L4.Annotation (emptyAnno)
import L4.Evaluate.ValueLazy
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
import L4.EvaluateLazy.DeonticStep (DeonticStep (..))
import L4.EvaluateLazy.Machine (pattern ValFulfilled)
import L4.Lts.Marking
import L4.Syntax
import qualified L4.TypeCheck as TypeCheck

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
  }

-- | Replay the trace as written.
position :: Rig -> Trace -> IO (Maybe Position)
position rig tr = replay rig tr [] >>= pure . fmap \ (res, steps) ->
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
  }
  deriving stock (Eq, Show)

-- | Read the candidates off the position. In 'IO' because instantiating an
-- @EXACTLY e@ reads the residual's heap ('reifyExpr').
candidatesOf :: Position -> IO [Candidate]
candidatesOf pos = case pos.posResidual of
  Nothing -> pure []
  Just residual -> do
    let raws  = liveObligations residual
        lives = [ n | InEffect n <- pos.posMarking ]
        -- liveObligations and markingOf walk the value in the same order
        paired = zip raws lives
    acts <- for paired \ (raw, live) -> do
      party <- either (fmap Just . reifyExpr raw.roEnv) (reifyValue reifyNF) raw.roParty
      action <- patternExpr raw.roEnv raw.roAction.action
      let hyp = do
            p <- maybe (Left "the party was never forced and could not be read back") Right party
            a <- action
            pure Act {hyParty = p, hyAction = a, hyAt = pos.posClock}
      pure MkCandidate {cdKind = ActBy live, cdHypothetical = hyp}
    dues <- for paired \ (raw, live) -> (live,) <$> deadlineOf pos.posClock raw
    let deadlines =
          Map.fromListWith (<>) [ (d, [live]) | (live, Right d) <- dues ]
        ticks =
          [ MkCandidate
              { cdKind = TickPast d (reverse ns)
              , cdHypothetical = Right (Tick (tickPast (Map.keys deadlines) d)) }
          | (d, ns) <- Map.toList deadlines ]
        noTicks =
          [ MkCandidate {cdKind = NoTick live, cdHypothetical = Left why}
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
-- armed by the last event), not a proof; if it fails the tick is late by
-- the gap, silently. The expression is read after 'reifyExpr'; if it is
-- still not a literal, the deadline is not known here and the reason says
-- so.
deadlineOf :: Rational -> RawObligation NF -> IO (Either Text Rational)
deadlineOf clock raw = case raw.roDue of
  Right (ValNumber r) -> pure (Right (clock + r))
  Right other         -> pure (Left ("the residual deadline is not a number: " <> Text.pack (show other)))
  Left Nothing        -> pure (Left "no WITHIN: the obligation has no deadline to tick past")
  Left (Just e)       -> reifyExpr raw.roEnv e >>= pure . \ case
    Lit _ (NumericLit _ r) -> Right (clock + r)
    _ -> Left "the WITHIN was never evaluated and is not a literal, so its deadline is not known here"

-- | The stamp that reveals the expiry of deadline @d@ and of no later one:
-- the machine expires on @stamp > deadline@, so a tick AT @d@ shows
-- nothing. One unit past @d@ (the corpus clock counts days), or half-way to
-- the next live deadline when that is nearer.
tickPast :: [Rational] -> Rational -> Rational
tickPast deadlines d = d + minimum (1 : [ (d' - d) / 2 | d' <- deadlines, d' > d ])

-- | What the evaluator said the hypothetical does. Only the machine's own
-- terminals are read: @FULFILLED@ discharges, @BREACHED@ breaches, and
-- anything else is the next position, with its marking.
data Verdict
  = Discharging
  | Breaching !Blame
  | Advancing ![NormPlacement]
  | Untried !Text
    -- ^ the candidate could not be instantiated, or the replay errored or
    -- refused; the text says which
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
  Nothing -> (Untried "the replay produced no result", [])
  Just (res, steps) -> (classify (contextOf steps) res, afterCommonPrefix pos.posSteps steps)

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
    outcomes <- for cands \ cand -> case cand.cdHypothetical of
      Left why -> pure MkOutcome {ocCandidate = cand, ocVerdict = Untried why, ocSteps = []}
      Right hyp -> do
        (verdict, steps) <- whatIf rig tr pos hyp
        pure MkOutcome {ocCandidate = cand, ocVerdict = verdict, ocSteps = steps}
    pure (Just MkEnabledSet {esPosition = pos, esOutcomes = outcomes})

-- | Endpoint 19: the candidates that lead to @FULFILLED@.
discharging :: EnabledSet -> [Outcome]
discharging es = [ o | o <- es.esOutcomes, Discharging <- [o.ocVerdict] ]

-- | Endpoint 20: the candidates that lead to @BREACHED@.
breaching :: EnabledSet -> [Outcome]
breaching es = [ o | o <- es.esOutcomes, Breaching _ <- [o.ocVerdict] ]

-- | The rest of endpoint 18: the candidates that lead to another position.
advancing :: EnabledSet -> [Outcome]
advancing es = [ o | o <- es.esOutcomes, Advancing _ <- [o.ocVerdict] ]

-- | The shapes that were listed but could not be run.
untried :: EnabledSet -> [Outcome]
untried es = [ o | o <- es.esOutcomes, Untried _ <- [o.ocVerdict] ]

-- | Run the module with every directive dropped except this trace, which
-- gets the extra events appended. The directive is found by equality with
-- the one the module carries.
replay :: Rig -> Trace -> [Expr Resolved] -> IO (Maybe (EvalDirectiveResult, [DeonticStep]))
replay rig tr extra = do
  let MkModule a uri section = rig.rigModule
      m' = MkModule a uri (rewrite section)
  (_, results) <- execEvalModuleWithDeonticLog rig.rigConfig rig.rigEntityInfo rig.rigEnv m'
  pure (listToMaybe results)
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
-- choosing the value, so the shape is reported and not tried.
patternExpr :: Environment -> Pattern Resolved -> IO (Either Text (Expr Resolved))
patternExpr env = \ case
  PatVar _ v -> pure (Left ("the action binds `" <> nameToText (getOriginal v) <> "`, which the what-if cannot choose"))
  PatLit _ l -> pure (Right (Lit emptyAnno l))
  PatExpr _ e -> Right <$> reifyExpr env e
  PatApp _ con ps -> do
    args <- traverse (patternExpr env) ps
    pure (App emptyAnno con <$> sequence args)
  PatCons _ _ _ -> pure (Left "the action is a list pattern, which the what-if does not instantiate")

-- | Substitute what the residual's heap has already forced. A @Var@ bound
-- in the obligation's environment to a forced value becomes that value's
-- literal form ('reifyRef'), so an @EXACTLY t@ under an @EVERY@ names the
-- member; anything unforced, or not a value this can spell, is left as
-- written and resolves — or fails, loudly, as 'Untried' — when the replay
-- evaluates it in the module's environment.
reifyExpr :: Environment -> Expr Resolved -> IO (Expr Resolved)
reifyExpr env = \ case
  Var a r -> case Map.lookup (getUnique r) env of
    Just rf -> fromMaybe (Var a r) <$> reifyRef rf
    Nothing -> pure (Var a r)
  App a f args -> App a f <$> traverse (reifyExpr env) args
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
