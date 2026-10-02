{-# LANGUAGE GADTs #-}
module L4.EvaluateLazy
( EvalConfig(..)
, AllocationLimit(..)
, resolveEvalConfig
, resolveEvalConfigWithSafeMode
, parseFixedNow
, readFixedNowEnv
, EvalDirectiveResult (..)
, EvalDirectiveValue(..)
, AssertionOutcome(..)
, ReductionOutcome(..)
, EntityInfo
, getTemporalContext
, setTemporalContext
, withEvalClauses
, execEvalModuleWithEnv
, execEvalModuleWithEnvAndImports
, execEvalModuleWithDeonticLog
, captureDeonticSteps
, execEvalModuleWithJSON
, execEvalExprInContextOfModule
, execEvalExprInContextOfModuleWith
, RootFills
, Presumed (..)
, PresumedOrigin (..)
, renderPresumedPath
, requestPresumed
, moduleDeclares
, prettyEvalException
, prettyRefusal
, Refusal(..)
, prettyEvalDirectiveResult
, prettyEvalDirectiveResultWithFields
, prettyNotes
, prettyAssertionOutcome
, prettyReductionOutcome
, prettyUndetermined
, undeterminedJson
, postprocessTrace
, safePostprocessTrace
, tracePostprocessFailed
, prettyLedger
  -- * Ledger substrate (M0). Exposed for the test suite; not part of the
  -- stable public API.
, Eval
, tellEvent
, currentLedger
, currentStore
, runEvalAction
, evalExprForLedger
, evalExprForLedgerWithEnv
, moduleEnvForLedger
)
where

import Base
import L4.Discharge (dischargeModuleWith, sectionBinders, Binder (..))
import qualified Base.DList as DList
import qualified Base.Map as Map
import qualified Base.Set as Set
import qualified Data.IntMap.Strict as IntMap
import qualified Base.Text as Text
import L4.EvaluateLazy.Machine
import L4.EvaluateLazy.DeonticStep (DeonticLog (..), DeonticStep, newDeonticLog)
import L4.EvaluateLazy.Trace
import L4.Evaluate.Ledger
  ( EventRoute (..)
  , Ledger
  , LedgerEvent (..)
  , LedgerStore (..)
  , Path
  , Provenance (..)
  , emptyStore
  )
import L4.Evaluate.ValueLazy
import L4.Evaluate.ValueLazyJSON () -- ToJSON instances for NF/Value/ReasonForBreach (batch --json)
import L4.Parser.SrcSpan (SrcRange)
import L4.Annotation
import L4.Print
import L4.Syntax
import L4.TypeCheck.Types (EntityInfo)
import L4.TemporalContext (EvalClause, TemporalContext, applyEvalClauses, initialTemporalContext, noReads)
import L4.TracePolicy (TracePolicy)

import Control.Exception (throwIO, try, evaluate, finally, catch, ErrorCall)
import GHC.IO.Exception (AllocationLimitExceeded (..))
import Data.Int (Int64)
import GHC.Conc (setAllocationCounter, enableAllocationLimit, disableAllocationLimit)
import Data.Time (UTCTime, getCurrentTime)
import qualified Data.Time.Format.ISO8601 as ISO8601
import System.Environment (lookupEnv)
import qualified Data.Aeson as Aeson

-----------------------------------------------------------------------------
-- Configuration for running evaluations.
--
-- The Eval monad itself (and the machine state) lives in
-- 'L4.EvaluateLazy.Machine'; this module provides the high-level driver.
-----------------------------------------------------------------------------

data EvalConfig = EvalConfig
  { evalTime :: !(Maybe UTCTime)
    -- ^ 'Nothing' means use the wall-clock at each evaluation (live mode).
    -- 'Just t' means use a fixed time (for tests / JL4_FIXED_NOW).
  , tracePolicy :: !TracePolicy
  , safeMode :: !Bool  -- ^ When True, HTTP operations (FETCH/POST) return errors instead of making requests
  , requestRecord :: !(Maybe Text)
    -- ^ The record type a wrapper decodes the request's arguments into, when
    -- the evaluation has a request (@l4 batch@, the service's wrapper path):
    -- 'L4.Presumption.requestRecordName'. 'Nothing' for @#EVAL@ and @l4 run@,
    -- where every decode is the rules' own. See 'presumeDefaults'.
  , presumeDefaults :: !Bool
    -- ^ T4's presumption switch (TYPICALLY-ONE-BEHAVIOUR-SPEC.md §5), on by
    -- default. Off (\"hard\"): a @TYPICALLY@ default is not used where a
    -- value could be supplied, so a section @GIVEN@ that nothing supplies is
    -- an assumed term and an absent JSON field is a missing one. On
    -- (\"soft\"): defaults apply. @null@ never takes a default either way.
    --
    -- The switch withdraws a default only where a request can supply its
    -- value (T4b): a section @GIVEN@ at the root, and a field of the request's
    -- own decode ('requestRecord'). A decode the rules make of their own
    -- always fills its defaults.
  , allocationLimit :: !(Maybe AllocationLimit)
    -- ^ A cap on what one evaluation may allocate, counted on the thread that
    -- runs it. 'Nothing' (the default) sets none. A caller that evaluates
    -- through a build system (jl4-service's wrapper path, which runs the
    -- module as a Shake rule) must say so here, because GHC's allocation
    -- counter belongs to a thread and the rule runs on another one than the
    -- caller's: a limit set on the caller never sees it.
  }

-- | A cap, in bytes, on what an evaluation may allocate.
-- Exceeding it raises 'AllocationLimitExceeded' out of the evaluation, and
-- sets 'exceeded' first: a build system catches the exception on its own
-- thread and reports it as a diagnostic, so the caller reads the flag to
-- learn that it was this limit.
data AllocationLimit = MkAllocationLimit
  { bytes :: !Int64
  , exceeded :: !(IORef Bool)
  }

resolveEvalConfig :: Maybe UTCTime -> TracePolicy -> IO EvalConfig
resolveEvalConfig mTime tracePolicy = resolveEvalConfigWithSafeMode mTime tracePolicy False

resolveEvalConfigWithSafeMode :: Maybe UTCTime -> TracePolicy -> Bool -> IO EvalConfig
resolveEvalConfigWithSafeMode mTime tracePolicy safe =
  pure (EvalConfig mTime tracePolicy safe Nothing True Nothing)

-- | Resolve the eval time: use the fixed time if set, otherwise get the wall clock.
resolveEvalTime :: EvalConfig -> IO UTCTime
resolveEvalTime cfg = case cfg.evalTime of
  Just t  -> pure t
  Nothing -> getCurrentTime

parseFixedNow :: Text -> Maybe UTCTime
parseFixedNow = ISO8601.iso8601ParseM . Text.unpack

readFixedNowEnv :: IO (Maybe UTCTime)
readFixedNowEnv = do
  menv <- lookupEnv "JL4_FIXED_NOW"
  pure $ menv >>= parseFixedNow . Text.pack

-- | The previous temporal context is restored afterwards.
setTemporalContext :: TemporalContext -> Eval ()
setTemporalContext = putTemporalContext

-----------------------------------------------------------------------------
-- STATE-AS-LEDGER: test seams over the ledger ops defined in
-- 'L4.EvaluateLazy.Machine'. The real ledger logic lives in Machine.hs (so the
-- backward frame arms can reach it without an import cycle); these thin
-- wrappers keep the historical names the test suite imports.
-----------------------------------------------------------------------------

-- | Append an event to the acting party's own ledger (a @RECORD@). Kept for the
-- test seam and any caller that knows it wants the own ledger.
tellEvent :: LedgerEvent -> Eval ()
tellEvent = tellEventRouted RouteOwn

-- | Read the current ledger as seen by a @RECALL@ (the current party's own log).
-- Retained name for the test suite / public API.
currentLedger :: Eval Ledger
currentLedger = currentLedgerEval

-- | Read the whole per-party store (own ledgers + official record). Used by
-- 'nfDirective' to capture the full state and by the test suite.
currentStore :: Eval LedgerStore
currentStore = readEvalRef (.envLedger)

-- | Run an action with a freshly-empty ledger, restoring the caller's ledger
-- afterwards. This is what guarantees ledger isolation between top-level
-- directives: each #EVAL / #ASSERT / #TRACE evaluates against its own empty
-- event log, so assignments cannot leak from one directive into the next.
--
-- We follow the same save/swap/restore idiom as 'captureTrace' and
-- 'withEvalClauses': swap in a fresh IORef via 'local' for the duration of the
-- action. Because we hand the action a brand-new IORef, the caller's ledger is
-- left completely untouched, even on exceptions.
withFreshLedger :: Eval a -> Eval a
withFreshLedger m = do
  fresh      <- liftIO (newIORef emptyStore)
  freshParty <- liftIO (newIORef Nothing)
  freshNotes <- liftIO (newIORef mempty)
  freshPresumed <- liftIO (newIORef emptyPresumedLog)
  -- the run's notes ('tellNote') are per directive for the same reason the
  -- ledger is: a note belongs to the directive whose value it qualifies; so
  -- does a default it forced ('EvalState.presumed')
  local (\s -> s { envLedger = fresh, currentParty = freshParty, notes = freshNotes, presumed = freshPresumed }) m

-- | Apply runtime EVAL clauses for the duration of an action,
-- restoring the previous temporal context afterwards.
withEvalClauses :: [EvalClause] -> Eval a -> Eval a
withEvalClauses clauses action = do
  original <- getTemporalContext
  setTemporalContext (applyEvalClauses clauses original)
  result <- tryEval action
  setTemporalContext original
  either (liftIO . throwIO) pure result

-- | For the given eval action, enable tracing and accumulate a trace.
--
-- We try to make it so that in principle, nested calls to `captureTrace`
-- will yield the correct result.
--
captureTrace :: Eval a -> Eval (a, [EvalTraceAction])
captureTrace m = do
  mtr <- asks (.evalTrace) -- save old state
  ntr <- liftIO (newIORef mempty)
  r <- local (\ s -> s { evalTrace = Just ntr }) m
  tas <- liftIO (readIORef ntr)
  combine mtr tas -- combine our trace with old trace if it was active
  pure (r, toList tas)
  where
    combine :: Maybe (IORef (DList EvalTraceAction)) -> DList EvalTraceAction -> Eval ()
    combine Nothing   _   = pure ()
    combine (Just tr) tas = liftIO (modifyIORef' tr (<> tas))

-- | LTS-VISUALISER §4.3 (P2b): run an action with the deontic step log ON,
-- and return the steps it logged, oldest-first.
--
-- Modelled on 'captureTrace', with one deliberate difference: a nested
-- capture gets a FRESH log and does not merge into the enclosing one. The
-- log carries per-site activation counters and an @EVERY@ cast register
-- beside the steps, and two captures sharing those would number the same
-- site twice. Nothing nests captures today; if something must, it should
-- capture once at the outermost directive.
captureDeonticSteps :: Eval a -> Eval (a, [DeonticStep])
captureDeonticSteps m = do
  l <- liftIO newDeonticLog
  r <- local (\ s -> s { deonticLog = Just l }) m
  steps <- liftIO (readIORef l.dlSteps)
  pure (r, toList steps)

runConfig :: Config -> Eval WHNF
runConfig = \ case
  DoneMachine whnf ->
    pure whnf
  config -> do
    -- UNKNOWN-EVALUATION-SPEC §4.5: every step counts once the counter has
    -- started, and none before
    tickUnknownSteps
    runConfigStep config

runConfigStep :: Config -> Eval WHNF
runConfigStep = \ case
  ForwardMachine env expr -> do
    traceEval (Enter expr)
    next <- forwardExpr env expr
    runConfig next
  MatchBranchesMachine clauses scrutinee env branches -> do
    next <- matchBranches clauses scrutinee env branches
    runConfig next
  MatchPatternMachine r env pat -> do
    next <- matchPattern r env pat
    runConfig next
  BackwardMachine whnf -> do
    traceEval (Exit (Right whnf))
    next <- backward whnf
    runConfig next
  EvalRefMachine r -> do
    -- W8: a default being forced for the first time is an event of its own,
    -- and it comes before the force it belongs to, in the caller's trace
    traceDefaultForce r
    traceEval (SetRef r)
    next <- evalRef r
    runConfig next
  DoneMachine whnf ->
    pure whnf

-- | Evaluate an EVAL directive. For this, we evaluate to normal form,
-- not just WHNF.
nfDirective :: EvalDirective -> Eval EvalDirectiveResult
nfDirective d = fst <$> nfDirectiveWith False d

-- | 'nfDirective', optionally with the deontic step log captured for the
-- directive (P2b). The log is switched on around the evaluation only — the
-- normal-form pass runs inside it too, because forcing the residual can run
-- nothing regulative — and it is off again before the ledger is snapshotted.
-- With the flag off this IS 'nfDirective': the same code path, an empty list.
nfDirectiveWith :: Bool -> EvalDirective -> Eval (EvalDirectiveResult, [DeonticStep])
nfDirectiveWith withSteps (MkEvalDirective r traced assertKind expr env) = withFreshLedger $ do
  -- T6: open a fresh, directive-local context-read span. (Exceptional
  -- unwinding closes spans as it pops UpdateThunk frames — see
  -- 'unwindFrame' — but a successful directive legitimately leaves its own
  -- reads in the root accumulator; spans are directive-local, so clear it.)
  _ <- swapCtxReads noReads
  -- UNKNOWN-EVALUATION-SPEC §4.5 (C4): the step counter starts afresh, and
  -- stopped, for every directive.
  resetUnknownSteps
  -- Snapshot the ambient temporal context and restore it unconditionally
  -- after the directive. 'unwindFrame' already restores saved contexts
  -- frame by frame during exceptional unwinding; this directive boundary is
  -- the belt-and-braces layer guaranteeing that no temporal override active
  -- during THIS directive can leak into subsequent directives, whatever the
  -- unwind path.
  ambientCtx <- getTemporalContext
  ((v, mt), steps) <- captureSteps $
    if traced
      then second Just <$> do
        captureTrace $ tryEval $ do
          whnf <- runConfig $ ForwardMachine env expr
          nf whnf
      else fmap (, Nothing) $ tryEval $ do
        whnf <- runConfig $ ForwardMachine env expr
        nf whnf
  -- T6: restore the ambient temporal context unconditionally after the
  -- directive (belt-and-braces; independent of the ledger/trace snapshots below).
  putTemporalContext ambientCtx
  finalTrace <- case mt of
    Nothing      -> pure Nothing
    Just actions -> Just <$> liftIO (safePostprocessTrace actions)
  -- STATE-AS-LEDGER M2/M4: snapshot the per-directive ledger STORE (per-party
  -- own ledgers + the official record) BEFORE 'withFreshLedger' restores the
  -- caller's (empty) store and discards this one. This is the directive's whole
  -- event log — the RECORD 'Assign's per party plus the COMMIT/ATTEST 'Assign's
  -- in the official record. D5 (keep-on-breach) falls out for free: 'tellEvent'
  -- is an append and 'ValBreached' does not roll back, so any pre-breach
  -- 'Assign' is already in here.
  directiveLedger <- currentStore
  -- likewise the notes the run raised while producing this value (R-X6's
  -- early act, the empty window): read before the fresh ref is discarded
  directiveNotes <- map (\ (MkNote t) -> t) . toList <$> readEvalRef (.notes)
  -- and the defaults it forced (W8's event), for the same reason
  directivePresumed <- presumedEvents <$> readEvalRef (.presumed)
  reached <- reachedUnknowns
  let
    -- What a directive that could not be decided waits on
    -- (UNKNOWN-EVALUATION-SPEC §4.7.4, build step 3): a 'Stuck' names it,
    -- and running out of steps names every input that reached a §4.3 site.
    stuckOnExc = \ case
      UserEvalException (Stuck ns)    -> Just ns
      UserEvalException RanOutOfSteps -> nonEmpty reached
      _                               -> Nothing
    v' = case assertKind of
      NotAnAssert -> Reduction
        case v of
          -- A refusal is NOT an evaluation error: the model declined to
          -- answer, and every surface must be able to say so without calling
          -- the program broken.
          Left (RefusalException ref) -> ReducedRefused ref
          -- Not an error either: a result not yet known, the undetermined
          -- outcome of the default report.
          Left exc | Just ns <- stuckOnExc exc -> ReducedUndetermined ns
          Left exc                    -> ReducedErrored exc
          -- A result that is a bare assumed term is no value (row 52), and
          -- neither is one that holds any term but a bare input (decided by
          -- Claude overnight 2026-10-02, pending Meng's review; §8 step 3):
          -- each was Stuck before the lift, and is undetermined, naming what
          -- it waits on. One whose only terms are bare inputs below its root
          -- prints as the value it is, @LIST n, 6@ (C4, row 60).
          Right nfv | Just ns <- resultUnknowns nfv -> ReducedUndetermined ns
          Right nfv                   -> Reduced nfv
      AssertHolds -> Assertion
        case v of
          -- A refusal is a determinate outcome of the assertion, distinct
          -- both from a failure and from an error. '#ASSERT NOT e' where e
          -- refuses lands here too: 'NOT' desugars to an 'IfThenElse' that
          -- forces its scrutinee, so the refusal propagates and BOTH
          -- polarities report "refused" rather than one of them collapsing.
          Left (RefusalException ref) -> Refused ref
          -- An assertion whose expression RAISED is neither satisfied nor
          -- failed: the evaluator could not decide it. Collapsing the
          -- exception into 'False' made '#ASSERT P' and '#ASSERT NOT P'
          -- both report "assertion failed" whenever P raised, so a test
          -- suite could not tell a wrong answer from an error. One that
          -- could not be decided for want of an input is undetermined.
          Left exc | Just ns <- stuckOnExc exc -> Undetermined ns
          Left exc                    -> Errored exc
          Right (MkNF (ValBool True)) -> Holds
          -- A result that is an unknown did not raise, but it is no verdict
          -- either — neither TRUE nor FALSE: a bare assumed term, or a
          -- residual such as @x AND y@ (§4.12 rows 23, 24). Report it as the
          -- raising polarity does ('#ASSERT NOT b' forces b and is Stuck), so
          -- both polarities of an '#ASSERT' agree instead of one of them
          -- collapsing to "failed".
          Right nfv | Just ns <- resultUnknowns nfv -> Undetermined ns
          Right _                     -> Fails
      AssertRefuses mwanted -> Assertion
        case v of
          Left (RefusalException ref)
            | Just wanted <- mwanted, wanted /= ref.message ->
                FailsBecause
                  ( "expected the refusal " <> quoted wanted
                    <> ", got " <> quoted ref.message )
            | otherwise -> Holds
          -- An error is not a refusal. Conflating them would destroy exactly
          -- the distinction '#ASSERT REFUSED' exists to test.
          Left exc | Just ns <- stuckOnExc exc -> Undetermined ns
          Left exc -> Errored exc
          -- A value, an unknown or a residual: none of them refuses, since
          -- an input never refuses and, before build step 5, no residual
          -- holds a refusal (row 72; decided by Claude overnight 2026-10-02,
          -- pending Meng's review).
          Right _  -> FailsBecause "expected a refusal, but the expression produced a value"
    quoted t = "\"" <> t <> "\""
  pure (MkEvalDirectiveResult r v' finalTrace directiveLedger directiveNotes directivePresumed, steps)
  where
    captureSteps :: Eval a -> Eval (a, [DeonticStep])
    captureSteps
      | withSteps = captureDeonticSteps
      | otherwise = fmap (, [])

-- | What a directive's result waits on, if it is not a value
-- (UNKNOWN-EVALUATION-SPEC §4.7.4, build step 3): a result that is itself an
-- unknown input, or that holds any term but a bare input anywhere inside it.
-- Then every unknown in it is named, bare inputs included, in the order they
-- occur. A result whose only unknowns are bare inputs below its root, such as
-- @LIST n, 6@, is a value (C4, row 60).
resultUnknowns :: NF -> Maybe (NonEmpty Term)
resultUnknowns = \ case
  MkNF (ValAssumed r ty) -> Just (TInput r ty :| [])
  nfv
    | holdsTerm nfv -> nonEmpty (nubTerms (unknownsIn nfv))
    | otherwise     -> Nothing
  where
    holdsTerm = \ case
      MkNF (ValTerm _) -> True
      MkNF v           -> any holdsTerm (toList v)
      Omitted          -> False
    unknownsIn = \ case
      MkNF (ValTerm t)       -> termNames t
      MkNF (ValAssumed r ty) -> [TInput r ty]
      MkNF v                 -> concatMap unknownsIn (toList v)
      Omitted                -> []
    nubTerms = foldr (\ x acc -> x : filter (/= x) acc) []

-- | 'postprocessTrace', guarded so it can never escape an exception: if trace
-- post-processing throws (e.g. a malformed action sequence produced by an
-- unbalanced push/pop), degrade to a one-node fallback trace instead of letting
-- an ErrorCall abort the surrounding evaluation and discard the already-computed
-- #EVAL result (see T7). Catches 'ErrorCall' specifically — not 'SomeException'
-- — so asynchronous exceptions (request cancellation, timeouts) still propagate.
safePostprocessTrace :: [EvalTraceAction] -> IO EvalTrace
safePostprocessTrace actions = do
  r <- try (evaluate (force (postprocessTrace actions)))
  pure $ case r of
    Right t               -> t
    Left (_ :: ErrorCall) -> tracePostprocessFailed

-- | Fallback substituted for a trace when post-processing it fails. Keeps the
-- directive's result intact and degrades only the trace to a single marker
-- node, instead of letting the failure abort the surrounding evaluation.
tracePostprocessFailed :: EvalTrace
tracePostprocessFailed =
  Trace Nothing [] (Right (MkNF (ValString "trace unavailable (internal error during trace post-processing)")))

postprocessTrace :: [EvalTraceAction] -> EvalTrace
postprocessTrace actions =
  let
    labels = collectTraceLabels actions
    splitActions = splitEvalTraceActions actions
    tracedHeap = buildEvalPreTraces splitActions
    mainTrace = case Map.lookup Nothing tracedHeap of
                  Nothing -> err
                  Just t  -> t
    err = error "postprocessTrace: no trace for main value"
    mainPreTrace = either err id mainTrace
    finalTrace = simplifyEvalTrace (buildEvalTrace labels tracedHeap Nothing mainPreTrace)
  in
    finalTrace

data EvalDirectiveResult =
  MkEvalDirectiveResult
    { range  :: Maybe SrcRange -- ^ of the (L)EVAL / DEONTIC directive
    , result :: EvalDirectiveValue
    , trace  :: Maybe EvalTrace
    , ledger :: !LedgerStore
      -- ^ STATE-AS-LEDGER M2/M4: the event store this directive produced (each
      -- party's own RECORD 'Assign's plus the official COMMIT/ATTEST 'Assign's),
      -- captured before 'withFreshLedger' discarded the per-directive store.
      -- Newest-last within each ledger. Empty for a directive that wrote nothing
      -- (pure reads / ordinary expressions) — rendered as nothing in that case
      -- so reads do not clutter the output.
    , notes :: ![Text]
      -- ^ what the run REPORTED without failing while producing the value
      -- ('L4.EvaluateLazy.Machine.tellNote'; EVERY-EACH-QUANTIFIER-SPEC
      -- §5.1.2, 2026-09-16): an act before its window opened (R-X6, a
      -- nullity the run must not swallow), an explicitly anchored window a
      -- run found empty. In the order raised. Empty for almost every
      -- directive, and rendered as nothing then, so no older output moves.
    , presumed :: ![Presumed]
      -- ^ The @TYPICALLY@ defaults the run actually forced while producing
      -- the value, in the order forced: W8's \"took its default\" event
      -- (TYPICALLY-ONE-BEHAVIOUR-SPEC.md §4 W8, §5 T6). The trace shows the
      -- same events ('TraceDefault'); the list itself is not printed here, and
      -- @l4 batch@ and @jl4-service@ turn it into their @presumed@ list.
    }
  deriving stock (Generic, Show)
  deriving anyclass NFData

data EvalDirectiveValue =
    Assertion AssertionOutcome
    -- ^ @#ASSERT@ and @#ASSERT REFUSED@.
  | Reduction ReductionOutcome
    -- ^ @#EVAL@ \/ @#EVALTRACE@ \/ @#TRACE@.
  deriving stock (Generic, Show)
  deriving anyclass NFData

-- | What an @#ASSERT@ (of either kind) came to.
--
-- Four outcomes, not two, and the fourth is the point of @REFUSE@: a refused
-- assertion is neither satisfied, nor failed, nor an evaluation error. Every
-- consumer must render all four distinctly — collapsing 'Refused' into 'Fails'
-- launders a declined answer into a determinate FALSE, and collapsing it into
-- 'Errored' reports a designed outcome as a defect.
data AssertionOutcome
  = Holds
    -- ^ The assertion is satisfied.
  | Fails
    -- ^ The assertion is not satisfied.
  | FailsBecause !Text
    -- ^ Not satisfied, with a specific explanation (what @#ASSERT REFUSED@
    -- reports when the expression produced a value, or refused with a
    -- different reason than the @BECAUSE@ clause named).
  | Refused !Refusal
    -- ^ The expression REFUSED: the model declined to answer.
  | Errored !EvalException
    -- ^ The expression raised before it could be decided.
  | Undetermined !(NonEmpty Term)
    -- ^ The expression could not be decided for want of these inputs
    -- (UNKNOWN-EVALUATION-SPEC §4.7.4); rendered as a 'Stuck' always was.
  deriving stock (Generic, Show)
  deriving anyclass NFData

-- | What an @#EVAL@ came to. The refusal arm exists for the same reason as
-- 'AssertionOutcome'\'s: a refusal reaching a surface as an ordinary
-- 'EvalException' is rendered as a crash, which is the wrong answer.
data ReductionOutcome
  = Reduced !NF
  | ReducedRefused !Refusal
  | ReducedErrored !EvalException
  | ReducedUndetermined !(NonEmpty Term)
    -- ^ The result is not known: it waits on these inputs, each once, in the
    -- order evaluation reached them (UNKNOWN-EVALUATION-SPEC §4.7.4, the
    -- default report). Rendered exactly as a 'Stuck' always was, since that
    -- is what the default report shows; not an error.
  deriving stock (Generic, Show)
  deriving anyclass NFData

prettyEvalDirectiveValue :: EvalDirectiveValue -> Text
prettyEvalDirectiveValue (Assertion a) = prettyAssertionOutcome a
prettyEvalDirectiveValue (Reduction v) = prettyReductionOutcome v

-- | The outcomes of an @#ASSERT@, as the user sees them. The exception case
-- keeps the exception's own lines verbatim under a header, so the reason
-- (division by zero, an assumed term, a CONSIDER with no matching branch, …)
-- is never lost. Every surface that renders an assertion goes through here.
prettyAssertionOutcome :: AssertionOutcome -> Text
prettyAssertionOutcome Holds            = "assertion satisfied"
prettyAssertionOutcome Fails            = "assertion failed"
prettyAssertionOutcome (FailsBecause t) = "assertion failed: " <> t
prettyAssertionOutcome (Refused r)      =
  Text.unlines ("assertion refused:" : prettyRefusal r)
prettyAssertionOutcome (Errored exc)    =
  Text.unlines ("assertion could not be evaluated:" : prettyEvalException exc)
prettyAssertionOutcome (Undetermined ns) =
  Text.unlines ("assertion could not be evaluated:" : prettyUndetermined ns)

-- | What an undetermined result says: the default report, which is the
-- 'Stuck' message it always was, naming every input it waits on
-- (UNKNOWN-EVALUATION-SPEC §4.7.4).
prettyUndetermined :: NonEmpty Term -> [Text]
prettyUndetermined ns = prettyEvalException (UserEvalException (Stuck ns))

-- | The outcomes of an @#EVAL@, as the user sees them.
prettyReductionOutcome :: ReductionOutcome -> Text
prettyReductionOutcome (Reduced v)          = prettyLayout v
prettyReductionOutcome (ReducedRefused r)   = Text.unlines (prettyRefusal r)
prettyReductionOutcome (ReducedErrored exc) = Text.unlines (prettyEvalException exc)
prettyReductionOutcome (ReducedUndetermined ns) =
  Text.unlines (prettyUndetermined ns)

-- | STATE-AS-LEDGER M2/M4: render the per-party store a directive produced, as
-- labelled sections. Returns the empty 'Text' when the directive wrote nothing,
-- so that pure reads / ordinary expressions are not cluttered.
--
-- Each non-empty own ledger renders as a @Ledger (<party>):@ block (the
-- anonymous own ledger, from a top-level @RECORD@, renders as a bare @Ledger:@
-- block), and a non-empty official record renders as an @Official record:@
-- block. One row per 'Assign', oldest-first (each ledger is newest-last as a
-- 'DList', and 'toList' yields oldest-first — the order the writes happened):
--
-- > Ledger (Alice):
-- >   RECORD `freezing point of water` IS 273.15   [party=Alice, source=RECORD, at=...]
-- > Official record:
-- >   COMMIT `fp` IS 273.15   [party=Court, source=COMMIT, at=...]
prettyLedger :: LedgerStore -> Text
prettyLedger store =
  Text.concat (ownBlocks <> [officialBlock])
  where
    ownBlocks =
      [ renderBlock (ownHeader party) led
      | (party, led) <- Map.toList store.ownLedgers
      , not (null (DList.toList led))
      ]
    officialBlock = renderBlock "Official record" store.officialLedger

    -- The anonymous own ledger (top-level RECORD, empty party key) has no party
    -- name, so it renders as a bare "Ledger:" header.
    ownHeader party
      | Text.null party = "Ledger"
      | otherwise       = "Ledger (" <> party <> ")"

    renderBlock header led =
      case DList.toList led of
        []     -> Text.empty
        events -> "\n" <> header <> ":\n" <> Text.intercalate "\n" (map prettyLedgerEvent events)

prettyLedgerEvent :: LedgerEvent -> Text
prettyLedgerEvent (Assign path val prov) =
  "  " <> verb <> " " <> renderPath path <> " IS " <> prettyLayout val
    <> "   " <> renderProvenance prov
  where
    -- The provenance source distinguishes RECORD (own ledger) from
    -- COMMIT/ATTEST (official record); echo it as the surface verb.
    verb = case prov.source of
      "COMMIT" -> "COMMIT"
      _        -> "RECORD"

-- | Render a cell 'Path' back to its backtick surface form, e.g.
-- @`freezing point of water`@. M1/M1.5 cells are single-segment; nested
-- segments (a later milestone) join with @'s@ to mirror the genitive read.
renderPath :: Path -> Text
renderPath segs = Text.intercalate "'s " (map (\s -> "`" <> s <> "`") segs)

renderProvenance :: Provenance -> Text
renderProvenance prov =
  "[" <> Text.intercalate ", " (catMaybes [partyField, sourceField, atField, vtField]) <> "]"
  where
    partyField  = if Text.null prov.party then Nothing else Just ("party=" <> prov.party)
    sourceField = Just ("source=" <> prov.source)
    -- the transaction stamp, rendered exactly as the pre-bitemporal free-form
    -- position was (ISO-8601 of the root eval clock) — goldens are stable
    atField     = Just ("at=" <> formatUTCTimeIso prov.txTime)
    -- the valid-from stamp appears ONLY when a fact time was explicitly
    -- asserted at the write (an enclosing EVAL UNDER VALID TIME); a
    -- contemporaneous write renders as before
    vtField     = ("vt=" <>) . Text.pack . ISO8601.iso8601Show <$> prov.vtFrom

-- | Prints the results but not the range of an eval directive, including
-- the trace if present, and the ledger section if the directive wrote anything.
--
prettyEvalDirectiveResult :: EvalDirectiveResult -> Text
prettyEvalDirectiveResult (MkEvalDirectiveResult _range res mtrace led ns _presumed) =
   prettyEvalDirectiveValue res
   <> prettyNotes ns
   <> prettyLedger led
   <> case mtrace of
        Nothing -> Text.empty
        Just t  -> "\n─────\n" <> prettyLayout t

-- | Like 'prettyEvalDirectiveResult' but uses named-field syntax (WITH / IS)
-- for constructors whose field names are provided.
prettyEvalDirectiveResultWithFields :: ConstructorFieldNames -> EvalDirectiveResult -> Text
prettyEvalDirectiveResultWithFields fields (MkEvalDirectiveResult _range res mtrace led ns _presumed) =
   prettyEvalDirectiveValueWithFields fields res
   <> prettyNotes ns
   <> prettyLedger led
   <> case mtrace of
        Nothing -> Text.empty
        Just t  -> "\n─────\n" <> prettyLayout t

-- | The run's notes, one @NOTE:@ line each after the value; nothing when
-- there are none (the usual case), so no older output moves.
prettyNotes :: [Text] -> Text
prettyNotes = foldMap (\ n -> "\nNOTE: " <> n)

-- ----------------------------------------------------------------------------
-- ToJSON instances for batch --json output
-- ----------------------------------------------------------------------------

instance Aeson.ToJSON EvalDirectiveResult where
  toJSON (MkEvalDirectiveResult _range res _trace _ledger ns _presumed) = Aeson.object $
    [ "result" Aeson..= res
    , "trace"  Aeson..= Aeson.Null
    ]
    -- the run's notes, only when there are any, so the object of a
    -- directive with none is unchanged
    <> [ "notes" Aeson..= ns | not (null ns) ]

instance Aeson.ToJSON EvalDirectiveValue where
  toJSON (Assertion Holds) = Aeson.object
    [ "type"  Aeson..= ("assertion" :: Text)
    , "value" Aeson..= True
    ]
  toJSON (Assertion Fails) = Aeson.object
    [ "type"  Aeson..= ("assertion" :: Text)
    , "value" Aeson..= False
    ]
  toJSON (Assertion a@(FailsBecause _)) = Aeson.object
    [ "type"  Aeson..= ("assertion" :: Text)
    , "value" Aeson..= False
    , "error" Aeson..= prettyAssertionOutcome a
    ]
  -- Still an assertion (consumers counting them must see it), with a value
  -- that is neither true nor false. A refusal is reported under its own key,
  -- NOT under "error": a consumer that treats every non-boolean assertion as
  -- a broken program is exactly what REFUSE exists to prevent.
  toJSON (Assertion (Refused r)) = Aeson.object
    [ "type"    Aeson..= ("assertion" :: Text)
    , "value"   Aeson..= Aeson.Null
    , "refused" Aeson..= Aeson.object [ "reason" Aeson..= r.message ]
    ]
  toJSON (Assertion a@(Errored _)) = Aeson.object
    [ "type"  Aeson..= ("assertion" :: Text)
    , "value" Aeson..= Aeson.Null
    , "error" Aeson..= prettyAssertionOutcome a
    ]
  -- Still an assertion, as in @l4 run --json@, with a null value and what it
  -- waits on under "undetermined": not an "error", which it is not
  -- ('undeterminedJson').
  toJSON v@(Assertion (Undetermined _)) = Aeson.object
    [ "type"         Aeson..= ("assertion" :: Text)
    , "value"        Aeson..= Aeson.Null
    , "undetermined" Aeson..= undeterminedJson v
    ]
  toJSON (Reduction (Reduced val)) = Aeson.toJSON val
  toJSON (Reduction (ReducedRefused r)) = Aeson.object
    [ "refused" Aeson..= Aeson.object [ "reason" Aeson..= r.message ]
    ]
  toJSON (Reduction (ReducedErrored exc)) = Aeson.object
    [ "error" Aeson..= Text.unlines (prettyEvalException exc)
    ]
  -- Under its own key, as a refusal is: neither a value nor an error.
  toJSON v@(Reduction (ReducedUndetermined _)) = Aeson.object
    [ "undetermined" Aeson..= undeterminedJson v
    ]

-- | What an undetermined result waits on, as every JSON surface reports it
-- (UNKNOWN-EVALUATION-SPEC §4.7.4): @{"needs": [...], "message": "..."}@,
-- the inputs each once, in the order evaluation reached them, and the
-- default report's text. 'Nothing' for any other result. @l4 run --json@,
-- the JSON above and the API's result objects all carry this one object.
undeterminedJson :: EvalDirectiveValue -> Maybe Aeson.Value
undeterminedJson = \ case
  Assertion a@(Undetermined ns)        -> Just (needsAnd ns (prettyAssertionOutcome a))
  Reduction o@(ReducedUndetermined ns) -> Just (needsAnd ns (prettyReductionOutcome o))
  _                                    -> Nothing
  where
    needsAnd ns message = Aeson.object
      [ "needs"   Aeson..= map termNeedText (toList ns)
      , "message" Aeson..= message
      ]

prettyEvalDirectiveValueWithFields :: ConstructorFieldNames -> EvalDirectiveValue -> Text
prettyEvalDirectiveValueWithFields _fields (Assertion a)                    = prettyAssertionOutcome a
prettyEvalDirectiveValueWithFields _fields (Reduction (ReducedErrored exc)) = Text.unlines (prettyEvalException exc)
prettyEvalDirectiveValueWithFields _fields (Reduction (ReducedRefused r))   = Text.unlines (prettyRefusal r)
prettyEvalDirectiveValueWithFields _fields (Reduction o@(ReducedUndetermined _)) = prettyReductionOutcome o
prettyEvalDirectiveValueWithFields fields  (Reduction (Reduced v))          = prettyLayoutNF fields v

-- | Evaluate WHNF to NF, with a cutoff (which possibly could be made configurable).
nf :: WHNF -> Eval NF
nf = nfAux maximumStackSize

nfAux :: Int -> WHNF -> Eval NF
nfAux  d _v | d < 0                  = pure Omitted
nfAux _d (ValNumber i)               = pure (MkNF (ValNumber i))
nfAux _d (ValString s)               = pure (MkNF (ValString s))
nfAux _d (ValDate day)               = pure (MkNF (ValDate day))
nfAux _d (ValTime tod)               = pure (MkNF (ValTime tod))
nfAux _d (ValDateTime utc tz)        = pure (MkNF (ValDateTime utc tz))
nfAux _d ValNil                      = pure (MkNF ValNil)
nfAux  d (ValCons r1 r2)             = do
  v1 <- evalAndNF d r1
  v2 <- evalAndNF d r2
  pure (MkNF (ValCons v1 v2))
nfAux _d (ValClosure givens e env)   = pure (MkNF (ValClosure givens e env))
nfAux _d (ValNullaryBuiltinFun b)    = pure (MkNF (ValNullaryBuiltinFun b))
nfAux d (ValObligation env party act opens due followup lest) = do
  party' <- traverseAndNF d party
  opens' <- traverse (traverse (traverse (evalAndNF d))) opens
  due' <- traverseAndNF d due
  pure (MkNF (ValObligation env party' act opens' due' followup lest))
nfAux _d (ValUnaryBuiltinFun b)      = pure (MkNF (ValUnaryBuiltinFun b))
nfAux _d (ValBinaryBuiltinFun b)     = pure (MkNF (ValBinaryBuiltinFun b))
nfAux _d (ValConnective c)           = pure (MkNF (ValConnective c))
nfAux _d (ValTernaryBuiltinFun b)    = pure (MkNF (ValTernaryBuiltinFun b))
nfAux  d (ValPartialTernary b r1)    = do
  v1 <- evalAndNF d r1
  pure (MkNF (ValPartialTernary b v1))
nfAux  d (ValPartialTernary2 b r1 r2) = do
  v1 <- evalAndNF d r1
  v2 <- evalAndNF d r2
  pure (MkNF (ValPartialTernary2 b v1 v2))
nfAux _d (ValUnappliedConstructor n) = pure (MkNF (ValUnappliedConstructor n))
nfAux  d (ValConstructor n rs)       = do
  vs <- traverse (evalAndNF d) rs
  pure (MkNF (ValConstructor n vs))
nfAux _d (ValAssumed n ty)           = pure (MkNF (ValAssumed n ty))
nfAux _d (ValTerm t)                 = pure (MkNF (ValTerm t))
nfAux _d (ValEnvironment env)        = pure (MkNF (ValEnvironment env))
nfAux d (ValBreached r')             = do
  -- Every reference inside the breach — the revealing event's party and
  -- action, and each failure's party and BECAUSE — is forced to normal form;
  -- the 'Traversable' instances of 'ReasonForBreach', 'Blame' and 'Failure'
  -- reach all of them.
  r <- traverse (evalAndNF d) r'
  pure (MkNF (ValBreached r))
nfAux d (ValROp env op l r) = do
  l' <- traverseAndNF d l
  r' <- traverseAndNF d r
  pure (MkNF (ValROp env op l' r'))
-- An armed-but-unrun EVERY holds only syntax and its arming environment, so
-- there is nothing under it to force to normal form.
nfAux _ (ValQuantified env d) = pure (MkNF (ValQuantified env d))

traverseAndNF :: Int -> Either a WHNF -> Eval (Either a (Value NF))
traverseAndNF d = traverse (traverse (evalAndNF d))

evalAndNF :: Int -> Reference -> Eval NF
evalAndNF d r = do
  w <- runConfig (EvalRefMachine r)
  nfAux (d - 1) w

-- | Main entry point.
--
-- Given an initial environment (which is supposed to contain the environment for
-- imported entities), evaluate a module.
--
-- Returns the environment of the entities defined in *this* module, and
-- the results of the (L)EVAL directives in this module.
--
execEvalModuleWithEnv :: EvalConfig -> EntityInfo -> Environment -> Module Resolved -> IO (Environment, [EvalDirectiveResult])
execEvalModuleWithEnv = execEvalModuleWith nfDirective

-- | LTS-VISUALISER §4.3 (P2b): 'execEvalModuleWithEnv' with the deontic step
-- log switched on for every directive, returning each directive's steps
-- beside its result. The result half is exactly what 'execEvalModuleWithEnv'
-- returns — the log changes nothing the machine computes — and the steps
-- are oldest-first. A @#TRACE@ is where the steps come from; a plain
-- @#EVAL@ of a non-regulative expression logs none.
--
-- This is the library seam P2c (the marking and the enabled set) and P2a′
-- (the list) build on; it is deliberately not a CLI.
execEvalModuleWithDeonticLog :: EvalConfig -> EntityInfo -> Environment -> Module Resolved -> IO (Environment, [(EvalDirectiveResult, [DeonticStep])])
execEvalModuleWithDeonticLog = execEvalModuleWith (nfDirectiveWith True)

execEvalModuleWith :: (EvalDirective -> Eval r) -> EvalConfig -> EntityInfo -> Environment -> Module Resolved -> IO (Environment, [r])
execEvalModuleWith = execEvalModuleWithDefaults noRootFills []

-- | 'execEvalModuleWithEnv', also told the @DECLARE@s of the modules @m@
-- imports, so that the JSON decoder fills an absent field of a record
-- declared in one of them from its @DECLARE@ (T1b), as it does for a record
-- declared in @m@ itself. @l4 batch@ and the service's wrapper path decode
-- their inputs this way.
execEvalModuleWithEnvAndImports :: EvalConfig -> EntityInfo -> Environment -> [Declare Resolved] -> Module Resolved -> IO (Environment, [EvalDirectiveResult])
execEvalModuleWithEnvAndImports evalConfig entityInfo env imported =
  execEvalModuleWithDefaults noRootFills imported nfDirective evalConfig entityInfo env

-- | Definitions a caller filled with a @TYPICALLY@ default at the root, keyed
-- by the 'Unique' of the 0-ary definition holding the default. Forcing one
-- reports it ('L4.EvaluateLazy.Machine.Presumed').
type RootFills = Map Unique Presumed

noRootFills :: RootFills
noRootFills = Map.empty

execEvalModuleWithDefaults :: RootFills -> [Declare Resolved] -> (EvalDirective -> Eval r) -> EvalConfig -> EntityInfo -> Environment -> Module Resolved -> IO (Environment, [r])
execEvalModuleWithDefaults rootFills imported runDirective evalConfig entityInfo env m0@(MkModule _ moduleUri _) = do
  -- Discharge is a property of EVALUATION, not of the checked module: the
  -- checker's job is to say the program is well formed, and this pass says what
  -- an implicit input means when it is run. Doing it here rather than in
  -- 'L4.TypeCheck' keeps the module the LSP hovers over, the printers re-emit
  -- and the backends lower exactly the module the author wrote.
  --
  -- With presumption off (T4), discharge fills no section binder's default, so
  -- one that nothing supplies stays an assumed term.
  let m = dischargeModuleWith evalConfig.presumeDefaults m0
  st0 <- mkInitialEvalState evalConfig entityInfo moduleUri
  let st = withDefaultsKnown evalConfig rootFills m0 imported st0
  r <- try (withAllocationLimit evalConfig.allocationLimit (runEval st (evalModuleAndDirectivesWith runDirective env m)))
  case r of
    Left exc -> do
      hPutStrLn stderr $ "Eval failure in module: " <> show moduleUri
      traverse_ (hPutStrLn stderr . Text.unpack) (prettyEvalException exc)
      -- exceptions at the top-level are unusual; after all, we don't actually
      -- force any evaluation here, and we catch exceptions for eval directives
      pure (emptyEnvironment, [])
    Right result -> pure result

-- | Run an action under an allocation cap on the current thread, and switch
-- the cap off again however the action ends.
withAllocationLimit :: Maybe AllocationLimit -> IO a -> IO a
withAllocationLimit Nothing act = act
withAllocationLimit (Just limit) act =
  (setAllocationCounter limit.bytes >> enableAllocationLimit >> act)
    `catch` (\AllocationLimitExceeded -> writeIORef limit.exceeded True >> throwIO AllocationLimitExceeded)
    `finally` disableAllocationLimit

mkInitialEvalState :: EvalConfig -> EntityInfo -> NormalizedUri -> IO EvalState
mkInitialEvalState evalConfig entityInfo moduleUri = do
  stack     <- newIORef emptyStack
  supply    <- newIORef 0
  actualTime <- resolveEvalTime evalConfig
  let temporalCtx = initialTemporalContext actualTime
  temporalContext <- newIORef temporalCtx
  ctxReads <- newIORef noReads
  let evalTrace = Nothing
  reofferedEvents <- newIORef mempty
  envLedger    <- newIORef emptyStore
  currentParty <- newIORef Nothing
  notes        <- newIORef mempty
  -- P2b: off by default (R5); 'captureDeonticSteps' installs one per directive
  let deonticLog = Nothing
  -- UNKNOWN-EVALUATION-SPEC §4.5: stopped until a directive's first term
  unknownSteps   <- newIORef (-1)
  unknownReached <- newIORef []
  presumable <- newIORef IntMap.empty
  presumed   <- newIORef emptyPresumedLog
  pure MkEvalState
    { moduleUri, stack, supply, evalTrace, envLedger, currentParty, entityInfo
    , evalTime = actualTime, temporalContext, ctxReads
    , tracePolicy = evalConfig.tracePolicy, safeMode = evalConfig.safeMode
    , reofferedEvents, notes, unknownSteps, unknownReached, deonticLog
    , presume = evalConfig.presumeDefaults
    , requestRecord = evalConfig.requestRecord
      -- filled by 'withDefaultsKnown' for a module run
    , presumableDefs = Map.empty, presumable, recordDefaults = Map.empty, presumed
    }

-- | Tell a run where defaults come from: the section binders of the evaluated
-- module whose default discharge fills (when presumption is on), the caller's
-- own root fills, and the field defaults of every record the module and the
-- given @DECLARE@s (its imports') declare.
withDefaultsKnown :: EvalConfig -> RootFills -> Module Resolved -> [Declare Resolved] -> EvalState -> EvalState
withDefaultsKnown evalConfig rootFills m imported st =
  st { presumableDefs = binderDefaults <> rootFills
     , recordDefaults = recordFieldDefaults (moduleDeclares m <> imported)
     }
 where
  binderDefaults
    | evalConfig.presumeDefaults =
      Map.fromList
        [ ( u
          , MkPresumed
              { path       = [rawNameToText (rawName (getActual b.resolved))]
              , declaredAt = rangeOf d
              , origin     = FromSectionBinder
              }
          )
        | (u, b) <- Map.toList (sectionBinders m)
        , Just d <- [b.typically]
        ]
    | otherwise = Map.empty

-- | Every @DECLARE@ in a module, in any section.
moduleDeclares :: Module Resolved -> [Declare Resolved]
moduleDeclares (MkModule _ _ sect) = goSection sect
 where
  goSection (MkSection _ _ _ _ decls) = decls >>= goDecl
  goDecl = \ case
    Declare _ d -> [d]
    Section _ s -> goSection s
    _ -> []

-- | The field defaults of every record among some @DECLARE@s, keyed by the
-- record type's 'Unique', then by field name. Only fields with a @TYPICALLY@
-- appear.
recordFieldDefaults :: [Declare Resolved] -> Map Unique (Map Text (Expr Resolved))
recordFieldDefaults decls = Map.fromList
  [ (getUnique tyName, ds)
  | MkDeclare _ _ (MkAppForm _ tyName _ _) (RecordDecl _ _ fields) <- decls
  , let ds = Map.fromList
               [ (rawNameToText (rawName (getActual fn)), d)
               | MkTypedName _ fn _ (Just d) _ <- fields ]
  , not (Map.null ds)
  ]

-- | The @presumed@ list of a request's answer (T6), from the events its
-- evaluation forced: each as the input's name, or the path to a field below
-- it. Shared by @l4 batch@ and the service.
--
-- Only events that belong to the request count (T6b): a section binder's or a
-- root fill's for an input the function takes, and one from the request's own
-- decode. A decode the RULES made is not the request's, and is listed only
-- when presumption is hard (@presume@ False): there it is a default the switch
-- could not withdraw, because no request can supply it, and the answer rests
-- on it (T4b: "rests on presumed x"). It is written @JSONDECODE T: path@,
-- naming the type the rules decoded.
--
-- @fieldName@ maps a wrapper's own field name back to the input's (the service
-- suffixes them, 'Backend.CodeGen.inputFieldName').
requestPresumed :: Bool -> (Text -> Text) -> Set Text -> [Presumed] -> [Text]
requestPresumed presume fieldName inputs events =
  nubOrd (mapMaybe entry events)
 where
  entry p = case (p.origin, p.path) of
    (FromDecode root, path)
      | not presume -> Just ("JSONDECODE " <> root <> ": " <> renderPresumedPath path)
      | otherwise   -> Nothing
    (_, n : rest)
      | fieldName n `Set.member` inputs -> Just (renderPresumedPath (fieldName n : rest))
    _ -> Nothing

-- | Build a minimal 'EvalState' and run an 'Eval' action against it, catching
-- evaluation exceptions at the boundary.
--
-- This is a test seam for exercising the ledger substrate (and other 'Eval'
-- effects) end-to-end through the monad, without standing up a full module
-- evaluation. Like the real entry points, it initializes the ledger EMPTY
-- (routed through 'mkInitialEvalState', so there is a single construction site).
--
-- Not part of the stable public API; exposed for the test suite only.
runEvalAction :: EvalConfig -> Eval a -> IO (Either EvalException a)
runEvalAction evalConfig action = do
  st0 <- mkInitialEvalState evalConfig mempty (toNormalizedUri (Uri "test:runEvalAction"))
  try (runEval st0 action)

-- | Forward-evaluate a single 'Expr Resolved' to 'WHNF' in the empty
-- environment, as an 'Eval' action. This is the test seam that lets the
-- ledger-write path (M1 @RECORD@/@COMMIT@/@ATTEST@) be exercised end-to-end:
-- run this, then observe the ledger with 'currentLedger' in the same action.
--
-- Not part of the stable public API; exposed for the test suite only.
evalExprForLedger :: Expr Resolved -> Eval WHNF
evalExprForLedger expr = runConfig (ForwardMachine emptyEnvironment expr)

-- | As 'evalExprForLedger', but evaluate the expression against a SUPPLIED
-- environment (so a directive expr that references a top-level binding — e.g. a
-- party constructor named in a NOTIFY @RECORD q's …@ recipient — resolves at
-- runtime). The companion 'moduleEnvForLedger' builds such an environment from a
-- module. Like 'evalExprForLedger', this does NOT wrap the evaluation in
-- 'withFreshLedger', so a sequence of these in ONE 'runEvalAction' shares one
-- ledger — the seam a cross-party WRITE/READ test needs.
--
-- Not part of the stable public API; exposed for the test suite only.
evalExprForLedgerWithEnv :: Environment -> Expr Resolved -> Eval WHNF
evalExprForLedgerWithEnv env expr = runConfig (ForwardMachine env expr)

-- | Build the runtime environment a module's directives evaluate against (the
-- module's top-level bindings combined with the initial/prelude environment),
-- WITHOUT running any directive. Used with 'evalExprForLedgerWithEnv' so a test
-- can sequence several directive exprs against one shared ledger while still
-- resolving top-level references (constructors, defs).
--
-- Not part of the stable public API; exposed for the test suite only.
moduleEnvForLedger :: Environment -> Module Resolved -> Eval Environment
moduleEnvForLedger env m = do
  ienv <- initialEnvironment
  let baseEnv = env <> ienv
  (moduleEnv, _directives) <- evalModule baseEnv m
  pure (moduleEnv <> baseEnv)

-- TODO: This currently allocates the initial environment once per module.
-- This isn't a big deal, but can we somehow do this only once per program,
-- for example by passing this in from the outside?
evalModuleAndDirectivesWith :: (EvalDirective -> Eval r) -> Environment -> Module Resolved -> Eval (Environment, [r])
evalModuleAndDirectivesWith runDirective env m = do
  ienv <- initialEnvironment
  let baseEnv = env <> ienv
  -- First pass: get env' (the module's exported bindings) and the directive
  -- count/order for the return value.
  (env', directives0) <- evalModule baseEnv m
  -- STATE-AS-LEDGER CAF ISOLATION: re-thunk the top-level heap per directive so a
  -- nullary top-level definition that is forced (and memoized in its shared
  -- Reference IORef) in directive N is Unevaluated again in directive N+1. This is
  -- the heap analog of 'withFreshLedger': each directive evaluates the top-level
  -- defs against fresh References, so an effectful read (RECALL) inside a CAF is
  -- re-run against that directive's own (isolated) ledger instead of returning a
  -- value cached from whichever directive forced it first. See 'forEachDirectiveFreshHeap'.
  results <- forEachDirectiveFreshHeap (\_ -> pure ()) runDirective baseEnv m (length directives0)
  -- NOTE: We are only returning the new definitions of this module, not any imports.
  -- Depending on future export semantics, this may have to change.
  pure (env', results)

-- | Run every directive of a module against its OWN freshly-allocated top-level
-- heap. We re-run 'evalModule' once per directive: each pass re-'preAllocate's a
-- fresh set of top-level References (all 'Unevaluated') and re-writes the body
-- thunks into them, then we normal-form just the i-th directive from THAT pass.
--
-- Why this is correct and minimal:
--   * Top-level definitions are stored as shared 'Reference' IORefs that the lazy
--     evaluator overwrites in place to 'WHNF' on first force (standard
--     lazy-sharing memoization). That memoization is unsound for a nullary def
--     whose body performs an effectful read ('RECALL'), because its WHNF is not a
--     pure function of the source — it depends on the per-directive ledger that
--     'withFreshLedger' (correctly) resets. Re-thunking discards the stale WHNF.
--   * 'evalModule' forces nothing (it only allocates References and writes
--     thunks), so re-running it per directive is side-effect-free except for heap
--     allocation and supply/address bumps; pure CAFs simply recompute (cheap).
--   * 'nfDirective' still wraps each evaluation in 'withFreshLedger', so ledger
--     isolation is unchanged.
--
-- The @prepare@ hook lets a caller (the JSON entry point) write extra bindings
-- (ASSUME'd variables) into each fresh pass's combined environment before the
-- directive is evaluated.
forEachDirectiveFreshHeap
  :: (Environment -> Eval ())     -- ^ per-pass preparation over the fresh combined env (e.g. JSON writes)
  -> (EvalDirective -> Eval r)    -- ^ how to run one directive ('nfDirective', or its step-logging form)
  -> Environment                  -- ^ base env (imports <> initial environment), allocated once
  -> Module Resolved
  -> Int                          -- ^ number of directives (from the first pass)
  -> Eval [r]
forEachDirectiveFreshHeap prepare runDirective baseEnv m n =
  for [0 .. n - 1] $ \i -> do
    (moduleEnv, dirs) <- evalModule baseEnv m  -- fresh preAllocate => fresh IORefs => Unevaluated CAFs
    prepare (moduleEnv <> baseEnv)
    case drop i dirs of
      (d : _) -> runDirective d
      []      -> error "forEachDirectiveFreshHeap: directive index out of range (evalModule produced fewer directives than the first pass)"

-- | Evaluate module with JSON input bindings for batch processing.
-- JSON keys are matched to ASSUME'd L4 variables by name.
-- The approach: first evaluate the module normally (which pre-allocates References),
-- then write JSON values into the References for ASSUME'd variables.
evalModuleAndDirectivesWithJSON :: Aeson.Value -> Environment -> Module Resolved -> Eval (Environment, [EvalDirectiveResult])
evalModuleAndDirectivesWithJSON json env m = do
  ienv <- initialEnvironment
  let baseEnv = env <> ienv
  -- First pass: get moduleEnv (exports) and the directive count for the return value.
  (moduleEnv, dirs0) <- evalModule baseEnv m
  -- Same CAF-isolation rebuild as 'evalModuleAndDirectivesWith', but the per-pass
  -- 'prepare' hook re-applies the JSON ASSUME bindings to EACH fresh heap's
  -- combined environment — otherwise the freshly re-thunked References would lack
  -- the JSON-provided values.
  results <- forEachDirectiveFreshHeap (writeJSONToReferences json) nfDirective baseEnv m (length dirs0)
  pure (moduleEnv, results)

execEvalModuleWithJSON :: EvalConfig -> EntityInfo -> Aeson.Value -> Module Resolved -> IO (Environment, [EvalDirectiveResult])
execEvalModuleWithJSON evalConfig entityInfo json m0@(MkModule _ moduleUri _) = do
  -- @l4 batch@: the JSON is written into the module-level References, which are
  -- the ROOT of the evaluation, so discharge and a JSON supply compose — a
  -- definition reads its binder through its own parameter, and the value that
  -- parameter is handed at the root is the one the request supplied.
  let m = dischargeModuleWith evalConfig.presumeDefaults m0
  st0 <- mkInitialEvalState evalConfig entityInfo moduleUri
  let st = withDefaultsKnown evalConfig noRootFills m0 [] st0
  r <- try (runEval st (evalModuleAndDirectivesWithJSON json emptyEnvironment m))
  case r of
    Left exc -> do
      hPutStrLn stderr $ "Eval failure in module: " <> show moduleUri
      traverse_ (hPutStrLn stderr . Text.unpack) (prettyEvalException exc)
      pure (emptyEnvironment, [])
    Right result -> pure result

{- | Evaluate an expression in the context of a module and initial environment.

Didn't try to cache even more computation with rules,
because the current Rule type seems to
be Uri-focused, and so you'll emd up needing to pretty print and then re-parse.
Also, it's not clear how much caching can actually be done,
given that we won't be re-using the result from this.
 -}
execEvalExprInContextOfModule :: EvalConfig -> EntityInfo -> Expr Resolved -> (Environment, Module Resolved) -> IO (Maybe EvalDirectiveResult)
execEvalExprInContextOfModule evalConfig entityInfo =
  execEvalExprInContextOfModuleWith evalConfig entityInfo noRootFills []

-- | 'execEvalExprInContextOfModule' with the caller's root fills (definitions
-- it added to the module, each holding a default it filled for an input the
-- request left out) and the modules whose record field defaults the JSON
-- decoder should know beside the module's own.
execEvalExprInContextOfModuleWith :: EvalConfig -> EntityInfo -> RootFills -> [Declare Resolved] -> Expr Resolved -> (Environment, Module Resolved) -> IO (Maybe EvalDirectiveResult)
execEvalExprInContextOfModuleWith evalConfig entityInfo rootFills imported expr (env, m) = do
  let
    evalExprDirective =
      Directive emptyAnno $ LazyEval emptyAnno expr
    -- Didn't make a new module that imported the context module,
    -- because making the import requires a Resolved.
    -- Filter directives recursively (including in nested sections)
    moduleWithoutDirectives = filterDirectivesFromModule m
  (_, res) <- execEvalModuleWithDefaults rootFills imported nfDirective evalConfig entityInfo env (evalExprDirective `prependToModule` moduleWithoutDirectives)
  case res of
    [result] -> pure (Just result)
    _        -> pure Nothing
  where
    prependToModule :: TopDecl Resolved -> Module Resolved -> Module Resolved
    prependToModule newDecl = over moduleTopDecls (newDecl :)

-- | Recursively filter out all Directive nodes from a module (including nested sections)
filterDirectivesFromModule :: Module Resolved -> Module Resolved
filterDirectivesFromModule (MkModule ann uri section) =
  MkModule ann uri (filterDirectivesFromSection section)

filterDirectivesFromSection :: Section Resolved -> Section Resolved
filterDirectivesFromSection (MkSection sann sresolved maka mgiven decls) =
  MkSection sann sresolved maka mgiven (mapMaybe filterTopDecl decls)
  where
    filterTopDecl :: TopDecl Resolved -> Maybe (TopDecl Resolved)
    filterTopDecl (Directive _ _) = Nothing  -- Remove directives
    filterTopDecl (Section ann sec) = Just (Section ann (filterDirectivesFromSection sec))  -- Recurse into sections
    filterTopDecl other = Just other  -- Keep everything else
