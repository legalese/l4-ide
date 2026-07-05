{-# LANGUAGE GADTs #-}
module L4.EvaluateLazy
( EvalConfig(..)
, resolveEvalConfig
, resolveEvalConfigWithSafeMode
, parseFixedNow
, readFixedNowEnv
, EvalDirectiveResult (..)
, EvalDirectiveValue(..)
, EntityInfo
, getTemporalContext
, setTemporalContext
, withEvalClauses
, execEvalModuleWithEnv
, execEvalModuleWithJSON
, execEvalExprInContextOfModule
, prettyEvalException
, prettyEvalDirectiveResult
, prettyEvalDirectiveResultWithFields
, prettyLedger
  -- * Ledger substrate (M0). Exposed for the test suite; not part of the
  -- stable public API.
, Eval
, tellEvent
, currentLedger
, currentStore
, runEvalAction
, evalExprForLedger
)
where

import Base
import qualified Base.DList as DList
import qualified Base.Map as Map
import qualified Base.Text as Text
import L4.EvaluateLazy.Machine
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
import L4.Parser.SrcSpan (SrcRange)
import L4.Annotation
import L4.Print
import L4.Syntax
import L4.TypeCheck.Types (EntityInfo)
import L4.TemporalContext (EvalClause, TemporalContext, applyEvalClauses, initialTemporalContext)
import L4.TracePolicy (TracePolicy)

import Control.Exception (throwIO, try)
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
  }

resolveEvalConfig :: Maybe UTCTime -> TracePolicy -> IO EvalConfig
resolveEvalConfig mTime tracePolicy = resolveEvalConfigWithSafeMode mTime tracePolicy False

resolveEvalConfigWithSafeMode :: Maybe UTCTime -> TracePolicy -> Bool -> IO EvalConfig
resolveEvalConfigWithSafeMode mTime tracePolicy safe =
  pure (EvalConfig mTime tracePolicy safe)

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
  local (\s -> s { envLedger = fresh, currentParty = freshParty }) m

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

runConfig :: Config -> Eval WHNF
runConfig = \ case
  ForwardMachine env expr -> do
    traceEval (Enter expr)
    next <- forwardExpr env expr
    runConfig next
  MatchBranchesMachine scrutinee env branches -> do
    next <- matchBranches scrutinee env branches
    runConfig next
  MatchPatternMachine r env pat -> do
    next <- matchPattern r env pat
    runConfig next
  BackwardMachine whnf -> do
    traceEval (Exit (Right whnf))
    next <- backward whnf
    runConfig next
  EvalRefMachine r -> do
    traceEval (SetRef r)
    next <- evalRef r
    runConfig next
  DoneMachine whnf ->
    pure whnf

-- | Evaluate an EVAL directive. For this, we evaluate to normal form,
-- not just WHNF.
nfDirective :: EvalDirective -> Eval EvalDirectiveResult
nfDirective (MkEvalDirective r traced isAssert expr env) = withFreshLedger $ do
  (v, mt) <-
    if traced
      then second Just <$> do
        captureTrace $ tryEval $ do
          whnf <- runConfig $ ForwardMachine env expr
          nf whnf
      else fmap (, Nothing) $ tryEval $ do
        whnf <- runConfig $ ForwardMachine env expr
        nf whnf
  -- STATE-AS-LEDGER M2/M4: snapshot the per-directive ledger STORE (per-party
  -- own ledgers + the official record) BEFORE 'withFreshLedger' restores the
  -- caller's (empty) store and discards this one. This is the directive's whole
  -- event log — the RECORD 'Assign's per party plus the COMMIT/ATTEST 'Assign's
  -- in the official record. D5 (keep-on-breach) falls out for free: 'tellEvent'
  -- is an append and 'ValBreached' does not roll back, so any pre-breach
  -- 'Assign' is already in here.
  directiveLedger <- currentStore
  let
    finalTrace = postprocessTrace <$> mt
    v' =
      if isAssert
        then Assertion
          case v of
            Right (MkNF (ValBool True)) -> True
            _                           -> False
        else Reduction v
  pure (MkEvalDirectiveResult r v' finalTrace directiveLedger)

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
    }
  deriving stock (Generic, Show)
  deriving anyclass NFData

data EvalDirectiveValue =
    Assertion Bool
  | Reduction (Either EvalException NF)
  deriving stock (Generic, Show)
  deriving anyclass NFData

prettyEvalDirectiveValue :: EvalDirectiveValue -> Text
prettyEvalDirectiveValue (Assertion True)       = "assertion satisfied"
prettyEvalDirectiveValue (Assertion False)      = "assertion failed"
prettyEvalDirectiveValue (Reduction (Left exc)) = Text.unlines (prettyEvalException exc)
prettyEvalDirectiveValue (Reduction (Right v))  = prettyLayout v

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
  "[" <> Text.intercalate ", " (catMaybes [partyField, sourceField, atField]) <> "]"
  where
    partyField  = if Text.null prov.party then Nothing else Just ("party=" <> prov.party)
    sourceField = Just ("source=" <> prov.source)
    atField     = ("at=" <>) <$> prov.position

-- | Prints the results but not the range of an eval directive, including
-- the trace if present, and the ledger section if the directive wrote anything.
--
prettyEvalDirectiveResult :: EvalDirectiveResult -> Text
prettyEvalDirectiveResult (MkEvalDirectiveResult _range res mtrace led) =
   prettyEvalDirectiveValue res
   <> prettyLedger led
   <> case mtrace of
        Nothing -> Text.empty
        Just t  -> "\n─────\n" <> prettyLayout t

-- | Like 'prettyEvalDirectiveResult' but uses named-field syntax (WITH / IS)
-- for constructors whose field names are provided.
prettyEvalDirectiveResultWithFields :: ConstructorFieldNames -> EvalDirectiveResult -> Text
prettyEvalDirectiveResultWithFields fields (MkEvalDirectiveResult _range res mtrace led) =
   prettyEvalDirectiveValueWithFields fields res
   <> prettyLedger led
   <> case mtrace of
        Nothing -> Text.empty
        Just t  -> "\n─────\n" <> prettyLayout t

-- ----------------------------------------------------------------------------
-- ToJSON instances for batch --json output
-- ----------------------------------------------------------------------------

instance Aeson.ToJSON EvalDirectiveResult where
  toJSON (MkEvalDirectiveResult _range res _trace _ledger) = Aeson.object
    [ "result" Aeson..= res
    , "trace"  Aeson..= Aeson.Null
    ]

instance Aeson.ToJSON EvalDirectiveValue where
  toJSON (Assertion b) = Aeson.object
    [ "type"  Aeson..= ("assertion" :: Text)
    , "value" Aeson..= b
    ]
  toJSON (Reduction (Right val)) = Aeson.toJSON val
  toJSON (Reduction (Left exc)) = Aeson.object
    [ "error" Aeson..= Text.unlines (prettyEvalException exc)
    ]

prettyEvalDirectiveValueWithFields :: ConstructorFieldNames -> EvalDirectiveValue -> Text
prettyEvalDirectiveValueWithFields _fields (Assertion True)        = "assertion satisfied"
prettyEvalDirectiveValueWithFields _fields (Assertion False)       = "assertion failed"
prettyEvalDirectiveValueWithFields _fields (Reduction (Left exc))  = Text.unlines (prettyEvalException exc)
prettyEvalDirectiveValueWithFields fields  (Reduction (Right v))   = prettyLayoutNF fields v

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
nfAux d (ValObligation env party act due followup lest) = do
  party' <- traverseAndNF d party
  due' <- traverseAndNF d due
  pure (MkNF (ValObligation env party' act due' followup lest))
nfAux _d (ValUnaryBuiltinFun b)      = pure (MkNF (ValUnaryBuiltinFun b))
nfAux _d (ValBinaryBuiltinFun b)     = pure (MkNF (ValBinaryBuiltinFun b))
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
nfAux _d (ValAssumed n)              = pure (MkNF (ValAssumed n))
nfAux _d (ValEnvironment env)        = pure (MkNF (ValEnvironment env))
nfAux d (ValBreached r')             = do
  r <- case r' of
    DeadlineMissed ev'party ev'act ev'timestamp party act deadline -> do
      ev'party' <- evalAndNF d ev'party
      act' <- evalAndNF d ev'act
      party' <- evalAndNF d party
      pure (DeadlineMissed ev'party' act' ev'timestamp party' act deadline)
    ExplicitBreach mParty mReason -> do
      mParty' <- traverse (evalAndNF d) mParty
      mReason' <- traverse (evalAndNF d) mReason
      pure (ExplicitBreach mParty' mReason')
  pure (MkNF (ValBreached r))
nfAux d (ValROp env op l r) = do
  l' <- traverseAndNF d l
  r' <- traverseAndNF d r
  pure (MkNF (ValROp env op l' r'))

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
execEvalModuleWithEnv evalConfig entityInfo env m@(MkModule _ moduleUri _) = do
  st0 <- mkInitialEvalState evalConfig entityInfo moduleUri
  r <- try (runEval st0 (evalModuleAndDirectives env m))
  case r of
    Left exc -> do
      hPutStrLn stderr $ "Eval failure in module: " <> show moduleUri
      traverse_ (hPutStrLn stderr . Text.unpack) (prettyEvalException exc)
      -- exceptions at the top-level are unusual; after all, we don't actually
      -- force any evaluation here, and we catch exceptions for eval directives
      pure (emptyEnvironment, [])
    Right result -> pure result

mkInitialEvalState :: EvalConfig -> EntityInfo -> NormalizedUri -> IO EvalState
mkInitialEvalState evalConfig entityInfo moduleUri = do
  stack     <- newIORef emptyStack
  supply    <- newIORef 0
  actualTime <- resolveEvalTime evalConfig
  let temporalCtx = initialTemporalContext actualTime
  temporalContext <- newIORef temporalCtx
  let evalTrace = Nothing
  envLedger    <- newIORef emptyStore
  currentParty <- newIORef Nothing
  pure MkEvalState {moduleUri, stack, supply, evalTrace, envLedger, currentParty, entityInfo, evalTime = actualTime, temporalContext, tracePolicy = evalConfig.tracePolicy, safeMode = evalConfig.safeMode}

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

-- TODO: This currently allocates the initial environment once per module.
-- This isn't a big deal, but can we somehow do this only once per program,
-- for example by passing this in from the outside?
evalModuleAndDirectives :: Environment -> Module Resolved -> Eval (Environment, [EvalDirectiveResult])
evalModuleAndDirectives env m = do
  ienv <- initialEnvironment
  (env', directives) <- evalModule (env <> ienv) m
  results <- traverse nfDirective directives
  -- NOTE: We are only returning the new definitions of this module, not any imports.
  -- Depending on future export semantics, this may have to change.
  pure (env', results)

-- | Evaluate module with JSON input bindings for batch processing.
-- JSON keys are matched to ASSUME'd L4 variables by name.
-- The approach: first evaluate the module normally (which pre-allocates References),
-- then write JSON values into the References for ASSUME'd variables.
evalModuleAndDirectivesWithJSON :: Aeson.Value -> Environment -> Module Resolved -> Eval (Environment, [EvalDirectiveResult])
evalModuleAndDirectivesWithJSON json env m = do
  ienv <- initialEnvironment
  (moduleEnv, dirs) <- evalModule (env <> ienv) m
  -- Now write JSON values into the pre-allocated References
  -- The combined environment includes both the initial env and the moduleEnv
  let combinedEnv = moduleEnv <> env <> ienv
  writeJSONToReferences json combinedEnv
  results <- traverse nfDirective dirs
  pure (moduleEnv, results)

execEvalModuleWithJSON :: EvalConfig -> EntityInfo -> Aeson.Value -> Module Resolved -> IO (Environment, [EvalDirectiveResult])
execEvalModuleWithJSON evalConfig entityInfo json m@(MkModule _ moduleUri _) = do
  st0 <- mkInitialEvalState evalConfig entityInfo moduleUri
  r <- try (runEval st0 (evalModuleAndDirectivesWithJSON json emptyEnvironment m))
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
execEvalExprInContextOfModule evalConfig entityInfo expr (env, m) = do
  let
    evalExprDirective =
      Directive emptyAnno $ LazyEval emptyAnno expr
    -- Didn't make a new module that imported the context module,
    -- because making the import requires a Resolved.
    -- Filter directives recursively (including in nested sections)
    moduleWithoutDirectives = filterDirectivesFromModule m
  (_, res) <- execEvalModuleWithEnv evalConfig entityInfo env (evalExprDirective `prependToModule` moduleWithoutDirectives)
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
filterDirectivesFromSection (MkSection sann sresolved maka decls) =
  MkSection sann sresolved maka (mapMaybe filterTopDecl decls)
  where
    filterTopDecl :: TopDecl Resolved -> Maybe (TopDecl Resolved)
    filterTopDecl (Directive _ _) = Nothing  -- Remove directives
    filterTopDecl (Section ann sec) = Just (Section ann (filterDirectivesFromSection sec))  -- Recurse into sections
    filterTopDecl other = Just other  -- Keep everything else
