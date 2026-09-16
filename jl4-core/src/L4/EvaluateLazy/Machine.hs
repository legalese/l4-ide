{-# LANGUAGE CPP #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE GADTs #-}
module L4.EvaluateLazy.Machine
( Frame
, module L4.EvaluateLazy.Exceptions
, Machine
, Eval
, EvalState (..)
, Stack (..)
, emptyStack
, runEval
, tryEval
, traceEval
, raiseException
, withPoppedFrame
, newUnique
, getTemporalContext
, putTemporalContext
, swapCtxReads
, getEvalTime
, getModuleUri
, getSafeMode
, formatUTCTimeIso
-- * STATE-AS-LEDGER substrate. Exposed for the test suite and the high-level
-- driver in 'L4.EvaluateLazy'; not part of the stable public API.
, tellEventRouted
-- * The deontic step log (LTS-VISUALISER §4.3, P2b). 'tellDeonticStep' is
-- the write; the capture lives in 'L4.EvaluateLazy'.
, tellDeonticStep
, partyKeyWHNF
-- * What the marking (LTS-VISUALISER §4.2a, P2c) needs to read a residual:
-- the barrier sentinels' names and the FULFILLED view.
, joinCheckpointName
, joinFailpointName
, pattern ValFulfilled
-- * What the what-if (LTS-VISUALISER §2.4: no second semantics) needs to
-- read an anchored deadline (R-Q7B/C) off a residual without re-deriving it:
-- the lifecycle an environment carries, and the anchor's lowering.
, lifecycleOf
, anchorInstant
, currentLedgerEval
, readEvalRef
, Note (..)
, tellNote
, Config (..)
, forwardExpr
, matchBranches
, matchPattern
, backward
, EvalDirective (..)
, AssertKind (..)
, evalModule
, initialEnvironment
, evalRef
, emptyEnvironment
, boolView
, pattern ValBool
-- * Constants exposed for the eager evaluator
, builtinBinOps
, writeJSONToReferences
)
where

import Base
import qualified Base.DList as DList
import qualified Base.Text as Text
import qualified Base.Map as Map
import qualified Base.Set as Set
import Control.Concurrent
import System.Environment (lookupEnv)
import qualified Data.ByteString as BS
import qualified Data.Text.Encoding as TE
#ifdef HTTP_ENABLED
import           Network.HTTP.Req ((=:))
import qualified Network.HTTP.Req as Req
import qualified Data.ByteString.Lazy.Char8 as LBS
#endif
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Vector as Vector
import qualified Data.Text.Read as TR
import qualified Data.Char as Char
import Data.Either (isLeft)
import Data.Fixed (Pico)
import Data.Time (UTCTime)
import qualified Data.Time as Time
import Data.Time.LocalTime (TimeOfDay(..), LocalTime(..), timeToTimeOfDay, timeOfDayToTime)
import qualified Data.Time.Format as TimeFormat
import qualified Data.Time.Zones as TZ
import qualified Data.Time.Zones.All as TZAll
import L4.Annotation
import L4.Evaluate.Ledger
  ( EventRoute (..)
  , Ledger
  , LedgerEvent (..)
  , LedgerStore (..)
  , Provenance (..)
  , anonymousParty
  , readCellBitemporal
  , readCellAllBitemporal
  , storeAppendOfficial
  , storeAppendOwn
  , storeOwnLedger
  )
import L4.Evaluate.Operators
import L4.Evaluate.ValueLazy
import L4.TemporalContext (CtxReads (..), EvalClause (..), ReadObs (..), TemporalContext (..), applyEvalClauses, hasReads, noReads, validFor)
import L4.Parser.SrcSpan (SrcRange, prettySrcRangeM)
import L4.Print hiding (tryLoadTZ, tryLoadTZPure, formatDateTimeIso)
import L4.Syntax
import qualified L4.TypeCheck as TypeCheck
import L4.TypeCheck.Types (EntityInfo)
import L4.EvaluateLazy.ContractFrame
import L4.EvaluateLazy.DeonticStep hiding (Branch)
import qualified L4.EvaluateLazy.DeonticStep as DS
import L4.EvaluateLazy.Exceptions
import L4.EvaluateLazy.Trace (EvalTraceAction (..))
import L4.TracePolicy (TracePolicy)
import qualified L4.TracePolicy as TracePolicy
import L4.Utils.Ratio
import Text.Read (readMaybe)
import qualified Data.Scientific as Sci
import System.IO.Unsafe (unsafePerformIO)
import Control.Exception (SomeException, catch)
import qualified Control.Exception

data Frame =
    BinOp1 BinOp {- -} (Expr Resolved) Environment
  | BinOp2 BinOp WHNF {- -}
  | Post1 {- -} (Expr Resolved) (Expr Resolved) Environment
  | Post2 WHNF {- -} (Expr Resolved) Environment
  | Post3 WHNF WHNF {- -}
  -- STATE-AS-LEDGER: RECORD/COMMIT/ATTEST (+ NOTIFY-v1 recipient). When a
  -- @RECORD q's <cell> IS <v>@ carries a recipient qualifier, we evaluate the
  -- recipient FIRST (mirroring 'ReadCell2'): 'Record0' holds the still-unevaluated
  -- cell + value exprs, the env, isOfficial, and the M5 HENCE while the recipient
  -- party expr evaluates; on its WHNF we key via 'partyKeyWHNF' and thread that
  -- recipient key through the rest of the write.
  --
  -- 'Record1' waits for the cell to evaluate (holds the still-unevaluated value
  -- expr, its env, isOfficial, the M5 HENCE, and the resolved recipient key —
  -- 'Nothing' for a bare own write, @Just rk@ for a NOTIFY write); 'Record2'
  -- waits for the value (holds the evaluated cell WHNF, isOfficial, the HENCE,
  -- the env, and the recipient key). The 'Maybe (Expr Resolved)' is the M5 HENCE:
  -- 'Nothing' is M1 expression use (the write returns its value); @Just k@ makes
  -- the write an event-free deontic step (after 'tellEvent', forward
  -- @[time, events]@ to @k@). The 'Maybe Text' is the NOTIFY recipient key.
  | Record0 {- -} (Expr Resolved) (Expr Resolved) Environment Bool (Maybe (Expr Resolved))
  | Record1 {- -} (Expr Resolved) Environment Bool (Maybe (Expr Resolved)) (Maybe Text)
  | Record2 WHNF {- -} Bool Environment (Maybe (Expr Resolved)) (Maybe Text)
  -- STATE-AS-LEDGER M1.5 / M4.5: RECALL. 'ReadCell1' waits for the CELL to
  -- evaluate to a 'WHNF'; it carries the optional party-qualifier expr (still
  -- unevaluated), the isOfficial flag, and the env to evaluate the qualifier in.
  -- Once the cell is in hand we branch on the qualifier:
  --   * isOfficial          -> read the OFFICIAL ledger, finish.
  --   * Just partyExpr       -> push 'ReadCell2' (holding the cell WHNF) and
  --                             forward-eval the party expr; on its value we key
  --                             via 'partyKeyWHNF' and read that party's ledger.
  --   * Nothing (default)    -> read the CURRENT party's own ledger, finish.
  -- The 'RecallMode' (last-write-wins vs collect-all, approach B) is carried
  -- through to 'finishRead' so the read folds the chosen ledger into either a
  -- MAYBE (last) or a LIST (all).
  | ReadCell1 {- -} (Maybe (Expr Resolved)) Bool RecallMode Environment
  -- 'ReadCell2' waits for the PARTY qualifier to evaluate; it carries the
  -- already-evaluated cell WHNF and the 'RecallMode' so 'finishRead' can complete
  -- the read against the named party's own ledger. The mode MUST be threaded here
  -- too: the cross-party branch pushes 'ReadCell2' before reaching 'finishRead',
  -- so without it @RECALL ALL <party>'s@ would silently fall back to last-write-wins.
  | ReadCell2 WHNF RecallMode {- -}
  -- STATE-AS-LEDGER M4: restore the acting party once a HENCE/LEST body (and its
  -- App1 continuation) has fully evaluated. Pushed by 'continueWithFollowup'
  -- BEFORE the followup runs (so it is processed LAST, after the whole subtree),
  -- mirroring the 'EvalAsOfSystemTime2' save/restore-frame idiom. Carries the
  -- party to restore TO (the enclosing party, or Nothing at the outer level).
  | RestoreCurrentParty (Maybe Text)
  | App1 {- -} [Reference] (Maybe (Type' Resolved)) -- Added type for type-directed builtins
  | IfThenElse1 {- -} (Expr Resolved) (Expr Resolved) Environment
  | ConsiderWhen1 Reference {- -} (Expr Resolved) [Branch Resolved] Environment
  | PatNil0
  | PatCons0 (Pattern Resolved) Environment (Pattern Resolved)
  | PatCons1 {- -} Reference Environment (Pattern Resolved)
  | PatCons2 Environment {- -}
  | PatLit0 Environment (Expr Resolved) -- env, literal
  | PatLit1 WHNF -- the scrutinee
  | PatLit2
  | PatApp0 Resolved Environment [Pattern Resolved]
  | PatApp1 Environment [Environment] {- -} [(Reference, Pattern Resolved)]
    -- ^ The FIRST field is the AMBIENT environment the whole pattern is being
    -- matched in; the second accumulates the binding environments the
    -- sub-patterns have produced so far. Keeping them apart is load-bearing:
    -- an @EXACTLY e@ sub-pattern evaluates @e@, and it must do so where the
    -- pattern was written, not where the previous sub-pattern's bindings
    -- live. 'PatCons0'\/'PatCons1' already carry the ambient environment this
    -- way; 'PatApp1' did not, which is why @Pay (EXACTLY t) (EXACTLY theLandlord)@
    -- reported @theLandlord is not in scope@ while
    -- @Pay (EXACTLY theLandlord) payee@ worked.
  | EqConstructor1 {- -} Reference [(Reference, Reference)]
  | EqConstructor2 WHNF {- -} [(Reference, Reference)]
  | EqConstructor3 {- -} [(Reference, Reference)]
  | UnaryBuiltin0 UnaryBuiltinFun (Maybe (Type' Resolved)) -- Added type for type-directed decoding
  | BinBuiltin1 BinOp Reference
  | BinBuiltin2 BinOp WHNF
  -- Ternary builtin frames: accumulate evaluated args
  | TernaryBuiltin1 TernaryBuiltinFun Reference Reference  -- evaluating 1st arg, has refs to 2nd and 3rd
  | TernaryBuiltin2 TernaryBuiltinFun WHNF Reference       -- has 1st arg value, evaluating 2nd, has ref to 3rd
  | TernaryBuiltin3 TernaryBuiltinFun WHNF WHNF            -- has 1st and 2nd arg values, evaluating 3rd
  -- Temporal context scoping for EVAL AS OF SYSTEM TIME
  | EvalAsOfSystemTime1 Reference Environment
  | EvalAsOfSystemTime2 TemporalContext
  -- Temporal context scoping for EVAL UNDER VALID TIME
  | EvalUnderValidTime1 Reference Environment
  | EvalUnderValidTime2 TemporalContext
  -- Temporal context scoping for rules effective time
  | EvalUnderRulesEffectiveAt1 Reference Environment
  | EvalUnderRulesEffectiveAt2 TemporalContext
  -- Temporal context scoping for rules encoded time
  | EvalUnderRulesEncodedAt1 Reference Environment
  | EvalUnderRulesEncodedAt2 TemporalContext
  -- Temporal iteration frames
  | EverBetweenFrame TemporalContext WHNF Time.Day Time.Day Integer
  | AlwaysBetweenFrame TemporalContext WHNF Time.Day Time.Day Integer
  | WhenLastFrame TemporalContext WHNF Time.Day
  | WhenNextFrame TemporalContext WHNF Time.Day Time.Day
  | ValueAtFrame TemporalContext
  -- Deep pinning (smucclaw/l4-ide#934): see 'startDeepPin'
  | DeepPinRestore TemporalContext
  | DeepPinStep !Int !(Set Address) [(Int, Reference)] WHNF
  | UpdateThunk Reference !CtxReads !(Maybe (CtxReads, WHNF))
    -- ^ write-back frame for a thunk force; carries the ENCLOSING span's
    -- saved read accumulator, merged back in 'backward' (T6), plus the
    -- displaced 'WHNFWhen' cache (fingerprint, value) when this force
    -- re-forces a stale context-dependent cache — so an aborted force can
    -- put the still-fingerprint-guarded cache back ('unwindFrame')
  | ContractFrame ContractFrame
  | ConcatFrame [WHNF] {- -} [Expr Resolved] Environment -- accumulated values, remaining exprs, env
  | AsStringFrame -- AsString frame
  | ToStringDate1 Reference Reference -- evaluating DATE day, have month & year refs
  | ToStringDate2 Rational Reference  -- have day, evaluating month, have year ref
  | ToStringDate3 Rational Rational   -- have day & month, evaluating year
  | JsonEncodeListFrame [Text] {- -} Reference Bool -- accumulated JSON strings, tail reference, expecting_tail (True = next value is tail, False = next value is element)
  | JsonEncodeNestedFrame [Text] {- -} Reference -- accumulated JSON strings, tail reference (waiting for element encoding to complete)
  | JsonEncodeConstructorFrame [(Text, Text)] Text [(Text, Reference)] -- accumulated (fieldName, encodedJson) pairs, current field name, remaining (fieldName, fieldRef) pairs to encode
  deriving stock Show

-- ----------------------------------------------------------------------------
-- The evaluation monad.
--
-- This used to be a defunctionalized free monad ('Machine' as a GADT with a
-- 'Bind' constructor) interpreted into an @ExceptT EvalException (ReaderT
-- EvalState IO)@ stack. That double interpretation dominated evaluation
-- allocation (every machine step allocated GADT nodes, interpreter closures
-- and 'Either' results, and it kept GHC from inlining the primitives).
-- It is now a plain reader-over-IO monad: exceptions are thrown as
-- synchronous IO exceptions ('EvalException' has an 'Exception' instance)
-- and caught at directive boundaries via 'tryEval'.
-- ----------------------------------------------------------------------------

data EvalState =
  MkEvalState
    { moduleUri  :: !NormalizedUri
    , stack      :: !(IORef Stack)
    , supply     :: !(IORef Int)   -- used for uniques and addresses
    , evalTrace  :: !(Maybe (IORef (DList EvalTraceAction)))
    , envLedger  :: !(IORef LedgerStore) -- append-only event store (M0 substrate, M4
                                         -- per-party + official record); always collected
                                         -- (non-optional, unlike evalTrace)
    , currentParty :: !(IORef (Maybe Text))
                                     -- ^ M4: the party whose deontic HENCE/LEST we are
                                     -- currently inside, so a RECORD fired there routes to
                                     -- that party's own ledger. 'Nothing' = no enclosing
                                     -- party (a top-level RECORD), routed to the anonymous
                                     -- own ledger. Set/restored around 'continueWithFollowup'.
    , entityInfo :: !EntityInfo    -- type information for constructors/records
    , evalTime   :: !UTCTime
    , temporalContext :: !(IORef TemporalContext)
    , ctxReads   :: !(IORef CtxReads)
      -- ^ temporal-context observations made since entering the innermost
      -- in-flight thunk-force span (T6). Single-threaded within a run
      -- (EvalState is constructed per run); cross-run sharing is handled at
      -- cache-serve time via 'validFor'.
    , tracePolicy :: !TracePolicy  -- controls trace collection and output
    , safeMode   :: !Bool          -- when True, HTTP operations return errors
    , reofferedEvents :: !(IORef (Map Address Reoffered))
      -- ^ the EVENT copies an expiring obligation has re-offered to its
      -- HENCE/LEST continuation, each keyed by its store address and
      -- carrying its 'Reoffered' mark: the latest deadline it has revealed
      -- the expiry of, and how many hand-offs in a row failed to pass it
      -- (see the Contract5 expiry NOTE in 'backwardContractFrame'). The
      -- mark never withholds an event from a layer; it only lets the
      -- machine refuse a chain whose deadlines have stopped advancing,
      -- loudly, instead of walking it forever.
    , notes :: !(IORef (DList Note))
      -- ^ what the run wants REPORTED without failing: a non-fatal note,
      -- appended by 'tellNote', collected per directive (swapped fresh by
      -- 'L4.EvaluateLazy.withFreshLedger', read back into the directive's
      -- result beside the ledger) and printed after the value. The first
      -- occupant is R-X6's early act (EVERY-EACH-QUANTIFIER-SPEC §5.1.2,
      -- 2026-09-16): an act before its window opened is a nullity, and a
      -- silent nullity is how a party loses a deadline it believed it had
      -- met; the second is the empty window a run reveals. Nothing here is
      -- an error: the value stands.
    , deonticLog :: !(Maybe DeonticLog)
      -- ^ LTS-VISUALISER §4.3 (P2b): the deontic step log, OPTIONAL and off
      -- by default exactly as 'evalTrace' is (ruling R5, §8). 'Nothing' means
      -- no call site computes anything; 'L4.EvaluateLazy.captureDeonticSteps'
      -- installs one for the duration of a directive.
    }

-- | A note the run reports beside a directive's value ('EvalState.notes').
-- Plain text: rendered where it is raised, from what the machine has in
-- hand at that point ('peekNF' for a party).
newtype Note = MkNote Text
  deriving stock (Show, Eq, Generic)
  deriving anyclass NFData

-- | Report something without failing (see 'EvalState.notes').
tellNote :: Text -> Eval ()
tellNote t = do
  notesRef <- asks (.notes)
  liftIO (modifyIORef' notesRef (`DList.snoc` MkNote t))

data Stack =
  MkStack
    { size   :: !Int
    , frames :: [Frame]
    }
  deriving stock (Generic, Show)

emptyStack :: Stack
emptyStack = MkStack 0 []

newtype Eval a = MkEval (EvalState -> IO a)
  deriving (Functor, Applicative, Monad, MonadReader EvalState, MonadIO)
    via ReaderT EvalState IO

-- | The historical name of the evaluation monad; the machine code below is
-- written against this alias.
type Machine = Eval

runEval :: EvalState -> Eval a -> IO a
runEval s (MkEval f) = f s

-- | Catch evaluation exceptions (used at directive boundaries).
tryEval :: Eval a -> Eval (Either EvalException a)
tryEval (MkEval f) = MkEval \s -> Control.Exception.try (f s)

nextSupply :: Eval Int
nextSupply = do
  supplyRef <- asks (.supply)
  liftIO do
    i <- readIORef supplyRef
    writeIORef supplyRef $! i + 1
    pure i

newUnique :: Eval Unique
newUnique = do
  i <- nextSupply
  u <- asks (.moduleUri)
  pure (MkUnique 'e' i u)

newAddress :: Eval Address
newAddress = do
  i <- nextSupply
  u <- asks (.moduleUri)
  pure (MkAddress u i)

traceEval :: EvalTraceAction -> Eval ()
traceEval ta = do
  mtr <- asks (.evalTrace)
  case mtr of
    Nothing -> pure ()
    Just tr -> liftIO (modifyIORef' tr (`DList.snoc` ta))

-----------------------------------------------------------------------------
-- The deontic step log (LTS-VISUALISER §4.3, amended by §4.9; P2b).
--
-- Modelled on 'traceEval': an optional IORef in the reader env, newest-last.
-- Every call site goes through 'whenDeonticLog', so with the log off the
-- machine computes nothing for it; what it does do is carry state it never
-- reads — a lazy 'NormKey' through the contract frames, @ev'reoffered@ past
-- @Contract5@ (the only frame that consults it), and a @pending@ step
-- (always 'Nothing' when off) on 'ResolvePartyFrame'. The types are in
-- "L4.EvaluateLazy.DeonticStep".
-----------------------------------------------------------------------------

-- | Run a log-side action only when the log is on. The action receives the
-- log so it can also bump the counters the key needs.
whenDeonticLog :: (DeonticLog -> Eval ()) -> Eval ()
whenDeonticLog k = asks (.deonticLog) >>= maybe (pure ()) k

-- | Append a step to the log, if there is one. The write; the read is
-- 'L4.EvaluateLazy.captureDeonticSteps'.
tellDeonticStep :: DeonticStep -> Eval ()
tellDeonticStep step = whenDeonticLog \ l -> logStep l step

logStep :: DeonticLog -> DeonticStep -> Eval ()
logStep l step = liftIO (modifyIORef' l.dlSteps (`DList.snoc` step))

-- | Log a step that ROUTES control (a 'Matched' or 'Expired'), filling in
-- §4.9's join progress from the norm's membership: a barrier member's
-- 'ToHence' satisfies one arm (and bumps the arm count), a fork member's
-- continuation runs on its own. The join's own release is NOT recorded here;
-- see 'JoinProgress'.
tellRoutedStep :: NormKey -> DS.Branch -> DeonticStep -> Eval ()
tellRoutedStep norm branch step = whenDeonticLog \ l -> do
  progress <- case (norm.nkMember, branch) of
    (Just m, ToHence) | isBarrier m.moJoin -> do
      n <- liftIO (bumpCounter l.dlJoinDone m.moJoinSite)
      pure (Just (MemberSatisfied n m.moTotal))
    (Just m, b) | m.moJoin == Fork, b /= ToBreach ->
      pure (Just (ForkContinued m.moIndex m.moTotal))
    _ -> pure Nothing
  logStep l step {dsNorm = Just norm, dsJoin = progress}

-- | Increment a per-key counter and return the new count (from 1).
bumpCounter :: Ord k => IORef (Map k Int) -> k -> IO Int
bumpCounter counter k = atomicModifyIORef' counter \ m ->
  let n = Map.findWithDefault 0 k m + 1 in (Map.insert k n m, n)

-- | Read a reference WITHOUT forcing it. The log must never change what the
-- machine evaluates, so anything it reports about an unforced thunk is
-- 'Nothing'.
peekWHNF :: Reference -> Eval (Maybe WHNF)
peekWHNF rf = liftIO (readIORef rf.pointer) >>= pure . \ case
  WHNF v            -> Just v
  WHNFWhen _ v _ _  -> Just v
  Unevaluated {}    -> Nothing

-- | The contract clock held in a reference, if it has been forced.
peekClock :: Reference -> Eval (Maybe Rational)
peekClock rf = peekWHNF rf >>= pure . \ case
  Just (ValNumber t) -> Just t
  _                  -> Nothing

-- | The party key of a forced party reference, if forced.
peekParty :: Reference -> Eval (Maybe Text)
peekParty rf = fmap partyKeyWHNF <$> peekWHNF rf

-- | The action of a forced action reference, if forced.
peekAction :: Reference -> Eval (Maybe Text)
peekAction rf = fmap prettyLayout <$> peekWHNF rf

-- | The event key for a scrutiny, from the pieces the frame holds. The
-- stamp is always in hand (it is what the deadline was compared with).
eventKeyAt :: Rational -> Maybe Text -> Reference -> Eval EventKey
eventKeyAt stamp mParty actRef = do
  action <- peekAction actRef
  pure MkEventKey {ekStamp = stamp, ekParty = mParty, ekAction = action}

-- | The scrutiny an event-bearing step reports (§4.4): a re-offered event's
-- second look is always 'Reoffered'; otherwise the site says. The argument
-- is the frame's @ev'reoffered@ — the mark a re-offered copy carries, or
-- 'Nothing' for a fresh event (spec §5.2.1; the mark's payload is the
-- machine's business, and the log reads only whether there is one).
scrutinyOf :: Maybe mark -> Scrutiny -> Scrutiny
scrutinyOf reoffered s = if isJust reoffered then Reoffered else s

-- | The key an obligation is armed with when it meets its event stream (the
-- @App1@ arm below). With the log off this is a lazy record that nothing
-- forces; with it on, the site's activation counter is bumped and the cast
-- register consulted for §4.9's per-member identity.
armNormKey :: MaybeEvaluated -> RAction Resolved -> Eval NormKey
armNormKey party act = do
  mlog <- asks (.deonticLog)
  let site   = rangeOf act
      bearer = either (const Nothing) (Just . partyKeyWHNF) party
  (activation, member) <- case mlog of
    Nothing -> pure (0, Nothing)
    Just l  -> do
      n <- liftIO (bumpCounter l.dlActivations site)
      m <- case bearer of
        Nothing -> pure Nothing
        Just b  -> liftIO (Map.lookup (site, b) <$> readIORef l.dlMembers)
      pure (n, m)
  pure MkNormKey
    { nkSite = site, nkActivation = activation, nkBearer = bearer
    , nkModal = act.modal, nkMember = member }

-- | Refresh a key's bearer once the machine has forced the party.
bearing :: WHNF -> NormKey -> NormKey
bearing v k = k {nkBearer = Just (partyKeyWHNF v)}

-- | The site an @EVERY@'s join steps are keyed by: the join line when there
-- is one, else the whole rule.
joinSiteOf :: Deonton Resolved -> Maybe SrcRange
joinSiteOf d = maybe (rangeOf d) rangeOf d.join

-- | The join's own key, made when the quantified obligation is armed
-- ('startRollCall'); it is what the barrier's 'JoinReleased' /
-- 'JoinExpired' / 'JoinFailed' steps carry.
armJoinKey :: Deonton Resolved -> Eval NormKey
armJoinKey d = do
  mlog <- asks (.deonticLog)
  let site = joinSiteOf d
  activation <- case mlog of
    Nothing -> pure 0
    Just l  -> liftIO (bumpCounter l.dlActivations site)
  pure MkNormKey
    { nkSite = site, nkActivation = activation, nkBearer = Nothing
    , nkModal = d.action.modal, nkMember = Nothing }

-- | Register an @EVERY@'s cast, so each member's obligation can find its
-- membership when it is armed ('armNormKey'). A barrier's arm count starts
-- at zero here.
registerCast :: QuantCtx -> JoinKind -> [CastMember] -> Eval ()
registerCast ctx kind members = whenDeonticLog \ l -> liftIO do
  let site  = rangeOf ctx.deonton.action
      jsite = joinSiteOf ctx.deonton
      total = length members
      entries =
        [ ((site, partyKeyWHNF mval), MkMemberOf {moJoin = kind, moIndex = i, moTotal = total, moJoinSite = jsite})
        | (i, (_, mval)) <- zip [1 ..] members ]
  modifyIORef' l.dlMembers (\ m -> foldl' (\ acc (k, v) -> Map.insert k v acc) m entries)
  modifyIORef' l.dlJoinDone (Map.insert jsite 0)

-- | The blame a breach value carries, as far as it has been forced: the
-- anchor's party, stamp and deadline as the headline, and every failure the
-- breach names (R-T3) in order, the anchor among them. Nothing is forced.
breachSummary :: ReasonForBreach Reference -> Eval BreachSummary
breachSummary reason = do
  let blame = breachBlame reason
  failures <- traverse failureSummary (toList (blameList blame))
  (party, deadline) <- case blame.anchor of
    MissedDeadline partyR _ d -> (, Just d) <$> peekParty partyR
    DeclaredBreach mParty _   -> (, Nothing) <$> maybe (pure Nothing) peekParty mParty
  pure MkBreachSummary
    { bsBlame = party
    , bsStamp = case reason of
        DeadlineMissed _ _ stamp _ -> Just stamp
        ExplicitBreach _           -> Nothing
    , bsDeadline = deadline
    , bsFailures = failures
    , bsAnchor = anchorIndex blame
    }
  where
    failureSummary = \ case
      MissedDeadline partyR act d -> do
        party <- peekParty partyR
        pure (MissedSummary party (prettyLayout act) d)
      DeclaredBreach mParty mReason -> do
        -- whether BY named anyone is known without forcing; who, only if forced
        party <- maybe (pure NobodyNamed) (fmap PartyNamed . peekParty) mParty
        why <- maybe (pure Nothing) peekReason mReason
        pure (DeclaredSummary party why)
    peekReason rf = peekWHNF rf >>= pure . \ case
      Just (ValString t) -> Just t
      _                  -> Nothing

-- | Construct a declared breach (@BREACH [BY …] [BECAUSE …]@) and log it
-- (P2b): the log's 'Breached' step, with no norm — a terminal is not an
-- obligation — and no clock, the expression arm having none in hand. The
-- blame is peeked, never forced.
declareBreach :: ReasonForBreach Reference -> Machine Config
declareBreach reason = do
  whenDeonticLog \ l -> do
    summary <- breachSummary reason
    logStep l MkDeonticStep
      { dsClock = Nothing, dsEvent = Nothing, dsScrutiny = NoEvent, dsNorm = Nothing
      , dsOutcome = Breached summary, dsJoin = Nothing }
  continueBackward (ValBreached reason)

-- | A step with no event and no join progress, for the sites that have
-- neither.
plainStep :: Maybe Rational -> Maybe EventKey -> Scrutiny -> NormKey -> StepOutcome -> DeonticStep
plainStep clock ev scrutiny norm outcome = MkDeonticStep
  { dsClock = clock, dsEvent = ev, dsScrutiny = scrutiny
  , dsNorm = Just norm, dsOutcome = outcome, dsJoin = Nothing }

-- | Throw an evaluation exception: unwind the stack frame by frame (so an
-- active trace records the pops, mirroring the historical behaviour),
-- interpreting the state-restoring frames along the way ('unwindFrame'),
-- and then throw an IO exception.
raiseException :: EvalException -> Eval a
raiseException e = do
  traceEval (Exit (Left e))
  withPoppedFrame \ case
    Nothing -> liftIO (Control.Exception.throwIO e)
    Just f  -> unwindFrame f >> raiseException e

-- | Interpret the state-restoring effects of a frame while unwinding on an
-- exception. Most frames are pure control flow and need nothing, but:
--
--   * frames that saved a 'TemporalContext' to restore in 'backward' must
--     restore it during unwinding too — otherwise an exception raised inside
--     an @EVAL AS OF SYSTEM TIME@ \/ @EVAL UNDER VALID TIME@ \/ iterator
--     scope leaves the override in the ambient context (and, post-T6, lets
--     subsequent forces cache values under the leaked context);
--
--   * 'UpdateThunk' frames must close their read span (mirroring the
--     success path in 'backward') and return the thunk to a re-forcible
--     state — otherwise the blackhole mark left by the aborted force makes
--     every later force of the thunk report a bogus infinite loop;
--
--   * 'RestoreCurrentParty' frames must restore the acting party (mirroring
--     the success path in 'backward') — otherwise an exception raised inside
--     a HENCE\/LEST body leaves 'currentParty' pointing at that body's party,
--     and any later ledger write against the same 'EvalState' is attributed
--     to the wrong party. (Today every 'EvalException' aborts its whole
--     directive and 'withFreshLedger' hands the next directive a fresh
--     'currentParty' ref, so this is defense in depth; it becomes load-
--     bearing the moment anything catches an 'EvalException' and resumes
--     evaluation mid-directive.)
--
-- The remaining frames are pure control flow. They are enumerated explicitly
-- (no wildcard) so that adding a state-restoring 'Frame' constructor without
-- deciding its unwind behavior is a compile-time error
-- (@-Wincomplete-patterns@ + @-Werror@), not a silent state leak — the
-- missing 'RestoreCurrentParty' arm was exactly such a leak.
unwindFrame :: Frame -> Eval ()
unwindFrame = \ case
  EvalAsOfSystemTime2 originalCtx        -> putTemporalContext originalCtx
  EvalUnderValidTime2 originalCtx        -> putTemporalContext originalCtx
  EvalUnderRulesEffectiveAt2 originalCtx -> putTemporalContext originalCtx
  EvalUnderRulesEncodedAt2 originalCtx   -> putTemporalContext originalCtx
  EverBetweenFrame originalCtx _ _ _ _   -> putTemporalContext originalCtx
  AlwaysBetweenFrame originalCtx _ _ _ _ -> putTemporalContext originalCtx
  WhenLastFrame originalCtx _ _          -> putTemporalContext originalCtx
  WhenNextFrame originalCtx _ _ _        -> putTemporalContext originalCtx
  ValueAtFrame originalCtx               -> putTemporalContext originalCtx
  DeepPinRestore originalCtx             -> putTemporalContext originalCtx
  RestoreCurrentParty mOriginal          -> putCurrentParty mOriginal
  UpdateThunk rf saved displaced         -> do
    -- Close this force's read span exactly as the success path does (the
    -- reads made before the abort soundly over-approximate the enclosing
    -- span's dependencies), then undo the blackhole.
    mine <- swapCtxReads noReads
    noteCtxRead (saved <> mine)
    restoreThunkOnUnwind rf displaced
  -- pure control flow from here on: nothing to restore
  BinOp1 {}                     -> pure ()
  BinOp2 {}                     -> pure ()
  Post1 {}                      -> pure ()
  Post2 {}                      -> pure ()
  Post3 {}                      -> pure ()
  Record0 {}                    -> pure ()
  Record1 {}                    -> pure ()
  Record2 {}                    -> pure ()
  ReadCell1 {}                  -> pure ()
  ReadCell2 {}                  -> pure ()
  App1 {}                       -> pure ()
  IfThenElse1 {}                -> pure ()
  ConsiderWhen1 {}              -> pure ()
  PatNil0 {}                    -> pure ()
  PatCons0 {}                   -> pure ()
  PatCons1 {}                   -> pure ()
  PatCons2 {}                   -> pure ()
  PatLit0 {}                    -> pure ()
  PatLit1 {}                    -> pure ()
  PatLit2 {}                    -> pure ()
  PatApp0 {}                    -> pure ()
  PatApp1 {}                    -> pure ()
  EqConstructor1 {}             -> pure ()
  EqConstructor2 {}             -> pure ()
  EqConstructor3 {}             -> pure ()
  UnaryBuiltin0 {}              -> pure ()
  BinBuiltin1 {}                -> pure ()
  BinBuiltin2 {}                -> pure ()
  TernaryBuiltin1 {}            -> pure ()
  TernaryBuiltin2 {}            -> pure ()
  TernaryBuiltin3 {}            -> pure ()
  EvalAsOfSystemTime1 {}        -> pure ()
  EvalUnderValidTime1 {}        -> pure ()
  EvalUnderRulesEffectiveAt1 {} -> pure ()
  EvalUnderRulesEncodedAt1 {}   -> pure ()
  -- The pinned context is restored by the 'DeepPinRestore' frame sitting
  -- underneath every 'DeepPinStep', so the step frames themselves are pure
  -- control flow (an abort mid-traversal unwinds through both).
  DeepPinStep {}                -> pure ()
  -- ContractFrame sub-frames (Contract1..11, RBinOp1/2, ResolveParty) carry
  -- only continuation data (WHNFs/envs/refs), never saved global state; the
  -- party set around a followup is restored by 'RestoreCurrentParty' above.
  ContractFrame {}              -> pure ()
  ConcatFrame {}                -> pure ()
  AsStringFrame {}              -> pure ()
  ToStringDate1 {}              -> pure ()
  ToStringDate2 {}              -> pure ()
  ToStringDate3 {}              -> pure ()
  JsonEncodeListFrame {}        -> pure ()
  JsonEncodeNestedFrame {}      -> pure ()
  JsonEncodeConstructorFrame {} -> pure ()

-- | Return an aborted force's thunk to a re-forcible state. If the force had
-- displaced a stale 'WHNFWhen' cache, put the cache back: it is still
-- fingerprint-guarded, so it can only ever be served under contexts it is
-- valid for (and a later force under the original context then correctly
-- serves the cached value). Otherwise just clear our blackhole mark.
-- Mirrors the keep-theirs policy of 'updateThunkToWHNFWhen': if the thunk is
-- no longer 'Unevaluated' (another thread completed it) or our mark is gone,
-- keep what is there.
restoreThunkOnUnwind :: Reference -> Maybe (CtxReads, WHNF) -> Eval ()
restoreThunkOnUnwind rf displaced =
  pokeThunk rf \tid -> \ case
    thunk@(Unevaluated tids e env)
      | tid `Set.member` tids ->
          case displaced of
            Just (fp, v) -> (WHNFWhen fp v e env, ())
            Nothing      -> (Unevaluated (Set.delete tid tids) e env, ())
      | otherwise -> (thunk, ())
    other -> (other, ())

internalException :: InternalEvalException -> Eval a
internalException = raiseException . InternalEvalException

userException :: UserEvalException -> Eval a
userException = raiseException . UserEvalException

stuckOnAssumed :: Resolved -> Eval a
stuckOnAssumed assumedResolved = userException (Stuck assumedResolved)

-- | REFUSE: stop evaluation with the author's reason.
--
-- UNCATCHABLE, and that is the point. 'tryEval' is the only @try@ over an
-- 'EvalException' anywhere in the tree, and it is used only at the directive
-- boundary ('L4.EvaluateLazy.nfDirective') and in @withEvalClauses@ (which
-- rethrows). There is no user-facing catch construct, so nothing between a
-- 'Refuse' and the directive that demanded it can observe the refusal or turn
-- it into a value: not a CONSIDER arm, not a boolean connective, not a
-- WHERE\/LET binding. THIS IS AN INVARIANT, not an accident of the current
-- code: a static refusal analysis is only sound while it holds. Anything that
-- adds a second @try@ (a TRY\/RECOVER construct, a service-level resume)
-- breaks it, and would also have to reckon with 'unwindFrame'\'s docstring.
refuseWith :: Refusal -> Eval a
refuseWith = raiseException . RefusalException

pushFrame :: Frame -> Eval ()
pushFrame frame = do
  stackRef <- asks (.stack)
  s <- liftIO (readIORef stackRef)
  if s.size >= maximumFrameDepth
    then userException StackOverflow
    else do
      -- Emit the trace `Push` only once the frame is actually pushed. If we
      -- recorded it before the overflow check, a StackOverflow would leave a
      -- dangling Push (M Pushes / M+1 Pops) that later unbalances trace
      -- post-processing and crashes it (see T7).
      traceEval Push
      liftIO (writeIORef stackRef (MkStack (s.size + 1) (frame : s.frames)))

-- | Pops a stack frame (if any are left) and calls the continuation on it.
withPoppedFrame :: (Maybe Frame -> Eval a) -> Eval a
withPoppedFrame k = do
  traceEval Pop
  stackRef <- asks (.stack)
  s <- liftIO (readIORef stackRef)
  case s.frames of
    []       -> k Nothing
    (f : fs) -> do
      liftIO (writeIORef stackRef (MkStack (s.size - 1) fs))
      k (Just f)
{-# INLINE withPoppedFrame #-}

getEvalTime :: Eval UTCTime
getEvalTime = asks (.evalTime)

getTracePolicy :: Eval TracePolicy
getTracePolicy = asks (.tracePolicy)

getSafeMode :: Eval Bool
getSafeMode = asks (.safeMode)

getEntityInfo :: Eval EntityInfo
getEntityInfo = asks (.entityInfo)

getModuleUri :: Eval NormalizedUri
getModuleUri = asks (.moduleUri)

-- | Raw access to the temporal context — reserved for frame save\/restore
-- plumbing and cache validation. READER CONTRACT (T6): any code that lets an
-- axis's value influence a computed RESULT must instead go through the
-- @readTc*@ helpers below so the observation is recorded into the current
-- force span; a raw read that affects a result silently reintroduces the
-- stale-thunk bug. When adding a reader for a currently-latent axis
-- (tcValidTime etc.), add the corresponding field to 'CtxReads', an
-- instrumented reader, and flip the @temporal-under-valid-time-latent@
-- golden.
getTemporalContext :: Eval TemporalContext
getTemporalContext = do
  r <- asks (.temporalContext)
  liftIO (readIORef r)

putTemporalContext :: TemporalContext -> Eval ()
putTemporalContext ctx = do
  r <- asks (.temporalContext)
  liftIO (writeIORef r ctx)

-- | Record that an EVENT value (identified by its store address) is a copy
-- re-offered to a HENCE/LEST continuation, with its 'Reoffered' mark. See
-- the Contract5 expiry NOTE in 'backwardContractFrame'.
markReoffered :: Reference -> Reoffered -> Eval ()
markReoffered rf mark = do
  r <- asks (.reofferedEvents)
  liftIO (modifyIORef' r (Map.insert rf.address mark))

-- | Is this EVENT value a re-offered copy, and if so what is its mark?
-- (see 'markReoffered')
isReoffered :: Reference -> Eval (Maybe Reoffered)
isReoffered rf = do
  r <- asks (.reofferedEvents)
  liftIO (Map.lookup rf.address <$> readIORef r)

-- | How many hand-offs in a row a re-offered event may make to a
-- continuation whose deadline is no later than one it has already revealed
-- the expiry of, before the machine refuses the chain as one that cannot
-- end ('stalledChainRefusal'). Deliberately generous: a stalled layer costs
-- about a microsecond, and the number decides only how soon an ill-founded
-- chain is reported, not whether — a chain of DISTINCT layers is finite by
-- its syntax and never comes near it. See the Contract5 expiry NOTE.
maximumStalledReoffers :: Int
maximumStalledReoffers = 1_000

-- | What the machine says when a re-offered event has walked
-- 'maximumStalledReoffers' continuations in a row without the deadline
-- advancing: a continuation that names itself (or reaches itself) and is
-- already past its deadline when it is entered — a LEST with a
-- non-positive @WITHIN@ (its clock is the missed deadline), a kept SHANT's
-- HENCE with a negative one (its clock is the revealing stamp), or an
-- anchored deadline no later than the one just missed.
stalledChainRefusal :: Rational -> Rational -> Text
stalledChainRefusal highWater stamp = Text.unwords
  [ "A chain of HENCE or LEST continuations has stalled: the event at " <> prettyRatio stamp
  , "has been handed on " <> Text.textShow maximumStalledReoffers <> " times in a row to"
  , "continuations whose deadlines never advanced past " <> prettyRatio highWater <> ","
  , "a deadline it had already revealed the expiry of, so no continuation this"
  , "chain reaches can ever be open to it. A continuation that names itself and"
  , "is already past its deadline when it is entered - a negative WITHIN, a"
  , "LEST's WITHIN 0, or an anchored deadline no later than the one just"
  , "missed - is such a chain. Give it a positive WITHIN, anchor it later than"
  , "the missed deadline, or end the chain with BREACH."
  , "(EVERY-EACH-QUANTIFIER-SPEC section 5.2.1.)"
  ]

-----------------------------------------------------------------------------
-- STATE-AS-LEDGER: the ledger operations as direct 'Eval' actions.
--
-- These used to be 'Machine' GADT constructors (TellEvent, CurrentLedger,
-- PartyLedger, OfficialLedger, GetCurrentParty, PutCurrentParty) dispatched by
-- 'interpMachine'. On the direct-Eval evaluator they are plain functions that
-- read/write the two 'EvalState' IORef fields ('envLedger', 'currentParty').
-- They live here (not in EvaluateLazy.hs) so 'runRecord'/'finishRead'/the
-- backward frame arms can call them without an import cycle.
-----------------------------------------------------------------------------

-- | Read an IORef-typed 'EvalState' field. (origin/main has no generic
-- readRef/writeRef helper, so we provide small local ones.)
readEvalRef :: (EvalState -> IORef a) -> Eval a
readEvalRef f = asks f >>= liftIO . readIORef

-- | Write an IORef-typed 'EvalState' field.
writeEvalRef :: (EvalState -> IORef a) -> a -> Eval ()
writeEvalRef f !x = asks f >>= liftIO . flip writeIORef x

-- | Append an event to the appropriate ledger (M4 routing).
--
-- A @RECORD@ ('RouteOwn') lands in the /current acting party's/ own ledger
-- (keyed by 'currentParty', defaulting to 'anonymousParty' at top level). A
-- @COMMIT@/@ATTEST@ ('RouteOfficial') lands in the shared official record.
-- Modeled on 'traceEval', but non-optional: every write is recorded, newest-last.
tellEventRouted :: EventRoute -> LedgerEvent -> Eval ()
tellEventRouted route ev = do
  noteLedgerWrite -- a write POISONS the current force span (T6+ledger): write-once
  store <- asks (.envLedger)
  case route of
    RouteOfficial ->
      liftIO (modifyIORef' store (storeAppendOfficial ev))
    RouteOwn -> do
      party <- fromMaybe anonymousParty <$> readEvalRef (.currentParty)
      liftIO (modifyIORef' store (storeAppendOwn party ev))
    -- NOTIFY v1: the acting party performs the write, but the event lands in the
    -- NAMED recipient's own ledger (keyed by 'partyKeyWHNF', the same key a
    -- cross-party @RECALL@ reads). 'storeAppendOwn' already takes a 'Text' key —
    -- we simply pass the recipient key instead of the acting party.
    RouteNotify recipientKey ->
      liftIO (modifyIORef' store (storeAppendOwn recipientKey ev))

-- | Read the /current acting party's/ own ledger (M1.5 @RECALL@ semantics).
currentLedgerEval :: Eval Ledger
currentLedgerEval = do
  noteLedgerRead -- a RECALL marks the span as a ledger READ: snapshot per scope
  party <- fromMaybe anonymousParty <$> readEvalRef (.currentParty)
  storeOwnLedger party <$> readEvalRef (.envLedger)

-- | Read a NAMED party's own ledger (M4.5 cross-party @RECALL@).
partyLedgerEval :: Text -> Eval Ledger
partyLedgerEval key = do
  noteLedgerRead -- see 'currentLedgerEval'
  storeOwnLedger key <$> readEvalRef (.envLedger)

-- | Read the shared official record (M4.5 @RECALL OFFICIAL's@).
officialLedgerEval :: Eval Ledger
officialLedgerEval = do
  noteLedgerRead -- see 'currentLedgerEval'
  (.officialLedger) <$> readEvalRef (.envLedger)

-- | The party whose HENCE/LEST we are currently inside (M4).
getCurrentParty :: Eval (Maybe Text)
getCurrentParty = readEvalRef (.currentParty)

-- | Set the current acting party (M4); restored via a 'RestoreCurrentParty' frame.
putCurrentParty :: Maybe Text -> Eval ()
putCurrentParty = writeEvalRef (.currentParty)

-- ----------------------------------------------------------------------------
-- Per-force context-read tracking (T6).
--
-- Value-affecting reads of the temporal context MUST go through the readTc*
-- helpers below so the observation lands in the current force span's
-- accumulator (see the READER CONTRACT on 'TemporalContext').
-- ----------------------------------------------------------------------------

-- | Merge an observation into the current force span's accumulator.
noteCtxRead :: CtxReads -> Eval ()
noteCtxRead r = do
  accRef <- asks (.ctxReads)
  liftIO (modifyIORef' accRef (<> r))

-- | STATE-AS-LEDGER write-poison bit (see 'crLedgerWrite'): record that the
-- current force span APPENDED to the ledger (a RECORD\/COMMIT\/ATTEST\/NOTIFY).
-- A force so marked must never be cached as a 'WHNFWhen' — a re-force would
-- replay the write (double-append) — so the @UpdateThunk@ arm of 'backward'
-- caches it as a plain 'WHNF' (snapshot at first force: the write fires
-- exactly once) instead. Rides the 'ctxReads' accumulator so it inherits the
-- span save\/merge discipline (including exceptional unwind) for free.
noteLedgerWrite :: Eval ()
noteLedgerWrite = noteCtxRead noReads { crLedgerWrite = True }

-- | STATE-AS-LEDGER read marker (see 'crLedgerRead'): record that the current
-- force span READ the ledger (a RECALL). Read-only ledger forces stay
-- 'WHNFWhen'-cacheable on their observed temporal axes — snapshot per
-- temporal scope: an unchanged context re-serves the first-force value
-- (the fingerprint does not track the ledger, preserving the pre-bitemporal
-- sharing semantics within a scope), a changed context re-forces against the
-- current ledger (smucclaw\/l4-ide#914 §2B).
noteLedgerRead :: Eval ()
noteLedgerRead = noteCtxRead noReads { crLedgerRead = True }

-- | Install a new accumulator, returning the previous one. Used to open a
-- fresh span at the start of a thunk force (and to reset residue at
-- directive boundaries).
swapCtxReads :: CtxReads -> Eval CtxReads
swapCtxReads new = do
  accRef <- asks (.ctxReads)
  liftIO do
    old <- readIORef accRef
    writeIORef accRef $! new
    pure old

-- | Instrumented reader for 'tcSystemTime' (see READER CONTRACT).
readTcSystemTime :: Eval UTCTime
readTcSystemTime = do
  tc <- getTemporalContext
  noteCtxRead noReads { crSystemTime = ReadEq tc.tcSystemTime }
  pure tc.tcSystemTime

-- | Instrumented reader for 'tcDocumentTimezone' (see READER CONTRACT).
-- Records the raw 'Maybe' (pre-defaulting): a read that falls back to
-- @\"Etc\/UTC\"@ is still an observation of the axis being 'Nothing'.
readTcDocumentTimezone :: Eval (Maybe Text)
readTcDocumentTimezone = do
  tc <- getTemporalContext
  noteCtxRead noReads { crDocumentTimezone = ReadEq tc.tcDocumentTimezone }
  pure tc.tcDocumentTimezone

-- | Instrumented reader for 'tcRuleValidTime' (see READER CONTRACT).
-- Records the raw 'Maybe' (pre-fallback): a RULES EFFECTIVE DATE that falls
-- back to the localized current day is still an observation of the axis
-- being 'Nothing' (and the fallback's own system-time\/timezone reads are
-- recorded by the instrumented readers it goes through).
readTcRuleValidTime :: Eval (Maybe Time.Day)
readTcRuleValidTime = do
  tc <- getTemporalContext
  noteCtxRead noReads { crRuleValidTime = ReadEq tc.tcRuleValidTime }
  pure tc.tcRuleValidTime

-- | Instrumented reader for 'tcValidTime' (see READER CONTRACT).
-- The fact/valid-time axis. Read by RULES EFFECTIVE DATE as its first
-- fallback when the rule-version axis is unset (option (b): with no
-- rule-version pinned, law-time tracks fact-time — consistent with the
-- interval builtins, which stamp @[UnderValidTime d, UnderRulesEffectiveAt d]@
-- together per stepped day). Recorded raw (pre-fallback) so a later force
-- under a changed valid-time invalidates the cache.
readTcValidTime :: Eval (Maybe Time.Day)
readTcValidTime = do
  tc <- getTemporalContext
  noteCtxRead noReads { crValidTime = ReadEq tc.tcValidTime }
  pure tc.tcValidTime

-- | Atomically inspect-and-update a thunk. The update function additionally
-- receives the current thread id (for blackhole bookkeeping).
pokeThunk :: Reference -> (ThreadId -> Thunk -> (Thunk, a)) -> Eval a
pokeThunk rf k = liftIO do
  tid <- myThreadId
  atomicModifyIORef' rf.pointer (k tid)

readThunk :: Reference -> Eval Thunk
readThunk rf = liftIO (readIORef rf.pointer)

-- | allocateRecursive a recursive thunk: the environment may refer back to the
-- freshly created reference. The reference does not escape before it is
-- filled in, so a plain write suffices.
allocateRecursive :: Expr Resolved -> (Reference -> Environment) -> Eval (Reference, Environment)
allocateRecursive expr env = do
  address <- newAddress
  pointer <- liftIO (newIORef (WHNF ValNil)) -- placeholder, overwritten below before rf escapes
  let rf = MkReference address pointer
      env' = env rf
  liftIO (writeIORef pointer (Unevaluated Set.empty expr env'))
  traceEval (Alloc expr rf)
  pure (rf, env')

allocateValue :: WHNF -> Eval Reference
allocateValue whnf = do
  address <- newAddress
  pointer <- liftIO (newIORef (WHNF whnf))
  -- we don't trace this because it is used for allocating values in the
  -- initial environment which would be misleading in the trace
  pure (MkReference address pointer)

-- | allocateRecursive a blackhole that will be filled in later (used for mutually
-- recursive bindings). Forcing it before it is written is an error.
preAllocateRef :: Resolved -> Eval (Unique, Reference)
preAllocateRef r = do
  address <- newAddress
  rf <- liftIO do
    tid <- myThreadId
    pointer <- newIORef (Unevaluated (Set.singleton tid) (error "blackhole") Map.empty)
    pure (MkReference address pointer)
  traceEval (AllocPre r rf)
  pure (getUnique r, rf)

data Config
  = ForwardMachine Environment (Expr Resolved)
  | MatchBranchesMachine Reference Environment [Branch Resolved]
  | MatchPatternMachine Reference Environment (Pattern Resolved)
  | BackwardMachine WHNF
  | EvalRefMachine Reference
  | DoneMachine WHNF

-- Smart constructors for the next machine configuration. These used to be
-- pattern synonyms over the defunctionalized 'Machine' GADT.

continueExpr :: Environment -> Expr Resolved -> Machine Config
continueExpr env e = pure (ForwardMachine env e)
{-# INLINE continueExpr #-}

continueBranches :: Reference -> Environment -> [Branch Resolved] -> Machine Config
continueBranches r env e = pure (MatchBranchesMachine r env e)
{-# INLINE continueBranches #-}

continuePattern :: Reference -> Environment -> Pattern Resolved -> Machine Config
continuePattern r env pat = pure (MatchPatternMachine r env pat)
{-# INLINE continuePattern #-}

continueBackward :: WHNF -> Machine Config
continueBackward whnf = pure (BackwardMachine whnf)
{-# INLINE continueBackward #-}

continueRef :: Reference -> Machine Config
continueRef r = pure (EvalRefMachine r)
{-# INLINE continueRef #-}

continueDone :: WHNF -> Machine Config
continueDone whnf = pure (DoneMachine whnf)
{-# INLINE continueDone #-}


forwardExpr :: Environment -> Expr Resolved -> Machine Config
forwardExpr env = \ case
  RAnd _ann e1 e2 -> continueBackward (ValROp env ValRAnd (Left e1) (Left e2))
  ROr  _ann e1 e2 -> continueBackward (ValROp env ValROr (Left e1) (Left e2))
  And  _ann e1 e2 ->
    continueExpr env (IfThenElse emptyAnno e1 e2 falseExpr)
  Or   _ann e1 e2 ->
    continueExpr env (IfThenElse emptyAnno e1 trueExpr e2)
  Implies _ann e1 e2 ->
    continueExpr env (IfThenElse emptyAnno e1 e2 trueExpr)
  Not _ann e ->
    continueExpr env (IfThenElse emptyAnno e falseExpr trueExpr)
  Equals _ann e1 e2 -> do
    pushFrame (BinOp1 BinOpEquals e2 env)
    continueExpr env e1
  Plus _ann e1 e2 -> do
    pushFrame (BinOp1 BinOpPlus e2 env)
    continueExpr env e1
  Minus _ann e1 e2 -> do
    pushFrame (BinOp1 BinOpMinus e2 env)
    continueExpr env e1
  Times _ann e1 e2 -> do
    pushFrame (BinOp1 BinOpTimes e2 env)
    continueExpr env e1
  DividedBy _ann e1 e2 -> do
    pushFrame (BinOp1 BinOpDividedBy e2 env)
    continueExpr env e1
  Modulo _ann e1 e2 -> do
    pushFrame (BinOp1 BinOpModulo e2 env)
    continueExpr env e1
  Leq _ann e1 e2 -> do
    pushFrame (BinOp1 BinOpLeq e2 env)
    continueExpr env e1
  Geq _ann e1 e2 -> do
    pushFrame (BinOp1 BinOpGeq e2 env)
    continueExpr env e1
  Lt _ann e1 e2 -> do
    pushFrame (BinOp1 BinOpLt e2 env)
    continueExpr env e1
  Gt _ann e1 e2 -> do
    pushFrame (BinOp1 BinOpGt e2 env)
    continueExpr env e1
  Proj _ann e l ->
    continueExpr env (App emptyAnno l [e]) -- we desugar projection to plain function application
  Var _ann n -> do -- still problematic: similarity / overlap between this and App with no args
    -- Auto-apply a discharged import only in VALUE position. The App case above
    -- fetches the function it is about to apply by re-entering here, and
    -- applying it twice would hand the caller the RESULT where it expects a
    -- function: measured, that took @legal/promissory-note.l4@ and
    -- @legal/regcf/regcf.l4@ red with "expected a function but found:
    -- Money OF ...". An argument is never in this position -- arguments are
    -- allocated, not forwarded -- so an 'App1' carrying arguments on top of the
    -- stack means this reference is the function of that application.
    beingApplied <- topFrameAppliesArguments
    r <- expectTerm env n
    if beingApplied then continueRef r else autoApplyDischargedImport r
  Cons _ann e1 e2 -> do
    rf1 <- allocate_ e1 env
    rf2 <- allocate_ e2 env
    continueBackward (ValCons rf1 rf2)
  Lam _ann givens e ->
    continueBackward (ValClosure givens e env)
  App _ann n [] ->
    expectTerm env n >>= autoApplyDischargedImport
  App ann n es@(_ : _) -> do
    -- Handle temporal context override: EVAL AS OF SYSTEM TIME <serial> <thunk>
    -- The second argument is evaluated under the mutated temporal context.
    case getUnique n of
      uniq | uniq == TypeCheck.evalAsOfSystemTimeUnique
           , [dateExpr, thunkExpr] <- es -> do
               thunkRef <- allocate_ thunkExpr env
               pushFrame (EvalAsOfSystemTime1 thunkRef env)
               continueExpr env dateExpr
      uniq | uniq == TypeCheck.evalUnderValidTimeUnique
           , [dateExpr, thunkExpr] <- es -> do
               thunkRef <- allocate_ thunkExpr env
               pushFrame (EvalUnderValidTime1 thunkRef env)
               continueExpr env dateExpr
      uniq | uniq == TypeCheck.evalUnderRulesEffectiveAtUnique
           , [dateExpr, thunkExpr] <- es -> do
               thunkRef <- allocate_ thunkExpr env
               pushFrame (EvalUnderRulesEffectiveAt1 thunkRef env)
               continueExpr env dateExpr
      uniq | uniq == TypeCheck.evalUnderRulesEncodedAtUnique
           , [dateExpr, thunkExpr] <- es -> do
               thunkRef <- allocate_ thunkExpr env
               pushFrame (EvalUnderRulesEncodedAt1 thunkRef env)
               continueExpr env dateExpr
      _ -> do
        let expectedType = case getAnno ann of
              Anno {extra = Extension {resolvedInfo = Just (TypeInfo ty _)}} -> Just ty
              _ -> Nothing
        rs <- traverse (`allocate_` env) es
        pushFrame (App1 rs expectedType)
        -- Re-enter as a 'Var'. That extra 'ForwardMachine' step is what the
        -- evaluation tracer records as the function being entered, so short-
        -- circuiting it here silently drops a line from every #EVALTRACE (five
        -- goldens, measured). 'forwardExpr'\'s Var case knows not to
        -- auto-apply while this 'App1' is on top of the stack.
        continueExpr env (Var emptyAnno n)
  AppNamed ann n [] _ ->
    continueExpr env (App ann n [])
  AppNamed _ann _n _nes Nothing ->
    internalException $ RuntimeTypeError
      "named application where the order of arguments is not resolved"
  AppNamed _ann n _nes (Just order)
    | any (< 0) order ->
    -- A negative entry marks a named argument that supplies a SECTION BINDER
    -- rather than one of the callee's declared parameters (see 'AppNamed' in
    -- "L4.Syntax"). 'L4.Discharge.dischargeModule' rewrites every such site
    -- into a plain application; one reaching here means the module skipped
    -- that pass, and sorting the entry into argument position would silently
    -- pass the override to the WRONG parameter.
    internalException $ RuntimeTypeError $
      "named application supplying an implicit input reached the evaluator undischarged: "
      <> prettyLayout (TypeCheck.getName n)
      <> " ("
      <> Text.pack (show (length (filter (< 0) order)))
      <> " implicit argument(s)). This is a compiler bug:"
      <> " L4.Discharge.dischargeModule must run before evaluation."
  AppNamed ann n nes (Just order) ->
    let
     -- move expressions into order, drop names
      es = (\ (MkNamedExpr _ _ e) -> e) . snd <$> sortOn fst (zip order nes)
    in
      continueExpr env (App ann n es)
  IfThenElse _ann e1 e2 e3 -> do
    pushFrame (IfThenElse1 e2 e3 env)
    continueExpr env e1
  MultiWayIf _ann es e -> continueExpr env $ desugarMultiWayIf es e
    where
    desugarMultiWayIf :: [GuardedExpr Resolved] -> Expr Resolved -> Expr Resolved
    desugarMultiWayIf [] o = o
    desugarMultiWayIf (MkGuardedExpr _ann c f : es') o = IfThenElse emptyAnno c f $ desugarMultiWayIf es' o
  Consider _ann e branches -> do
    rf <- allocate_ e env
    continueBranches rf env branches
  Lit _ann lit -> do
    rval <- runLit lit
    continueBackward rval
  Percent _ann e -> do
    pushFrame (UnaryBuiltin0 UnaryPercent Nothing)
    continueExpr env e
  List _ann [] ->
    continueBackward ValNil
  List _ann (e : es) ->
    continueExpr env (Cons emptyAnno e (List emptyAnno es))
  Where _ann e ds -> do
    env' <- evalRecLocalDecls env ds
    let combinedEnv = Map.union env' env
    continueExpr combinedEnv e
  LetIn _ann ds e -> do
    env' <- evalRecLocalDecls env ds
    let combinedEnv = Map.union env' env
    continueExpr combinedEnv e
  Regulative _ann deonton@(MkDeonton _ subject action opens due _join followup lest) ->
    case subject of
      Party _ party ->
        continueBackward (ValObligation env (Left party) action (Left opens) (Left due) (fromMaybe fulfilExpr followup) lest)
      Every{} ->
        -- EVERY-EACH-QUANTIFIER-SPEC phase 2. A quantified obligation cannot
        -- become one obligation here, because it does not yet know its cast:
        -- the roll is read when the contract meets its event stream, which is
        -- when it is ARMED (R-Q6/R-T6, "the cast is evaluated once at
        -- arming"). So evaluation stops at a 'ValQuantified', which prints
        -- back as the source form and is expanded by the 'App1' frame.
        continueBackward (ValQuantified env deonton)
  Event _ann ev ->
    continueExpr env (desugarEvent ev)
  Fetch _ann e -> do
    pushFrame (UnaryBuiltin0 UnaryFetch Nothing)
    continueExpr env e
  Env _ann e -> do
    pushFrame (UnaryBuiltin0 UnaryEnv Nothing)
    continueExpr env e
  Post _ann e1 e2 e3 -> do
    pushFrame (Post1 e2 e3 env)
    continueExpr env e1
  Record _ann mParty cell val isOfficial mHence -> do
    -- STATE-AS-LEDGER M1 (+ NOTIFY-v1): evaluate the cell to a String path, then
    -- the value to WHNF, append an Assign event to the ledger. M5: if a HENCE
    -- continuation is present, forward [time, events] to it (event-free deontic
    -- step); otherwise return the written value (M1 expression use). The 'env' is
    -- carried so the HENCE can be forwarded in the RECORD's lexical environment.
    --
    -- NOTIFY v1: if a recipient qualifier is present (@RECORD q's <cell> IS v@),
    -- evaluate the RECIPIENT first (push 'Record0', mirroring 'ReadCell2'); on its
    -- WHNF we key it via 'partyKeyWHNF' and route the write to that recipient's
    -- own ledger. A bare @RECORD@ (no qualifier) carries 'Nothing' and routes to
    -- the acting party's own ledger exactly as before.
    case mParty of
      Just partyExpr -> do
        pushFrame (Record0 cell val env isOfficial mHence)
        continueExpr env partyExpr
      Nothing -> do
        pushFrame (Record1 val env isOfficial mHence Nothing)
        continueExpr env cell
  ReadCell _ann mParty isOfficial mode cell -> do
    -- STATE-AS-LEDGER M1.5 / M4.5: evaluate the cell to a String path first,
    -- carrying the optional party qualifier (still unevaluated), the isOfficial
    -- flag, the 'RecallMode' (approach B), and the env. The 'ReadCell1' frame then
    -- routes to the right ledger (own / cross-party / official) and reads it,
    -- yielding MAYBE (RecallLast) or a LIST (RecallAll).
    pushFrame (ReadCell1 mParty isOfficial mode env)
    continueExpr env cell
  Concat _ann [] ->
    continueBackward (ValString "")
  Concat _ann (e : es) -> do
    pushFrame (ConcatFrame [] es env)
    continueExpr env e
  AsString _ann e -> do
    pushFrame AsStringFrame
    continueExpr env e
  Breach ann mParty mReason -> do
    -- Explicit breach terminal clause - produces a breach value. The BY
    -- expression is a party or a LIST of parties (R-T3, spec §6.1): the
    -- checker admits both and leaves no mark, so the machine forces it and
    -- decides by shape ('BreachBy'). The one collision — a party type that
    -- is itself a LIST — the checker settles by handing the party over
    -- wrapped as a one-element list ('checkBreachParty'). A breach with no
    -- BY is ONE declared failure naming nobody.
    mReasonRef <- traverse (\r -> allocate_ r env) mReason
    case mParty of
      -- P2b: a declared breach is logged where it is constructed — here for
      -- a BREACH with no BY, and at the 'BreachBy' frame's end otherwise
      -- ('declareBreach'). No norm (a terminal is not an obligation), no
      -- clock (the expression arm has none in hand), and the blame is
      -- peeked, never forced.
      Nothing -> declareBreach (ExplicitBreach (singleBlame (DeclaredBreach Nothing mReasonRef)))
      Just p  -> do
        partyRef <- allocate_ p env
        pushFrame $ ContractFrame $ BreachBy BreachByFrame
          { partyRef, acc = [], mReason = mReasonRef, clause = prettySrcRangeM (rangeOf ann) }
        continueRef partyRef
  -- REFUSE only ever reaches 'forwardExpr' when the machine actually REDUCES
  -- it, so a refusal inside an unforced thunk is never entered. That is what
  -- makes @FALSE AND <refusing>@ answer FALSE while @<refusing> AND FALSE@
  -- refuses: 'And' desugars to an 'IfThenElse' whose scrutinee is forced first.
  Refuse _ann (Lit _ (StringLit _ txt)) ->
    refuseWith (MkRefusal txt)
  Refuse _ann _msg ->
    -- Unreachable: the parser accepts only a literal message and the type
    -- checker requires that literal to be a STRING.
    internalException (RuntimeTypeError "the message of a REFUSE is not a string literal")
  Inert _ann _txt ctx ->
    -- Inert elements are grammatical scaffolding with context-aware evaluation
    -- In AND context: True (identity), in OR context: False (identity)
    case ctx of
      InertCtxAnd  -> continueBackward (ValBool True)
      InertCtxOr   -> continueBackward (ValBool False)
      InertCtxNone -> continueBackward (ValBool True)  -- Default to True for compatibility

backward :: WHNF -> Machine Config
backward val = withPoppedFrame $ \ case
  Nothing -> continueDone val
  Just (BinOp1 binOp e2 env) -> do
    pushFrame (BinOp2 binOp val)
    continueExpr env e2
  Just (BinOp2 binOp val1) -> do
    runBinOp binOp val1 val
  Just (Post1 e2 e3 env) -> do
    pushFrame (Post2 val e3 env)
    continueExpr env e2
  Just (Post2 val1 e3 env) -> do
    pushFrame (Post3 val1 val)
    continueExpr env e3
  Just (Post3 val1 val2) -> do
    runPost val1 val2 val
  Just (Record0 cell valExpr env isOfficial mHence) -> do
    -- NOTIFY v1: the recipient party qualifier has evaluated to 'val' (a WHNF);
    -- key it the SAME way a cross-party RECALL read does ('partyKeyWHNF'), so the
    -- write-key matches the recipient's read-key by construction. Carry that key
    -- through to 'Record1'/'Record2'/'runRecord', then proceed to evaluate the
    -- cell exactly as a bare RECORD does.
    let recipientKey = partyKeyWHNF val
    pushFrame (Record1 valExpr env isOfficial mHence (Just recipientKey))
    continueExpr env cell
  Just (Record1 valExpr env isOfficial mHence mRecipientKey) -> do
    -- the cell has evaluated to 'val'; now evaluate the value expression. Carry
    -- the env, the M5 HENCE, and the NOTIFY recipient key so 'runRecord' can
    -- route the write and forward to the continuation.
    pushFrame (Record2 val isOfficial env mHence mRecipientKey)
    continueExpr env valExpr
  Just (Record2 cellVal isOfficial env mHence mRecipientKey) -> do
    -- both the cell ('cellVal') and the value ('val') are evaluated: append the
    -- Assign event to the ledger (D2 / Rung 3). Then M5: with a HENCE, become the
    -- continuation (forward [time, events] to it); without, return the value (M1).
    runRecord cellVal val isOfficial env mHence mRecipientKey
  Just (ReadCell1 mParty isOfficial mode env) -> do
    -- the cell has evaluated to 'val' (a String path). Route to the right
    -- ledger and finish (M1.5 / M4.5), carrying the 'RecallMode' (approach B):
    --   * isOfficial   -> read the shared OFFICIAL record.
    --   * Just party    -> evaluate the party qualifier (push ReadCell2 holding
    --                      the cell AND the mode), then key it and read that
    --                      party's ledger.
    --   * Nothing       -> read the CURRENT acting party's own ledger (M1.5).
    if isOfficial
      then do
        ledger <- officialLedgerEval
        finishRead mode val ledger
      else case mParty of
        Just partyExpr -> do
          pushFrame (ReadCell2 val mode)
          continueExpr env partyExpr
        Nothing -> do
          ledger <- currentLedgerEval
          finishRead mode val ledger
  Just (ReadCell2 cellVal mode) -> do
    -- the party qualifier has evaluated to 'val' (a WHNF): key it the SAME way
    -- a RECORD write does ('partyKeyWHNF'), so a cross-party read matches a
    -- write, then read that party's own ledger and finish (M4.5), in 'mode'.
    let key = partyKeyWHNF val
    ledger <- partyLedgerEval key
    finishRead mode cellVal ledger
  Just (RestoreCurrentParty mOriginal) -> do
    -- the HENCE/LEST followup (and its App1 continuation) has fully evaluated:
    -- restore the enclosing acting party and pass the value on unchanged (M4).
    putCurrentParty mOriginal
    continueBackward val
  Just (BinBuiltin1 binOp r) -> do
    pushFrame (BinBuiltin2 binOp val)
    continueRef r
  Just (BinBuiltin2 binOp val1) ->
    runBinOp binOp val1 val
  Just f@(App1 rs mTy) -> do
    case val of
      ValClosure givens e env' -> do
        env'' <- matchGivens env' givens f rs
        continueExpr (Map.union env'' env') e
      ValUnappliedConstructor r ->
        continueBackward (ValConstructor r rs)
      ValObligation env party act opens due followup lest -> do
        (time, events) <- case rs of
          [t, r] -> pure (t, r)
          rs' -> internalException $ RuntimeTypeError $
            "expected a time stamp, and a list of events but found: " <> foldMap prettyLayout rs'
        -- P2b: this is the ENTRY into the obligation's site — the activation
        -- the step log's key counts. Lazy when the log is off.
        norm <- armNormKey party act
        -- this is the arming point: the clock now is what THE ARMING will
        -- name in this obligation's continuation (R-Q7B), so keep it —
        -- 'time' itself advances with every scrutinised event; no event has
        -- been taken from the stream yet
        pushFrame (ContractFrame (Contract1 ScrutinizeEvents {armed = time, seen = 0, ..}))
        continueRef events
      ValQuantified env deonton -> do
        -- EVERY meets its event stream: this is the arming point, so the roll
        -- call runs here (spec §2.2.7.5 point 5, R-Q6).
        (time, events) <- case rs of
          [t, r] -> pure (t, r)
          rs' -> internalException $ RuntimeTypeError $
            "expected a time stamp, and a list of events but found: " <> foldMap prettyLayout rs'
        startRollCall env deonton time events
      ValROp env op rexpr1 rexpr2 -> do
        -- make sure to reassemble the operation after returning
        pushFrame $ ContractFrame $ RBinOp1 MkRBinOp1 {args = rs, ..}
        -- apply the arguments of the left hand expression to the
        -- expression
        pushFrame f
        -- R-Q7B: the operand is handed off here, exactly as a HENCE's
        -- value is, so a continuation that arrives as a VALUE inside a
        -- compound anchors to the obligation the compound is attached
        -- to ('operandHandoff').
        operandHandoff env rexpr1
        maybeEvaluate env rexpr1 -- TODO: build application
      ValUnaryBuiltinFun fn -> do
        r <- expect1 rs
        pushFrame (UnaryBuiltin0 fn mTy)
        continueRef r
      ValBinaryBuiltinFun fn -> do
        (x, y) <- expect2 rs
        case fn of
          -- 'BinOpCons' doesn't need to evaluate anything!
          BinOpCons -> do
            continueBackward $ ValCons x y
          _ -> do
            pushFrame (BinBuiltin1 fn y)
            continueRef x
      ValTernaryBuiltinFun fn -> do
        (x, y, z) <- expect3 rs
        -- Push frame for when we have all 3 args, then evaluate args right-to-left
        pushFrame (TernaryBuiltin1 fn y z)
        continueRef x
      ValPartialTernary fn arg1 -> do
        -- Already has 1 arg (as ref), need 2 more
        (y, z) <- expect2 rs
        -- We need to evaluate arg1, then y, then z
        pushFrame (TernaryBuiltin1 fn y z)
        continueRef arg1
      ValPartialTernary2 fn arg1 arg2 -> do
        -- Already has 2 args (as refs), need 1 more
        z <- expect1 rs
        -- We need to evaluate arg1, then arg2, then z
        pushFrame (TernaryBuiltin1 fn arg2 z)
        continueRef arg1
      ValFulfilled -> continueBackward ValFulfilled
      ValBreached r -> continueBackward (ValBreached r)
      ValAssumed r ->
        stuckOnAssumed r -- TODO: we can do better here
      res -> internalException (RuntimeTypeError $ "expected a function but found: " <> prettyLayout res)
  -- Evaluate thunk under overridden system time (serial number)
  Just (EvalAsOfSystemTime1 thunkRef _env) -> do
    day <- expectDateValue val
    -- frame plumbing (save/override), not a context observation (see T6)
    originalCtx <- getTemporalContext
    let newCtx = applyEvalClauses [AsOfSystemTime (Time.UTCTime day 0)] originalCtx
    putTemporalContext newCtx
    pushFrame (EvalAsOfSystemTime2 originalCtx)
    continueRef thunkRef
  Just (EvalUnderValidTime1 thunkRef _env) -> do
    day <- expectDateValue val
    -- frame plumbing (save/override), not a context observation (see T6)
    originalCtx <- getTemporalContext
    let newCtx = applyEvalClauses [UnderValidTime day] originalCtx
    putTemporalContext newCtx
    pushFrame (EvalUnderValidTime2 originalCtx)
    continueRef thunkRef
  Just (EvalUnderRulesEffectiveAt1 thunkRef _env) -> do
    day <- expectDateValue val
    -- frame plumbing (save/override), not a context observation (see T6)
    originalCtx <- getTemporalContext
    let newCtx = applyEvalClauses [UnderRulesEffectiveAt day] originalCtx
    putTemporalContext newCtx
    pushFrame (EvalUnderRulesEffectiveAt2 originalCtx)
    continueRef thunkRef
  Just (EvalUnderRulesEncodedAt1 thunkRef _env) -> do
    day <- expectDateValue val
    -- frame plumbing (save/override), not a context observation (see T6)
    originalCtx <- getTemporalContext
    let newCtx = applyEvalClauses [UnderRulesEncodedAt (Time.UTCTime day 0)] originalCtx
    putTemporalContext newCtx
    pushFrame (EvalUnderRulesEncodedAt2 originalCtx)
    continueRef thunkRef
  Just (IfThenElse1 e2 e3 env) ->
    case val of
      ValBool True -> continueExpr env e2
      ValBool False -> continueExpr env e3

      ValAssumed r -> stuckOnAssumed r

      _ -> internalException $ RuntimeTypeError $
        "expected a BOOLEAN but found: " <> prettyLayout val <> " when evaluating IF-THEN-ELSE"
  Just (ConsiderWhen1 _scrutinee e _branches env) -> do
    case val of
      ValEnvironment env' ->
        continueExpr (Map.union env' env) e
      _ ->
        internalException $ RuntimeTypeError $
          "expected an environment but found: " <> prettyLayout val <> " when evaluating WHEN"
  Just PatNil0 -> do
    case val of
      ValNil ->
        continueBackward (ValEnvironment Map.empty)
      _ ->
        patternMatchFailure
  Just (PatCons0 p1 env p2) -> do
    case val of
      ValCons rf1 rf2 -> do
        pushFrame (PatCons1 rf2 env p2)
        continuePattern rf1 env p1
      _ ->
        patternMatchFailure
  Just (PatCons1 rf2 env p2) -> do
    case val of
      ValEnvironment env1 -> do
        pushFrame (PatCons2 env1)
        continuePattern rf2 env p2
      _ ->
        internalException $ RuntimeTypeError $
          "expected an environment but found: " <> prettyLayout val <> " when matching FOLLOWED BY"
  Just (PatCons2 env1) ->
    case val of
      ValEnvironment env2 ->
        continueBackward (ValEnvironment (Map.union env2 env1))
      _ -> internalException $ RuntimeTypeError $
        "expected an environment but found: " <> prettyLayout val <> " when matching FOLLOWED BY"
  Just (PatApp0 n env ps) ->
    case val of
      ValConstructor n' rfs
        | sameResolved n n' ->
          if length rfs == length ps
            then
              let
                pairs = zip rfs ps
              in
                case pairs of
                  []             -> continueBackward (ValEnvironment Map.empty)
                  ((r, p) : rps) -> do
                    pushFrame (PatApp1 env [] rps)
                    continuePattern r env p
            else internalException $ RuntimeTypeError
              "pattern for constructor has the wrong number of arguments"
      _ ->
        patternMatchFailure
  Just (PatApp1 ambient envs rps) ->
    case val of
      ValEnvironment env ->
        case rps of
          []              -> continueBackward (ValEnvironment (Map.unions (env : envs)))
          ((r, p) : rps') -> do
            pushFrame (PatApp1 ambient (env : envs) rps')
            -- 'ambient', NOT 'env': see the note on the 'PatApp1' frame.
            continuePattern r ambient p
      _ -> internalException $ RuntimeTypeError $
        "expected an environment but found: " <> prettyLayout val <> " when matching constructor"
  Just (PatLit0 env lit) -> do
    pushFrame (PatLit1 val)
    continueExpr env lit
  Just (PatLit1 lit) -> do
    pushFrame PatLit2
    runBinOpEquals lit val
  Just PatLit2 ->
    case val of
      -- NOTE: in future, we may give the pattern that was matched a name, potentially
      ValBool True -> continueBackward $ ValEnvironment emptyEnvironment
      ValBool False -> patternMatchFailure
      _ -> internalException $ RuntimeTypeError $
        "expected a boolean but found: " <> prettyLayout val <> " while matching literal pattern"
  Just (EqConstructor1 rf rfs) -> do
    pushFrame (EqConstructor2 val rfs)
    continueRef rf
  Just (EqConstructor2 val1 rfs) -> do
    pushFrame (EqConstructor3 rfs)
    runBinOpEquals val1 val
  Just (EqConstructor3 rfs) ->
    case boolView val of
      Just False -> continueBackward $ valBool False
      Just True ->
        case rfs of
          [] -> continueBackward $ valBool True
          ((r1, r2) : rfs') -> do
            pushFrame (EqConstructor1 r2 rfs')
            continueRef r1
      Nothing -> internalException $ RuntimeTypeError $
        "expected a BOOLEAN but found: " <> prettyLayout val <> " when testing equality"
  Just (UnaryBuiltin0 fn mTy) -> do
    runBuiltin val fn mTy
  -- Ternary builtin handling: got 1st arg value, need to eval 2nd
  Just (TernaryBuiltin1 fn refArg2 refArg3) -> do
    pushFrame (TernaryBuiltin2 fn val refArg3)
    continueRef refArg2
  -- Ternary builtin handling: got 2nd arg value, need to eval 3rd
  Just (TernaryBuiltin2 fn val1 refArg3) -> do
    pushFrame (TernaryBuiltin3 fn val1 val)
    continueRef refArg3
  -- Ternary builtin handling: got all 3 args
  Just (TernaryBuiltin3 fn val1 val2) -> do
    runTernaryBuiltin fn val1 val2 val
  -- Temporal context scoping: the pinned expression is forced to normal form
  -- BEFORE the original context is restored ('startDeepPin', #934), then the
  -- 'DeepPinRestore' frame underneath puts the original context back.
  -- These (and the iterator frames below) are frame plumbing — context
  -- writers, not context observations (see T6).
  Just (EvalAsOfSystemTime2 originalCtx) -> startDeepPin originalCtx val
  Just (EvalUnderValidTime2 originalCtx) -> startDeepPin originalCtx val
  Just (EvalUnderRulesEffectiveAt2 originalCtx) -> startDeepPin originalCtx val
  Just (EvalUnderRulesEncodedAt2 originalCtx) -> startDeepPin originalCtx val
  Just (DeepPinRestore originalCtx) -> do
    putTemporalContext originalCtx
    continueBackward val
  Just (DeepPinStep d seen pending result) ->
    driveDeepPin (toList val) d seen pending result
  Just (EverBetweenFrame originalCtx predicate endDay currentDay step) -> do
    putTemporalContext originalCtx
    case boolView val of
      Just True -> continueBackward (valBool True)
      Just False ->
        if currentDay == endDay
          then continueBackward (valBool False)
          else do
            let nextDay = Time.addDays (fromIntegral step) currentDay
            let ctxForDay = applyEvalClauses [UnderValidTime nextDay, UnderRulesEffectiveAt nextDay] originalCtx
            putTemporalContext ctxForDay
            pushFrame (EverBetweenFrame originalCtx predicate endDay nextDay step)
            applyDatePredicate predicate nextDay
      Nothing ->
        userException $ UserError "EVER BETWEEN expects predicate returning BOOLEAN"
  Just (AlwaysBetweenFrame originalCtx predicate endDay currentDay step) -> do
    putTemporalContext originalCtx
    case boolView val of
      Just False -> continueBackward (valBool False)
      Just True ->
        if currentDay == endDay
          then continueBackward (valBool True)
          else do
            let nextDay = Time.addDays (fromIntegral step) currentDay
            let ctxForDay = applyEvalClauses [UnderValidTime nextDay, UnderRulesEffectiveAt nextDay] originalCtx
            putTemporalContext ctxForDay
            pushFrame (AlwaysBetweenFrame originalCtx predicate endDay nextDay step)
            applyDatePredicate predicate nextDay
      Nothing ->
        userException $ UserError "ALWAYS BETWEEN expects predicate returning BOOLEAN"
  Just (WhenLastFrame originalCtx predicate currentDay) -> do
    putTemporalContext originalCtx
    case boolView val of
      Just True -> do
        dateRef <- allocateValue (ValDate currentDay)
        continueBackward $ ValConstructor TypeCheck.justRef [dateRef]
      Just False -> do
        if dayNumberFromDay currentDay <= 0
          then continueBackward $ ValConstructor TypeCheck.nothingRef []
          else do
            let nextDay = Time.addDays (-1) currentDay
            let ctxForDay = applyEvalClauses [UnderValidTime nextDay, UnderRulesEffectiveAt nextDay] originalCtx
            putTemporalContext ctxForDay
            pushFrame (WhenLastFrame originalCtx predicate nextDay)
            applyDatePredicate predicate nextDay
      Nothing ->
        userException $ UserError "WHEN LAST expects predicate returning BOOLEAN"
  Just (WhenNextFrame originalCtx predicate currentDay limitDay) -> do
    putTemporalContext originalCtx
    case boolView val of
      Just True -> do
        dateRef <- allocateValue (ValDate currentDay)
        continueBackward $ ValConstructor TypeCheck.justRef [dateRef]
      Just False -> do
        if currentDay >= limitDay
          then continueBackward $ ValConstructor TypeCheck.nothingRef []
          else do
            let nextDay = Time.addDays 1 currentDay
            let ctxForDay = applyEvalClauses [UnderValidTime nextDay, UnderRulesEffectiveAt nextDay] originalCtx
            putTemporalContext ctxForDay
            pushFrame (WhenNextFrame originalCtx predicate nextDay limitDay)
            applyDatePredicate predicate nextDay
      Nothing ->
        userException $ UserError "WHEN NEXT expects predicate returning BOOLEAN"
  -- VALUE AT is the one interval builtin whose result is not forced to a
  -- BOOLEAN/DATE by its own frame, so it needs the same deep pin as the four
  -- EVAL clause builtins (#934). EVER/ALWAYS BETWEEN and WHEN LAST/NEXT demand
  -- a scalar from their predicate, for which WHNF is already normal form.
  Just (ValueAtFrame originalCtx) -> startDeepPin originalCtx val
  Just (ConcatFrame acc [] _env) -> do
    -- All arguments evaluated, concatenate them
    runConcat (reverse (val : acc))
  Just (ConcatFrame acc (e : es) env) -> do
    -- Evaluate next argument
    pushFrame (ConcatFrame (val : acc) es env)
    continueExpr env e
  Just AsStringFrame -> do
    -- Convert the value to string
    runAsString val
  Just (ToStringDate1 monthRef yearRef) -> do
    dayNum <- expectNumber val
    pushFrame (ToStringDate2 dayNum yearRef)
    continueRef monthRef
  Just (ToStringDate2 dayNum yearRef) -> do
    monthNum <- expectNumber val
    pushFrame (ToStringDate3 dayNum monthNum)
    continueRef yearRef
  Just (ToStringDate3 dayNum monthNum) -> do
    yearNum <- expectNumber val
    runDateToString dayNum monthNum yearNum
  Just (JsonEncodeListFrame acc tailRef expectingTail) -> do
    -- Handle the value we got back
    if expectingTail
      then
        -- We just evaluated the tail, so val is either ValNil or ValCons
        case val of
          ValNil -> do
            -- We're done! Combine all accumulated JSON strings into an array
            let jsonArray = "[" <> Text.intercalate "," (reverse acc) <> "]"
            continueBackward $ ValString jsonArray
          ValCons headRef nextTailRef -> do
            -- More elements to process. Evaluate the head element first
            pushFrame (JsonEncodeListFrame acc nextTailRef False)
            continueRef headRef
          _ ->
            -- Should not happen - tail should be ValNil or ValCons
            internalException $ RuntimeTypeError "Expected list (ValNil or ValCons) for tail"
      else
        -- We just evaluated an element, so encode it and continue with the tail
        case val of
          ValNil -> do
            -- Element is an empty list
            pushFrame (JsonEncodeListFrame ("[]" : acc) tailRef True)
            continueRef tailRef
          ValCons elemHeadRef elemTailRef -> do
            -- Element is a non-empty list, need to recursively encode it
            -- Push a frame to wait for the nested encoding, then start encoding the nested list
            pushFrame (JsonEncodeNestedFrame acc tailRef)  -- Will continue with tail after nested encoding
            pushFrame (JsonEncodeListFrame [] elemTailRef False)  -- Encode the nested list
            continueRef elemHeadRef
          _ -> do
            -- Element needs encoding (could be constructor, primitive, etc.)
            -- allocateRecursive it and use frame-based encoding to handle all cases properly
            elemRef <- allocateValue val
            pushFrame (JsonEncodeNestedFrame acc tailRef)  -- Will add result to acc and continue with tail
            pushFrame (UnaryBuiltin0 UnaryJsonEncode Nothing)  -- Encode using proper frame-based logic
            continueRef elemRef
  Just (JsonEncodeNestedFrame acc tailRef) -> do
    -- We just finished encoding an element (nested list, constructor, or primitive), val should be a ValString with the JSON
    case val of
      ValString encodedJson -> do
        -- Add the encoded JSON to accumulator and continue with the tail
        pushFrame (JsonEncodeListFrame (encodedJson : acc) tailRef True)
        continueRef tailRef
      _ ->
        -- Should not happen - encoding should return ValString
        internalException $ RuntimeTypeError "Expected ValString from element encoding"
  Just (JsonEncodeConstructorFrame acc currentFieldName remaining) -> do
    -- We just finished encoding a field value, val should be a ValString with the JSON
    case val of
      ValString encodedJson -> do
        -- Pair the current field name with the encoded value
        let newPair = (currentFieldName, encodedJson)
            newAcc = newPair : acc
        -- Check if there are more fields to encode
        case remaining of
          [] -> do
            -- All fields encoded! Build the final JSON object
            -- Note: acc is in reverse order, so reverse it
            let allPairs = reverse newAcc
                jsonFields = map (\(fname, fval) -> "\"" <> fname <> "\":" <> fval) allPairs
                jsonObject = "{" <> Text.intercalate "," jsonFields <> "}"
            continueBackward $ ValString jsonObject
          ((nextFieldName, nextFieldRef):rest) -> do
            -- More fields to encode
            pushFrame (JsonEncodeConstructorFrame newAcc nextFieldName rest)
            pushFrame (UnaryBuiltin0 UnaryJsonEncode Nothing)
            continueRef nextFieldRef
      _ ->
        -- Should not happen - field encoding should return ValString
        internalException $ RuntimeTypeError "Expected ValString from field encoding"
  Just (UpdateThunk rf saved _displaced) -> do
    -- Close this force's read span. LIFO frame discipline guarantees any
    -- scope/iterator frames pushed during the force were popped (restoring
    -- the temporal context) before this frame, so 'mine' reflects exactly
    -- this force's observations. Reads propagate to the enclosing span so a
    -- consuming thunk inherits the dependency.
    mine <- swapCtxReads noReads
    noteCtxRead (saved <> mine)
    if mine.crLedgerWrite
      -- STATE-AS-LEDGER write poison (see 'noteLedgerWrite'): this force
      -- APPENDED to the ledger, so re-forcing is NOT a deterministic replay
      -- — it would fire the RECORD again (double-write). Cache as a plain
      -- 'WHNF' (snapshot at first force): the write fires exactly once and
      -- every later use shares the first-force value.
      then updateThunkToWHNF rf val
      else if hasReads mine
        -- Covers both plain temporal reads AND read-only ledger forces
        -- ('crLedgerRead' — finishRead always records the tx/vt axes, so a
        -- RECALL force lands here): the fingerprint re-serves the value
        -- while the observed axes match and re-forces under a different
        -- temporal scope, giving each scope its own ledger snapshot
        -- (smucclaw/l4-ide#914 §2B; snapshot-per-scope, see 'crLedgerRead').
        then updateThunkToWHNFWhen rf mine val
        else updateThunkToWHNF rf val -- read-free force: plain WHNF, full sharing forever
    continueBackward val
  Just (ContractFrame cFrame) -> backwardContractFrame val cFrame

backwardContractFrame :: Value Reference -> ContractFrame -> Machine Config
backwardContractFrame val = \ case
  Contract1 ScrutinizeEvents {..} -> do
    case val of
      ValCons e es -> do
        ev'reoffered <- isReoffered e
        -- one more event taken: 'seen' is now this event's position in the
        -- stream, which is what a barrier orders same-stamp failures by
        pushCFrame (Contract2 ScrutinizeEvent {events = es, seen = seen + 1, ..})
        continueRef e
      ValNil -> do
        -- P2b: the stream ran out; the residual stands. The clock is peeked,
        -- not forced: with no event seen yet it may still be a thunk.
        whenDeonticLog \ l -> do
          clock <- peekClock time
          logStep l (plainStep clock Nothing NoEvent norm Waiting)
        continueBackward (ValObligation env party act opens due followup lest)
      _ -> internalException $ RuntimeTypeError $
        "expected LIST EVENT but found: " <> prettyLayout val <> " when scrutinizing regulative events"
  Contract2 ScrutinizeEvent {..} -> case val of
    ValEvent ev'party ev'act ev'time -> do
      pushCFrame (Contract3 CurrentTimeWHNF {..})
      continueRef ev'time
    _ -> internalException $ RuntimeTypeError $
      "expected an EVENT but found: " <> prettyLayout val <> " when scrutinizing a regulative event"
  Contract3 CurrentTimeWHNF {..} -> do
    pushCFrame (Contract4 ScrutinizeDue {ev'time = val, ..})
    continueRef time
  Contract4 frame@ScrutinizeDue {..} -> do
    -- 'val' is the frame's clock, forced. The window's OPENING edge comes
    -- first (EVERY-EACH-QUANTIFIER-SPEC §5.1.2, R-X5, 2026-09-16), because a
    -- bare WITHIN beside an AFTER counts from the instant the window opens
    -- (R-X5 as amended, §5.1.2.2: re-anchor). Like the deadline it is
    -- resolved ONCE, at the first event, when 'time' is still the arming
    -- time; after 'Contract5' it is a relative number ('MaybeOpened').
    case opens of
      -- the opening already resolved: the window opens 'rel' after the clock
      Right (Just rel) -> do
        time' <- assertTime val
        rel' <- assertTime rel
        scrutinizeDue val (Just (time' + rel')) frame
      -- no opening edge, or the window already open
      Right Nothing -> scrutinizeDue val Nothing frame
      Left Nothing  -> scrutinizeDue val Nothing frame
      Left (Just (MkOpening _ offset Nothing)) -> do
        pushCFrame (Contract4o ScrutinizeOpening {time = val, openAnchorT = Nothing, ..})
        continueExpr env offset
      Left (Just (MkOpening _ offset (Just anchor))) -> do
        pushCFrame (Contract4oa ScrutinizeOpeningAnchor {time = val, ..})
        resolveAnchor env armed anchor
  Contract4oa ScrutinizeOpeningAnchor {..} -> do
    instant <- lowerInstant "The anchor of the AFTER" armed val
    pushCFrame (Contract4o ScrutinizeOpening {openAnchorT = Just instant, ..})
    continueExpr env offset
  Contract4o frame@ScrutinizeOpening {..} -> do
    -- the offset, forced: a duration from the opening's anchor (or from the
    -- clock, i.e. the arming on this first evaluation), or a DATE — the
    -- opening instant itself — lowered by its serial (the checker has
    -- refused an anchor on a DATE)
    time' <- assertTime time
    open <- case val of
      ValNumber d -> pure (fromMaybe time' openAnchorT + d)
      ValDate _   -> lowerInstant "AFTER" armed val
      v -> internalException $ RuntimeTypeError $
        "expected a NUMBER or a DATE after AFTER but got: " <> prettyLayout v
    scrutinizeDue time (Just open) (dueFrameOfOpening frame)
  Contract4b ScrutinizeAnchor {..} -> do
    -- the anchor's instant, lowered to the trace's clock: a DATE by its
    -- serial (what DATE_SERIAL computes), a NUMBER as it is ('lowerInstant',
    -- which guards 'anchorInstant' with the floating-clock refusal)
    instant <- lowerInstant "The anchor of the WITHIN" armed val
    pushCFrame (Contract5 CheckTiming {origin = Just instant, ..})
    continueExpr env duration
  Contract5 CheckTiming {..} -> do
    stamp <- assertTime ev'time
    time' <- assertTime time
    -- The closing edge, forced. A NUMBER is a duration: unanchored and with
    -- no AFTER, it counts from the obligation's clock — its arming, on this
    -- first evaluation — and after that evaluation it is the REMAINING due
    -- relative to the clock, so the same sum holds. Anchored (@WITHIN d OF
    -- …@, R-Q7) it is ABSOLUTE, the anchor's instant plus @d@, which may
    -- already be in the past at arming; then this very event reveals the
    -- expiry, which is right and not an error. Beside an AFTER, a bare
    -- WITHIN counts from the instant the window opens ('origin' is that
    -- instant: R-X5 as amended, re-anchor). A DATE is a @BEFORE@: the
    -- instant itself, lowered by its serial ('lowerInstant' refuses a clock
    -- that is not on that scale).
    deadline <- case val of
      ValNumber due' -> pure (fromMaybe time' origin + due')
      ValDate _      -> lowerInstant "BEFORE" armed val
      v -> internalException $ RuntimeTypeError $
        "expected a NUMBER or a DATE as the closing edge but got: " <> prettyLayout v
    -- The explicitly anchored empty window (§5.1.2.2): @AFTER d1 WITHIN d2
    -- OF …@ with @d1 > d2@ from one anchor closes before it opens. The
    -- checker catches it when both offsets are literals; a run reports it
    -- here, once, when both instants are first known. The obligation then
    -- runs as written: every act is early or late, and the expiry is what
    -- ends it.
    when (isLeft due) $ forM_ openT \ open ->
      when (open > deadline) $ tellNote (emptyWindowNote open deadline)
    let
      -- NOTE: the new due is the current due minus the time that has passed
      -- by observing the current event e.g. if the thing
      -- was due within 3, then if the last current time
      -- is 2, and we are looking at an event at 3, then
      -- the current time is advances to 3 but the due is
      -- now earlier, it is  due within 2, i.e. 3 - (3 - 2).
      -- For an anchored deadline the same invariant — the absolute deadline
      -- is @time + due@ — is what makes the remaining due @deadline - stamp@.
      -- While the window has still to OPEN, the remaining due is relative
      -- to the opening instead ('relativeDue'): the residual then prints as
      -- the bare re-anchored window it is (@AFTER 1 WITHIN 30@ at 12 is
      -- @[13, 43]@, not @[13, 44]@), and the next scrutiny adds it back to
      -- the same instant ('scrutinizeDue', 'origin').
      newDue = deadline - relativeDue openT stamp
    -- NOTE: the deadline comparison is strict: an event arriving EXACTLY at
    -- the deadline instant is timely; expiry requires stamp strictly greater.
    -- The spec (doc/reference/regulative/README.md) speaks of the deadline
    -- "passing", which at the boundary instant it has not yet done.
    if stamp > deadline
      -- NOTE: the deadline has passed. What happens depends on the deontic modal:
      -- MUST/DO: deadline passed without action = BREACH (or LEST if specified)
      -- MUST NOT: deadline passed without prohibited action = FULFILLED (or HENCE if specified)
      -- MAY: deadline passed without exercising permission = FULFILLED (or LEST if specified)
      --
      -- NOTE: the event whose timestamp reveals that the deadline has passed
      -- is only a WITNESS that time advanced; it is not consumed by the
      -- expired obligation (CSL residuation: the obligation reduces to its
      -- continuation, which then processes the event). So we re-offer the
      -- revealing event to the HENCE/LEST continuation — e.g. a payment
      -- arriving after the deadline must still be able to discharge the LEST
      -- reparation it was authored for.
      --
      -- The continuation's CLOCK — what an unanchored WITHIN inside it
      -- counts from (R-Q7's default, spec §5.1/§5.2) — depends on the slot:
      --
      --   * under LEST it is the FAILURE TIME, which R-Q5 fixes by modal:
      --     for MUST/DO/MAY the deadline that was just missed (§5.2, built
      --     2026-09-16), so a defaulting party's silence cannot postpone
      --     the start of its own cure period; the re-offered event then
      --     decrements the continuation's WITHIN by the time that had
      --     already passed since the deadline. It is the SAME reference
      --     THE DEADLINE reads in that continuation ('lifecycleAt'), so
      --     @WITHIN d@ and @WITHIN d OF THE DEADLINE@ agree under LEST by
      --     construction. (For SHANT the failure is a violation, handled
      --     at 'Contract10' with the violating event's own stamp.)
      --   * under HENCE — here, a kept prohibition — it is the hand-off,
      --     i.e. the revealing event's stamp, which is also THE JOIN there
      --     (spec §5.1.1.1; moving a kept SHANT's join to its deadline is
      --     a separate decision, not taken here).
      --
      -- Before 2026-09-16 both slots used the revealing event's stamp,
      -- which made the re-offered event decrement a LEST's WITHIN by zero.
      --
      -- Termination. Because a LEST continuation counts from the missed
      -- deadline, its own deadline can lie BEFORE the re-offered event's
      -- stamp — the ordinary case whenever the miss came to light late —
      -- so the very same event reveals a second expiry, a third, and so
      -- on down a chain of LEST layers (or a continuation that names the
      -- enclosing obligation, @x MEANS PARTY p MUST a WITHIN d LEST x@).
      -- Every one of those layers is a real obligation whose window the
      -- event is past, and the event must reach the first layer whose
      -- window it is NOT past: that is the layer it can perform, or fail
      -- (spec §5.2, R-Q5). So a re-offered copy is ALWAYS handed on to the
      -- next layer, whatever that layer's deadline: a chain of DISTINCT
      -- layers is finite by its syntax, and withholding the copy from any
      -- of them is a wrong answer (round 2 of the adversarial pass of
      -- 2026-09-16: a middle layer anchored at or before the missed
      -- deadline, or a @WITHIN 0@, swallowed the next layer's timely
      -- performance, and the verdict at an instant depended on how many
      -- events the trace carried). The only chain that does not end is
      -- one that reaches ITSELF without the deadline advancing — a
      -- self-naming LEST with a non-positive WITHIN, or anchored at an
      -- instant no later than the deadline just missed — whose every
      -- incarnation is already past when it is entered. That is an
      -- ill-founded contract, and the machine refuses it by name rather
      -- than walking it forever: the copy carries a 'Reoffered' mark
      -- ('markReoffered', read back at Contract1 as 'ev'reoffered') with
      -- the latest deadline it has revealed the expiry of and the number
      -- of hand-offs in a row that failed to pass that mark; past
      -- 'maximumStalledReoffers' of those the walk stops with
      -- 'stalledChainRefusal'. A chain whose deadlines advance is finite
      -- whenever the durations are bounded away from zero (the deadlines
      -- are increasing and bounded above by the stamp); the one chain
      -- neither bound catches is a Zeno chain — durations shrinking
      -- geometrically, so the deadlines advance forever without reaching
      -- the stamp — which is left to the machine's 'StackOverflow' guard
      -- ('maximumFrameDepth': every nested hand-off leaves a
      -- 'RestoreCurrentParty' frame on the stack, so a 1,500,000-layer
      -- chain of cheap steps reports the overflow in about a second); a
      -- halving chain's rationals grow a bit per layer, so it hangs long
      -- before that guard is reached — as ordinary non-terminating
      -- recursion (@f x MEANS f (x PLUS 1)@, a tail call that pushes no
      -- frame) hangs too. Until round 2 of the adversarial pass a copy
      -- whose deadline had not advanced was CONSUMED — applied to the
      -- events after it — which dropped it before the first layer whose
      -- window it was not past; until round 1 it was consumed on its
      -- second expiry, whatever the deadline did (spec §5.2.1).
      --
      -- STATE-AS-LEDGER (M4) integration: rather than calling 'continueWithFollowup'
      -- directly (as the re-offer logic did before the ledger landed),
      -- 'reofferResolve' pushes a 'ResolveParty' frame and forces the obligation
      -- party first, so a RECORD in the followup/reparation is attributed to the
      -- real acting party rather than the anonymous ledger. The (possibly
      -- re-offered) event stream and anchored time are carried in the frame and
      -- handed to 'continueWithFollowup' once the party has been keyed.
      then do
        -- What the continuation may anchor to (R-Q7B): the deadline that
        -- just passed, this obligation's arming, and — only when the
        -- continuation is the HENCE, i.e. the join fired — the hand-off
        -- clock as THE JOIN. Under LEST the hand-off clock IS 'deadlineR'
        -- (§5.2): one reference, read both as the unanchored default and
        -- as THE DEADLINE, so the two cannot drift apart. A barrier member
        -- hands that same reference to the failure sentinel as its anchor
        -- ('continueWithFollowup', 'sentinelArgs'), which is how the
        -- barrier's LEST comes to count from the failing member's deadline
        -- without a mechanism of its own ('barrierFail').
        deadlineR <- allocateValue (ValNumber deadline)
        -- P2b: the 'Expired' step. It is built here, where the deadline and
        -- the revealing event are in hand, but LOGGED at the ResolveParty
        -- frame for the routed cases, because that is where the party gets
        -- forced and the key wants the bearer. The scrutiny follows the
        -- re-offer rule above: a fresh event's look is 'WitnessedOnly' (it
        -- is re-offered onward), a re-offered copy's look is 'Reoffered' —
        -- and since round 2 of the LEST pass (spec §5.2.1, 2026-09-16) the
        -- copy is handed on again either way, never consumed.
        let expiredStep :: DS.Branch -> Maybe Text -> Eval (Maybe DeonticStep)
            expiredStep branch mBearer = asks (.deonticLog) >>= \ case
              Nothing -> pure Nothing
              Just _  -> do
                mParty <- peekParty ev'party
                ev <- eventKeyAt stamp mParty ev'act
                let norm' = norm {nkBearer = maybe norm.nkBearer Just mBearer}
                pure $ Just $ plainStep (Just time') (Just ev)
                  (scrutinyOf ev'reoffered WitnessedOnly) norm' (Expired branch deadline)
        let lifecycleAt isHence t = MkLifecycle
              { join = if isHence then Just t else Nothing
              , deadline = Just deadlineR
              , armed }
            clockAt isHence stampR = if isHence then stampR else deadlineR
            reofferResolve isHence followup' branch = do
              pending <- expiredStep branch Nothing
              -- The mark the copy carries on: a fresh event starts the walk
              -- at this deadline; a copy that has revealed an earlier
              -- expiry advances its high-water mark when this deadline
              -- passes it, and otherwise counts one more stalled hand-off
              -- — refused, by name, once there have been too many in a row
              -- (see NOTE above). The failure time is the deadline whether
              -- the event that revealed the miss was fresh or already
              -- marked.
              mark <- case ev'reoffered of
                Nothing -> pure MkReoffered {highWater = deadline, stalled = 0}
                Just m
                  | deadline > m.highWater -> pure MkReoffered {highWater = deadline, stalled = 0}
                  | m.stalled >= maximumStalledReoffers -> userException (UserError (stalledChainRefusal m.highWater stamp))
                  | otherwise -> pure m {stalled = m.stalled + 1}
              ev'timeR <- allocateValue ev'time
              evR <- allocateValue (ValEvent ev'party ev'act ev'timeR)
              markReoffered evR mark
              eventsR <- allocateValue (ValCons evR events)
              pushCFrame (ResolveParty ResolvePartyFrame {followup = followup', env, events = eventsR, time = clockAt isHence ev'timeR, pending, seen, lifecycle = lifecycleAt isHence ev'timeR})
              maybeEvaluate env party
        case act.modal of
          DMustNot ->
            -- Prohibition was RESPECTED: the prohibited action didn't occur before deadline
            -- Continue with HENCE (followup), which defaults to FULFILLED
            reofferResolve True followup ToHence
          DMay ->
            -- Permission was NOT EXERCISED: per the README default-consequence
            -- matrix, expiry of a MAY routes to LEST (default FULFILLED);
            -- HENCE fires only when the permitted action is taken. The
            -- LEST counts from the deadline, as a MUST's does (R-Q5: a MAY
            -- fails at its deadline).
            reofferResolve False (fromMaybe fulfilExpr lest) ToLest
          _ -> -- DMust, DDo: deadline passed = failure
            case lest of
              Nothing -> do
                -- NOTE: this is not too nice, but not wanting this would require to change `App1` to take MaybeEvaluated's
                -- The breach is DATED at the revealing event ('stamp') and
                -- carries the deadline it missed; §5.2 moves the LEST's
                -- clock, not this stamp (spec §3.4's last paragraph).
                partyR <- either (`allocate_` env) allocateValue party
                -- P2b: no continuation to force the party in; the bearer is
                -- what the breach's own party cell holds, if anything has
                -- forced it (a nullary constructor is allocated as a value,
                -- so @PARTY Alice@ is known; a computed party may not be).
                whenDeonticLog \ _ -> do
                  mBearer <- peekParty partyR
                  expiredStep ToBreach mBearer >>= traverse_ tellDeonticStep
                continueBackward (ValBreached (DeadlineMissed ev'party ev'act stamp (singleBlame (MissedDeadline partyR act deadline))))
              Just lestFollowup -> reofferResolve False lestFollowup ToLest
      else do
        -- NOTE: we have observed the event and do not branch, either, the
        -- only thing that may now happen is that we try a new event. Hence we
        -- drop the ev'time, set our time to ev'time and set our due to the new due
        -- (and the opening edge, when there is one, to what is still to run
        -- until the window opens — 'relOpening')
        pushCFrame (Contract6 PartyWHNF {time = ev'time, opens = relOpening openT stamp opens, due = Right $ ValNumber newDue, ..})
        maybeEvaluate env party
  Contract6 PartyWHNF {..} -> do
    -- P2b: the party is forced now; every later frame's key knows the bearer.
    pushCFrame (Contract7 PartyEqual {party = val, norm = bearing val norm, ..})
    continueRef ev'party
  Contract7 PartyEqual {..} -> do
    pushCFrame (Contract8 ScrutinizeParty {ev'party = val, ..})
    runBinOpEquals party val
  Contract8 ScrutinizeParty {..} ->
    case val of
      ValBool True -> do
        pushCFrame (Contract11 (ActionDoesn'tmatch {..}))
        pushCFrame (Contract9 ScrutinizeEnvironment {..})
        continuePattern ev'act env act.action
      ValBool False -> do
        whenDeonticLog \ l -> do
          stamp <- assertTime time
          ev <- eventKeyAt stamp (Just (partyKeyWHNF ev'party)) ev'act
          logStep l (plainStep (Just stamp) (Just ev) (scrutinyOf ev'reoffered WitnessedOnly) norm PartyMismatch)
        newTime <- allocateValue time
        tryNextEvent ScrutinizeEvents {party = Right party, time = newTime, ..} events
      _ -> internalException $ RuntimeTypeError $
        "expected BOOLEAN but found: " <> prettyLayout val
  Contract11 ActionDoesn'tmatch {} ->
    -- NOTE: this is a "guard frame" which only matters if we're unwinding the stack after a pattern match failure
    continueBackward val
  Contract9 ScrutinizeEnvironment {..} ->
    case val of
      ValEnvironment henceEnv -> do
        pushCFrame $ Contract10 ScrutinizeActions {..}
        continueExpr (env `Map.union` henceEnv) (fromMaybe trueExpr act.provided)
      _ -> internalException $ RuntimeTypeError $
        "expected environment but found: " <> prettyLayout val
  Contract10 ScrutinizeActions {..} ->
    case val of
      -- THE act, by THIS party, BEFORE the window opened (R-X6, RULED
      -- 2026-09-07, EVERY-EACH-QUANTIFIER-SPEC §5.1.2): a NULLITY. It is not
      -- performance (MUST/MAY/DO), and not a violation (SHANT: the
      -- prohibition has not started). The obligation is unchanged — its
      -- absolute deadline is what it was, its opening instant too — and the
      -- party may act again once the window opens; the event is passed over
      -- exactly as a non-matching one is. What R-X6 adds is that the run
      -- REPORTS it: a silent nullity is how a party loses a deadline it
      -- believed it had met. This is the only place that can know the act
      -- was the act: party, action and PROVIDED have all matched here.
      ValBool True | Right (Just untilOpen) <- opens -> do
        stamp <- assertTime time
        rel <- assertTime untilOpen
        partyNF <- peekNF party
        -- the remaining due is measured from the opening while the window
        -- is still to open ('relativeDue'), which it is here
        let open = stamp + rel
            deadlineAt = case due of
              Right (ValNumber remaining) -> Just (open + remaining)
              _                           -> Nothing
        tellNote (earlyActNote act.modal partyNF act.action stamp open deadlineAt)
        -- P2b: the look is logged, as every other look at an event is (one
        -- record per scrutiny, 'DeonticStep'): a pass-over that names the
        -- opening, so a what-if can say WHY the act was not taken and a
        -- step log shows the event at all. 'WitnessedOnly': the event stays
        -- on the stream (or 'Reoffered', for a copy handed down a LEST chain).
        whenDeonticLog \ l -> do
          ev <- eventKeyAt stamp (Just (partyKeyWHNF ev'party)) ev'act
          logStep l (plainStep (Just stamp) (Just ev) (scrutinyOf ev'reoffered WitnessedOnly) norm (EarlyAct open))
        newTime <- allocateValue time
        tryNextEvent ScrutinizeEvents {party = Right party, time = newTime, ..} events
      ValBool True -> do
        -- P2b: the match, routed per modal. Logged before the continuation
        -- is entered, so the log reads in machine order.
        let matchedStep branch = whenDeonticLog \ _ -> do
              stamp <- assertTime time
              ev <- eventKeyAt stamp (Just (partyKeyWHNF ev'party)) ev'act
              tellRoutedStep norm branch
                (plainStep (Just stamp) (Just ev) (scrutinyOf ev'reoffered Consumed) norm (Matched branch))
        -- Action matched! What happens depends on the deontic modal:
        -- MUST/MAY/DO: action done = success → continue with HENCE (followup)
        -- MUST NOT: action done = VIOLATION → continue with LEST (or BREACH if no LEST)
        case act.modal of
          DMustNot -> case lest of
            -- Prohibition violated: action was done, trigger LEST clause
            Just lestFollowup -> do
              matchedStep ToLest
              -- The LEST counts from the violating event's own stamp,
              -- which 'time' already is here ('Contract6' set it): R-Q5's
              -- failure time for SHANT, the one modal whose failure is an
              -- act rather than a lapse (spec §5.2). The violating event
              -- is consumed, not re-offered — 'events' is what followed it.
              timeR <- allocateValue time
              deadlineR <- absoluteDeadline time due
              -- LEST: the join did not fire, so no THE JOIN (R-Q7B); THE
              -- DEADLINE is the window's end, which is NOT the clock here
              let lifecycle = MkLifecycle {join = Nothing, deadline = deadlineR, armed}
              continueWithFollowup (Just (partyKeyWHNF party)) lifecycle (env `Map.union` henceEnv) lestFollowup events timeR seen
            -- No LEST clause: immediate breach
            Nothing -> do
              matchedStep ToBreach
              -- Extract timestamp from time (which has been updated to event time)
              stamp <- assertTime time
              -- allocateRecursive references for the WHNF values
              ev'partyRef <- allocateValue ev'party
              partyRef <- allocateValue party
              -- For prohibition breach, we use the action time as "deadline"
              -- since the action should never have happened. This sentinel
              -- (deadline == event timestamp) is deliberate and reaches the
              -- wire: a violated prohibition serializes with equal
              -- "timestamp" and "deadline" fields (see the ReasonForBreach
              -- ToJSON instance in L4.Evaluate.ValueLazyJSON). The README
              -- matrix only mandates SHANT+action => LEST/breach and does not
              -- prescribe the breach record's deadline field, so this does
              -- not contradict the spec.
              continueBackward (ValBreached (DeadlineMissed ev'partyRef ev'act stamp (singleBlame (MissedDeadline partyRef act stamp))))
          -- MUST, MAY, DO: action done = success
          _ -> do
            matchedStep ToHence
            timeR <- allocateValue time
            deadlineR <- absoluteDeadline time due
            -- HENCE: the join is this completion (R-Q7, §5.1: an unanchored
            -- continuation counts from here, so OF THE JOIN is the default
            -- said out loud)
            let lifecycle = MkLifecycle {join = Just timeR, deadline = deadlineR, armed}
            continueWithFollowup (Just (partyKeyWHNF party)) lifecycle (env `Map.union` henceEnv) followup events timeR seen
      ValBool False -> do
        -- P2b: the action matched but the PROVIDED did not hold; next event.
        whenDeonticLog \ l -> do
          stamp <- assertTime time
          ev <- eventKeyAt stamp (Just (partyKeyWHNF ev'party)) ev'act
          logStep l (plainStep (Just stamp) (Just ev) (scrutinyOf ev'reoffered WitnessedOnly) norm GuardFailed)
        newTime <- allocateValue time
        tryNextEvent ScrutinizeEvents {party = Right party, time = newTime, ..} events
      _ -> internalException $ RuntimeTypeError $
        "expected BOOLEAN but found: " <> prettyLayout val
  ResolveParty ResolvePartyFrame {..} -> do
    -- P2b: the party is forced; log the 'Expired' step Contract5 built,
    -- with the bearer filled in and the join progress worked out.
    for_ pending \ step -> for_ step.dsNorm \ norm ->
      for_ (expiredBranch step.dsOutcome) \ branch ->
        tellRoutedStep (bearing val norm) branch step
    -- 'val' is the obligation party, now forced to WHNF by 'maybeEvaluate env party'
    -- on the deadline-passed / LEST path. Key it exactly as the matched HENCE path
    -- does, so a RECORD in the followup/reparation attributes to the real party.
    -- 'time' is the continuation's clock as 'Contract5' chose it: the
    -- missed deadline under LEST, the revealing event's stamp under HENCE.
    continueWithFollowup (Just (partyKeyWHNF val)) lifecycle env followup events time seen
  -- R-Q7B: the continuation's value, about to meet its [time, events]: make
  -- the anchors inside it name THIS hand-off's obligation, whatever
  -- environment the value happened to capture ('rebindLifecycle').
  Handoff lifecycle ->
    continueBackward (rebindLifecycle lifecycle val)
  -- EVERY, the roll call. One cons cell of the roll per step.
  QuantRoll QuantRollFrame {..} ->
    case val of
      ValNil -> assembleQuantified ctx (reverse acc)
      ValCons hd tl -> do
        pushCFrame (QuantCast QuantCastFrame {candidate = hd, rest = tl, ..})
        continueRef hd
      _ -> internalException $ RuntimeTypeError $
        "expected a LIST for the cast of EVERY but found: " <> prettyLayout val
  -- EVERY: the cast test. @EVERY Tenant t@ admits only values built by the
  -- constructor @Tenant@; @EVERY t@ admits every entry of the roll.
  QuantCast QuantCastFrame {..} -> do
    let admitted = case ctx.cast of
          Nothing -> True
          Just c  -> case val of
            ValConstructor n _ -> n `sameResolved` c
            _                  -> False
    if not admitted
      then quantNext QuantRollFrame {..} rest
      else case ctx.filt of
        Nothing -> quantNext QuantRollFrame {acc = (candidate, val) : acc, ..} rest
        Just f  -> do
          pushCFrame (QuantFilter QuantFilterFrame {candidateV = val, ..})
          continueExpr (Map.insert (getUnique ctx.var) candidate ctx.env) f
  -- EVERY: the WHO filter's verdict for one candidate.
  QuantFilter QuantFilterFrame {..} ->
    case boolView val of
      Just True  -> quantNext QuantRollFrame {acc = (candidate, candidateV) : acc, ..} rest
      Just False -> quantNext QuantRollFrame {..} rest
      Nothing    -> internalException $ RuntimeTypeError $
        "expected BOOLEAN from the WHO filter of EVERY but found: " <> prettyLayout val
  -- EVERY, the barrier: one member's result. NOTE: a barrier member never
  -- carries the barrier's LEST as an EXPRESSION — it carries a sentinel
  -- ('failpoint') in that slot instead. That is what keeps the three outcomes
  -- apart here: the checkpoint sentinel (completed), the failure sentinel
  -- (definitively did not), and a residual 'ValObligation' (still waiting).
  -- Hand a member the real LEST and the last two collapse, because a pending
  -- reparation and a pending member are both 'ValObligation'.
  Barrier1 BarrierStepFrame {..} ->
    case val of
      ValConstructor n args
        | n `sameResolved` checkpoint
        , Just (dRef, _, tRef, evRef) <- sentinelArgs args -> do
        pushCFrame (Barrier2 BarrierStampFrame {step = BarrierStepFrame {..}, evsRef = evRef, dueRef = dRef})
        continueRef tRef
      -- The failure sentinel carries the anchor and the residual stream the
      -- machine computed for this member's miss, which is exactly what the
      -- barrier's LEST needs — so it runs ONCE, after every member has been
      -- run ('barrierFinish'), anchored at the EARLIEST failure, and no
      -- member is ever applied to the stream a second time. The anchor is
      -- forced here so the failures can be ordered; it is R-Q5's failure
      -- time as 'Contract5' and 'Contract10' compute it for a single
      -- obligation — the member's missed deadline for MUST/DO/MAY (§5.2),
      -- its violating event's stamp for SHANT. The sentinel also carries
      -- the stream position of the event that revealed the miss (its third
      -- argument; forced next, 'Barrier5c') and the member's deadline (its
      -- fourth, when it had one; 'Barrier5b'), which is what OF THE
      -- DEADLINE in the LEST names (R-Q7B): kept beside the anchor, so the
      -- LEST is handed the deadline of the member whose failure anchors it
      -- — for MUST/DO/MAY the very same reference as the anchor.
      ValConstructor n args
        | Just fp <- failpoint, n `sameResolved` fp
        , Just (dRef, pRef, tRef, evRef) <- sentinelArgs args -> do
        pushCFrame (Barrier5 BarrierFailStampFrame {step = BarrierStepFrame {..}, timeRef = tRef, evsRef = evRef, posRef = pRef, dueRef = dRef})
        continueRef tRef
      -- Still waiting. Keep the RESIDUAL ('val'), not the obligation as it
      -- stood before the scan ('current'): the residual is the one whose
      -- deadline has been decremented by the time that has passed.
      ValObligation{} -> barrierNext BarrierStepFrame {pending = val : pending, ..}
      ValROp{}        -> barrierNext BarrierStepFrame {pending = val : pending, ..}
      -- A member's own breach, under a barrier with no LEST (so no sentinel
      -- was minted). Recorded, not returned: the scan goes on so that the
      -- verdict can name EVERY member that failed (R-T3, spec §6.1). P2b's
      -- 'JoinFailed ToBreach' step is logged where the verdict is decided
      -- ('barrierFinish'), not per member.
      ValBreached reason ->
        barrierNext BarrierStepFrame {failures = BarrierBreached reason : failures, ..}
      -- A MAY member whose permission expired under a barrier with no LEST:
      -- nothing was owed, so nothing is breached, but the join cannot fire.
      -- P2b's 'JoinStalled' step is likewise logged at 'barrierFinish'.
      ValFulfilled    -> barrierNext BarrierStepFrame {lapsed = True, ..}
      -- Every terminal a member can reach is named above; anything else is a
      -- machine bug, and is loud (P2b) rather than returned as the verdict.
      other -> internalException $ RuntimeTypeError $
        "unexpected barrier member value: " <> prettyLayout other
  -- EVERY, the barrier: a completion's timestamp. The LATEST one is the
  -- join's firing time, and the stream that followed it is what the HENCE
  -- scrutinizes (spec §3.4, §5.1).
  Barrier2 BarrierStampFrame {..} -> do
    stamp <- assertTime val
    let better = case step.tLast of
          Just (t, _) | t >= stamp -> step.tLast
          _                        -> Just (stamp, evsRef)
        step' = step {tLast = better}
    -- the completer's own absolute deadline, when it had one, so the
    -- HENCE can be told the LATEST of them ('dueLatest'); a maximum, so the
    -- roll's order decides nothing here (it does decide the stream, above)
    case dueRef of
      Nothing -> barrierNext step'
      Just d  -> do
        pushCFrame (Barrier2b BarrierDueFrame {step = step'})
        continueRef d
  Barrier2b BarrierDueFrame {..} -> do
    due <- assertTime val
    barrierNext step {dueLatest = Just (maybe due (max due) step.dueLatest)}
  -- EVERY, the barrier over nobody: armed, and therefore joined — "all zero
  -- of them have acted" is true at once. The join fires at the arming time,
  -- through the ONCE line's WITHIN when it has one, like any other join;
  -- nobody had an act deadline, so there is no 'dueLatest'.
  BarrierEmpty BarrierEmptyFrame {..} -> do
    t <- assertTime val
    barrierJoined ctx t ctx.events Nothing
  -- EVERY, the barrier: a failing member's anchor, forced. Kept in roll
  -- order; 'barrierFinish' picks the earliest. The failure's stream position
  -- is forced next ('Barrier5c'): it breaks a tie between two failures at
  -- one stamp that two DIFFERENT events revealed (a SHANT barrier, where the
  -- failure is the member's own violating event). Then the member's
  -- deadline, when it had one ('Barrier5b'). Since the anchor became the
  -- deadline for MUST/DO/MAY (§5.2, 2026-09-16) the third key can no
  -- longer separate what the first two tied: two such members with one
  -- anchor have one deadline, and are revealed by one event. It is kept,
  -- and documented as redundant, rather than half-removed.
  Barrier5 BarrierFailStampFrame {..} -> do
    stamp <- assertTime val
    pushCFrame (Barrier5c BarrierFailPosFrame {step, failAt = stamp, timeRef, evsRef, dueRef})
    continueRef posRef
  Barrier5c BarrierFailPosFrame {..} -> do
    pos <- case val of
      ValNumber n -> pure (truncate n)
      v -> internalException $ RuntimeTypeError $
        "expected a NUMBER as a barrier sentinel's stream position but got: " <> prettyLayout v
    case dueRef of
      Nothing -> barrierNext step
        { failures = BarrierFailedAt {failAt, failPos = pos, failDue = Nothing, failTimeRef = timeRef, failEvsRef = evsRef, failDueRef = Nothing} : step.failures }
      Just d -> do
        pushCFrame (Barrier5b BarrierFailDueFrame {step, failAt, failPos = pos, timeRef, evsRef, dueRef = d})
        continueRef d
  Barrier5b BarrierFailDueFrame {..} -> do
    due <- assertTime val
    barrierNext step
      { failures = BarrierFailedAt {failAt, failPos, failDue = Just due, failTimeRef = timeRef, failEvsRef = evsRef, failDueRef = Just dueRef} : step.failures }
  -- BREACH BY e: the party expression, forced. A LIST names each of its
  -- elements (walked one cell per step, like the roll call), ONE declared
  -- failure each, in the list's order and WITH duplicates — @BY LIST a, a@
  -- is two entries (RULED 2026-09-15, spec §6.1: no dedup). The elements
  -- themselves stay thunks; nothing here needs them forced. Anything that is
  -- not a list is the one party. The head of the list is the anchor (a
  -- declared breach carries no time, so the choice is nominal).
  BreachBy BreachByFrame {..} ->
    case val of
      ValCons hd tl -> do
        pushCFrame (BreachBy BreachByFrame {acc = hd : acc, ..})
        continueRef tl
      ValNil -> case reverse acc of
        []       -> userException (UserError (emptyBreachByRefusal clause))
        (p : ps) -> declareBreach $ ExplicitBreach
          Blame { before = [], anchor = declared p, after = map declared ps }
      _ | null acc -> declareBreach (ExplicitBreach (singleBlame (declared partyRef)))
        | otherwise -> internalException $ RuntimeTypeError $
            "expected a LIST of parties after BREACH BY but found: " <> prettyLayout val
    where
      declared p = DeclaredBreach (Just p) mReason
  -- EVERY, the barrier: the WITHIN on the ONCE line (R-T2), which bounds the
  -- WHOLE (spec §2.2.7.5 point 3) rather than any one act.
  Barrier3 BarrierStateDueFrame {..} -> do
    stateDue <- assertTime val
    pushCFrame (Barrier4 BarrierArmingFrame {..})
    -- what the state deadline counts from: the EVERY's arming (unanchored,
    -- and OF THE ARMING says the same thing on a join line), or the
    -- instant an OF-expression names. OF THE JOIN and OF THE DEADLINE are
    -- refused on a join line by the checker ('L4.TypeCheck.checkAnchor').
    case joinStateDue ctx of
      Just (MkDeadline _ _ (Just (AnchorAt _ e))) -> continueExpr ctx.env e
      Just (MkDeadline _ _ (Just a@AnchorJoin{}))     -> unreachableAnchor a
      Just (MkDeadline _ _ (Just a@AnchorDeadline{})) -> unreachableAnchor a
      Just MkBefore{} -> beforeOnJoinLine
      _ -> continueRef ctx.time
  Barrier4 BarrierArmingFrame {..} -> do
    -- the state deadline's origin, forced (see 'Barrier3'): a NUMBER, or a
    -- DATE lowered to its serial ('anchorInstant')
    origin <- either (internalException . RuntimeTypeError) pure (anchorInstant val)
    let stateDeadline = origin + stateDue
    if joinTime > stateDeadline
      then barrierStateMissed ctx joinTime stateDeadline
      else do
        tRef <- allocateValue (ValNumber joinTime)
        dRef <- allocateValue (ValNumber stateDeadline)
        fireBarrierHence ctx (Just dRef) tRef joinEvents
  -- EVERY, the barrier, the state layer's LEST ('barrierStateMissed'): the
  -- walk from the barrier's arming to the first event stamped after the
  -- state deadline, one cons cell per step — the cell, then its event, then
  -- the event's stamp — so the LEST is handed the stream from that event
  -- on, as the act layer hands its LEST the stream from the revealing
  -- event on. The walk stops at the FIRST such event and keeps everything
  -- after it (a trace is stamp-sorted, so that is also every such event).
  BarrierTrim BarrierTrimFrame {..} -> case val of
    ValNil -> barrierStateLest ctx lestExpr cutoffRef cell
    ValCons e es -> do
      pushCFrame (BarrierTrimEvent BarrierTrimCellFrame {rest = es, ..})
      continueRef e
    _ -> internalException $ RuntimeTypeError $
      "expected LIST EVENT but found: " <> prettyLayout val <> " when trimming a barrier's stream to its state deadline"
  BarrierTrimEvent BarrierTrimCellFrame {..} -> case val of
    ValEvent _ _ tR -> do
      pushCFrame (BarrierTrimStamp BarrierTrimCellFrame {..})
      continueRef tR
    _ -> internalException $ RuntimeTypeError $
      "expected an EVENT but found: " <> prettyLayout val <> " when trimming a barrier's stream to its state deadline"
  BarrierTrimStamp BarrierTrimCellFrame {..} -> do
    stamp <- assertTime val
    if stamp > cutoff
      then barrierStateLest ctx lestExpr cutoffRef cell
      else do
        pushCFrame (BarrierTrim BarrierTrimFrame {cell = rest, ..})
        continueRef rest
  RBinOp1 MkRBinOp1 {..}
    -- NOTE: this is weirdly asymmetric because
    -- in case of AND we can never abort earlier but have to instead
    -- wait for the left hand side expression to run to observe
    -- how we'll have to do the blame assignment
    | ValROr <- op
    , ValFulfilled <- val -> do
      -- P2b: the OR's commonest success path. The RBinOp2 arm for a
      -- fulfilled LEFT operand is unreachable because of this short-circuit,
      -- so the step is logged here.
      joinedStep op JoinFulfilled (Just LeftSide) False
      continueBackward ValFulfilled

  RBinOp1 MkRBinOp1 {..} -> do

    -- push a frame for when the evaluation of the
    -- second argument has completed
    pushCFrame $ RBinOp2 MkRBinOp2 {rval1 = val, ..}
    -- pass the arguments to the regulative expression
    pushFrame $ App1 args Nothing
    -- R-Q7B: the right operand is handed off like the left one was
    operandHandoff env rexpr2
    maybeEvaluate env rexpr2

  RBinOp2 MkRBinOp2 {..}
    -- if both obligations have been breached — with ANY mix of breach kinds
    -- (DeadlineMissed / ExplicitBreach) — then the compound is breached:
    -- for RAND because all components must be fulfilled, for ROR because
    -- every alternative has been definitively lost.
    | ValBreached r1 <- rval1
    , ValBreached r2 <- val
    -> do
      -- NOTE: the compound breach is ANCHORED at one operand's breach and
      -- NAMES every failure of both operands (R-T3, spec §6.1, built
      -- 2026-09-15; per-entry detail and no dedup RULED the same day).
      --
      -- The anchor — whose kind ('DeadlineMissed' with its revealing event,
      -- or 'ExplicitBreach') and whose time the result carries — is chosen
      -- by time: the FIRST breach for RAND, because it is already the reason
      -- the conjunction is lost; the SECOND for ROR, because that is when
      -- the last alternative "missed its chance". When both happen at the
      -- same time the tie goes to the left operand for RAND and the right
      -- for ROR (consistently with CSL). ExplicitBreach carries no timestamp
      -- (adding one would ripple through the constructor arity and the
      -- jl4-service wire — known limitation), so a pair involving one is
      -- treated as simultaneous and resolved by the same tie-break: with a
      -- BECAUSE on both sides, the order they were lost in is never
      -- consulted. Each entry keeps its own action, deadline or BECAUSE, so
      -- nothing is lost by the choice except which side dates the breach.
      --
      -- The failures are the CONCATENATION of both operands', left operand
      -- first, with duplicates: @PARTY alice MUST x RAND PARTY alice MUST y@
      -- both missed names alice twice, once per way. A breach with no BY is
      -- one entry naming nobody.
      let leftAnchored = case (breachTime r1, breachTime r2, op) of
            (Just vt, Just vt', ValRAnd) -> vt <= vt'
            (Just vt, Just vt', ValROr)  -> vt > vt'
            (_, _, ValRAnd)              -> True
            (_, _, ValROr)               -> False
          -- P2b: simultaneous, or one side untimestamped, is CSL's tie-break
          tieBreak = case (breachTime r1, breachTime r2) of
            (Just vt, Just vt') -> vt == vt'
            _                   -> True
          (anchor, blame)
            | leftAnchored = (r1, anchorLeft  (breachBlame r1) (breachBlame r2))
            | otherwise    = (r2, anchorRight (breachBlame r1) (breachBlame r2))
          chosen = rebase blame anchor
      -- P2b: which side's breach anchors the compound's, and whether the
      -- tie-break chose it. The summary names every failure of both sides.
      whenDeonticLog \ _ -> do
        summary <- breachSummary chosen
        joinedStep op (JoinBreached summary) (Just (if leftAnchored then LeftSide else RightSide)) tieBreak
      continueBackward (ValBreached chosen)

  RBinOp2 MkRBinOp2 {..}
    | ValFulfilled <- val
    , ValFulfilled <- rval1
    -> do
      joinedStep op JoinFulfilled (Just BothSides) False
      continueBackward ValFulfilled

  -- NOTE: note that blame assignment in the case of AND
  -- operators may be wrong if the events are passed out
  -- of order wrt time

  -- AND
  RBinOp2 MkRBinOp2 {..}
    | ValRAnd <- op
    , ValBreached reason <- rval1
    -- NOTE: we have a breach and we assume that all "previous"
    -- events have been seen, thus this is the "actual" breach
    -- more specifically, with this assumption, there's no
    -- possibility for future events to advance a possible
    -- remaining obligation while changing the blame assignment
    -> do
      whenDeonticLog \ _ -> do
        summary <- breachSummary reason
        joinedStep op (JoinBreached summary) (Just LeftSide) False
      continueBackward (ValBreached reason)
  RBinOp2 MkRBinOp2 {..}
    | ValRAnd <- op
    , ValBreached reason <- val
    -> do
      whenDeonticLog \ _ -> do
        summary <- breachSummary reason
        joinedStep op (JoinBreached summary) (Just RightSide) False
      continueBackward (ValBreached reason)

  -- OR
  RBinOp2 MkRBinOp2 {..}
    | ValROr <- op
    , ValFulfilled <- val
    -> do
      joinedStep op JoinFulfilled (Just RightSide) False
      continueBackward ValFulfilled
  -- NOTE: unreachable — a fulfilled LEFT operand of an OR never gets past
  -- the RBinOp1 short-circuit above, which is where that step is logged.
  -- Kept so the arms read as the full table.
  RBinOp2 MkRBinOp2 {..}
    | ValROr <- op
    , ValFulfilled <- rval1
    -> do
      joinedStep op JoinFulfilled (Just LeftSide) False
      continueBackward ValFulfilled


  -- NOTE: otherwise, we do not have enough information to do
  -- any reduction of the contract clauses and thus have to return
  -- a value that represents the operator applied to each operand
  RBinOp2 MkRBinOp2 {..} -> do
    joinedStep op JoinPending Nothing False
    continueBackward (ValROp env op (Right rval1) (Right val))
  where
    tryNextEvent :: ScrutinizeEvents -> Reference -> Machine Config
    tryNextEvent frame events = do
      pushCFrame (Contract1 frame)
      continueRef events

    -- The closing edge, once the opening instant (if any) is known: what
    -- 'Contract4' did on its own before the window had an opening edge.
    -- @timeW@ is the frame's clock, forced; @openT@ the absolute instant the
    -- window opens, when it has one. Three shapes of closing edge, plus none:
    --
    --   * an already-evaluated remaining due, relative to the clock;
    --   * the source deadline, met for the first time — the arming point as
    --     far as the deadline is concerned: no event has advanced 'time' yet,
    --     so an anchor is resolved ONCE, here, in the obligation's own
    --     environment and at its arming clock (R-Q7C: "evaluated once at
    --     arming"). After 'Contract5' the due is a relative number and the
    --     anchor is spent. A bare WITHIN beside an AFTER takes the opening
    --     instant as its origin (re-anchor, §5.1.2.2); an anchored one takes
    --     its anchor's; a BEFORE is a DATE and has no origin to add to;
    --   * no closing edge at all: the timing step is skipped, so the clock
    --     is advanced to the event's stamp here, which the timing step would
    --     otherwise have done — and the opening edge, when the act has one
    --     (@AFTER@ alone: a window that opens and never closes), is still
    --     re-relativised to that stamp, so 'Contract10' can see whether the
    --     window has opened.
    scrutinizeDue :: WHNF -> Maybe Rational -> ScrutinizeDue -> Machine Config
    scrutinizeDue timeW openT ScrutinizeDue {..} = case due of
      -- the remaining due is relative to the instant the WITHIN runs from:
      -- the window's opening while that is still ahead, the clock otherwise
      -- ('relativeDue'); 'openT' is that opening exactly when it is ahead
      Right due' -> do
        pushCFrame (Contract5 CheckTiming {time = timeW, origin = openT, openT, ..})
        continueBackward due'
      Left (Just (MkDeadline _ duration Nothing)) -> do
        pushCFrame (Contract5 CheckTiming {time = timeW, origin = openT, openT, ..})
        continueExpr env duration
      Left (Just (MkDeadline _ duration (Just anchor))) -> do
        pushCFrame (Contract4b ScrutinizeAnchor {time = timeW, openT, ..})
        resolveAnchor env armed anchor
      Left (Just (MkBefore _ instant)) -> do
        pushCFrame (Contract5 CheckTiming {time = timeW, origin = Nothing, openT, ..})
        continueExpr env instant
      Left Nothing -> do
        stamp <- assertTime ev'time
        pushCFrame (Contract6 PartyWHNF {time = ev'time, opens = relOpening openT stamp opens, ..})
        maybeEvaluate env party

    -- An anchor, put to the machine: an expression is evaluated in the
    -- obligation's environment (a NUMBER on the trace's clock, or a DATE);
    -- the lifecycle positions of the ENCLOSING obligation are read from the
    -- bindings its hand-off made ('bindLifecycle'); THE ARMING with no
    -- enclosing obligation is this obligation's own arming. Shared by both
    -- edges (R-Q7 for the WITHIN, R-X5 for the AFTER).
    resolveAnchor :: Environment -> Reference -> Anchor Resolved -> Machine Config
    resolveAnchor env armed anchor = case anchor of
      AnchorAt _ e     -> continueExpr env e
      AnchorJoin _     -> continueRef =<< lifecycleRef env anchor lifecycleJoinUnique Nothing
      AnchorDeadline _ -> continueRef =<< lifecycleRef env anchor lifecycleDeadlineUnique Nothing
      AnchorArming _   -> continueRef =<< lifecycleRef env anchor lifecycleArmingUnique (Just armed)

    -- The opening edge re-relativised to an event's stamp, for the frames
    -- after 'Contract5' and for the residual: what is still to run until the
    -- window opens while it has not, nothing once it has. An act with no
    -- opening edge keeps its @Left Nothing@.
    relOpening :: Maybe Rational -> Rational -> MaybeOpened -> MaybeOpened
    relOpening openT stamp opens = case openT of
      Nothing   -> opens
      Just open
        | open > stamp -> Right (Just (ValNumber (open - stamp)))
        | otherwise    -> Right Nothing

    -- The instant a remaining due is measured from: the window's opening
    -- while that is still ahead of the stamp, the stamp otherwise.
    relativeDue :: Maybe Rational -> Rational -> Rational
    relativeDue openT stamp = maybe stamp (max stamp) openT

    -- 'Contract4o' carries the same fields as 'Contract4' plus the opening's
    -- anchor; hand the deadline scrutiny the frame it expects.
    dueFrameOfOpening :: ScrutinizeOpening -> ScrutinizeDue
    dueFrameOfOpening ScrutinizeOpening {..} = ScrutinizeDue {time = armed, ..}

    pushCFrame = pushFrame . ContractFrame

    -- | The time at which a breach materialized, if it carries one.
    -- ExplicitBreach is untimestamped (see NOTE at the both-breached clause).
    breachTime :: ReasonForBreach a -> Maybe Rational
    breachTime (DeadlineMissed _ _ stamp _) = Just stamp
    breachTime (ExplicitBreach _) = Nothing

    -- P2b: the branch a pending 'Expired' step was routed to.
    expiredBranch :: StepOutcome -> Maybe DS.Branch
    expiredBranch (Expired b _) = Just b
    expiredBranch _             = Nothing

    -- P2b: an 'RBinOp2' reduction, logged as a 'Joined' step. The compound
    -- is not a norm instance, so the step carries no key (see 'dsNorm').
    joinedStep :: RBinOp -> JoinResult -> Maybe Side -> Bool -> Eval ()
    joinedStep op result winner tieBreak = tellDeonticStep MkDeonticStep
      { dsClock = Nothing, dsEvent = Nothing, dsScrutiny = NoEvent, dsNorm = Nothing
      , dsOutcome = Joined op MkJoinNote {jnResult = result, jnWinner = winner, jnTieBreak = tieBreak}
      , dsJoin = Nothing }

    -- M4 party-threading hinge: set the acting party for the DURATION of the
    -- HENCE/LEST body, so a RECORD fired inside it routes to that party's own
    -- ledger and stamps its provenance. Because the CEK machine is trampolined
    -- (the followup is forced later by 'runConfig', not inline here), a plain
    -- monadic bracket would restore the party BEFORE the followup runs. So we
    -- use the SAME save/restore-FRAME idiom as 'EvalAsOfSystemTime': capture the
    -- enclosing party, set the new one, and push 'RestoreCurrentParty' FIRST (so
    -- it is processed LAST — after the followup and its App1 continuation have
    -- fully evaluated). The party is rendered to a 'Text' key by 'partyKey…'; an
    -- unevaluated/unkeyable party yields 'Nothing' (the RECORD then falls back to
    -- the anonymous own ledger), and a nested obligation's own followup re-sets
    -- and re-restores the party around its body.
    --
    -- The obligation's 'Lifecycle' is bound into the continuation's
    -- environment here ('bindLifecycle'), which is what an anchored
    -- @WITHIN … OF THE JOIN \/ THE DEADLINE \/ THE ARMING@ inside it reads
    -- (R-Q7B). An @A AND B@ continuation captures this environment for
    -- both operand EXPRESSIONS, so an operand written inline sees the one
    -- obligation whose hand-off this is; an operand that turns out to be a
    -- value built elsewhere is handed off again, with this same lifecycle,
    -- when the compound is applied ('operandHandoff').
    --
    -- A barrier's SENTINEL ('barrierMember') is the one continuation that
    -- takes two further arguments — the stream position of the hand-off and,
    -- when the member has one, its absolute deadline (see the paragraph below
    -- and 'sentinelArgs') — so that the barrier learns both without a second
    -- pass ('Barrier1'). A sentinel is recognised by its unique ('isSentinel');
    -- every other continuation is applied to @[time, events]@ exactly as before.
    --
    -- The binding is made twice, on purpose. Into the environment the
    -- followup EXPRESSION is evaluated in, so an obligation written inline
    -- (or under a RECORD's HENCE, which forwards without a hand-off of its
    -- own) captures it; and again into the VALUE that expression produced,
    -- by the 'Handoff' frame, so a continuation that arrived as a value — a
    -- @GIVEN k IS A DEONTIC …@ parameter, a @WHERE@ local, a top-level rule
    -- named here — anchors to the obligation it is attached to now, not to
    -- whatever its closure captured when it was built. The type checker only
    -- ever sees where an anchor is WRITTEN, which is why it refuses THE JOIN
    -- and THE DEADLINE at the top level: a value's anchor is resolved here.
    --
    -- A barrier sentinel ('isSentinel') is handed two more things after the
    -- @[time, events]@ every continuation receives: the stream position of
    -- the event this hand-off happened at ('seen' — what a barrier orders
    -- same-stamp failures by), and the obligation's absolute deadline when
    -- it had one (what @OF THE DEADLINE@ in the barrier's @LEST@ names).
    -- See 'sentinelArgs'.
    continueWithFollowup :: Maybe Text -> Lifecycle -> Environment -> RExpr -> Reference -> Reference -> Int -> Machine Config
    continueWithFollowup mParty lifecycle env followup events time seen = do
      mOriginal <- getCurrentParty
      putCurrentParty mParty
      pushFrame (RestoreCurrentParty mOriginal)
      args <- case followup of
        App _ r [] | isSentinel r -> do
          posRef <- allocateValue (ValNumber (fromIntegral seen))
          pure ([time, events, posRef] <> maybeToList lifecycle.deadline)
        _ -> pure [time, events]
      pushFrame (App1 args Nothing)
      pushCFrame (Handoff lifecycle)
      continueExpr (bindLifecycle lifecycle env) followup

    -- the obligation's absolute deadline at hand-off, if it has one: after
    -- 'Contract5' the due is the REMAINING due relative to 'time', so the
    -- absolute deadline is their sum (the invariant 'Contract5' keeps)
    absoluteDeadline :: WHNF -> MaybeEvaluated' (Maybe (Deadline Resolved)) -> Machine (Maybe Reference)
    absoluteDeadline time due = case due of
      Right (ValNumber remaining) -> do
        t <- assertTime time
        Just <$> allocateValue (ValNumber (t + remaining))
      _ -> pure Nothing

    assertTime = \ case
      ValNumber i -> pure i
      v -> internalException $ RuntimeTypeError $
        "expected a NUMBER but got: " <> prettyLayout v

maybeEvaluate :: Environment -> MaybeEvaluated -> Machine Config
maybeEvaluate env = either (continueExpr env) continueBackward

-- * EVERY: running a quantified obligation
--
-- $every
--
-- EVERY-EACH-QUANTIFIER-SPEC phase 2. The shape of the implementation is
-- forced by one fact about the language: a quantified obligation ranges over
-- a party type that is usually OPEN. @Tenant HAS name IS A STRING@ has one
-- constructor and infinitely many values, so "every tenant" is not something
-- the machine can enumerate. The spec says so itself (§2.2.7.5 point 5: the
-- pattern form "ranges over an open type and needs §2.1's @WHO member_of …@
-- filter"), and every runnable example in the spec and on the doc page draws
-- its cast from a list.
--
-- So: the CAST comes from the ROLL, and the roll comes from the filter. A
-- @WHO@ condition with an @elem <variable> <list>@ conjunct names the list to
-- draw from; the whole condition then narrows it, and the cast constructor
-- narrows it again. Without such a conjunct there is nothing to call the roll
-- from and evaluation refuses, naming the fix ('rollCallRefusal') — the same
-- move the language makes for a non-exhaustive @CONSIDER@ or a continuation
-- with no join line: decline to guess.

-- | The FALLBACK for a quantifier that names no roll outright: the first
-- @elem v xs@ conjunct of the @WHO@ filter, read left to right through @AND@.
-- Returns @xs@.
--
-- Consulted only when there is no @IN@ clause (§11.0.2, 2026-09-08). @IN@ is
-- the spelling to reach for; this one is kept because it is what the corpus
-- and the published examples were written against, and because an
-- @elem v xs@ conjunct is a perfectly good FILTER in its own right, so
-- reading a roll out of it costs nothing when no roll was written.
--
-- DEPRECATED as a spelling, 2026-09-08 (§13.5), and note what that does and
-- does not mean for this function. It is NOT scheduled for removal, and there
-- is deliberately NO warning: the recognition happens here, in the evaluator,
-- and 'L4.EvaluateLazy.Machine' imports 'L4.TypeCheck' rather than the other
-- way round, so a check-time warning would mean moving this function across a
-- module boundary or keeping one rule in two phases. The corpus was migrated
-- instead (§13.5), and what still exercises this path is
-- @jl4\/examples\/ok\/every\/run-roll.l4@, which exists for that purpose --
-- including its @circular@ rule, whose run-time refusal has no @IN@
-- counterpart because an @IN@ roll naming the member is caught at check time.
-- If you are here to delete this, read §13.5 first: it says what a removal
-- would need, and a warning is the first step, not this.
--
-- Matched by SPELLING — the function must be called @elem@ — which is the
-- device the parser already uses for @EACH@ in @UPON EACH@ and for @TIMEZONE@.
-- A user-defined two-argument @elem@ that shadows the prelude's would be taken
-- as the roll; that sharp edge is stated on doc\/reference\/regulative\/EVERY.md,
-- and is one of the reasons @IN@ exists.
quantifierRoll :: Resolved -> Expr Resolved -> Maybe (Expr Resolved)
quantifierRoll v = go
  where
    go :: Expr Resolved -> Maybe (Expr Resolved)
    go = \ case
      -- The surface 'And' node does not survive type checking: 'inferExpr''
      -- rewrites @a AND b@ to an application of the overloadable @AND@
      -- function ('L4.TypeCheck.desugarBinOpToFunction'), so the resolved
      -- filter of @WHO elem t tenants AND NOT (t EQUALS carol)@ is an 'App'.
      -- Both shapes are matched: the surface one costs nothing and stops this
      -- from silently regressing if an unchecked tree ever reaches here.
      And _ e1 e2 -> either' (go e1) (go e2)
      App _ f [e1, e2]
        -- @AND@'s builtin is spelled @__AND__@ internally
        -- ('L4.TypeCheck.Environment': @"and" `rename` "__AND__"@); matching by
        -- that name rather than by 'andUnique' also catches the set-valued
        -- overload, which cannot occur in a BOOLEAN filter but costs nothing.
        | nameToText (TypeCheck.getName f) == "__AND__" -> either' (go e1) (go e2)
      App _ f [Var _ x, xs]
        | nameToText (TypeCheck.getName f) == "elem"
        , x `sameResolved` v -> Just xs
      _ -> Nothing

    either' :: Maybe a -> Maybe a -> Maybe a
    either' (Just r) _ = Just r
    either' Nothing  r = r

-- | What the machine says when an @EVERY@ has no roll to call.
rollCallRefusal :: Text
rollCallRefusal = Text.unwords
  [ "EVERY has nothing to draw its cast from. Running a quantified obligation"
  , "needs a list of the parties it ranges over, because a party type is"
  , "normally open: `Tenant HAS name IS A STRING` has infinitely many values."
  , "Name the list with IN, as `EVERY Tenant t IN tenants MUST ...`,"
  , "with `tenants` a LIST of the party type."
  , "(The older `EVERY Tenant t WHO elem t tenants` spelling is DEPRECATED"
  , "and still runs, but IN says the roll outright and is checked earlier.)"
  , "(EVERY-EACH-QUANTIFIER-SPEC sections 11.0.2 and 2.2.7.5 point 5;"
  , "doc/reference/regulative/EVERY.md.)"
  ]

-- | What the machine says when an INFERRED roll would have to know its own
-- answer. An @IN@ roll cannot get here: it is checked with the member out of
-- scope ('L4.TypeCheck.checkDeonton'), so the circular case is a check-time
-- error there. The filter genuinely does bind the member, so the same trick is
-- not available for the inferred form.
circularRollRefusal :: Text
circularRollRefusal = Text.unwords
  [ "EVERY's roll cannot mention the member it is drawing. The list after"
  , "`elem` is read once, before there is any member to speak of, so it may"
  , "not depend on one. Say the roll outright with IN -"
  , "`EVERY Tenant t IN tenants` - which also moves you off the DEPRECATED"
  , "`WHO elem` spelling that is the only way to reach this message. To"
  , "narrow the group by something about each member, put that in a WHO"
  , "condition, where the member IS in scope -"
  , "`EVERY Tenant t IN tenants WHO isAdult t`."
  ]

-- | Arm a quantified obligation: start the roll call.
--
-- The roll comes from the @IN@ clause when one is written (§11.0.2), and
-- otherwise from an @elem@ conjunct of the @WHO@ filter ('quantifierRoll',
-- §11.0). When BOTH are present the @IN@ clause wins and the @elem@ conjunct
-- keeps its ordinary job of narrowing: it is still evaluated per candidate,
-- like every other part of the filter, so the cast is the members of the @IN@
-- list that satisfy the whole filter, in the @IN@ list's order.
startRollCall :: Environment -> Deonton Resolved -> Reference -> Reference -> Machine Config
startRollCall env deonton time events =
  case deonton.subject of
    Party{} -> internalException $ RuntimeTypeError
      "a PARTY obligation reached the quantifier's roll call"
    Every _ cast var roll filt -> do
      -- P2b: arming is the join's own entry into its site.
      norm <- armJoinKey deonton
      let ctx = MkQuantCtx {deonton, var, cast, roll, filt, env, time, events, norm}
      case maybe (filt >>= quantifierRoll var) Just roll of
        Nothing -> userException (UserError rollCallRefusal)
        -- The roll is read BEFORE any member exists, so it cannot depend on
        -- one. An IN roll is rejected for that at CHECK time; an inferred one
        -- cannot be — @WHO elem t (peersOf t)@ type-checks, because the
        -- variable is in scope throughout the filter — and would otherwise
        -- reach the evaluator as an unbound name, i.e. as "please report this
        -- as a bug".
        Just rollExpr
          | any (sameResolved var) rollExpr -> userException (UserError circularRollRefusal)
          | otherwise -> do
              pushFrame (ContractFrame (QuantRoll QuantRollFrame {ctx, acc = []}))
              continueExpr env rollExpr

-- | Continue the roll call with the rest of the roll.
quantNext :: QuantRollFrame -> Reference -> Machine Config
quantNext frame rest = do
  pushFrame (ContractFrame (QuantRoll frame))
  continueRef rest

-- | The roll has been called; build the family. Which family depends on the
-- join line (spec §2.4, R-Q1):
--
--   * no join line at all — and so, the checker having refused a bare
--     continuation, no HENCE and no LEST: the plain distributive obligation
--     (§3.3), one per member, interleaved;
--   * @UPON EACH@ — the fork (§3.2): each member carries its own copy of the
--     continuation, with the member variable bound to itself;
--   * @ONCE ALL HAVE@ — the barrier (§3.1): the continuation belongs to the
--     JOIN, not to any member, and fires once.
assembleQuantified :: QuantCtx -> [CastMember] -> Machine Config
assembleQuantified ctx members =
  case ctx.deonton.join of
    Nothing                      -> registerCast ctx Distributive members >> runQuantifiedFold ctx members memberDue
    Just JoinUpon{}              -> registerCast ctx Fork members >> runQuantifiedFold ctx members memberDue
    Just (JoinOnce _ threshold@AllHave{} _)
      -- A barrier's HENCE and LEST belong to the JOIN, not to a member (spec
      -- §3.1 writes them @shared_h@ / @shared_l@), so there is no member for
      -- the variable to denote. The type checker binds it throughout the rule
      -- — right for a fork, where each member carries its own copy — so this
      -- is caught here rather than at check time, and named rather than
      -- crashed on.
      | any (mentionsVar ctx.var) (catMaybes [ctx.deonton.hence, ctx.deonton.lest])
      -> userException (UserError (sharedContinuationRefusal ctx.var))
      | otherwise -> registerCast ctx (Barrier threshold) members >> startBarrier ctx members memberDue
  where
    -- The act's own WITHIN bounds each performance; the join's bounds the
    -- whole (R-T2). When only the join carries one it has to bound the acts
    -- too, or no member would ever expire and the rule could never fail —
    -- and that holds for a FORK as much as for a barrier, which is why this
    -- reads 'joinDue' (either join) and not 'joinStateDue' (the ONCE line
    -- only). When BOTH are present the act's governs each member, and a
    -- BARRIER additionally checks the state deadline at the join
    -- ('Barrier3'); a fork has no join event to check, so there the act's
    -- deadline is the only one enforced — a phase-2 limit, on the doc page
    -- and in the spec.
    --
    -- A demoted join-line deadline keeps its join-line meaning: OF THE
    -- ARMING on it is the EVERY's arming ('memberObligation' binds it), not
    -- the arming of whatever obligation the EVERY is nested in.
    memberDue = case ctx.deonton.due of
      Just d  -> MemberDue d
      Nothing -> maybe NoMemberDue DemotedJoinDue (joinDue ctx)

-- | Where a member's deadline comes from ('assembleQuantified').
data MemberDue
  = NoMemberDue
  | MemberDue (Deadline Resolved)         -- ^ the act's own WITHIN
  | DemotedJoinDue (Deadline Resolved)    -- ^ the join line's WITHIN, bounding each act because the act has none

-- | The deadline a member obligation is built with.
--
-- A demoted join-line @WITHIN@ bounds the whole from the EVERY's arming
-- (R-T2), whatever the act line says; so when the act has an @AFTER@
-- (§5.1.2, 2026-09-16), the bare join-line duration is handed to the member
-- anchored @OF THE ARMING@ explicitly — which 'memberEnv' binds to the
-- EVERY's arming — rather than as a bare @WITHIN@, which beside an @AFTER@
-- would count from the instant the member's window opened (re-anchor,
-- §5.1.2.2). Without an @AFTER@ the two readings coincide and the deadline
-- is handed over as written, so no residual of an older program prints
-- differently.
memberDueExpr :: Maybe (Opening Resolved) -> MemberDue -> Maybe (Deadline Resolved)
memberDueExpr mopen = \ case
  NoMemberDue      -> Nothing
  MemberDue d      -> Just d
  DemotedJoinDue (MkDeadline a d Nothing)
    | isJust mopen -> Just (MkDeadline a d (Just (AnchorArming emptyAnno)))
  DemotedJoinDue d -> Just d

-- | A member's environment: the EVERY's, with the member variable bound —
-- and, when the member's deadline is the join line's demoted one, with THE
-- ARMING bound to the EVERY's arming, which is what that anchor means on a
-- join line whatever the EVERY is nested in.
memberEnv :: QuantCtx -> MemberDue -> Reference -> Environment
memberEnv ctx mdue mref =
  demoted (Map.insert (getUnique ctx.var) mref ctx.env)
  where
    demoted = case mdue of
      DemotedJoinDue _ -> Map.insert lifecycleArmingUnique ctx.time
      _                -> id

-- | Does this expression name the quantifier's member variable anywhere?
mentionsVar :: Resolved -> Expr Resolved -> Bool
mentionsVar v = any (sameResolved v)

-- | What the machine says when a barrier's shared continuation names a member.
sharedContinuationRefusal :: Resolved -> Text
sharedContinuationRefusal v = Text.unwords
  [ "A barrier's HENCE and LEST belong to the join, not to any one member, so"
  , "they cannot name"
  , "`" <> nameToText (TypeCheck.getName v) <> "`:"
  , "`ONCE ALL HAVE` fires once, after everybody has acted, and there is no"
  , "member for the name to stand for. Either write the continuation without"
  , "it, or use the fork, `UPON EACH`, which fires once per member and does"
  , "bind the member inside it."
  ]

-- | The @WITHIN@ on EITHER join line, if there is one.
joinDue :: QuantCtx -> Maybe (Deadline Resolved)
joinDue ctx = case ctx.deonton.join of
  Just (JoinOnce _ _ d) -> d
  Just (JoinUpon _ _ d) -> d
  Nothing               -> Nothing

-- | The @WITHIN@ on a @ONCE@ line specifically: the deadline on the joined
-- STATE (R-T2), which only the barrier has an event to check against.
joinStateDue :: QuantCtx -> Maybe (Deadline Resolved)
joinStateDue ctx = case ctx.deonton.join of
  Just (JoinOnce _ _ d) -> d
  _                     -> Nothing

-- | One member's obligation: the member variable bound to it, the member
-- itself as the obligation's party (already forced by the roll call, so
-- 'Contract6' has nothing to evaluate).
memberObligation :: QuantCtx -> RExpr -> Maybe RExpr -> MemberDue -> CastMember -> WHNF
memberObligation ctx hence lest mdue (mref, mval) =
  ValObligation
    (memberEnv ctx mdue mref)
    (Right mval) ctx.deonton.action (Left ctx.deonton.opens) (Left (memberDueExpr ctx.deonton.opens mdue)) hence lest

-- | @A AND B AND C@, right-nested, as the source-level 'RAnd' would build it.
randFoldWHNF :: Environment -> WHNF -> [WHNF] -> WHNF
randFoldWHNF _   o []       = o
randFoldWHNF env o (x : xs) = ValROp env ValRAnd (Right o) (Right (randFoldWHNF env x xs))

-- | The distributive fold: the members run in parallel over the same event
-- stream, which is what @RAND@ already means (spec §3.3, §3.2). Under a fork
-- each member carries the continuation, with the member variable bound.
--
-- An EMPTY cast is fulfilled: nobody is bound, so nothing is owed. (§10.3
-- would have this warn; a warning is not built.)
runQuantifiedFold :: QuantCtx -> [CastMember] -> MemberDue -> Machine Config
runQuantifiedFold ctx members mdue =
  case map (memberObligation ctx (fromMaybe fulfilExpr ctx.deonton.hence) ctx.deonton.lest mdue) members of
    []       -> continueBackward ValFulfilled
    (o : os) -> do
      pushFrame (App1 [ctx.time, ctx.events] Nothing)
      continueBackward (randFoldWHNF ctx.env o os)

-- | One member of a BARRIER. One difference from 'memberObligation': both
-- continuation slots hold SENTINELS rather than the drafter's expressions —
-- the checkpoint in the HENCE, and (when the barrier has a LEST) the
-- failpoint in the LEST. Each reports back to the barrier, carrying the
-- anchor and the residual stream the machine computed. See the 'Barrier1'
-- NOTE for why the real LEST is never handed to a member.
--
-- Each sentinel is a constructor minted with 'defSentinel', which is what
-- lets the member's hand-off recognise it and pass it the hand-off's stream
-- position and the member's absolute deadline as further arguments (see
-- 'continueWithFollowup') — how the barrier learns where in the stream a
-- member failed, and the deadline it met or missed, without a second pass.
barrierMember
  :: QuantCtx -> Resolved -> Reference -> Maybe (Resolved, Reference)
  -> MemberDue -> CastMember -> WHNF
barrierMember ctx cp cpRef mfail mdue (mref, mval) =
  ValObligation env' (Right mval) ctx.deonton.action (Left ctx.deonton.opens) (Left (memberDueExpr ctx.deonton.opens mdue))
    (Var emptyAnno cp)
    (fmap (\ (fp, _) -> Var emptyAnno fp) mfail)
  where
    env' =
      Map.insert (getUnique cp) cpRef
      $ maybe id (\ (fp, fpRef) -> Map.insert (getUnique fp) fpRef) mfail
      $ memberEnv ctx mdue mref

-- | The arguments a barrier sentinel reports: the anchor and the residual
-- stream every continuation receives, then the stream position of the event
-- the hand-off happened at, then the member's absolute deadline when it had
-- one. See 'barrierMember' and 'continueWithFollowup'.
--
-- For a MUST\/DO\/MAY member's failure the first and the fourth are the SAME
-- reference (§5.2: the LEST's clock is the missed deadline, and 'Contract5'
-- hands one 'deadlineR' as both). That is deliberate, not a duplicate to
-- fold away: the fourth argument is what OF THE DEADLINE reads and exists
-- for the checkpoint and the SHANT failure too, where it differs from the
-- first.
sentinelArgs :: [Reference] -> Maybe (Maybe Reference, Reference, Reference, Reference)
sentinelArgs = \ case
  [tRef, evRef, pRef]       -> Just (Nothing, pRef, tRef, evRef)
  [tRef, evRef, pRef, dRef] -> Just (Just dRef, pRef, tRef, evRef)
  _                         -> Nothing

-- | Mint a barrier sentinel: a fresh constructor whose unique is of sort
-- @s@, used nowhere else, so 'isSentinel' can tell it from every other name.
defSentinel :: Name -> Machine Resolved
defSentinel n = do
  u <- newUnique
  pure (Def u { sort = 's' } n)

-- | Is this a barrier sentinel ('defSentinel')?
isSentinel :: Resolved -> Bool
isSentinel r = (getUnique r).sort == 's'

-- | The names of the barrier's two sentinels, as a member's residual prints
-- them (@HENCE `the join` LEST `the join fails`@). They are minted fresh per
-- barrier ('startBarrier'), so the NAME is the only thing a reader of a
-- residual can recognise them by; "L4.Lts.Marking" does exactly that.
joinCheckpointName, joinFailpointName :: Text
joinCheckpointName = "the join"
joinFailpointName  = "the join fails"

-- | Arm the barrier. The checkpoint is a FRESH constructor, minted here and
-- bound into each member's environment: applied to the @[time, events]@ that
-- every continuation receives, it yields @ValConstructor cp [time, events]@,
-- which reports both that the member completed and when.
--
-- An empty cast fires the HENCE at once: "all zero of them have acted" is
-- vacuously true.
startBarrier :: QuantCtx -> [CastMember] -> MemberDue -> Machine Config
startBarrier ctx members mdue = do
  -- Both names are user-visible: a member that has not yet acted when the
  -- event stream runs out is printed as a residual obligation carrying these
  -- sentinels in its HENCE and LEST, so they have to read as English there.
  cp <- defSentinel (MkName emptyAnno (NormalName joinCheckpointName))
  cpRef <- allocateValue (ValUnappliedConstructor cp)
  mfail <- for ctx.deonton.lest \ _ -> do
    fp <- defSentinel (MkName emptyAnno (NormalName joinFailpointName))
    fpRef <- allocateValue (ValUnappliedConstructor fp)
    pure (fp, fpRef)
  case map (barrierMember ctx cp cpRef mfail mdue) members of
    -- an empty cast is joined at its arming: the join fires there, through
    -- the ONCE line's WITHIN when it has one ('BarrierEmpty', 'barrierJoined')
    []       -> do
      pushFrame (ContractFrame (BarrierEmpty BarrierEmptyFrame {ctx}))
      continueRef ctx.time
    (o : os) -> barrierRun BarrierStepFrame
      { ctx, checkpoint = cp, failpoint = fmap fst mfail
      , current = o, queue = os, tLast = Nothing, dueLatest = Nothing, pending = []
      , failures = [], lapsed = False }

-- | Apply the barrier's current member to the (whole) event stream.
barrierRun :: BarrierStepFrame -> Machine Config
barrierRun step = do
  pushFrame (ContractFrame (Barrier1 step))
  pushFrame (App1 [step.ctx.time, step.ctx.events] Nothing)
  continueBackward step.current

-- | Next member, or the verdict.
barrierNext :: BarrierStepFrame -> Machine Config
barrierNext step = case step.queue of
  []       -> barrierFinish step
  (o : os) -> barrierRun step {current = o, queue = os}

-- | Every member has been run: the verdict.
--
-- Failures come first, because a member that definitively did not complete
-- settles the barrier whatever the others did — as it did when the first
-- failure ended the scan, only now every member has been run, so ALL of
-- them are named and the earliest of them is the anchor (R-T3, spec §6.1;
-- ordering by R-Q5's failure time, §5.2). Running every member has one
-- consequence the first-failure scan did not have: a member later on the
-- roll is evaluated even after an earlier one has failed, so an error in
-- its @WITHIN@ (or anywhere its run reaches) is now the barrier's verdict
-- where it used to be masked by the earlier failure.
--
--   * with a @LEST@, each failure arrived through the failpoint sentinel
--     ('BarrierFailedAt'). The @LEST@ runs ONCE, with the anchor, the
--     residual stream AND the missed deadline (R-Q7B's @THE DEADLINE@) of
--     the EARLIEST failure. The ordering key is the sentinel's own anchor,
--     forced ('failAt' is the same reference the @LEST@ is handed), and
--     since 2026-09-16 that anchor IS R-Q5's failure time (§5.2): for
--     @MUST@\/@DO@\/@MAY@ the member's missed deadline, for @SHANT@ its
--     violating event's stamp — so the primary key orders by the failure
--     time directly, for every modal. For @MUST@\/@DO@\/@MAY@ a tie on it
--     is two members with one deadline, which the same event reveals, so
--     the later keys tie too and roll order names the same anchor, residual
--     and deadline either way. For @SHANT@ the window's end does not order
--     the failures at all, and two members violated at one stamp are two
--     DIFFERENT events with two different residuals — a tie there is NOT
--     the same event. So a tie on the stamp is broken first by the stream
--     position ('failPos': the failure the stream reached first, whose
--     residual still holds whatever followed it; measured before this key,
--     a refund between two same-stamp violations was dropped from the
--     chosen residual and the verdict flipped, spec §11.0.1 round 1), which
--     only the same event ties; then by the deadline ('failDue', added when
--     the anchor was still the revealing stamp and one event could reveal
--     two deadlines — measured then: `LIST alice, bob, carol` reported 19
--     and the reversed roll 10 for the same events; now redundant for every
--     modal, kept rather than half-removed), and only a tie on all three
--     keeps the first in roll order.
--   * with no @LEST@, each failure is the member's own breach
--     ('BarrierBreached'). The verdict is ONE breach: anchored at the
--     earliest failure — the smallest missed deadline for @MUST@\/@DO@, the
--     violating event's stamp for @SHANT@, which is R-Q5's failure time and
--     what the anchoring 'MissedDeadline' carries as its deadline — and
--     naming every failed member, in roll order, each with its own action
--     and deadline (no dedup: RULED 2026-09-15).
--
-- A lapsed @MAY@ (no @LEST@) is a non-completer that breached nothing: the
-- join cannot fire and the verdict is @FULFILLED@, as before.
barrierFinish :: BarrierStepFrame -> Machine Config
barrierFinish step = case reverse step.failures of
  (f : fs) -> case earliestFailure (f :| fs) of
    -- the LEST is handed the anchor, the residual stream AND the missed
    -- deadline of the member whose failure anchors it (R-Q7B's THE
    -- DEADLINE under a barrier's LEST is the earliest failer's, by the
    -- same choice)
    (_, BarrierFailedAt {failTimeRef, failEvsRef, failDueRef}) -> barrierFail step.ctx failDueRef failTimeRef failEvsRef
    (i, BarrierBreached {failReason}) ->
      -- Every failed member's own failure, in roll order, anchored at the
      -- earliest's: the members before it on the roll are prepended, those
      -- after it appended, each with its own action and deadline. A member
      -- listed twice on the roll fails twice (no dedup, RULED 2026-09-15).
      let (earlier, later) = splitAt i (f : fs)
          own = breachBlame failReason
          blame = own
            { before = concatMap entries earlier ++ own.before
            , after  = own.after ++ concatMap entries (drop 1 later) }
          verdict = rebase blame failReason
      in do
        -- P2b: the barrier's own step, logged once the verdict is decided
        -- (every member has run). The clock is the anchoring failure's
        -- revealing stamp — in hand for a missed deadline, absent only when
        -- the anchoring member's own breach was an explicit BREACH.
        let clock = case verdict of
              DeadlineMissed _ _ stamp _ -> Just stamp
              ExplicitBreach {}          -> Nothing
        tellDeonticStep $ plainStep clock Nothing NoEvent step.ctx.norm (JoinFailed ToBreach)
        continueBackward (ValBreached verdict)
  []
    | step.lapsed -> do
        -- P2b: a MAY member lapsed under a barrier with no LEST; the join
        -- can never fire. 'ValFulfilled' carries no time, so no clock.
        tellDeonticStep $ plainStep Nothing Nothing NoEvent step.ctx.norm JoinStalled
        continueBackward ValFulfilled
    | otherwise -> case reverse step.pending of
      -- Some members are still waiting for their event. The barrier has neither
      -- fired nor failed; what remains to be done is those obligations, as the
      -- scan left them — deadlines already decremented by the time that passed.
      -- Their continuation slots still hold the sentinels, which print as
      -- @`the join`@ and @`the join fails`@. Phase-2 limit: the residual does NOT
      -- carry the JOIN LINE, so re-applying it to more events would run the
      -- members and not the join.
      (o : os) -> continueBackward (randFoldWHNF step.ctx.env o os)
      [] -> case step.tLast of
        -- every member ran, none is pending, none failed and no MAY lapsed,
        -- so every one of them passed through 'Barrier2', which records a
        -- completion; an empty cast never reaches this frame ('startBarrier')
        Nothing       -> internalException $ RuntimeTypeError
          "the barrier finished with every member complete but no completion recorded"
        Just (t, evs) -> barrierJoined step.ctx t evs step.dueLatest
  where
    entries = \ case
      BarrierBreached {failReason} -> toList (blameList (breachBlame failReason))
      BarrierFailedAt {}           -> []

-- | The earliest of a barrier's failures, with its position in the order
-- they were recorded (roll order): a later one replaces the best so far only
-- when both carry a time and the later one's is strictly earlier — or the
-- times tie and the later one's stream position is strictly earlier — or
-- both tie and both carry a deadline and the later one's deadline is
-- strictly earlier — so a tie on all three keeps the first in roll order,
-- and an untimed failure ('ExplicitBreach', which no barrier member produces
-- today) neither wins nor loses. The second and third keys only ever apply
-- to 'BarrierFailedAt' (a 'BarrierBreached' orders by its deadline already,
-- and carries no position: with no @LEST@ there is no residual to hand on,
-- so a same-stamp tie there falls to roll order, and names every failure
-- regardless).
earliestFailure :: NonEmpty BarrierFailure -> (Int, BarrierFailure)
earliestFailure (f :| fs) = foldl' pick (0, f) (zip [1 ..] fs)
  where
    pick best@(_, b) cand@(_, c) = case (failureTime b, failureTime c) of
      (Just tb, Just tc)
        | tc < tb -> cand
        | tc == tb, Just pb <- failurePos b, Just pc <- failurePos c, pc < pb -> cand
        | tc == tb, failurePos b == failurePos c
        , Just db <- failureDue b, Just dc <- failureDue c, dc < db -> cand
      _ -> best
    failurePos = \ case
      BarrierFailedAt {failPos} -> Just failPos
      BarrierBreached {}        -> Nothing
    failureDue = \ case
      BarrierFailedAt {failDue} -> failDue
      BarrierBreached {}        -> Nothing
    failureTime = \ case
      BarrierFailedAt {failAt} -> Just failAt
      BarrierBreached {failReason} -> case failReason of
        DeadlineMissed _ _ _ b -> case b.anchor of
          MissedDeadline _ _ deadline -> Just deadline
          DeclaredBreach _ _          -> Nothing
        ExplicitBreach _ -> Nothing

-- | The join has fired at @t@ (the last completion, or the arming for an
-- empty cast), with the stream that followed it: run the HENCE through the
-- @ONCE@ line's @WITHIN@ when it has one ('Barrier3'), else at once.
--
-- What THE DEADLINE names in that HENCE when the @ONCE@ line has no
-- @WITHIN@: the latest of the members' act deadlines — the instant by which
-- all performance fell due (spec §5.1.1: "the cure period runs from the date
-- performance fell due"), which no roll order can change — and nothing for
-- an empty cast, where nobody had one ('lifecycleRefusal' names that case).
barrierJoined :: QuantCtx -> Rational -> Reference -> Maybe Rational -> Machine Config
barrierJoined ctx t evs dueLatest = case joinStateDue ctx of
  Nothing -> do
    tRef <- allocateValue (ValNumber t)
    dRef <- traverse (allocateValue . ValNumber) dueLatest
    fireBarrierHence ctx dRef tRef evs
  Just (MkDeadline _ duration _) -> do
    pushFrame (ContractFrame
      (Barrier3 BarrierStateDueFrame {ctx, joinTime = t, joinEvents = evs}))
    continueExpr ctx.env duration
  Just MkBefore{} -> beforeOnJoinLine

-- | A @BEFORE@ on a join line is refused by the checker
-- ('L4.TypeCheck.checkDeadline', @BeforeOnJoinLine@); the machine never
-- lowers one there. Named, so that a checker regression shows as this and
-- not as a type error on a DATE.
beforeOnJoinLine :: Machine Config
beforeOnJoinLine = internalException $ RuntimeTypeError
  "BEFORE on a join line is refused by the type checker and is not lowered here; please report this as a bug"

-- | The join fires. The HENCE is anchored at the last completion and sees the
-- stream that followed it (R-Q7, §5.1: unanchored, a HENCE counts from the
-- join's firing).
--
-- It runs with NO acting party: the join fired, not a person, so a RECORD
-- inside it goes to the anonymous ledger rather than to whichever member
-- happened to act last. Set explicitly, so the answer cannot depend on the
-- order events arrived in.
--
-- What the HENCE may anchor to (R-Q7B): THE JOIN is this firing; THE
-- DEADLINE is the @ONCE@ line's when it has one, else the latest of the
-- members' act deadlines ('barrierJoined' decides which); THE ARMING is the
-- EVERY's.
fireBarrierHence :: QuantCtx -> Maybe Reference -> Reference -> Reference -> Machine Config
fireBarrierHence ctx deadlineRef timeRef eventsRef = do
  -- P2b: the join's own step. Peeked, not forced: for an empty cast the
  -- anchor is the arming time, which may still be a thunk.
  whenDeonticLog \ l -> do
    clock <- peekClock timeRef
    logStep l (plainStep clock Nothing NoEvent ctx.norm JoinReleased)
  mOriginal <- getCurrentParty
  putCurrentParty Nothing
  pushFrame (RestoreCurrentParty mOriginal)
  pushFrame (App1 [timeRef, eventsRef] Nothing)
  let lifecycle = MkLifecycle {join = Just timeRef, deadline = deadlineRef, armed = ctx.time}
  pushFrame (ContractFrame (Handoff lifecycle))
  continueExpr (bindLifecycle lifecycle ctx.env) (fromMaybe fulfilExpr ctx.deonton.hence)

-- | Some member did not complete, so the barrier cannot: run the barrier's
-- LEST, once, with the anchor and the residual stream the EARLIEST failing
-- member's own expiry produced ('barrierFinish'). Those arrive through the
-- 'failpoint' sentinel, which is why no member is applied to the event
-- stream twice.
--
-- The anchor is therefore the machine's usual one for a single-party
-- obligation, by construction: the member IS a single obligation, and its
-- 'Contract5' (a missed MUST\/DO\/MAY: the deadline, §5.2 since 2026-09-16)
-- or 'Contract10' (a SHANT violation: the event's stamp) chose the clock
-- before the sentinel ever saw it. There is one anchor mechanism in the
-- language and this function adds nothing to it — which is why it did not
-- change when the single-party clock did.
--
-- The LEST is the drafter's expression, run as written: a bare @LEST BREACH@
-- names nobody, and @LEST BREACH BY LIST a, b@ names whom the drafter named.
-- The machine does not inject the failed members into it — a quantified
-- @BY@ that would name them from inside a barrier's LEST is not ruled (spec
-- §6.1, BUILT 2026-09-15). Who failed is named by the verdict of a barrier
-- WITHOUT a LEST, which is one 'DeadlineMissed' over every non-completer.
--
-- What the LEST may anchor to (R-Q7B): THE DEADLINE is the failing member's
-- own — the act-layer deadline that was missed (R-Q5) — carried here by the
-- sentinel of the SAME member whose failure anchors the LEST (the earliest,
-- 'barrierFinish'); THE ARMING is the EVERY's; there is no THE JOIN.
--
-- When the barrier has NO LEST this is unreachable: no sentinel is minted.
barrierFail :: QuantCtx -> Maybe Reference -> Reference -> Reference -> Machine Config
barrierFail ctx deadlineRef timeRef eventsRef = case ctx.deonton.lest of
  Nothing -> internalException $ RuntimeTypeError
    "the barrier's LEST sentinel fired for a barrier that has no LEST"
  Just lestExpr -> do
    -- P2b: the failing member's own expiry step precedes this one.
    whenDeonticLog \ l -> do
      clock <- peekClock timeRef
      logStep l (plainStep clock Nothing NoEvent ctx.norm (JoinFailed ToLest))
    mOriginal <- getCurrentParty
    putCurrentParty Nothing
    pushFrame (RestoreCurrentParty mOriginal)
    pushFrame (App1 [timeRef, eventsRef] Nothing)
    let lifecycle = MkLifecycle {join = Nothing, deadline = deadlineRef, armed = ctx.time}
    pushFrame (ContractFrame (Handoff lifecycle))
    continueExpr (bindLifecycle lifecycle ctx.env) lestExpr

-- | Everyone acted, but the last of them acted after the @ONCE … WITHIN@
-- deadline, which bounds the whole (R-T2).
--
-- The LEST is anchored at the state deadline, which is also what THE
-- DEADLINE names in it (R-Q5's state layer, R-Q7B), and it is handed the
-- events AFTER that deadline — the same shape the act layer gives its LEST
-- (from the revealing event on), found here by walking the barrier's stream
-- from its arming to the first event stamped past the deadline
-- ('BarrierTrim'). Until 2026-09-16 the LEST was handed the WHOLE stream
-- from the arming, so a reparation performed before the deadline was
-- missed, even before anyone had acted, discharged it (spec §11.0.1,
-- "Stacking B on C" round 1, R1-5); the join's own residual — what followed
-- the LAST completion — is wrong the other way, since that completion is
-- what landed after the deadline.
--
-- P2b logs the 'JoinExpired' step here, in each arm beside the routing it
-- records, so the log cannot classify the routing differently from the
-- machine. @joinTime@ is the last completion, the step's clock.
barrierStateMissed :: QuantCtx -> Rational -> Rational -> Machine Config
barrierStateMissed ctx joinTime deadline = case ctx.deonton.lest of
  Just lestExpr -> do
    tellDeonticStep $ plainStep (Just joinTime) Nothing NoEvent ctx.norm (JoinExpired ToLest deadline)
    tRef <- allocateValue (ValNumber deadline)
    pushFrame (ContractFrame (BarrierTrim BarrierTrimFrame
      {ctx, lestExpr, cutoff = deadline, cutoffRef = tRef, cell = ctx.events}))
    continueRef ctx.events
  Nothing -> do
    tellDeonticStep $ plainStep (Just joinTime) Nothing NoEvent ctx.norm (JoinExpired ToBreach deadline)
    reason <- allocateValue (ValString
      "every member acted, but the last of them acted after the ONCE line's WITHIN deadline")
    continueBackward (ValBreached (ExplicitBreach (singleBlame (DeclaredBreach Nothing (Just reason)))))

-- | The state-layer LEST, applied to the trimmed stream ('BarrierTrim'):
-- @cellRef@ is the first cell of the barrier's stream whose event is
-- stamped after the state deadline (or the empty list).
barrierStateLest :: QuantCtx -> RExpr -> Reference -> Reference -> Machine Config
barrierStateLest ctx lestExpr tRef cellRef = do
  mOriginal <- getCurrentParty
  putCurrentParty Nothing
  pushFrame (RestoreCurrentParty mOriginal)
  pushFrame (App1 [tRef, cellRef] Nothing)
  let lifecycle = MkLifecycle {join = Nothing, deadline = Just tRef, armed = ctx.time}
  pushFrame (ContractFrame (Handoff lifecycle))
  continueExpr (bindLifecycle lifecycle ctx.env) lestExpr

-- * The lifecycle bindings an anchored WITHIN reads
--
-- $lifecycle
--
-- EVERY-EACH-QUANTIFIER-SPEC §5.1.1 (R-Q7B, built 2026-09-15). @WITHIN d OF
-- THE JOIN@, @OF THE DEADLINE@ and @OF THE ARMING@ name positions in the
-- life of the ENCLOSING obligation — the one whose HENCE or LEST the
-- anchored obligation is the continuation of. The machine already knows all
-- three at the moment it hands off; what was missing was a way for the
-- continuation to read them. It reads them from its ENVIRONMENT: the
-- hand-off ('continueWithFollowup', 'fireBarrierHence', 'barrierFail',
-- 'barrierStateMissed') binds them under three fixed uniques that live in
-- no name table, so no program can spell, shadow or capture them. Every
-- hand-off replaces all three — a position it does not have is DELETED, not
-- left to an outer obligation's binding — and it rebinds them into the
-- continuation's VALUE as well as into the expression's environment
-- ('Handoff', 'rebindLifecycle'), so the obligation an anchor names is the
-- one the continuation is attached to when it runs: the nearest enclosing
-- one, dynamically. For a continuation written inline that is exactly what
-- the type checker assumes ('L4.TypeCheck.checkAnchor'); for one that
-- arrives as a value the checker sees only where it was written, which is
-- why it refuses THE JOIN \/ THE DEADLINE at the top level and in a @WHERE@,
-- and why a value carrying THE JOIN that is later attached under a LEST is
-- refused here rather than there ('lifecycleRefusal').

-- | The three uniques. Sort @l@ is used nowhere else (@b@ builtins, @c@
-- checker, @d@ discharge, @e@ evaluator, @s@ the barrier's sentinels).
lifecycleJoinUnique, lifecycleDeadlineUnique, lifecycleArmingUnique :: Unique
lifecycleJoinUnique     = MkUnique 'l' 1 lifecycleUri
lifecycleDeadlineUnique = MkUnique 'l' 2 lifecycleUri
lifecycleArmingUnique   = MkUnique 'l' 3 lifecycleUri

lifecycleUri :: NormalizedUri
lifecycleUri = toNormalizedUri (Uri "jl4:lifecycle")

-- | Bind an obligation's lifecycle into its continuation's environment. A
-- position this hand-off does not have is deleted: otherwise an enclosing
-- obligation's binding would show through, and @OF THE DEADLINE@ in the
-- HENCE of a barrier over nobody, nested under an obligation with a WITHIN,
-- would silently read THAT deadline (measured before this was a delete:
-- 10 + 5 = 15, exit 0).
bindLifecycle :: Lifecycle -> Environment -> Environment
bindLifecycle lc =
  Map.insert lifecycleArmingUnique lc.armed
  . maybe (Map.delete lifecycleDeadlineUnique) (Map.insert lifecycleDeadlineUnique) lc.deadline
  . maybe (Map.delete lifecycleJoinUnique) (Map.insert lifecycleJoinUnique) lc.join

-- | Rebind a hand-off's lifecycle into the continuation VALUE it is about to
-- apply, so the anchors inside name this hand-off's obligation whatever the
-- value's closure captured. Reaches every obligation-shaped value: a single
-- obligation, an armed-but-not-run EVERY, and a compound. For a compound
-- only the compound's OWN environment is rebound here; its operands are
-- handed off one at a time when the compound is applied ('operandHandoff'),
-- because an operand written as an expression is not a value yet — it is
-- evaluated later, in 'App1' and 'RBinOp1', and may then turn out to be a
-- continuation built somewhere else (a @GIVEN k IS A DEONTIC@ parameter, a
-- @WHERE@ local). Rebinding the two operand expressions' shared environment
-- here does nothing for such a value, which carries its own (measured
-- before 'operandHandoff' existed: @HENCE (k RAND …)@ with @k@ a parameter
-- anchored @OF THE JOIN@ read the join of the obligation @k@ was WRITTEN
-- under — 3 + 5 = 8 instead of 50 + 5 = 55, exit 0). Anything else (a
-- sentinel, FULFILLED, a breach) has no anchors and passes through.
rebindLifecycle :: Lifecycle -> WHNF -> WHNF
rebindLifecycle lc = \ case
  ValObligation env party act opens due followup lest ->
    ValObligation (bindLifecycle lc env) party act opens due followup lest
  ValQuantified env deonton -> ValQuantified (bindLifecycle lc env) deonton
  ValROp env op r1 r2       -> ValROp (bindLifecycle lc env) op r1 r2
  v                         -> v

-- | The lifecycle a compound's environment carries, read back under the
-- three uniques. Exact, because 'bindLifecycle' deletes the positions a
-- hand-off does not have; 'Nothing' when no obligation has handed off to
-- this environment at all (the top level).
lifecycleOf :: Environment -> Maybe Lifecycle
lifecycleOf env = do
  armed <- Map.lookup lifecycleArmingUnique env
  pure MkLifecycle
    { join     = Map.lookup lifecycleJoinUnique env
    , deadline = Map.lookup lifecycleDeadlineUnique env
    , armed
    }

-- | Hand an operand of a compound off before it is evaluated and applied:
-- push a 'Handoff' carrying the lifecycle the compound's environment holds,
-- so the operand's VALUE is rebound the way a HENCE's or LEST's value is.
-- Only an operand still written as an EXPRESSION is handed off. One already
-- reduced to a value was built by the machine in this compound's own
-- context — a fork's member ('randFoldWHNF', whose environment binds THE
-- ARMING to the EVERY's own arming for a demoted join-line deadline and
-- must keep it), or this compound's residual ('RBinOp2') — and carries the
-- bindings it needs. At the top level there is no lifecycle and nothing is
-- pushed: the operand keeps whatever its closure captured, as before.
operandHandoff :: Environment -> MaybeEvaluated -> Machine ()
operandHandoff env = \ case
  Left _  -> for_ (lifecycleOf env) (pushFrame . ContractFrame . Handoff)
  Right _ -> pure ()

-- | Resolve a lifecycle anchor: the binding, or the fallback (THE ARMING with
-- no enclosing obligation is the obligation's own arming), or — for an
-- anchor the checker should have refused — a named refusal rather than a
-- scope error.
lifecycleRef :: Environment -> Anchor Resolved -> Unique -> Maybe Reference -> Machine Reference
lifecycleRef env a u fallback =
  case Map.lookup u env of
    Just r  -> pure r
    Nothing -> maybe (userException (UserError (lifecycleRefusal a))) pure fallback

-- | What the machine says when an anchor names a position that does not
-- exist here. The checker refuses what it can see ('L4.TypeCheck.checkAnchor');
-- this is the run-time's answer for the cases only a run can reveal, each
-- named: a barrier over an EMPTY cast (nobody had a deadline, and the ONCE
-- line names none), and a continuation that arrived as a VALUE and is
-- attached where the position does not exist — under a LEST for THE JOIN,
-- under an obligation with no WITHIN for THE DEADLINE, or at the top level.
-- The anchor may sit on either edge (a WITHIN, or since 2026-09-16 an
-- AFTER); the wording names the anchor, which is what was refused.
lifecycleRefusal :: Anchor Resolved -> Text
lifecycleRefusal a = Text.unwords
  [ "WITHIN … OF " <> Text.strip (prettyLayout a) <> " names a position in the life of the"
  , "obligation this one is the continuation of, and here that position does"
  , "not exist. One of: this is the HENCE of a barrier whose cast was EMPTY,"
  , "so nobody had a deadline to meet and the ONCE line names none (THE"
  , "DEADLINE); this obligation was passed as a value and attached under a"
  , "LEST, whose join never fired (THE JOIN), or under an obligation with no"
  , "WITHIN (THE DEADLINE); or it is running with no enclosing obligation at"
  , "all. Anchor it to THE ARMING or to an instant, give the enclosing"
  , "obligation the WITHIN, or guard an EVERY that may range over nobody."
  ]

-- | An anchor's instant on the trace's clock (R-Q7C): a NUMBER as it is, a
-- DATE by its serial — the same arithmetic as @DATE_SERIAL@, not a call
-- through it. This is the ONE place the lowering is defined: 'Barrier4' (a
-- join line's anchor) applies it directly, the act line's edges apply it
-- through 'lowerInstant' (which adds the floating-clock refusal, R-X5), and
-- "L4.Lts.WhatIf" reads an unforced anchored deadline through it rather
-- than re-deriving it (LTS-VISUALISER §2.4).
anchorInstant :: WHNF -> Either Text Rational
anchorInstant = \ case
  ValNumber t -> Right t
  ValDate d   -> Right (fromIntegral (dayNumberFromDay d))
  v -> Left ("expected a NUMBER or a DATE as the anchor of a WITHIN but got: " <> prettyLayout v)

-- | A join-line anchor the checker refuses ('OnJoinLine'), met at run time.
unreachableAnchor :: Anchor Resolved -> Machine Config
unreachableAnchor a = userException (UserError (lifecycleRefusal a))

-- | STATE-AS-LEDGER: render a forced party WHNF to the 'Text' key that names its
-- own ledger. A 'ValString' is its own key; anything else falls back to its
-- pretty layout. This is the SINGLE keying function used both by a RECORD write
-- (via 'continueWithFollowup' / 'currentParty') and a cross-party RECALL read
-- (via 'ReadCell2'), so read-key ≡ write-key by construction.
partyKeyWHNF :: WHNF -> Text
partyKeyWHNF = \ case
  ValString t -> t
  v           -> prettyLayout v

-- | The same breach — same kind, same revealing event if any — carrying this
-- blame instead (R-T3, spec §6.1). The anchor of the blame must be of the
-- breach's own kind; every caller builds it so.
rebase :: Blame a -> ReasonForBreach a -> ReasonForBreach a
rebase blame = \ case
  DeadlineMissed ev'p ev'a stamp _ -> DeadlineMissed ev'p ev'a stamp blame
  ExplicitBreach _                 -> ExplicitBreach blame

-- | What the machine says when @BREACH BY@ is given a list with nobody in it.
emptyBreachByRefusal :: Text -> Text
emptyBreachByRefusal clause = Text.unwords
  [ "BREACH BY names an empty list, at " <> clause <> "."
  , "A breach blames at least one party: give BY a party, or a LIST with"
  , "someone in it, or leave BY out to blame nobody."
  , "(EVERY-EACH-QUANTIFIER-SPEC section 6.1, R-T3.)"
  ]

-- | STATE-AS-LEDGER M1: perform a RECORD/COMMIT/ATTEST write.
--
-- The cell has already evaluated to a 'WHNF' that must be a 'ValString'; we
-- lower it to a single-segment 'Path' (typed nested schemas are deferred).
-- We append an 'Assign' event to the ledger (D2 / Rung 3 — an APPEND, not a
-- store) and return the written value so it can chain in a HENCE continuation.
--
-- M4: own ('RECORD') writes route to the acting party's own ledger, official
-- ('COMMIT'/'ATTEST') writes route to the shared official record. The acting
-- party is read from 'getCurrentParty' (set by 'continueWithFollowup' around the
-- HENCE/LEST body) and recorded in the provenance @party@. A top-level
-- @#EVAL RECORD@ has no enclosing party, so @party@ is "" and it routes to the
-- anonymous own ledger.
--
-- M5: 'runRecord' fires the write EXACTLY ONCE per forward-eval of the 'Record'
-- node — it is reached precisely when the 'Record2' frame is popped (once). It
-- then branches on the optional HENCE continuation @mHence@:
--
--   * 'Nothing' (M1, expression position): 'continueBackward' the written value.
--   * @Just hence@ (M5, deontic step): 'continueExpr' the continuation in the
--     RECORD's lexical @env@. The 'App1 [time, events]' that the ENCLOSING
--     'continueWithFollowup' already pushed is still on the stack, so once
--     @hence@ reduces to a 'ValObligation' that 'App1' applies it to
--     @[time, events]@ — the next step scrutinizes the SAME event stream.
runRecord :: WHNF -> WHNF -> Bool -> Environment -> Maybe (Expr Resolved) -> Maybe Text -> Machine Config
runRecord cellVal val isOfficial env mHence mRecipientKey = do
  cell <- expectString cellVal
  -- Bitemporal stamps (smucclaw/l4-ide#914 §2A). Transaction time is the
  -- ROOT eval clock ('getEvalTime'): a plain EvalState field that
  -- @EVAL AS OF SYSTEM TIME@ never touches — that clause scopes reads,
  -- never writes (the audit invariant). Valid-from is the ambient fact-time
  -- axis when set (an enclosing @EVAL UNDER VALID TIME@ = an explicitly
  -- dated assertion), 'Nothing' otherwise (contemporaneous; the effective
  -- valid-from defaults to the tx day at read time, 'effectiveVt'). The
  -- axis is read through the instrumented reader per the READER CONTRACT;
  -- the enclosing force is write-poisoned by 'tellEventRouted' anyway, so
  -- the observation can never install a context-fingerprint cache entry.
  evalNow <- getEvalTime
  mVt     <- readTcValidTime
  mParty  <- getCurrentParty
  let prov = MkProvenance
        { party  = fromMaybe "" mParty
        , source = if isOfficial then "COMMIT"
                   else maybe "RECORD" (const "NOTIFY") mRecipientKey
        , txTime = evalNow
        , vtFrom = mVt
        }
      -- NOTIFY v1: a recipient-qualified RECORD routes the write to the named
      -- recipient's own ledger ('RouteNotify recipientKey'); a bare RECORD routes
      -- to the acting party's own ledger ('RouteOwn'); COMMIT/ATTEST stays
      -- official. The recipient key was computed via 'partyKeyWHNF' (Record0), the
      -- same key a cross-party RECALL reads — so write-key ≡ read-key.
      route = if isOfficial
              then RouteOfficial
              else maybe RouteOwn RouteNotify mRecipientKey
  tellEventRouted route (Assign [cell] val prov)
  case mHence of
    Nothing    -> continueBackward val          -- M1: terminal / expression use
    Just hence -> continueExpr env hence        -- M5: become the deontic continuation

-- | STATE-AS-LEDGER M1.5 / M4.5 (+ approach B): finish a RECALL (cell read)
-- against a given ledger, in the requested 'RecallMode'.
--
-- The cell has already evaluated to a 'WHNF' that must be a 'ValString'; we
-- lower it to a single-segment 'Path' (mirroring 'runRecord'). The @ledger@ is
-- chosen by the caller — the current party's own ledger (M1.5, the default), a
-- named party's own ledger (M4.5 cross-party), or the shared official record
-- (M4.5 @official's@).
--
--   * 'RecallLast' (@RECALL …@): read through the AMBIENT TEMPORAL CONTEXT
--     via 'readCellBitemporal' (smucclaw\/l4-ide#914 §2B): entries appended
--     after the system-time bound (@EVAL AS OF SYSTEM TIME@) are invisible,
--     and a fact-time point (@EVAL UNDER VALID TIME@) selects the visible
--     entry whose positional valid interval covers it. With no clause in
--     scope this degenerates to the last-write-wins projection. Result
--     @MAYBE a@: @JUST v@ when a visible entry answers, @NOTHING@ otherwise
--     — including when the cell HAS been written but the write is hidden by
--     the tx bound or postdates the vt point (a principled miss).
--   * 'RecallAll' (@RECALL ALL …@, approach B): fold every VISIBLE 'Assign'
--     (the tx bound applies; a vt point deliberately does not — ALL is a
--     whole-history projection) into a @LIST OF a@ via
--     'readCellAllBitemporal' (oldest->newest, append order), building it
--     right-to-left as 'ValCons'\/'ValNil'. Result @[]@ (ValNil) when no
--     visible entry exists — NOT @NOTHING@.
finishRead :: RecallMode -> WHNF -> Ledger -> Machine Config
finishRead mode cellVal ledger = do
  cell <- expectString cellVal
  -- Bitemporal read bounds (smucclaw/l4-ide#914 §2B): RECALL reads THROUGH
  -- the ambient temporal context. @EVAL AS OF SYSTEM TIME t@ hides entries
  -- appended after t (tx > t); @EVAL UNDER VALID TIME t@ selects, among
  -- visible entries, the one whose positional valid interval covers t. With
  -- neither clause in scope, tcSystemTime is the root eval clock — every
  -- entry's tx equals it, so nothing is hidden — and the valid-time axis is
  -- unset, so the fold degenerates to the historical last-write-wins
  -- projection: bare RECALL is unchanged by construction. The axes are read
  -- through the instrumented readers (READER CONTRACT): together with the
  -- 'crLedgerRead' marker they make the enclosing force WHNFWhen-cached on
  -- exactly these observations, so a SHARED thunk containing this RECALL is
  -- re-served only under an unchanged context and re-forced under a new one
  -- (snapshot per temporal scope — see 'noteLedgerRead').
  txBound <- readTcSystemTime
  vtBound <- readTcValidTime
  case mode of
    RecallLast ->
      case readCellBitemporal (Just txBound) vtBound [cell] ledger of
        Just storedVal -> do
          valueRef <- allocateValue storedVal
          continueBackward (ValConstructor TypeCheck.justRef [valueRef])
        Nothing ->
          continueBackward (ValConstructor TypeCheck.nothingRef [])
    RecallAll -> do
      -- oldest->newest list of every VISIBLE assignment to this cell (the
      -- tx cutoff applies; a valid-time point deliberately does not — RECALL
      -- ALL is a whole-history projection). Build the spine right-to-left as
      -- ValCons cells terminating in ValNil (ValueLazy list representation):
      -- the resulting WHNF has the oldest value at the head.
      let storedVals = readCellAllBitemporal (Just txBound) [cell] ledger
      listVal <- foldrM
        (\v tailWHNF -> do
            headRef <- allocateValue v
            tailRef <- allocateValue tailWHNF
            pure (ValCons headRef tailRef))
        ValNil
        storedVals
      continueBackward listVal

-- | A bare reference to a definition in an IMPORTED module that discharge gave
-- trailing parameters.
--
-- The companion to 'matchGivens'''s under-application case, for the references
-- that never become applications at all. Discharge runs per module, so nothing
-- rewrote this reference into a call, and handing the consumer the closure gives
-- a function where a value was asked for: measured on an importer of a module
-- with a section binder, @#EVAL doubled@ printed @\<function\>@ -- silently,
-- not as an error -- and @doubled PLUS 1@ died with a runtime type error.
--
-- Reads the thunk WITHOUT forcing it. Any definition with parameters is stored
-- as a 'ValClosure' at 'WHNF' by 'evalDecide', so this needs no evaluation and
-- leaves laziness exactly as it was; anything still 'Unevaluated' is passed
-- through untouched.
--
-- Guarded exactly as 'matchGivens'' is, and for the same reason: EVERY one of
-- the closure's parameters must already be a key in its OWN captured
-- environment, which is true only of parameters discharge appended for that
-- module's section binders. An ordinary function passed as a value has
-- parameters bound nowhere, so it is returned unchanged -- including a reader
-- that still has declared parameters of its own, such as @bump@, which must
-- stay a function so its caller can apply it.
-- | Is the top of the stack an application waiting for its function?
--
-- 'App1' with a NON-empty argument list. The empty one is what
-- 'autoApplyDischargedImport' itself pushes, and must not count.
topFrameAppliesArguments :: Machine Bool
topFrameAppliesArguments = do
  stackRef <- asks (.stack)
  st <- liftIO (readIORef stackRef)
  pure case st.frames of
    App1 (_ : _) _ : _ -> True
    _                  -> False

autoApplyDischargedImport :: Reference -> Machine Config
autoApplyDischargedImport r = do
  needsIt <- dischargedImportClosure r
  if needsIt
    then do
      pushFrame (App1 [] Nothing)
      continueRef r
    else continueRef r

-- | Does this reference hold a closure that only discharge could have built --
-- every one of its parameters already a key in its OWN captured environment?
--
-- Reads the thunk without forcing it: 'evalDecide' stores any definition with
-- parameters as a 'ValClosure' at 'WHNF' already, and anything still
-- 'Unevaluated' answers 'False' and is left alone.
--
-- An ordinary function value fails this test, because its parameters are bound
-- by the application that has not happened yet, not by the environment it
-- captured. That is what keeps a genuine higher-order argument a function.
dischargedImportClosure :: Reference -> Machine Bool
dischargedImportClosure r = do
  thunk <- readThunk r
  pure case thunk of
    WHNF (ValClosure (MkGivenSig _ otns) _ closureEnv) ->
      let ps = foldMap (either (const []) (\ x -> [fst x]) . TypeCheck.isQuantifier) otns
      in not (null ps) && all (\ p -> Map.member (getUnique p) closureEnv) ps
    _ -> False

matchGivens :: Environment -> GivenSig Resolved -> Frame -> [Reference] -> Machine Environment
matchGivens closureEnv (MkGivenSig _ann otns) f es = do
  let others = foldMap (either (const []) (\x -> [fst x]) . TypeCheck.isQuantifier) otns
  matchGivens' closureEnv others f es

-- | Bind a closure's parameters to the arguments a call site supplied.
--
-- The under-applied case is 'L4.Discharge' crossing an @IMPORT@. Discharge runs
-- per module, so a definition in an IMPORTED module gains its trailing section
-- binders when THAT module is discharged, while the importer's call site — which
-- the checker saw at the callee's original arity, and which declares no binder of
-- its own to discharge — still passes only the declared arguments. Before this
-- fallback the result was
-- @Internal error: given signatures' values' lengths do not match@ on a correct
-- program: measured on the @ASSUME@ sweep's tree, six sites in
-- @legal\/regcf\/regcf-wizard.l4@, which @IMPORT@s @regcf@.
--
-- Every parameter discharge appends is a section binder of the callee's own
-- module, so its 0-ary cell is in the closure's captured environment. We
-- therefore bind only what was supplied and let @Map.union env'' env'@ at the
-- call site resolve the rest from that environment — the imported module's own
-- binder cell, which is exactly what the callee would have read before
-- discharge.
--
-- Guarded so it cannot mask a real arity error: it fires only when the call is
-- UNDER-applied and every missing parameter is a key the closure's environment
-- already holds. An ordinary parameter the writer forgot is a fresh binding that
-- no module environment carries, so it still reaches the error below — and the
-- checker rejects a genuine arity mistake long before evaluation anyway.
--
-- What it does NOT give the importer is the ability to @WITH@-supply that
-- binder: 'L4.TypeCheck.CheckEnv.sectionBinderNames' is per module, so the name
-- is not suppliable across the boundary. The importer sees whatever the imported
-- module's own binder evaluates to — its @TYPICALLY@, or \"assumed term\".
matchGivens' :: Environment -> [Resolved] -> Frame -> [Reference] -> Machine Environment
matchGivens' closureEnv ns f rs = do
  let (supplied, missing) = splitAt (length rs) ns
  if length ns == length rs
    then
      pure $ Map.fromList (zipWith (\ r v -> (getUnique r, v)) ns rs)
    else if length rs < length ns
           && all (\ n -> Map.member (getUnique n) closureEnv) missing
      then
        pure $ Map.fromList (zipWith (\ r v -> (getUnique r, v)) supplied rs)
      else do
        pushFrame f -- provides better error context
        internalException $
          RuntimeTypeError "given signatures' values' lengths do not match"

matchBranches :: Reference -> Environment -> [Branch Resolved] -> Machine Config
matchBranches scrutinee _env [] = do
  -- The scrutinee has been forced by the failed branch matches, so we can
  -- usually show the actual value in the error instead of a heap reference.
  thunk <- readThunk scrutinee
  userException $ NonExhaustivePatterns case thunk of
    WHNF val          -> Right val
    -- A context-dependent cache still holds the value the branches were
    -- matched against, so it names the scrutinee just as well as a plain
    -- 'WHNF'; we are inside that very force, so it cannot be stale here.
    WHNFWhen _ val _ _ -> Right val
    Unevaluated{}     -> Left scrutinee
matchBranches _scrutinee env (MkBranch _ann (Otherwise _ann') e : _) =
  continueExpr env e
matchBranches scrutinee env (MkBranch _ann (When _ann' pat) e : branches) = do
  pushFrame (ConsiderWhen1 scrutinee e branches env)
  continuePattern scrutinee env pat

matchPattern :: Reference -> Environment -> Pattern Resolved -> Machine Config
matchPattern scrutinee _env (PatVar _ann n) = do
  continueBackward (ValEnvironment (Map.singleton (getUnique n) scrutinee))
matchPattern scrutinee _env (PatApp _ann n [])
  | getUnique n == TypeCheck.emptyUnique = do -- pattern for the empty list
  pushFrame PatNil0
  continueRef scrutinee
matchPattern scrutinee env (PatCons _ann p1 p2) = do
  pushFrame (PatCons0 p1 env p2 )
  continueRef scrutinee
matchPattern scrutinee env (PatApp _ann n ps) = do
  pushFrame (PatApp0 n env ps)
  continueRef scrutinee
matchPattern scrutinee env (PatExpr _ann expr) = do
  pushFrame (PatLit0 env expr)
  continueRef scrutinee
matchPattern scrutinee _env (PatLit _ann lit) = do
  pushFrame $ PatLit1 case lit of
    NumericLit _ n -> ValNumber n
    StringLit _ s -> ValString  s
  continueRef scrutinee

-- | This unwinds the stack until it finds the enclosing pattern match and then resumes.
patternMatchFailure :: Machine Config
patternMatchFailure = withPoppedFrame $ \ case
  Nothing ->
    internalException UnhandledPatternMatch
  Just (ConsiderWhen1 scrutinee _ branches env) ->
    continueBranches scrutinee env branches
  -- we have unwound the frame that would reenter when scrutinizing the event
  Just (ContractFrame (Contract11 ActionDoesn'tmatch {..})) -> do
    -- P2b: the action pattern did not match; next event.
    whenDeonticLog \ l -> do
      stamp <- case time of
        ValNumber t -> pure t
        v -> internalException $ RuntimeTypeError $ "expected a NUMBER but got: " <> prettyLayout v
      ev <- eventKeyAt stamp (Just (partyKeyWHNF ev'party)) ev'act
      logStep l (plainStep (Just stamp) (Just ev) (scrutinyOf ev'reoffered WitnessedOnly) norm ActionMismatch)
    newTime <- allocateValue time
    pushFrame $ ContractFrame $ Contract1 ScrutinizeEvents {party = Right party, time = newTime, ..}
    continueRef events
  Just _ ->
    patternMatchFailure

runLit :: Lit -> Machine WHNF
runLit (NumericLit _ann num) = pure (ValNumber num)
runLit (StringLit _ann str)  = pure (ValString str)

expect1 :: [a] -> Machine a
expect1 = \ case
  [x] -> pure x
  xs -> internalException (RuntimeTypeError $ "Expected 1 argument, but got " <> Text.textShow (length xs))

expect2 :: [a] -> Machine (a, a)
expect2 = \ case
  [x, y] -> pure (x, y)
  xs -> internalException (RuntimeTypeError $ "Expected 2 arguments, but got " <> Text.textShow (length xs))

expect3 :: [a] -> Machine (a, a, a)
expect3 = \ case
  [x, y, z] -> pure (x, y, z)
  xs -> internalException (RuntimeTypeError $ "Expected 3 arguments, but got " <> Text.textShow (length xs))

expectNumber :: WHNF -> Machine Rational
expectNumber = \ case
  ValNumber f -> pure f
  ValAssumed r -> stuckOnAssumed r
  v -> internalException $ RuntimeTypeError $ "expected a NUMBER but got: " <> prettyLayout v

expectString :: WHNF -> Machine Text
expectString = \ case
  ValString f -> pure f
  ValAssumed r -> stuckOnAssumed r
  v -> internalException $ RuntimeTypeError $ "expected a STRING but got: " <> prettyLayout v

expectDateValue :: WHNF -> Machine Time.Day
expectDateValue = \ case
  ValDate d -> pure d
  ValNumber serial -> pure (Time.utctDay (serialToUTCTime serial))
  ValAssumed r -> stuckOnAssumed r
  v -> internalException $ RuntimeTypeError $ "expected a DATE but got: " <> prettyLayout v

expectInteger :: BinOp -> Rational -> Machine Integer
expectInteger op n = do
  case isInteger n of
    Nothing -> userException (NotAnInteger op n)
    Just i -> pure i

expectWhole :: Text -> Rational -> Machine Integer
expectWhole label n =
  case isInteger n of
    Nothing -> internalException $ RuntimeTypeError label
    Just i -> pure i

-- | Extract field names from a constructor's function type
-- The constructor type is typically: forall args. (field1: Type1, field2: Type2, ...) -> ResultType
extractFieldNames :: Type' Resolved -> Machine [Text]
extractFieldNames ty = case ty of
  -- Strip forall quantifier if present
  Forall _ _ innerTy -> extractFieldNames innerTy
  -- Extract field names from function arguments
  Fun _ argTypes _resultTy -> do
    pure $ mapMaybe getFieldName argTypes
  -- Not a function type - might be a nullary constructor
  _ -> pure []
  where
    getFieldName :: OptionallyNamedType Resolved -> Maybe Text
    getFieldName (MkOptionallyNamedType _ maybeName _ty) =
      nameToText . TypeCheck.getName <$> maybeName

-- | Extract both field names AND types from a constructor's function type
-- This is needed for type-directed JSON decoding of nested structures
extractFieldNamesAndTypes :: Type' Resolved -> Machine [(Text, Type' Resolved)]
extractFieldNamesAndTypes ty = case ty of
  -- Strip forall quantifier if present
  Forall _ _ innerTy -> extractFieldNamesAndTypes innerTy
  -- Extract field names and types from function arguments
  Fun _ argTypes _resultTy -> do
    pure $ mapMaybe getFieldNameAndType argTypes
  -- Not a function type - might be a nullary constructor
  _ -> pure []
  where
    getFieldNameAndType :: OptionallyNamedType Resolved -> Maybe (Text, Type' Resolved)
    getFieldNameAndType (MkOptionallyNamedType _ maybeName fieldType) =
      case maybeName of
        Just name -> Just (nameToText (TypeCheck.getName name), fieldType)
        Nothing -> Nothing

-- | Check if a constructor type is nullary (no arguments) and returns the given type
-- Used for enum (ONE OF) type detection
isNullaryConstructorReturning :: Type' Resolved -> Resolved -> Bool
isNullaryConstructorReturning conType targetTypeRef = case conType of
  -- Strip forall quantifier if present
  Forall _ _ innerTy -> isNullaryConstructorReturning innerTy targetTypeRef
  -- If it's a function type, it's not nullary
  Fun {} -> False
  -- If it's directly a type application, check if it matches our target
  TyApp _ tyRef [] -> getUnique tyRef == getUnique targetTypeRef
  -- Other cases: not a match
  _ -> False

-- | Encode an L4 value to JSON string
encodeValueToJson :: WHNF -> Machine Text
encodeValueToJson = \case
  ValString s -> pure $ "\"" <> escapeJson s <> "\""
  ValNumber n
    | denominator n == 1 -> pure $ Text.pack $ show (numerator n)
    | otherwise -> pure $ Text.pack $ show (fromRational n :: Double)
  ValBool True -> pure "true"
  ValBool False -> pure "false"
  ValNil -> pure "[]"
  ValCons _x _xs ->
    -- This should not be reached as lists are handled in runBuiltin with frames
    internalException $ RuntimeTypeError "Internal error: ValCons should be handled by frame-based evaluation in runBuiltin"
  ValConstructor conRef []
    | nameToText (TypeCheck.getName conRef) == "NOTHING" -> pure "null"
    | nameToText (TypeCheck.getName conRef) == "TRUE" -> pure "true"
    | nameToText (TypeCheck.getName conRef) == "FALSE" -> pure "false"
    | otherwise -> pure $ "\"" <> escapeJson (nameToText (TypeCheck.getName conRef)) <> "\""
  -- Note: For constructors with fields, we can't encode them directly within encodeValueToJson
  -- because we need to evaluate (force) each field reference. This requires frames.
  -- So constructors are handled in runBuiltin where we can push frames.
  ValConstructor conRef _fields -> do
    internalException $ RuntimeTypeError $
      "Internal error: Constructor encoding should be handled in runBuiltin, not encodeValueToJson: " <>
      nameToText (TypeCheck.getName conRef)
  val -> internalException $ RuntimeTypeError $ "Cannot encode value to JSON: " <> prettyLayout val
  where
    escapeJson :: Text -> Text
    escapeJson = Text.concatMap \case
      '"' -> "\\\""
      '\\' -> "\\\\"
      '\n' -> "\\n"
      '\r' -> "\\r"
      '\t' -> "\\t"
      c -> Text.singleton c

-- | Decode JSON string to L4 value wrapped in EITHER
-- Returns LEFT errorMsg on parse error, RIGHT value on success
-- | Type-directed JSON decoding - uses type information to construct proper records
decodeJsonToValueTyped :: Text -> Type' Resolved -> Machine WHNF
decodeJsonToValueTyped jsonStr ty = do
  let jsonBytes :: BS.ByteString
      jsonBytes = TE.encodeUtf8 jsonStr
  case Aeson.eitherDecodeStrict' jsonBytes of
    Left err -> do
      -- Parse error: return LEFT errorMsg
      errorRef <- allocateValue (ValString (Text.pack err))
      pure $ ValConstructor TypeCheck.leftRef [errorRef]
    Right jsonValue -> do
      -- Parse success: convert to L4 value using type information and wrap in RIGHT
      l4Value <- jsonValueToWHNFTyped jsonValue ty
      valueRef <- allocateValue l4Value
      pure $ ValConstructor TypeCheck.rightRef [valueRef]

-- | Convert Aeson Value to L4 WHNF using type information
-- This function recursively handles nested structures: lists of records, records containing records, etc.
jsonValueToWHNFTyped :: Aeson.Value -> Type' Resolved -> Machine WHNF
jsonValueToWHNFTyped jsonValue ty = do
  case ty of
    -- Handle LIST OF α
    TyApp _anno listRef [elementType]
      | nameToText (TypeCheck.getName listRef) == "LIST" -> do
        case jsonValue of
          Aeson.Array vec -> do
            -- Recursively decode each element with the element type
            let values = Vector.toList vec
            jsonListToWHNFTyped values elementType
          _ -> do
            userException $ UserError $
              "Expected JSON array to decode to LIST type, but got: " <> Text.pack (show jsonValue)

    -- Handle MAYBE α
    TyApp _anno maybeRef [innerType]
      | nameToText (TypeCheck.getName maybeRef) == "MAYBE" -> do
        case jsonValue of
          Aeson.Null ->
            -- JSON null maps to NOTHING
            pure $ ValConstructor TypeCheck.nothingRef []
          _ -> do
            -- Non-null value: decode and wrap in JUST
            innerVal <- jsonValueToWHNFTyped jsonValue innerType
            innerRef <- allocateValue innerVal
            pure $ ValConstructor TypeCheck.justRef [innerRef]

    -- Handle custom record types and primitives: TyApp conRef []
    TyApp _anno tyRef [] -> do
      let typeName = nameToText (TypeCheck.getName tyRef)

      -- Handle primitive types first
      case typeName of
        "STRING" -> do
          case jsonValue of
            Aeson.String s -> pure $ ValString s
            _ -> userException $ UserError $
                  "Expected JSON string but got: " <> Text.pack (show jsonValue)
        "NUMBER" -> do
          case jsonValue of
            Aeson.Number n -> pure $ ValNumber (toRational n)
            _ -> userException $ UserError $
                  "Expected JSON number but got: " <> Text.pack (show jsonValue)
        "BOOLEAN" -> do
          case jsonValue of
            Aeson.Bool b -> pure $ if b then ValBool True else ValBool False
            _ -> userException $ UserError $
                  "Expected JSON boolean but got: " <> Text.pack (show jsonValue)
        "DATE" -> do
          -- DATE fields in JSON should be ISO-8601 strings (YYYY-MM-DD)
          case jsonValue of
            Aeson.String s -> do
              case parseDateText s of
                Just day -> pure $ ValDate day
                Nothing -> userException $ UserError $
                  "Could not parse date string '" <> s <> "'. Expected format: YYYY-MM-DD"
            _ -> userException $ UserError $
                  "Expected JSON string for DATE field but got: " <> Text.pack (show jsonValue)
        "TIME" -> do
          -- TIME fields in JSON should be strings (HH:MM:SS or HH:MM)
          case jsonValue of
            Aeson.String s -> do
              case parseTimeText s of
                Just tod -> pure $ ValTime tod
                Nothing -> userException $ UserError $
                  "Could not parse time string '" <> s <> "'. Expected format: HH:MM:SS or HH:MM"
            _ -> userException $ UserError $
                  "Expected JSON string for TIME field but got: " <> Text.pack (show jsonValue)
        "DATETIME" -> do
          -- DATETIME fields in JSON should be ISO-8601 strings with timezone
          case jsonValue of
            Aeson.String s -> do
              case parseDatetimeText s of
                Just utc -> do
                  -- instrumented read: the tz affects the result value (T6)
                  mTzName <- readTcDocumentTimezone
                  let tzName = fromMaybe "Etc/UTC" mTzName
                  pure $ ValDateTime utc tzName
                Nothing -> userException $ UserError $
                  "Could not parse datetime string '" <> s <> "'. Expected ISO-8601 format: YYYY-MM-DDTHH:MM:SSZ"
            _ -> userException $ UserError $
                  "Expected JSON string for DATETIME field but got: " <> Text.pack (show jsonValue)

        -- Not a primitive, check if it's a custom record type
        _ -> do
          -- For record types, we need to find the constructor with the same name
          entityInfo <- getEntityInfo

          -- First check if this is a type
          case Map.lookup (getUnique tyRef) entityInfo of
            Nothing ->
              jsonValueToWHNF jsonValue
            Just (typeNameRef, _checkEntity) -> do
              -- Now look for a constructor with the same name
              let constructors = Map.toList entityInfo
                  matchingConstructor = listToMaybe
                    [ (unique, name, conType)
                    | (unique, (name, TypeCheck.KnownTerm conType Constructor)) <- constructors
                    , nameToText (TypeCheck.getName name) == nameToText (TypeCheck.getName typeNameRef)
                    ]

              case matchingConstructor of
                Nothing -> do
                  -- No record constructor found. Check if this is an enum type
                  -- by looking for nullary constructors that return this type.
                  case jsonValue of
                    Aeson.String enumName -> do
                      -- Look for a nullary constructor with this name that returns tyRef
                      let enumConstructor = listToMaybe
                            [ (unique, name)
                            | (unique, (name, TypeCheck.KnownTerm conType Constructor)) <- constructors
                            , nameToText (TypeCheck.getName name) == enumName
                            , isNullaryConstructorReturning conType tyRef
                            ]
                      case enumConstructor of
                        Just (enumUnique, enumConName) -> do
                          -- Found a matching enum constructor
                          let enumRef = Def enumUnique enumConName
                          pure $ ValConstructor enumRef []
                        Nothing ->
                          -- No matching enum constructor, fall back to generic decoding
                          jsonValueToWHNF jsonValue
                    _ ->
                      -- Not a string, fall back to generic decoding
                      jsonValueToWHNF jsonValue
                Just (conUnique, conName, conType) -> do
                  -- Construct a Resolved reference for the constructor
                  let conRef = Def conUnique conName
                  -- Extract BOTH field names AND types from the constructor type
                  fieldNamesAndTypes <- extractFieldNamesAndTypes conType
                  case jsonValue of
                    Aeson.Object obj -> do
                      -- Decode each field from the JSON object WITH TYPE INFORMATION
                      -- Note: We ignore extra fields in the JSON (Postel's Law)
                      fieldRefs <- forM fieldNamesAndTypes $ \(fieldName, fieldType) -> do
                        case KeyMap.lookup (Key.fromText fieldName) obj of
                          Nothing
                            | isMaybeFieldTy fieldType ->
                              -- MAYBE field missing in JSON: treat as NOTHING
                              allocateValue $ ValConstructor TypeCheck.nothingRef []
                            | otherwise -> do
                              -- Required field missing in JSON: error
                              userException $ UserError $
                                "Missing required field '" <> fieldName <> "' in JSON object"
                          Just fieldValue -> do
                            -- RECURSIVELY decode the field value WITH TYPE INFORMATION
                            fieldWHNF <- jsonValueToWHNFTyped fieldValue fieldType
                            allocateValue fieldWHNF
                      -- Construct the record with the decoded fields
                      pure $ ValConstructor conRef fieldRefs
                    _ -> do
                      -- JSON value is not an object, can't decode to record
                      userException $ UserError $
                        "Expected JSON object to decode to record type, but got: " <> Text.pack (show jsonValue)

    -- For other types, fall back to generic decoding
    _ -> jsonValueToWHNF jsonValue

-- | Check if a type is MAYBE α (used for optional record field handling)
isMaybeFieldTy :: Type' Resolved -> Bool
isMaybeFieldTy (TyApp _ tyName [_]) = nameToText (TypeCheck.getName tyName) == "MAYBE"
isMaybeFieldTy _ = False

-- | Convert list of JSON values to L4 list (ValCons/ValNil) with type information
-- This recursively decodes each element using the provided element type
jsonListToWHNFTyped :: [Aeson.Value] -> Type' Resolved -> Machine WHNF
jsonListToWHNFTyped [] _elementType = pure ValNil
jsonListToWHNFTyped (x:xs) elementType = do
  headVal <- jsonValueToWHNFTyped x elementType
  headRef <- allocateValue headVal
  tailVal <- jsonListToWHNFTyped xs elementType
  tailRef <- allocateValue tailVal
  pure $ ValCons headRef tailRef

decodeJsonToValue :: Text -> Machine WHNF
decodeJsonToValue jsonStr = do
  case Aeson.eitherDecodeStrict' (TE.encodeUtf8 jsonStr) of
    Left err -> do
      -- Parse error: return LEFT errorMsg
      errorRef <- allocateValue (ValString (Text.pack err))
      pure $ ValConstructor TypeCheck.leftRef [errorRef]
    Right jsonValue -> do
      -- Parse success: convert to L4 value and wrap in RIGHT
      l4Value <- jsonValueToWHNF jsonValue
      valueRef <- allocateValue l4Value
      pure $ ValConstructor TypeCheck.rightRef [valueRef]

-- | Convert Aeson Value to L4 WHNF
jsonValueToWHNF :: Aeson.Value -> Machine WHNF
jsonValueToWHNF = \case
  Aeson.Null -> pure $ ValConstructor TypeCheck.nothingRef []
  Aeson.Bool b -> pure $ if b then ValBool True else ValBool False
  Aeson.Number n -> pure $ ValNumber (toRational n)
  Aeson.String s -> pure $ ValString s
  Aeson.Array vec -> do
    -- Convert array to L4 list (cons cells)
    let values = Vector.toList vec
    jsonListToWHNF values
  Aeson.Object _obj -> do
    -- Convert object to L4 constructor with named fields
    -- Without type information, we can't properly construct typed records
    -- Return NOTHING to indicate we can't decode this
    pure $ ValConstructor TypeCheck.nothingRef []

-- | Convert list of JSON values to L4 list (ValCons/ValNil)
jsonListToWHNF :: [Aeson.Value] -> Machine WHNF
jsonListToWHNF [] = pure ValNil
jsonListToWHNF (x:xs) = do
  headVal <- jsonValueToWHNF x
  headRef <- allocateValue headVal
  tailVal <- jsonListToWHNF xs
  tailRef <- allocateValue tailVal
  pure $ ValCons headRef tailRef

-- | Convert list of Text values to L4 list (ValCons/ValNil)
textListToWHNF :: [Text] -> Machine WHNF
textListToWHNF [] = pure ValNil
textListToWHNF (x:xs) = do
  headRef <- allocateValue (ValString x)
  tailVal <- textListToWHNF xs
  tailRef <- allocateValue tailVal
  pure $ ValCons headRef tailRef

#ifdef HTTP_ENABLED
runPost :: WHNF -> WHNF -> WHNF -> Machine Config
runPost urlVal headersVal bodyVal = do
  safe <- getSafeMode
  if safe
    then internalException (RuntimeTypeError "POST is disabled in safe mode (no HTTP requests allowed)")
    else do
      url <- expectString urlVal
      headersStr <- expectString headersVal
      body <- expectString bodyVal
      let (url', options) = Text.breakOn "?" url
          (protocol, _) = Text.breakOn "://" url'
      case protocol of
        "https" -> do
          let (hostname, path) = Text.breakOn "/" (Text.drop (Text.length "https://") url')
              pathSegments = filter (not . Text.null) $ Text.splitOn "/" path
              reqBase = Req.https hostname
              reqWithPath = foldl (Req./:) reqBase pathSegments
              params = if Text.null options then [] else Text.splitOn "&" (Text.drop 1 options)

              -- Parse headers from newline-separated format: "Header-Name: value\nAnother-Header: value"
              headerLines = filter (not . Text.null) $ Text.splitOn "\n" headersStr
              parseHeader line =
                let (name, rest) = Text.breakOn ":" line
                    value = Text.strip $ Text.drop 1 rest  -- drop the colon and strip whitespace
                in if Text.null rest
                   then Nothing  -- invalid header format
                   else Just (Req.header (TE.encodeUtf8 name) (TE.encodeUtf8 value))
              headerOptions = mapMaybe parseHeader headerLines

              queryOptions = map (\p -> let (k,v) = Text.breakOn "=" p in k =: Text.drop 1 v) params
              req_options = mconcat (headerOptions <> queryOptions)

          res <- liftIO $ Req.runReq Req.defaultHttpConfig $ do
            Req.req Req.POST reqWithPath (Req.ReqBodyLbs $ LBS.fromStrict $ TE.encodeUtf8 body) Req.lbsResponse req_options
          continueBackward $ ValString (TE.decodeUtf8 . LBS.toStrict $ Req.responseBody res)
        _ -> internalException (RuntimeTypeError "POST only supports https")
#else
runPost :: WHNF -> WHNF -> WHNF -> Machine Config
runPost _ _ _ = internalException (RuntimeTypeError "POST is not available (HTTP support disabled at compile time)")
#endif

runConcat :: [WHNF] -> Machine Config
runConcat vals = do
  strings <- traverse expectString vals
  continueBackward $ ValString (Text.concat strings)

runAsString :: WHNF -> Machine Config
runAsString = coerceToString

coerceToString :: WHNF -> Machine Config
coerceToString val = case val of
  ValNumber n ->
    continueBackward $ ValString (prettyRatio n)
  ValString s ->
    continueBackward $ ValString s
  ValBool b ->
    continueBackward $ ValString (if b then "TRUE" else "FALSE")
  ValDate day ->
    continueBackward $ ValString (formatDateIso day)
  ValTime tod ->
    continueBackward $ ValString (formatTimeOfDay tod)
  ValDateTime utc tzName ->
    continueBackward $ ValString (formatDateTimeIso utc tzName)
  ValConstructor con fields
    | isDateConstructor con -> do
        case fields of
          [dayRef, monthRef, yearRef] -> do
            pushFrame (ToStringDate1 monthRef yearRef)
            continueRef dayRef
          _ ->
            internalException $ RuntimeTypeError "DATE values must have three fields (day, month, year) for string conversion"
    | otherwise ->
        incompatible
  _ ->
    incompatible
  where
    incompatible =
      userException $ UserError $
        "AS STRING/TOSTRING can only convert NUMBER, BOOLEAN, DATE, TIME, DATETIME, or STRING to STRING, but found: " <> prettyLayout val

formatDateIso :: Time.Day -> Text
formatDateIso day =
  let (year, month, dayOfMonth) = Time.toGregorian day
  in formatDateParts (fromIntegral year) (fromIntegral month) (fromIntegral dayOfMonth)

isDateConstructor :: Resolved -> Bool
isDateConstructor con =
  Text.toUpper (nameToText (TypeCheck.getName con)) == "DATE"

runDateToString :: Rational -> Rational -> Rational -> Machine Config
runDateToString dayNum monthNum yearNum = do
  dayInt <- expectIntegerNamed "day" dayNum
  monthInt <- expectIntegerNamed "month" monthNum
  yearInt <- expectIntegerNamed "year" yearNum
  continueBackward $ ValString (formatDateParts yearInt monthInt dayInt)

expectIntegerNamed :: Text -> Rational -> Machine Integer
expectIntegerNamed label n =
  case isInteger n of
    Just i -> pure i
    Nothing ->
      internalException $ RuntimeTypeError $
        "Expected an integer " <> label <> " but got: " <> prettyRatio n

formatDateParts :: Integer -> Integer -> Integer -> Text
formatDateParts year month day =
  pad 4 year <> "-" <> pad 2 month <> "-" <> pad 2 day
  where
    pad width v =
      let raw = Text.textShow v
      in if Text.length raw >= width
           then raw
           else Text.replicate (width - Text.length raw) "0" <> raw

runBuiltin :: WHNF -> UnaryBuiltinFun -> Maybe (Type' Resolved) -> Machine Config
runBuiltin es op mTy = do
  case op of
    UnaryJsonEncode -> do
      case es of
        ValCons headRef tailRef -> do
          -- Start frame-based evaluation for non-empty lists
          -- We're about to evaluate the head element (expectingTail = False)
          pushFrame (JsonEncodeListFrame [] tailRef False)
          continueRef headRef
        ValNil -> do
          -- Empty list is simple
          continueBackward $ ValString "[]"
        ValConstructor conRef []
          | nameToText (TypeCheck.getName conRef) == "NOTHING" ->
            -- NOTHING encodes to null
            continueBackward $ ValString "null"
          | nameToText (TypeCheck.getName conRef) == "TRUE" ->
            -- TRUE encodes to true
            continueBackward $ ValString "true"
          | nameToText (TypeCheck.getName conRef) == "FALSE" ->
            -- FALSE encodes to false
            continueBackward $ ValString "false"
        ValConstructor conRef [field]
          | nameToText (TypeCheck.getName conRef) == "JUST" -> do
            -- JUST wraps a single value, evaluate it and encode
            pushFrame (UnaryBuiltin0 UnaryJsonEncode Nothing)
            continueRef field
        ValConstructor conRef fields -> do
          -- Encode record constructors as JSON objects with field names
          entityInfo <- getEntityInfo
          case Map.lookup (getUnique conRef) entityInfo of
            Nothing ->
              internalException $ RuntimeTypeError $ "Cannot find constructor in entity info: " <> nameToText (TypeCheck.getName conRef)
            Just (_name, checkEntity) -> case checkEntity of
              TypeCheck.KnownTerm conType Constructor -> do
                -- Extract field names from the constructor's function type
                fieldNames <- extractFieldNames conType
                if length fieldNames /= length fields
                  then internalException $ RuntimeTypeError $
                    "Field count mismatch for constructor " <> nameToText (TypeCheck.getName conRef) <>
                    ": expected " <> Text.pack (show (length fieldNames)) <>
                    " but got " <> Text.pack (show (length fields))
                  else
                    let fieldPairs = zip fieldNames fields
                    in case fieldPairs of
                      [] -> do
                        -- Nullary constructor (no fields) - encode as JSON string with constructor name
                        -- This handles enum (ONE OF) values
                        let conName = nameToText (TypeCheck.getName conRef)
                        jsonStr <- encodeValueToJson (ValString conName)
                        continueBackward $ ValString jsonStr
                      ((fn, fr):rest) -> do
                        -- Start frame-based encoding of fields
                        -- The frame stores: accumulated pairs, current field name being encoded, remaining pairs
                        pushFrame (JsonEncodeConstructorFrame [] fn rest)
                        -- Push frame to encode the first field value
                        pushFrame (UnaryBuiltin0 UnaryJsonEncode Nothing)
                        -- Evaluate the first field
                        continueRef fr
              _ ->
                internalException $ RuntimeTypeError $
                  "Expected constructor term but got different entity type for: " <> nameToText (TypeCheck.getName conRef)
        _ -> do
          -- For non-list, non-constructor values, use direct encoding
          jsonStr <- encodeValueToJson es
          continueBackward $ ValString jsonStr
    UnaryJsonDecode -> do
      jsonStr <- expectString es
      result <- case mTy of
        Just ty -> do
          -- Extract inner type from EITHER if present
          -- JSONDECODE returns EITHER STRING α, so if we have EITHER STRING Person, extract Person
          let innerTy = case ty of
                TyApp _ eitherRef [_errorType, valueType]
                  | nameToText (TypeCheck.getName eitherRef) == "EITHER" -> valueType
                _ -> ty
          decodeJsonToValueTyped jsonStr innerTy
        Nothing ->
          decodeJsonToValue jsonStr
      continueBackward result
#ifdef HTTP_ENABLED
    UnaryFetch -> do
      safe <- getSafeMode
      if safe
        then internalException (RuntimeTypeError "FETCH is disabled in safe mode (no HTTP requests allowed)")
        else do
          url <- expectString es
          let (url', options) = Text.breakOn "?" url
              (protocol, _) = Text.breakOn "://" url'
          case protocol of
            "https" -> do
              let (hostname, path) = Text.breakOn "/" (Text.drop (Text.length "https://") url')
                  pathSegments = filter (not . Text.null) $ Text.splitOn "/" path
                  reqBase = Req.https hostname
                  reqWithPath = foldl (Req./:) reqBase pathSegments
                  params = if Text.null options then [] else Text.splitOn "&" (Text.drop 1 options)
                  req_options =
                    mconcat (map (\p -> let (k,v) = Text.breakOn "=" p in k =: Text.drop 1 v) params)
              res <- liftIO $ Req.runReq Req.defaultHttpConfig $ do
                Req.req Req.GET reqWithPath Req.NoReqBody Req.lbsResponse req_options
              continueBackward $ ValString (TE.decodeUtf8 . LBS.toStrict $ Req.responseBody res)
            _ -> internalException (RuntimeTypeError "FETCH only supports https")
#else
    UnaryFetch -> do
      internalException (RuntimeTypeError "FETCH is not available (HTTP support disabled at compile time)")
#endif
    UnaryEnv -> do
      varName <- expectString es
      maybeValue <- liftIO $ lookupEnv (Text.unpack varName)
      case maybeValue of
        Just value -> do
          -- Return JUST value
          valueRef <- allocateValue (ValString (Text.pack value))
          continueBackward (ValConstructor TypeCheck.justRef [valueRef])
        Nothing -> do
          -- Return NOTHING
          continueBackward (ValConstructor TypeCheck.nothingRef [])
    UnaryToString -> do
      coerceToString es
    UnaryToNumber -> do
      str <- expectString es
      case parseNumberText str of
        Just num -> do
          numRef <- allocateValue (ValNumber num)
          continueBackward $ ValConstructor TypeCheck.justRef [numRef]
        Nothing ->
          continueBackward $ ValConstructor TypeCheck.nothingRef []
    UnaryToDate -> do
      str <- expectString es
      case parseDateText str of
        Nothing ->
          continueBackward $ ValConstructor TypeCheck.nothingRef []
        Just parsedDay -> do
          maybeInner <- resolveMaybeInnerType mTy
          dateVal <- buildDateValue parsedDay maybeInner
          dateRef <- allocateValue dateVal
          continueBackward $ ValConstructor TypeCheck.justRef [dateRef]
    -- String unary operations
    UnaryStringLength -> do
      str <- expectString es
      continueBackward $ ValNumber (fromIntegral $ Text.length str)
    UnaryToUpper -> do
      str <- expectString es
      continueBackward $ ValString (Text.toUpper str)
    UnaryToLower -> do
      str <- expectString es
      continueBackward $ ValString (Text.toLower str)
    UnaryTrim -> do
      str <- expectString es
      continueBackward $ ValString (Text.strip str)
    UnaryDateValue -> do
      str <- expectString es
      case parseDateValueText str of
        Left err -> do
          errRef <- allocateValue (ValString err)
          continueBackward $ ValConstructor TypeCheck.leftRef [errRef]
        Right dayVal -> do
          valRef <- allocateValue (ValDate dayVal)
          continueBackward $ ValConstructor TypeCheck.rightRef [valRef]
    UnaryDateSerial -> do
      day <- expectDateValue es
      continueBackward $ ValNumber (fromIntegral (dayNumberFromDay day))
    UnaryDateFromSerial -> do
      serial <- expectNumber es
      continueBackward $ ValDate (Time.utctDay (serialToUTCTime serial))
    UnaryDateDay -> do
      day <- expectDateValue es
      let (_, _, d) = Time.toGregorian day
      continueBackward $ ValNumber (fromIntegral d)
    UnaryDateMonth -> do
      day <- expectDateValue es
      let (_, m, _) = Time.toGregorian day
      continueBackward $ ValNumber (fromIntegral m)
    UnaryDateYear -> do
      day <- expectDateValue es
      let (y, _, _) = Time.toGregorian day
      continueBackward $ ValNumber (fromIntegral y)
    UnaryTimeValue -> do
      str <- expectString es
      case parseTimeValueText str of
        Left err -> do
          errRef <- allocateValue (ValString err)
          continueBackward $ ValConstructor TypeCheck.leftRef [errRef]
        Right fraction -> do
          valRef <- allocateValue (ValNumber fraction)
          continueBackward $ ValConstructor TypeCheck.rightRef [valRef]
    -- TIME builtins
    UnaryTimeHour -> do
      tod <- expectTimeValue es
      continueBackward $ ValNumber (fromIntegral $ todHour tod)
    UnaryTimeMinute -> do
      tod <- expectTimeValue es
      continueBackward $ ValNumber (fromIntegral $ todMin tod)
    UnaryTimeSecond -> do
      tod <- expectTimeValue es
      continueBackward $ ValNumber (realToFrac $ todSec tod)
    UnaryTimeToSerial -> do
      tod <- expectTimeValue es
      let seconds = timeOfDayToTime tod
      continueBackward $ ValNumber (toRational seconds / toRational (86400 :: Pico))
    UnaryTimeFromSerial -> do
      serial <- expectNumber es
      let seconds = realToFrac (serial * 86400) :: Pico
      continueBackward $ ValTime (timeToTimeOfDay (realToFrac seconds))
    UnaryToTime -> do
      str <- expectString es
      case parseTimeText str of
        Just tod -> do
          todRef <- allocateValue (ValTime tod)
          continueBackward $ ValConstructor TypeCheck.justRef [todRef]
        Nothing ->
          continueBackward $ ValConstructor TypeCheck.nothingRef []
    -- DATETIME builtins
    UnaryDatetimeDate -> do
      (utc, tzName) <- expectDateTimeValue es
      case tryLoadTZPure tzName of
        Just tz -> do
          let localTime' = TZ.utcToLocalTimeTZ tz utc
          continueBackward $ ValDate (localDay localTime')
        Nothing ->
          userException $ UserError $ "Could not load timezone: " <> tzName
    UnaryDatetimeTime -> do
      (utc, tzName) <- expectDateTimeValue es
      case tryLoadTZPure tzName of
        Just tz -> do
          let localTime' = TZ.utcToLocalTimeTZ tz utc
          continueBackward $ ValTime (localTimeOfDay localTime')
        Nothing ->
          userException $ UserError $ "Could not load timezone: " <> tzName
    UnaryDatetimeSerial -> do
      (utc, _tzName) <- expectDateTimeValue es
      continueBackward $ ValNumber (utcDatestamp utc)
    UnaryDatetimeTzName -> do
      (_utc, tzName) <- expectDateTimeValue es
      continueBackward $ ValString tzName
    UnaryToDatetime -> do
      str <- expectString es
      case parseDatetimeText str of
        Just utc -> do
          -- Use document timezone as default for the stored tz name
          -- (instrumented read: the tz affects the result value, T6)
          mTzName <- readTcDocumentTimezone
          let tzName = fromMaybe "Etc/UTC" mTzName
          dtRef <- allocateValue (ValDateTime utc tzName)
          continueBackward $ ValConstructor TypeCheck.justRef [dtRef]
        Nothing ->
          continueBackward $ ValConstructor TypeCheck.nothingRef []
    -- Numeric unary operations (catch-all)
    _ -> do
      val :: Rational <- expectNumber es
      let valDouble :: Double
          valDouble = fromRational val
      case op of
        UnaryLn ->
          if val <= 0
            then userException $ UserError "LN expects input greater than 0"
            else continueBackward $ ValNumber (toRational (log valDouble))
        UnaryLog10 ->
          if val <= 0
            then userException $ UserError "LOG10 expects input greater than 0"
            else continueBackward $ ValNumber (toRational (logBase 10 valDouble))
        UnarySin ->
          continueBackward $ ValNumber (toRational (sin valDouble))
        UnaryCos ->
          continueBackward $ ValNumber (toRational (cos valDouble))
        UnaryTan ->
          continueBackward $ ValNumber (toRational (tan valDouble))
        UnaryAsin ->
          if val < (-1) || val > 1
            then userException $ UserError "ASIN expects input between -1 and 1"
            else continueBackward $ ValNumber (toRational (asin valDouble))
        UnaryAcos ->
          if val < (-1) || val > 1
            then userException $ UserError "ACOS expects input between -1 and 1"
            else continueBackward $ ValNumber (toRational (acos valDouble))
        UnaryAtan ->
          continueBackward $ ValNumber (toRational (atan valDouble))
        UnaryIsInteger -> continueBackward $ valBool $ isJust $ isInteger val
        UnaryRound -> continueBackward $ valInt $ round val
        UnaryCeiling -> continueBackward $ valInt $ ceiling val
        UnaryFloor -> continueBackward $ valInt $ floor val
        UnaryPercent -> continueBackward $ ValNumber (val / 100)
        UnarySqrt ->
          if val < 0
            then userException $ UserError "SQRT expects input greater than or equal to 0"
            else continueBackward $ ValNumber (toRational (sqrt valDouble))
  where
    valInt :: Integer -> WHNF
    valInt = ValNumber . toRational

runTernaryBuiltin :: TernaryBuiltinFun -> WHNF -> WHNF -> WHNF -> Machine Config
runTernaryBuiltin TernarySubstring val1 val2 val3 = do
  str <- expectString val1
  start <- expectNumber val2
  len <- expectNumber val3
  let startInt = floor start :: Int
      lenInt = floor len :: Int
  -- Use Text.take and Text.drop for substring
  continueBackward $ ValString (Text.take lenInt (Text.drop startInt str))
runTernaryBuiltin TernaryReplace val1 val2 val3 = do
  str <- expectString val1
  old <- expectString val2
  new <- expectString val3
  -- Use Text.replace: replace needle replacement haystack
  continueBackward $ ValString (Text.replace old new str)
runTernaryBuiltin TernaryPost val1 val2 val3 = runPost val1 val2 val3
runTernaryBuiltin TernaryDateFromDMY dVal mVal yVal = do
  dNum <- expectNumber dVal
  mNum <- expectNumber mVal
  yNum <- expectNumber yVal
  dInt <- expectWhole "DATE_FROM_DMY expects integer day" dNum
  mInt <- expectWhole "DATE_FROM_DMY expects integer month" mNum
  yInt <- expectWhole "DATE_FROM_DMY expects integer year" yNum
  case Time.fromGregorianValid yInt (fromInteger mInt) (fromInteger dInt) of
    Just day -> continueBackward (ValDate day)
    Nothing ->
      userException $ UserError $
        "DATE_FROM_DMY produced an invalid date from day="
        <> Text.pack (show dInt) <> ", month=" <> Text.pack (show mInt) <> ", year=" <> Text.pack (show yInt)
runTernaryBuiltin TernaryTimeFromHMS hVal mVal sVal = do
  hNum <- expectNumber hVal
  mNum <- expectNumber mVal
  sNum <- expectNumber sVal
  hInt <- expectWhole "TIME_FROM_HMS expects integer hour" hNum
  mInt <- expectWhole "TIME_FROM_HMS expects integer minute" mNum
  let sPico = realToFrac sNum :: Pico
  if hInt >= 0 && hInt < 24 && mInt >= 0 && mInt < 60 && sPico >= 0 && sPico < 60
    then continueBackward $ ValTime (TimeOfDay (fromInteger hInt) (fromInteger mInt) sPico)
    else userException $ UserError "TIME_FROM_HMS: values out of range (H: 0-23, M: 0-59, S: 0-59)"
runTernaryBuiltin TernaryDatetimeFromDTZ dateVal timeVal tzVal = do
  day <- expectDateValue dateVal
  tod <- expectTimeValue timeVal
  tzName <- expectString tzVal
  case tryLoadTZPure tzName of
    Just tz -> do
      let localTime = LocalTime day tod
          utc = TZ.localTimeToUTCTZ tz localTime
      continueBackward $ ValDateTime utc tzName
    Nothing ->
      userException $ UserError $ "Unknown timezone: '" <> tzName <> "'. Use an IANA timezone name like \"Asia/Singapore\" or \"America/New_York\"."
runTernaryBuiltin TernaryEverBetween startVal endVal predicate =
  startEverBetween startVal endVal predicate
runTernaryBuiltin TernaryAlwaysBetween startVal endVal predicate =
  startAlwaysBetween startVal endVal predicate

runBinOp :: BinOp -> WHNF -> WHNF -> Machine Config
runBinOp BinOpPlus   (ValNumber num1) (ValNumber num2)           = continueBackward $ ValNumber (num1 + num2)
runBinOp BinOpMinus  (ValNumber num1) (ValNumber num2)           = continueBackward $ ValNumber (num1 - num2)
runBinOp BinOpTimes  (ValNumber num1) (ValNumber num2)           = continueBackward $ ValNumber (num1 * num2)
runBinOp BinOpDividedBy (ValNumber num1) (ValNumber num2)        = do
  if num2 /= 0
    then continueBackward $ ValNumber (num1 / num2)
    else userException (DivisionByZero BinOpDividedBy)
runBinOp BinOpModulo    (ValNumber num1) (ValNumber num2)      = do
  n1 <- expectInteger BinOpModulo num1
  n2 <- expectInteger BinOpModulo num2
  if n2 /= 0
    then continueBackward $ ValNumber (toRational $ n1 `mod` n2)
    else userException (DivisionByZero BinOpModulo)
runBinOp BinOpExponent  (ValNumber base) (ValNumber exp_)   =
  let result = (fromRational base :: Double) ** (fromRational exp_ :: Double)
  in if isNaN result || isInfinite result
       then userException $ UserError "TO THE POWER OF produced a non-finite result (overflow, 0 to a negative power, or a negative base raised to a fractional power)"
       else continueBackward $ ValNumber (toRational result)
runBinOp BinOpTrunc (ValNumber value) (ValNumber digits) =
  let digitsInt = round digits :: Integer
      scale k = (10 :: Rational) ^^ k
      truncated =
        if digitsInt >= 0
          then
            let factor = scale digitsInt
            in fromInteger (truncate (value * factor)) / factor
          else
            let factor = scale (abs digitsInt)
            in fromInteger (truncate (value / factor)) * factor
  in continueBackward $ ValNumber truncated
runBinOp BinOpEquals val1             val2                       = runBinOpEquals val1 val2
runBinOp BinOpLeq    (ValNumber num1) (ValNumber num2)           = continueBackward $ ValBool (num1 <= num2)
runBinOp BinOpLeq    (ValString str1) (ValString str2)           = continueBackward $ ValBool (str1 <= str2)
runBinOp BinOpLeq    (ValBool b1)     (ValBool b2)               = continueBackward $ ValBool (b1 <= b2)
runBinOp BinOpLeq    (ValDate d1)     (ValDate d2)               = continueBackward $ ValBool (d1 <= d2)
runBinOp BinOpLeq    (ValTime t1)     (ValTime t2)               = continueBackward $ ValBool (t1 <= t2)
runBinOp BinOpLeq    (ValDateTime u1 _) (ValDateTime u2 _)       = continueBackward $ ValBool (u1 <= u2)
runBinOp BinOpGeq    (ValNumber num1) (ValNumber num2)           = continueBackward $ ValBool (num1 >= num2)
runBinOp BinOpGeq    (ValString str1) (ValString str2)           = continueBackward $ ValBool (str1 >= str2)
runBinOp BinOpGeq    (ValBool b1)     (ValBool b2)               = continueBackward $ ValBool (b1 >= b2)
runBinOp BinOpGeq    (ValDate d1)     (ValDate d2)               = continueBackward $ ValBool (d1 >= d2)
runBinOp BinOpGeq    (ValTime t1)     (ValTime t2)               = continueBackward $ ValBool (t1 >= t2)
runBinOp BinOpGeq    (ValDateTime u1 _) (ValDateTime u2 _)       = continueBackward $ ValBool (u1 >= u2)
runBinOp BinOpLt     (ValNumber num1) (ValNumber num2)           = continueBackward $ ValBool (num1 < num2)
runBinOp BinOpLt     (ValString str1) (ValString str2)           = continueBackward $ ValBool (str1 < str2)
runBinOp BinOpLt     (ValBool b1)     (ValBool b2)               = continueBackward $ ValBool (b1 < b2)
runBinOp BinOpLt     (ValDate d1)     (ValDate d2)               = continueBackward $ ValBool (d1 < d2)
runBinOp BinOpLt     (ValTime t1)     (ValTime t2)               = continueBackward $ ValBool (t1 < t2)
runBinOp BinOpLt     (ValDateTime u1 _) (ValDateTime u2 _)       = continueBackward $ ValBool (u1 < u2)
runBinOp BinOpGt     (ValNumber num1) (ValNumber num2)           = continueBackward $ ValBool (num1 > num2)
runBinOp BinOpGt     (ValString str1) (ValString str2)           = continueBackward $ ValBool (str1 > str2)
runBinOp BinOpGt     (ValBool b1)     (ValBool b2)               = continueBackward $ ValBool (b1 > b2)
runBinOp BinOpGt     (ValDate d1)     (ValDate d2)               = continueBackward $ ValBool (d1 > d2)
runBinOp BinOpGt     (ValTime t1)     (ValTime t2)               = continueBackward $ ValBool (t1 > t2)
runBinOp BinOpGt     (ValDateTime u1 _) (ValDateTime u2 _)       = continueBackward $ ValBool (u1 > u2)
-- String binary operations
runBinOp BinOpContains   (ValString haystack) (ValString needle) = continueBackward $ ValBool (needle `Text.isInfixOf` haystack)
runBinOp BinOpStartsWith (ValString text) (ValString prefix)     = continueBackward $ ValBool (prefix `Text.isPrefixOf` text)
runBinOp BinOpEndsWith   (ValString text) (ValString suffix)     = continueBackward $ ValBool (suffix `Text.isSuffixOf` text)
runBinOp BinOpIndexOf    (ValString haystack) (ValString needle)
  | Text.null needle = continueBackward $ ValNumber 0  -- empty string found at position 0
  | otherwise =
    let (before, match) = Text.breakOn needle haystack
    in if Text.null match
       then continueBackward $ ValNumber (-1)  -- not found
       else continueBackward $ ValNumber (fromIntegral $ Text.length before)
-- SPLIT: STRING → STRING → LIST OF STRING
runBinOp BinOpSplit      (ValString text) (ValString delim) = do
  -- Text.splitOn returns [Text], convert to ValCons/ValNil list with proper allocation
  let parts = Text.splitOn delim text
  listVal <- textListToWHNF parts
  continueBackward listVal
-- CHARAT: STRING → NUMBER → STRING
runBinOp BinOpCharAt     (ValString text) (ValNumber idx) =
  let i = floor idx :: Int
  in if i < 0 || i >= Text.length text
     then continueBackward $ ValString ""  -- Out of bounds returns empty string
     else continueBackward $ ValString (Text.singleton (Text.index text i))
runBinOp BinOpWhenLast startVal predicateVal = startWhenLast startVal predicateVal
runBinOp BinOpWhenNext startVal predicateVal = startWhenNext startVal predicateVal
runBinOp BinOpValueAt dateVal attrVal = startValueAt dateVal attrVal
runBinOp _op         (ValAssumed r) _e2                          = stuckOnAssumed r
runBinOp _op         _e1 (ValAssumed r)                          = stuckOnAssumed r
runBinOp _           _                _                          = internalException (RuntimeTypeError "running bin op with invalid operation / value combination")

runBinOpEquals :: WHNF -> WHNF -> Machine Config
runBinOpEquals (ValNumber num1)        (ValNumber num2) = continueBackward $ valBool $ num1 == num2
runBinOpEquals (ValString str1)        (ValString str2) = continueBackward $ valBool $ str1 == str2
runBinOpEquals (ValDate d1)            (ValDate d2) = continueBackward $ valBool $ d1 == d2
runBinOpEquals (ValTime t1)            (ValTime t2) = continueBackward $ valBool $ t1 == t2
runBinOpEquals (ValDateTime u1 _)      (ValDateTime u2 _) = continueBackward $ valBool $ u1 == u2
runBinOpEquals ValNil                  ValNil           = continueBackward $ valBool True
runBinOpEquals (ValCons r1 rs1)        (ValCons r2 rs2) = do
  pushFrame (EqConstructor1 r2 [(rs1, rs2)])
  continueRef r1
runBinOpEquals ValNil                  (ValCons _ _)   = continueBackward $ ValBool False
runBinOpEquals (ValCons _ _)           ValNil           = continueBackward $ ValBool False
runBinOpEquals (ValConstructor n1 rs1) (ValConstructor n2 rs2)
  | sameResolved n1 n2 && length rs1 == length rs2 =
    let
      pairs = zip rs1 rs2
    in
      case pairs of
        [] -> continueBackward $ ValBool True
        ((r1, r2) : rss) -> do
          pushFrame (EqConstructor1 r2 rss)
          continueRef r1
  | otherwise                                           = continueBackward $ ValBool False
-- TODO: we probably also want to check ValObligations for equality
runBinOpEquals (ValAssumed r)          _                = stuckOnAssumed r
runBinOpEquals v1                       v2              = userException (EqualityOnUnsupportedType v1 v2)

infinityDay :: Time.Day
infinityDay = Time.fromGregorian 9999 12 31

applyDatePredicate :: WHNF -> Time.Day -> Machine Config
applyDatePredicate predicate day = do
  argRef <- allocateValue (ValDate day)
  pushFrame (App1 [argRef] Nothing)
  continueBackward predicate

-- NOTE (T6): the getTemporalContext calls in the iterator starters below are
-- frame plumbing (save/override), not context observations. The per-day
-- contexts override only the currently-latent tcValidTime/tcRule* axes, so
-- fingerprinted caches deliberately remain valid across iteration days.
startEverBetween :: WHNF -> WHNF -> WHNF -> Machine Config
startEverBetween startVal endVal predicate = do
  startDay <- expectDateValue startVal
  endDay <- expectDateValue endVal
  case compare startDay endDay of
    GT -> continueBackward (valBool False)
    _ -> do
      originalCtx <- getTemporalContext
      let step = if startDay <= endDay then 1 else -1
          ctxForDay = applyEvalClauses [UnderValidTime startDay, UnderRulesEffectiveAt startDay] originalCtx
      putTemporalContext ctxForDay
      pushFrame (EverBetweenFrame originalCtx predicate endDay startDay step)
      applyDatePredicate predicate startDay

startAlwaysBetween :: WHNF -> WHNF -> WHNF -> Machine Config
startAlwaysBetween startVal endVal predicate = do
  startDay <- expectDateValue startVal
  endDay <- expectDateValue endVal
  case compare startDay endDay of
    GT -> continueBackward (valBool True)
    _ -> do
      originalCtx <- getTemporalContext
      let step = if startDay <= endDay then 1 else -1
          ctxForDay = applyEvalClauses [UnderValidTime startDay, UnderRulesEffectiveAt startDay] originalCtx
      putTemporalContext ctxForDay
      pushFrame (AlwaysBetweenFrame originalCtx predicate endDay startDay step)
      applyDatePredicate predicate startDay

startWhenLast :: WHNF -> WHNF -> Machine Config
startWhenLast startVal predicate = do
  startDay <- expectDateValue startVal
  originalCtx <- getTemporalContext
  let ctxForDay = applyEvalClauses [UnderValidTime startDay, UnderRulesEffectiveAt startDay] originalCtx
  putTemporalContext ctxForDay
  pushFrame (WhenLastFrame originalCtx predicate startDay)
  applyDatePredicate predicate startDay

startWhenNext :: WHNF -> WHNF -> Machine Config
startWhenNext startVal predicate = do
  startDay <- expectDateValue startVal
  originalCtx <- getTemporalContext
  let ctxForDay = applyEvalClauses [UnderValidTime startDay, UnderRulesEffectiveAt startDay] originalCtx
  putTemporalContext ctxForDay
  pushFrame (WhenNextFrame originalCtx predicate startDay infinityDay)
  applyDatePredicate predicate startDay

startValueAt :: WHNF -> WHNF -> Machine Config
startValueAt dateVal attrVal = do
  day <- expectDateValue dateVal
  originalCtx <- getTemporalContext
  let ctxForDay = applyEvalClauses [UnderValidTime day, UnderRulesEffectiveAt day] originalCtx
  putTemporalContext ctxForDay
  pushFrame (ValueAtFrame originalCtx)
  applyDatePredicate attrVal day

-- ---------------------------------------------------------------------------
-- Deep pinning (smucclaw/l4-ide#934)
--
-- An EVAL clause builtin used to restore the ambient temporal context as soon
-- as its argument reached WHNF. For a scalar that is exact (WHNF = NF), but a
-- constructor, record or list returned from under the pin carries UNFORCED
-- child thunks out of the scope, and those are forced later under the AMBIENT
-- context. The pin then silently did not hold for them: the reported symptom
-- was `EVAL UNDER RULES EFFECTIVE AT (Date 1 6 2023) (JUST `GST rate`)`
-- answering @JUST OF 9@ (today's regime) where the same expression without the
-- `JUST` answered @7@ (the pinned regime), with no diagnostic and identical
-- types.
--
-- RULING (recorded in specs/todo/TEMPORAL-RULE-VERSION-DESIGN.md §1.4.1): the
-- pin is DEEP. `EVAL UNDER … e` means "the value of @e@, computed under this
-- context", not "the outermost constructor of @e@".
--
-- FORCING ALONE IS NOT ENOUGH, and this is the whole subtlety. Deep-forcing
-- the result under the pin does NOT change the answer, because a child
-- reference of a pinned result is usually the SHARED module-level thunk
-- (@allocate_@ short-circuits a @Var@ argument to 'expectTerm' rather than
-- minting a fresh thunk). Forcing it under the pin installs a 'WHNFWhen'
-- cache fingerprinted on the pinned axes; when the printer forces it again
-- after the context is restored, T6's 'validFor' correctly rejects that cache
-- and RE-forces under the ambient context — back to the wrong answer. T6 is
-- doing its job; the value simply has to leave the scope.
--
-- So the pin runs in two passes, both while the pinned context is installed:
--
--   1. FORCE every reachable child ('driveDeepPin', an explicit worklist over
--      the frame stack, de-duplicated by 'Address'), to the same
--      'maximumStackSize' depth budget the printer uses.
--   2. SNAPSHOT ('snapshotRef'): rebuild the result with every reachable
--      reference replaced by a FRESH reference holding a plain 'WHNF' — a
--      context-independent, final cache that nothing will ever re-derive. The
--      originals are never mutated, so the rest of the program keeps its
--      sharing and its own context-sensitivity. Pass 2 forces nothing (pass 1
--      already did), so it is ordinary monadic recursion rather than more
--      frames, and it can carry a proper memo.
--
-- Reachability is 'Foldable' on 'Value', which is exactly what
-- 'L4.EvaluateLazy.nfAux' traverses — the same fields, and nothing inside a
-- 'ValClosure' or 'ValEnvironment' (whose environments are not @a@-shaped).
--
-- Three boundaries, all deliberate:
--
--   * CLOSURES are opaque to both passes, as they are to 'nfAux'. A function
--     returned from under a pin still reads the AMBIENT context when it is
--     later applied: a pin cannot follow a value into a scope it does not
--     dominate. Asserted by case I of the fixture.
--   * A BACK-EDGE into a force we are still inside ('blackholedHere') is
--     skipped rather than forced, so a self-referential value whose recursion
--     runs through the pin keeps printing instead of raising "Infinite loop".
--   * Beyond the depth budget the original reference is kept, exactly where
--     the printer would have printed @…@ anyway.
--
-- The cost is strictness: a field the consumer never demands is now forced,
-- so an error or a divergence hiding in an undemanded field of a pinned
-- result becomes reachable. Measured against the corpus, nothing in the tree
-- relies on that laziness.

-- | Pass 1 entry: force @val@'s reachable children while the pinned context is
-- still installed. The 'DeepPinRestore' frame pushed underneath restores
-- @originalCtx@ once pass 2 has handed the snapshot back.
startDeepPin :: TemporalContext -> WHNF -> Machine Config
startDeepPin originalCtx val = do
  pushFrame (DeepPinRestore originalCtx)
  driveDeepPin (toList val) maximumStackSize Set.empty [] val

-- | One step of pass 1. @kids@ are the children of the value just forced,
-- which sat at depth @d@; @seen@ are the addresses already scheduled;
-- @pending@ is the rest of the worklist; @result@ is the pinned value, handed
-- to pass 2 once the worklist drains.
driveDeepPin :: [Reference] -> Int -> Set Address -> [(Int, Reference)] -> WHNF -> Machine Config
driveDeepPin kids d seen pending result =
  step seen ([ (d - 1, r) | d > 0, r <- kids ] <> pending)
  where
    step :: Set Address -> [(Int, Reference)] -> Machine Config
    step _seen [] = do
      (_memo, snapshot) <- snapshotVal maximumStackSize Map.empty result
      continueBackward snapshot
    step seen' ((d', r) : rest)
      | r.address `Set.member` seen' = step seen' rest
      | otherwise = do
          backEdge <- blackholedHere r
          let seen'' = Set.insert r.address seen'
          if backEdge
            then step seen'' rest
            else do
              pushFrame (DeepPinStep d' seen'' rest result)
              continueRef r

-- | Pass 2 on a value: replace each child reference by its snapshot,
-- threading the memo left to right. Forces nothing.
snapshotVal :: Int -> Map Address Reference -> WHNF -> Machine (Map Address Reference, WHNF)
snapshotVal d memo0 val = do
  (memo', rs) <- mapAccumLM (snapshotRef d) memo0 (toList val)
  pure (memo', refill rs val)
  where
    -- 'Traversable' and 'Foldable' agree on order, so refilling in list order
    -- is the exact inverse of 'toList'.
    refill :: [Reference] -> WHNF -> WHNF
    refill rs v = evalState (traverse (const next) v) rs
      where
        next = state \ case
          (x : xs) -> (x, xs)
          []       -> error "internal error: deep pin snapshot lost a reference"

    mapAccumLM :: Monad m => (s -> a -> m (s, b)) -> s -> [a] -> m (s, [b])
    mapAccumLM f = go
      where
        go s []       = pure (s, [])
        go s (x : xs) = do
          (s', y) <- f s x
          (s'', ys) <- go s' xs
          pure (s'', y : ys)

-- | Pass 2 on a reference. Returns a FRESH reference holding a plain 'WHNF'
-- of the snapshotted value, so the pinned answer can never be re-derived
-- under a later context. The original reference is left untouched.
--
-- Three cases keep the original reference instead: the depth budget is spent;
-- the thunk is still 'Unevaluated' (pass 1 skipped it as a back-edge); or the
-- address is already in the memo, in which case its snapshot is reused so
-- sharing and cycles in the pinned value survive as sharing and cycles in the
-- snapshot. The memo is seeded with a placeholder BEFORE recursing, which is
-- what makes a cycle terminate.
snapshotRef :: Int -> Map Address Reference -> Reference -> Machine (Map Address Reference, Reference)
snapshotRef d memo r
  | Just r' <- Map.lookup r.address memo = pure (memo, r')
  | d <= 0 = pure (memo, r)
  | otherwise = do
      thunk <- readThunk r
      case thunk of
        Unevaluated {}   -> pure (memo, r)
        WHNF v           -> freeze v
        WHNFWhen _ v _ _ -> freeze v
  where
    freeze v = do
      r' <- allocateValue v
      let memo' = Map.insert r.address r' memo
      (memo'', v') <- snapshotVal (d - 1) memo' v
      liftIO (writeIORef r'.pointer (WHNF v'))
      pure (memo'', r')

-- | Is this thunk currently being forced by THIS thread?
--
-- Such a reference is a back-edge into a force we are still inside: a
-- self-referential value whose recursion runs THROUGH the pin, e.g.
-- @xs MEANS EVAL UNDER … (1 FOLLOWED BY xs)@. Forcing it would raise the
-- blackhole \"Infinite loop detected\" error, where before the deep pin the
-- child was simply carried out unforced and the printer expanded it to its
-- own depth budget. Leaving it alone keeps that behaviour: the deep pin must
-- not turn a program that printed into a program that errors.
--
-- This is the only child the walk skips. A ref blackholed by a DIFFERENT
-- thread is another evaluation's business and 'continueRef' already handles
-- it.
blackholedHere :: Reference -> Machine Bool
blackholedHere r = do
  tid <- liftIO myThreadId
  thunk <- readThunk r
  pure $ case thunk of
    Unevaluated tids _ _ -> tid `Set.member` tids
    WHNF {}              -> False
    WHNFWhen {}          -> False

pattern ValFulfilled :: Value a
pattern ValFulfilled <- (fulfilView -> True)
  where
    ValFulfilled = ValConstructor TypeCheck.fulfilRef []

pattern ValEvent :: a -> a -> a -> Value a
pattern ValEvent p a t <- (eventCView -> Just (p, a, t))
  where
    ValEvent p a t = ValConstructor TypeCheck.eventCRef [p, a, t]

eventCView :: Value a -> Maybe (a, a, a)
eventCView (ValConstructor n [p, a, t]) | n `sameResolved` TypeCheck.eventCRef = pure (p, a, t)
eventCView _ = Nothing

fulfilView :: Value a -> Bool
fulfilView v
  | ValConstructor r [] <- v = r `sameResolved` TypeCheck.fulfilRef
  | otherwise = False

pattern ValBool :: Bool -> Value a
pattern ValBool b <- (boolView -> Just b)
  where
    ValBool b = valBool b

valBool :: Bool -> Value a
valBool False = falseVal
valBool True  = trueVal

-- | Checks if a value is a Boolean constructor.
boolView :: Value a -> Maybe Bool
boolView val =
  case val of
    ValConstructor n []
      | sameResolved n TypeCheck.trueRef  -> Just True
      | sameResolved n TypeCheck.falseRef -> Just False
    _ -> Nothing

sameResolved :: Resolved -> Resolved -> Bool
sameResolved r1 r2 =
  getUnique r1 == getUnique r2

def :: Name -> Machine Resolved
def n = do
  u <- newUnique
  pure (Def u n)

ref :: Name -> Resolved -> Machine Resolved
ref n a =
  let
    (u, o) = getUniqueName a
  in
    pure (Ref n u o)


lookupTerm :: Environment -> Resolved -> Maybe Reference
lookupTerm env r =
  Map.lookup (getUnique r) env

expectTerm :: Environment -> Resolved -> Machine Reference
expectTerm env r =
  case lookupTerm env r of
    Nothing -> internalException (RuntimeScopeError r)
    Just rf -> pure rf

updateThunk :: Reference -> Thunk -> Machine ()
updateThunk rf !thunk = pokeThunk rf \_ _ -> (thunk, ())

updateThunkToWHNF :: Reference -> WHNF -> Machine ()
updateThunkToWHNF rf v =
  updateThunk rf (WHNF v)

-- | Write back a context-DEPENDENT force result (T6), tagged with the reads
-- made during the force. The expr\/env are recovered from the blackholed
-- thunk itself so it can be re-forced when the fingerprint no longer matches
-- the current temporal context. If another thread\/session already completed
-- the thunk, keep theirs: a plain 'WHNF' implies a read-free
-- (context-independent) force, and a 'WHNFWhen' revalidates at serve time.
updateThunkToWHNFWhen :: Reference -> CtxReads -> WHNF -> Machine ()
updateThunkToWHNFWhen rf fp v =
  pokeThunk rf \_tid -> \ case
    Unevaluated _tids e env -> (WHNFWhen fp v e env, ())
    other                   -> (other, ())

-- NOTE: Once we start evaluating a thunk, we store the (Haskell) thread
-- that does so. If we encounter a thunk with such an entry created by
-- ourselves, we treat it as a blackhole: we tried to evaluate the thunk
-- again recursively, which means we're in a loop. If the evaluation was
-- triggered by a different thread though (in our case, this basically
-- means from a different module, then it's not necessarily a loop. We could
-- just wait (which is what GHC does), but we just try to evaluate it as
-- well, which should be benign.
evalRef :: Reference -> Machine Config
evalRef rf = do
  -- Fast path: plain-WHNF thunk updates are monotonic (Unevaluated ->
  -- Unevaluated with more blackhole marks, or Unevaluated -> WHNF, never
  -- back), so a thunk observed in WHNF is final and can be returned from a
  -- plain read, without the atomic read-modify-write and the 'myThreadId'
  -- call. Context-dependent caches ('WHNFWhen', T6) are validated against
  -- the current temporal context before being served; genuinely unevaluated
  -- (or stale) thunks take the atomic path below.
  thunk0 <- readThunk rf
  case thunk0 of
    WHNF val -> whnfConfig val
    WHNFWhen fp val _ _ -> do
      -- Lock-free serve: the fingerprint and the context are both
      -- effectively thread-local reads; a mismatch merely routes through
      -- the atomic path. Serving records the fingerprint into the current
      -- span, so a consuming thunk INHERITS the dependency.
      tc <- getTemporalContext
      if validFor tc fp
        then noteCtxRead fp >> whnfConfig val
        else forceIt
    Unevaluated{} -> forceIt
  where
    forceIt :: Machine Config
    forceIt = do
      -- Read the context BEFORE the atomic poke (the poke fn must stay pure).
      tc <- getTemporalContext
      join $ pokeThunk rf \tid -> \ case
        thunk@(WHNF val) ->
          -- Another thread finished it between our read and the atomic poke.
          (thunk, whnfConfig val)
        thunk@(WHNFWhen fp val e env)
          | validFor tc fp -> (thunk, noteCtxRead fp >> whnfConfig val)
          | otherwise ->
              -- Stale for the current temporal context: re-force under it.
              -- The displaced cache travels on the UpdateThunk frame so an
              -- aborted force can put it back ('restoreThunkOnUnwind').
              (Unevaluated (Set.singleton tid) e env, beginForce (Just (fp, val)) e env)
        thunk@(Unevaluated tids e env)
          | tid `Set.member` tids ->  (thunk, userException (BlackholeForced e))
          | otherwise -> (Unevaluated (Set.insert tid tids) e env, beginForce Nothing e env)
    beginForce :: Maybe (CtxReads, WHNF) -> Expr Resolved -> Environment -> Machine Config
    beginForce displaced e env = do
      -- Open a fresh read span for this force; the enclosing span's
      -- accumulator travels on the UpdateThunk frame and is merged back
      -- (together with this force's reads) in 'backward'.
      saved <- swapCtxReads noReads
      pushFrame (UpdateThunk rf saved displaced)
      continueExpr env e
    whnfConfig :: WHNF -> Machine Config
    whnfConfig val =
      case val of
        ValNullaryBuiltinFun fn -> do
          -- Nullary builtins (TIMEZONE, TODAY, NOW, CURRENTTIME) are stored
          -- as function values and (re-)evaluated on every serve because
          -- their results depend on the mutable TemporalContext. Evaluation
          -- routes through the instrumented readTc* readers, recording the
          -- observation into the CURRENT force span — which is exactly how
          -- an ordinary thunk whose body mentions TODAY ends up carrying a
          -- 'CtxReads' fingerprint (see 'UpdateThunk' / 'WHNFWhen').
          evaluated <- evalNullaryBuiltin fn
          continueBackward evaluated
        _ ->
          continueBackward val

-- | Recursive pre-allocation, used for mutually recursive let-bindings / declarations.
preAllocate :: [Resolved] -> Machine Environment
preAllocate ns = do
  pairs <- traverse preAllocateRef ns
  pure (Map.fromList pairs)

allocate_ :: Expr Resolved -> Environment -> Machine Reference
allocate_ (Var _ann n) env = do
  -- special case where we do not actually need to allocate
  --
  -- NOT extended to auto-apply a discharged import (see
  -- 'dischargedImportClosure'). Allocating the application here instead of
  -- sharing the cell fixes an operand-position reference across an IMPORT, but
  -- it also fires on every RECORD CONSTRUCTOR: a @DECLARE@'s field names are
  -- module-level selectors, so a constructor's parameters are keys in its own
  -- captured environment exactly as a discharged reader's are, and the guard
  -- cannot tell them apart. Measured 2026-09-05 on the sweep corpus:
  -- @legal\/promissory-note.l4@ and @legal\/regcf\/regcf.l4@ both went red with
  -- \"expected a function but found: Money OF ...\". See the operand-position
  -- limitation recorded in IMPLICIT-PROPS-DESIGN.md.
  expectTerm env n
allocate_ expr env =
  fst <$> allocateRecursive expr (const env)

-----------------------------------------------------------------------------
-- Prescanning and evaluation of modules
-----------------------------------------------------------------------------

evalModule :: Environment -> Module Resolved -> Machine (Environment, [EvalDirective])
evalModule env (MkModule _ann _uri section) = do
  names <- scanSection section
  env' <- preAllocate names
  let combinedEnv = Map.union env' env
  directives <- evalSection combinedEnv section
  pure (env', directives)

-- | Doesn't do any actual evaluation, just performs allocations
-- and returns the environment containing all the new bindings.
evalRecLocalDecls :: Environment -> [LocalDecl Resolved] -> Machine Environment
evalRecLocalDecls env decls = do
  names <- concat <$> traverse scanLocalDecl decls
  env' <- preAllocate names
  let combinedEnv = Map.union env' env
  traverse_ (evalLocalDecl combinedEnv) decls
  pure env'

-- | Just collect all defined names; could plausibly be done generically.
scanSection :: Section Resolved -> Machine [Resolved]
scanSection (MkSection _ann _mn _maka _ topdecls) =
  concat <$> traverse scanTopDecl topdecls

-- | Just collect all defined names; could plausibly be done generically.
scanTopDecl :: TopDecl Resolved -> Machine [Resolved]
scanTopDecl (Declare _ann declare) =
  scanDeclare declare
scanTopDecl (Decide _ann decide) =
  scanDecide decide
scanTopDecl (Assume _ann assume) =
  scanAssume assume
scanTopDecl (Section _ann section) =
  scanSection section
scanTopDecl (Directive _ann _directive) =
  pure []
scanTopDecl (Import _ann _import_) =
  pure []
scanTopDecl (Timezone _ann _expr) =
  pure []

-- | Just collect all defined names; could plausibly be done generically.
scanLocalDecl :: LocalDecl Resolved -> Machine [Resolved]
scanLocalDecl (LocalDecide _ann decide) =
  scanDecide decide
scanLocalDecl (LocalAssume _ann assume) =
  scanAssume assume

scanDecide :: Decide Resolved -> Machine [Resolved]
scanDecide (MkDecide _ann _tysig (MkAppForm _ n _ _) _expr) = pure [n]

scanAssume :: Assume Resolved -> Machine [Resolved]
scanAssume (MkAssume _ann _tysig (MkAppForm _ n _ _) _t _mTypically) = pure [n]

-- | The only run-time names a type declaration brings into scope are constructors and selectors.
scanDeclare :: Declare Resolved -> Machine [Resolved]
scanDeclare (MkDeclare _ann _tysig _appFormAka t) = scanTypeDecl t

scanTypeDecl :: TypeDecl Resolved -> Machine [Resolved]
scanTypeDecl (EnumDecl _ann conDecls) =
  concat <$> traverse scanConDecl conDecls
scanTypeDecl (RecordDecl _ann mcon tns) =
  concat <$> traverse (\ c -> scanConDecl (MkConDecl emptyAnno c tns)) (toList mcon)
scanTypeDecl (SynonymDecl _ann _t) =
  pure []
scanTypeDecl (OpaqueDecl _ann) =
  pure []

scanConDecl :: ConDecl Resolved -> Machine [Resolved]
scanConDecl (MkConDecl _ann n [])  = pure [n]
scanConDecl (MkConDecl _ann n tns) = pure (n : ((\ (MkTypedName _ n' _ _ _) -> n') <$> tns))

evalSection :: Environment -> Section Resolved -> Machine [EvalDirective]
evalSection env (MkSection _ann _mn _maka _ topdecls) =
  concat <$> traverse (evalTopDecl env) topdecls

evalTopDecl :: Environment -> TopDecl Resolved -> Machine [EvalDirective]
evalTopDecl env (Declare _ann declare) =
  [] <$ evalDeclare env declare
evalTopDecl env (Decide _ann decide) =
  [] <$ evalDecide env decide
evalTopDecl env (Assume _ann assume) =
  [] <$ evalAssume env assume
evalTopDecl env (Directive _ann directive) =
  evalDirective env directive
evalTopDecl env (Section _ann section) =
  evalSection env section
evalTopDecl _env (Import _ann _import_) =
  pure []
evalTopDecl env (Timezone _ann expr) = do
  -- Extract timezone string from the expression and set it in TemporalContext.
  -- We store the timezone name without eagerly validating it here, because a
  -- userException at module level aborts ALL evaluation (including unrelated
  -- #EVAL directives).  Validation happens lazily when TODAY / CURRENTTIME is
  -- actually used, where the error is caught per-directive and surfaced as a
  -- proper diagnostic.
  mTzName <- extractTimezoneString env expr
  case mTzName of
    Just tzName -> do
      -- Persistent context WRITE, not an observation (see T6). No ambient
      -- mirror is needed: fingerprinted caches revalidate against whatever
      -- the context is at serve time, so thunks forced before a mid-module
      -- TIMEZONE IS are correctly invalidated after it.
      tc <- getTemporalContext
      putTemporalContext tc { tcDocumentTimezone = Just tzName }
    Nothing ->
      userException $ UserError
        "TIMEZONE IS must be a string literal or a simple identifier that resolves to a string."
  pure []

evalDirective :: Environment -> Directive Resolved -> Machine [EvalDirective]
evalDirective env (LazyEval ann expr) = do
  tracePolicy <- getTracePolicy
  let shouldTrace = case tracePolicy.evalDirectiveTrace of
        TracePolicy.NoTrace -> False
        TracePolicy.CollectTrace _ -> True
  pure [MkEvalDirective (rangeOf ann) shouldTrace NotAnAssert expr env]
evalDirective env (LazyEvalTrace ann expr) = do
  tracePolicy <- getTracePolicy
  let shouldTrace = case tracePolicy.evaltraceDirectiveTrace of
        TracePolicy.NoTrace -> False
        TracePolicy.CollectTrace _ -> True
  pure [MkEvalDirective (rangeOf ann) shouldTrace NotAnAssert expr env]
evalDirective _env (Check _ann _expr) =
  pure []
evalDirective env (Contract ann expr t evs) =
  evalDirective env . LazyEval ann =<< contractToEvalDirective expr t evs
evalDirective env (Assert ann expr) = do
  tracePolicy <- getTracePolicy
  let shouldTrace = case tracePolicy.evalDirectiveTrace of
        TracePolicy.NoTrace -> False
        TracePolicy.CollectTrace _ -> True
  pure [MkEvalDirective (rangeOf ann) shouldTrace AssertHolds expr env]
evalDirective env (AssertRefused ann expr mmsg) = do
  tracePolicy <- getTracePolicy
  let shouldTrace = case tracePolicy.evalDirectiveTrace of
        TracePolicy.NoTrace -> False
        TracePolicy.CollectTrace _ -> True
  -- The BECAUSE message is a literal, so the comparison the directive asks for
  -- is decided statically here rather than evaluated.
  --
  -- 'Nothing' here means "the directive imposes no constraint on the reason",
  -- so the wildcard MUST be unreachable for a payload the author wrote: a
  -- payload we cannot read would otherwise become an assertion that holds for
  -- every refusal reason. Two upstream checks make it so -- 'Parser.directive'
  -- accepts only a 'lit' after BECAUSE, and 'TypeCheck.inferDirective' requires
  -- that literal to be a STRING -- which leaves the wildcard reachable only for
  -- a module that never type-checked. If you widen either of those, decide what
  -- an unreadable payload means before you land it.
  let wanted = case mmsg of
        Just (Lit _ (StringLit _ t)) -> Just t
        _                            -> Nothing
  pure [MkEvalDirective (rangeOf ann) shouldTrace (AssertRefuses wanted) expr env]

contractToEvalDirective :: Expr Resolved -> Expr Resolved -> [Expr Resolved] -> Machine (Expr Resolved)
contractToEvalDirective contract t evs = do
  pure $ App emptyAnno TypeCheck.evalContractRef [contract, t, evListExpr]
  where
  -- A trace is a SET of timestamped facts that must be processed in time order.
  -- STABLE-sort the authored #TRACE/EVALTRACE WITH event list by AT (nondecreasing),
  -- preserving authored order for equal timestamps. This is the single point where the
  -- event stream is built and handed to residuation, so it uniformly governs all
  -- RAND/ROR strands. A stable sort of an already-monotonic trace is the identity, and
  -- we do NOT touch the deadline/blame logic: sorting makes its "earlier events already
  -- seen" assumption hold.
  --
  -- We only reorder genuine literal-AT 'Event' nodes relative to one another. Entries
  -- whose AT is not a literal at parse time (e.g. @`WAIT UNTIL` 100@, which is a runtime
  -- @Number -> Event@ application, or an already-desugared event) carry no extractable
  -- key and stay PINNED in their authored positions -- 'sortByStablePinned' never moves
  -- an unkeyed element. This is why we use a comparison that only orders when both keys
  -- are present, rather than a plain @sortOn@ (which would float unkeyed entries to one
  -- end and scramble positional markers like WAIT UNTIL).
  evListExpr = List emptyAnno $ map eventExpr (sortByStablePinned eventAtKey evs)

-- | Sort key for an authored event: the literal AT timestamp as a 'Rational'.
-- Non-literal or already-desugared events yield 'Nothing'.
eventAtKey :: Expr Resolved -> Maybe Rational
eventAtKey (Event _ann (MkEvent _ _ _ (Lit _ (NumericLit _ r)) _)) = Just r
eventAtKey _ = Nothing

-- | A stable sort by a partial key that leaves every element whose key is 'Nothing'
-- pinned at its original index. Keyed elements ('Just') are stably sorted by their key
-- among themselves and then poured back into the non-pinned slots in that sorted order;
-- equal keys preserve authored order. Unkeyed elements (e.g. @`WAIT UNTIL` 100@, whose
-- AT is not a parse-time literal) never move, so positional markers are preserved.
-- For an all-keyed, already-monotonic list this is the identity.
sortByStablePinned :: Ord k => (a -> Maybe k) -> [a] -> [a]
sortByStablePinned key xs =
  let keyed  = [ (k, x) | x <- xs, Just k <- [key x] ]
      sorted = map snd (sortOn fst keyed)   -- stable sort of just the keyed elements
  in  refill sorted xs
  where
    refill _      []       = []
    refill sorted (x : rest) = case key x of
      Nothing -> x : refill sorted rest                       -- pinned slot
      Just _  -> case sorted of
        (s : ss) -> s : refill ss rest
        []       -> x : refill [] rest                        -- unreachable

eventExpr :: Expr Resolved -> Expr Resolved
eventExpr (Event _ann ev) = desugarEvent ev
eventExpr o = o -- NOTE: we must assume that the event is already desugared

desugarEvent :: Event Resolved -> Expr Resolved
desugarEvent (MkEvent ann party act timestamp _atFirst) = App ann TypeCheck.eventCRef [party, act, timestamp]

evalLocalDecl :: Environment -> LocalDecl Resolved -> Machine ()
evalLocalDecl env (LocalDecide _ann decide) =
  evalDecide env decide
evalLocalDecl env (LocalAssume _ann assume) =
  evalAssume env assume

-- We are assuming that the environment already contains an entry with an address for us.
evalAssume :: Environment -> Assume Resolved -> Machine ()
evalAssume env (MkAssume _ann _tysig (MkAppForm _ n []   _maka) _ _) =
  updateTerm env n (WHNF (ValAssumed n))
evalAssume env (MkAssume _ann _tysig (MkAppForm _ n _args _maka) _ _) = do
  -- TODO: we should create a given here yielding an assumed, but we currently cannot do that easily,
  -- because we do not have Assumed as an expression, and we also cannot embed values into expressions.
  updateTerm env n (WHNF (ValAssumed n))

-- NOTE (T6): writes module-eval-time closures/ValAssumed/Unevaluated bodies,
-- not force results — deliberately unfingerprinted.
updateTerm :: Environment -> Resolved -> Thunk -> Machine ()
updateTerm env n thunk = do
  rf <- expectTerm env n
  updateThunk rf thunk

-- We are assuming that the environment already contains an entry with an address for us.
evalDecide :: Environment -> Decide Resolved -> Machine ()
evalDecide env (MkDecide _ann _tysig (MkAppForm _ n []   _maka) expr) =
  updateTerm env n (Unevaluated Set.empty expr env)
evalDecide env (MkDecide _ann _tysig (MkAppForm _ n args _maka) expr) = do
  let
    v = ValClosure (MkGivenSig emptyAnno ((\ r -> MkOptionallyTypedName emptyAnno r Nothing Nothing) <$> args)) expr env
  updateTerm env n (WHNF v)

-- We are assuming that the environment already contains an entry with an address for us.
evalDeclare :: Environment -> Declare Resolved -> Machine ()
evalDeclare env (MkDeclare _ann _tysig _appFormAka t) =
  evalTypeDecl env t

evalTypeDecl :: Environment -> TypeDecl Resolved -> Machine ()
evalTypeDecl env (EnumDecl _ann conDecls) =
  traverse_ (evalConDecl env) conDecls
evalTypeDecl env (RecordDecl _ann mcon tns) =
  traverse_ (\ c -> evalConDecl env (MkConDecl emptyAnno c tns)) mcon
evalTypeDecl _env (SynonymDecl _ann _t) =
  pure ()
evalTypeDecl _env (OpaqueDecl _ann) =
  pure ()

evalConDecl :: Environment -> ConDecl Resolved -> Machine ()
evalConDecl env (MkConDecl _ann n []) =
  updateTerm env n (WHNF (ValConstructor n []))
evalConDecl env (MkConDecl _ann n tns) = do
  -- constructor
  updateTerm env n (WHNF (ValUnappliedConstructor n))
  conRef <- ref (TypeCheck.getName n) n
  -- selectors (we need to create fresh names for the lambda abstractions so that every binder is unique)
  traverse_ (\ (i, MkTypedName _ sn _t _ _) -> do
    arg    <- def (TypeCheck.getName n)
    argRef <- ref (TypeCheck.getName n) arg
    args <- traverse (def . TypeCheck.getName) tns
    body <- ref (TypeCheck.getName sn) (args !! i)
    let
      sel =
        ValClosure
          (MkGivenSig emptyAnno [MkOptionallyTypedName emptyAnno arg Nothing Nothing])      -- \ x ->
          (Consider emptyAnno (App emptyAnno argRef [])                             -- case x of
            [ MkBranch emptyAnno (When emptyAnno (PatApp emptyAnno conRef (PatVar emptyAnno <$> args)))  --   Con y_1 ... y_n ->
                (App emptyAnno body [])                                             --     y_i
            ]
          )
          emptyEnvironment
    updateTerm env sn (WHNF sel)
    ) (zip [0 ..] tns)

-----------------------------------------------------------------------------
-- Premade expressions and values
-----------------------------------------------------------------------------

falseExpr :: Expr Resolved
falseExpr = App emptyAnno TypeCheck.falseRef []

falseVal :: Value a
falseVal = ValConstructor TypeCheck.falseRef []

trueExpr :: Expr Resolved
trueExpr = App emptyAnno TypeCheck.trueRef []

trueVal :: Value a
trueVal = ValConstructor TypeCheck.trueRef []

fulfilExpr :: Expr Resolved
fulfilExpr = App emptyAnno TypeCheck.fulfilRef []

-- \a b c. a b c
evalContractVal :: Machine (Value a)
evalContractVal = do
  let mn = MkName emptyAnno . NormalName
      (na, nb, nc) = (mn "a", mn "b", mn "c")
  ad <- def na
  bd <- def nb
  cd <- def nc
  ar <- ref na ad
  br <- ref nb bd
  cr <- ref nc cd

  pure $ ValClosure
    (MkGivenSig emptyAnno
      [ MkOptionallyTypedName emptyAnno ad Nothing Nothing
      , MkOptionallyTypedName emptyAnno bd Nothing Nothing
      , MkOptionallyTypedName emptyAnno cd Nothing Nothing
      ]
    )
    (App emptyAnno ar [App emptyAnno br [], App emptyAnno cr []])
    emptyEnvironment

waitUntilVal :: Reference -> Reference -> Reference -> Machine (Value a)
waitUntilVal eventcRef neverMatchesPartyRef neverMatchesActRef = do
  let an = MkName emptyAnno $ NormalName "a"
  ad <- def an
  ar <- ref an ad
  pure $ ValClosure
    (MkGivenSig emptyAnno [MkOptionallyTypedName emptyAnno ad Nothing Nothing])
    (App emptyAnno TypeCheck.eventCRef [neverMatchesPartyExpr, neverMatchesActExpr, Var emptyAnno ar])
    (Map.fromList
      [ (TypeCheck.eventCUnique, eventcRef)
      , (TypeCheck.neverMatchesPartyUnique, neverMatchesPartyRef)
      , (TypeCheck.neverMatchesActUnique, neverMatchesActRef)
      ]
    )

pattern ValNeverMatchesParty, ValNeverMatchesAct :: Value a
pattern ValNeverMatchesParty <- (\case ValConstructor r [] -> r `sameResolved` TypeCheck.neverMatchesPartyRef; _ -> False -> True)
  where ValNeverMatchesParty = ValConstructor TypeCheck.neverMatchesPartyRef []
pattern ValNeverMatchesAct <- (\case ValConstructor r [] -> r `sameResolved` TypeCheck.neverMatchesActRef; _ -> False -> True)
  where ValNeverMatchesAct = ValConstructor TypeCheck.neverMatchesActRef []

neverMatchesPartyExpr, neverMatchesActExpr :: Expr Resolved
neverMatchesPartyExpr = App emptyAnno TypeCheck.neverMatchesPartyRef []
neverMatchesActExpr = App emptyAnno TypeCheck.neverMatchesActRef []

-- EVENT :: party -> act -> Number -> EVENT party act
eventCVal :: Value a
eventCVal = ValUnappliedConstructor TypeCheck.eventCRef

emptyEnvironment :: Environment
emptyEnvironment = Map.empty

-- | What kind of assertion (if any) a directive is.
--
-- Replaces a bare @isAssert :: Bool@, so that adding @#ASSERT REFUSED@ made
-- every consumer decide what it means rather than inheriting the plain
-- assertion's answer.
data AssertKind
  = NotAnAssert
    -- ^ @#EVAL@ \/ @#EVALTRACE@ \/ @#TRACE@: reduce and report the value.
  | AssertHolds
    -- ^ @#ASSERT e@: @e@ must evaluate to TRUE.
  | AssertRefuses !(Maybe Text)
    -- ^ @#ASSERT REFUSED e [BECAUSE m]@: @e@ must refuse, and when @m@ is
    -- present the refusal's reason must equal it.
  deriving stock (Generic, Show)

data EvalDirective =
  MkEvalDirective
    { range    :: Maybe SrcRange -- ^ of the (L)EVAL directive
    , trace    :: !Bool -- ^ whether a trace is wanted
    , assertKind :: !AssertKind -- ^ whether, and how, it is to be treated as an assertion
    , expr     :: !(Expr Resolved) -- ^ expression to evaluate
    , env      :: !Environment -- ^ environment to evaluate the expression in
    }
  deriving stock (Generic, Show)

-----------------------------------------------------------------------------
-- Prettyprinting of the EvalExceptions
-----------------------------------------------------------------------------

-- The initial environment has to be built by pre-allocation.
initialEnvironment :: Machine Environment
initialEnvironment = do
  falseRef <- allocateValue falseVal
  trueRef  <- allocateValue trueVal
  nilRef   <- allocateValue ValNil
  nothingRef <- allocateValue (ValConstructor TypeCheck.nothingRef [])
  justRef <- allocateValue (ValUnappliedConstructor TypeCheck.justRef)
  leftRef <- allocateValue (ValUnappliedConstructor TypeCheck.leftRef)
  rightRef <- allocateValue (ValUnappliedConstructor TypeCheck.rightRef)
  evalContractRef <- allocateValue =<< evalContractVal
  eventCRef <- allocateValue eventCVal
  isIntegerRef <- allocateValue (ValUnaryBuiltinFun UnaryIsInteger)
  roundRef <- allocateValue (ValUnaryBuiltinFun UnaryRound)
  ceilingRef <- allocateValue (ValUnaryBuiltinFun UnaryCeiling)
  floorRef <- allocateValue (ValUnaryBuiltinFun UnaryFloor)
  sqrtRef <- allocateValue (ValUnaryBuiltinFun UnarySqrt)
  lnRef <- allocateValue (ValUnaryBuiltinFun UnaryLn)
  log10Ref <- allocateValue (ValUnaryBuiltinFun UnaryLog10)
  sinRef <- allocateValue (ValUnaryBuiltinFun UnarySin)
  cosRef <- allocateValue (ValUnaryBuiltinFun UnaryCos)
  tanRef <- allocateValue (ValUnaryBuiltinFun UnaryTan)
  asinRef <- allocateValue (ValUnaryBuiltinFun UnaryAsin)
  acosRef <- allocateValue (ValUnaryBuiltinFun UnaryAcos)
  atanRef <- allocateValue (ValUnaryBuiltinFun UnaryAtan)
  -- String unary builtins
  stringLengthRef <- allocateValue (ValUnaryBuiltinFun UnaryStringLength)
  toUpperRef <- allocateValue (ValUnaryBuiltinFun UnaryToUpper)
  toLowerRef <- allocateValue (ValUnaryBuiltinFun UnaryToLower)
  trimRef <- allocateValue (ValUnaryBuiltinFun UnaryTrim)
  toStringRef <- allocateValue (ValUnaryBuiltinFun UnaryToString)
  toNumberRef <- allocateValue (ValUnaryBuiltinFun UnaryToNumber)
  toDateRef <- allocateValue (ValUnaryBuiltinFun UnaryToDate)
  -- TIME builtins
  timeHourRef <- allocateValue (ValUnaryBuiltinFun UnaryTimeHour)
  timeMinuteRef <- allocateValue (ValUnaryBuiltinFun UnaryTimeMinute)
  timeSecondRef <- allocateValue (ValUnaryBuiltinFun UnaryTimeSecond)
  timeToSerialRef <- allocateValue (ValUnaryBuiltinFun UnaryTimeToSerial)
  timeFromSerialRef <- allocateValue (ValUnaryBuiltinFun UnaryTimeFromSerial)
  timeFromHMSRef <- allocateValue (ValTernaryBuiltinFun TernaryTimeFromHMS)
  toTimeRef <- allocateValue (ValUnaryBuiltinFun UnaryToTime)
  -- DATETIME builtins
  datetimeDateRef <- allocateValue (ValUnaryBuiltinFun UnaryDatetimeDate)
  datetimeTimeRef <- allocateValue (ValUnaryBuiltinFun UnaryDatetimeTime)
  datetimeSerialRef <- allocateValue (ValUnaryBuiltinFun UnaryDatetimeSerial)
  datetimeTzNameRef <- allocateValue (ValUnaryBuiltinFun UnaryDatetimeTzName)
  datetimeFromDTZRef <- allocateValue (ValTernaryBuiltinFun TernaryDatetimeFromDTZ)
  toDatetimeRef <- allocateValue (ValUnaryBuiltinFun UnaryToDatetime)
  -- TIMEZONE nullary builtin
  timezoneRef <- allocateValue (ValNullaryBuiltinFun NullaryTimezone)
  -- Ternary string builtins
  substringRef <- allocateValue (ValTernaryBuiltinFun TernarySubstring)
  replaceRef <- allocateValue (ValTernaryBuiltinFun TernaryReplace)
  -- IO/JSON builtins from main
  fetchRef <- allocateValue (ValUnaryBuiltinFun UnaryFetch)
  envRef <- allocateValue (ValUnaryBuiltinFun UnaryEnv)
  jsonEncodeRef <- allocateValue (ValUnaryBuiltinFun UnaryJsonEncode)
  jsonDecodeRef <- allocateValue (ValUnaryBuiltinFun UnaryJsonDecode)
  todayRef <- allocateValue (ValNullaryBuiltinFun NullaryTodaySerial)
  nowRef <- allocateValue (ValNullaryBuiltinFun NullaryNowSerial)
  currentTimeRef <- allocateValue (ValNullaryBuiltinFun NullaryCurrentTime)
  rulesEffectiveDateRef <- allocateValue (ValNullaryBuiltinFun NullaryRulesEffectiveDate)
  dateFromTextRef <- allocateValue (ValUnaryBuiltinFun UnaryDateValue)
  dateSerialRef <- allocateValue (ValUnaryBuiltinFun UnaryDateSerial)
  dateFromSerialRef <- allocateValue (ValUnaryBuiltinFun UnaryDateFromSerial)
  dateFromDMYRef <- allocateValue (ValTernaryBuiltinFun TernaryDateFromDMY)
  dateDayRef <- allocateValue (ValUnaryBuiltinFun UnaryDateDay)
  dateMonthRef <- allocateValue (ValUnaryBuiltinFun UnaryDateMonth)
  dateYearRef <- allocateValue (ValUnaryBuiltinFun UnaryDateYear)
  timeValueRef <- allocateValue (ValUnaryBuiltinFun UnaryTimeValue)
  everBetweenRef <- allocateValue (ValTernaryBuiltinFun TernaryEverBetween)
  alwaysBetweenRef <- allocateValue (ValTernaryBuiltinFun TernaryAlwaysBetween)
  -- Temporal context switching entry (handled specially by the evaluator)
  evalAsOfSystemTimeRef <- allocateValue (ValAssumed TypeCheck.evalAsOfSystemTimeRef)
  evalUnderValidTimeRef <- allocateValue (ValAssumed TypeCheck.evalUnderValidTimeRef)
  evalUnderRulesEffectiveAtRef <- allocateValue (ValAssumed TypeCheck.evalUnderRulesEffectiveAtRef)
  evalUnderRulesEncodedAtRef <- allocateValue (ValAssumed TypeCheck.evalUnderRulesEncodedAtRef)
  fulfilRef <- allocateValue ValFulfilled
  neverMatchesPartyRef <- allocateValue ValNeverMatchesParty
  neverMatchesActRef <- allocateValue ValNeverMatchesAct
  waitUntilRef <- allocateValue =<< waitUntilVal eventCRef neverMatchesPartyRef neverMatchesActRef
  andRef <- allocateValue =<< andValClosure trueRef falseRef
  orRef <- allocateValue =<< orValClosure trueRef falseRef
  impliesRef <- allocateValue =<< impliesValClosure trueRef falseRef
  notRef <- allocateValue =<< notValClosure trueRef falseRef

  builtinBinOpRefs <-
    traverse
      (\(funVal, uniq) -> do
        r <- allocateValue $ ValBinaryBuiltinFun funVal
        pure (uniq, r)
      )
      builtinBinOps

  pure $
    Map.fromList $
      [ (TypeCheck.falseUnique, falseRef)
      , (TypeCheck.trueUnique,  trueRef)
      , (TypeCheck.emptyUnique, nilRef)
      , (TypeCheck.nothingUnique, nothingRef)
      , (TypeCheck.justUnique, justRef)
      , (TypeCheck.leftUnique, leftRef)
      , (TypeCheck.rightUnique, rightRef)
      , (TypeCheck.evalContractUnique, evalContractRef)
      , (TypeCheck.eventCUnique, eventCRef)
      , (TypeCheck.fulfilUnique, fulfilRef)
      , (TypeCheck.isIntegerUnique, isIntegerRef)
      , (TypeCheck.roundUnique, roundRef)
      , (TypeCheck.ceilingUnique, ceilingRef)
      , (TypeCheck.floorUnique, floorRef)
      , (TypeCheck.sqrtUnique, sqrtRef)
      , (TypeCheck.lnUnique, lnRef)
      , (TypeCheck.log10Unique, log10Ref)
      , (TypeCheck.sinUnique, sinRef)
      , (TypeCheck.cosUnique, cosRef)
      , (TypeCheck.tanUnique, tanRef)
      , (TypeCheck.asinUnique, asinRef)
      , (TypeCheck.acosUnique, acosRef)
      , (TypeCheck.atanUnique, atanRef)
      , (TypeCheck.fetchUnique, fetchRef)
      , (TypeCheck.envUnique, envRef)
      , (TypeCheck.jsonEncodeUnique, jsonEncodeRef)
      , (TypeCheck.jsonDecodeUnique, jsonDecodeRef)
      , (TypeCheck.todaySerialUnique, todayRef)
      , (TypeCheck.nowSerialUnique, nowRef)
      , (TypeCheck.currentTimeUnique, currentTimeRef)
      , (TypeCheck.rulesEffectiveDateUnique, rulesEffectiveDateRef)
      , (TypeCheck.dateFromTextUnique, dateFromTextRef)
      , (TypeCheck.dateSerialUnique, dateSerialRef)
      , (TypeCheck.dateFromSerialUnique, dateFromSerialRef)
      , (TypeCheck.dateFromDMYUnique, dateFromDMYRef)
      , (TypeCheck.dateDayUnique, dateDayRef)
      , (TypeCheck.dateMonthUnique, dateMonthRef)
      , (TypeCheck.dateYearUnique, dateYearRef)
      , (TypeCheck.timeValueFractionUnique, timeValueRef)
      , (TypeCheck.everBetweenUnique, everBetweenRef)
      , (TypeCheck.alwaysBetweenUnique, alwaysBetweenRef)
      , (TypeCheck.evalAsOfSystemTimeUnique, evalAsOfSystemTimeRef)
      , (TypeCheck.evalUnderValidTimeUnique, evalUnderValidTimeRef)
      , (TypeCheck.evalUnderRulesEffectiveAtUnique, evalUnderRulesEffectiveAtRef)
      , (TypeCheck.evalUnderRulesEncodedAtUnique, evalUnderRulesEncodedAtRef)
      , (TypeCheck.waitUntilUnique, waitUntilRef)
      , (TypeCheck.andUnique, andRef)
      , (TypeCheck.orUnique, orRef)
      , (TypeCheck.impliesUnique, impliesRef)
      , (TypeCheck.notUnique, notRef)
      -- String unary builtins
      , (TypeCheck.stringLengthUnique, stringLengthRef)
      , (TypeCheck.toUpperUnique, toUpperRef)
      , (TypeCheck.toLowerUnique, toLowerRef)
      , (TypeCheck.trimUnique, trimRef)
      , (TypeCheck.toStringUnique, toStringRef)
      , (TypeCheck.toNumberUnique, toNumberRef)
      , (TypeCheck.toDateUnique, toDateRef)
      -- TIME builtins
      , (TypeCheck.timeHourUnique, timeHourRef)
      , (TypeCheck.timeMinuteUnique, timeMinuteRef)
      , (TypeCheck.timeSecondUnique, timeSecondRef)
      , (TypeCheck.timeToSerialUnique, timeToSerialRef)
      , (TypeCheck.timeFromSerialUnique, timeFromSerialRef)
      , (TypeCheck.timeFromHMSUnique, timeFromHMSRef)
      , (TypeCheck.toTimeUnique, toTimeRef)
      -- DATETIME builtins
      , (TypeCheck.datetimeDateUnique, datetimeDateRef)
      , (TypeCheck.datetimeTimeUnique, datetimeTimeRef)
      , (TypeCheck.datetimeSerialUnique, datetimeSerialRef)
      , (TypeCheck.datetimeTzNameUnique, datetimeTzNameRef)
      , (TypeCheck.datetimeFromDTZUnique, datetimeFromDTZRef)
      , (TypeCheck.toDatetimeUnique, toDatetimeRef)
      -- TIMEZONE
      , (TypeCheck.timezoneUnique, timezoneRef)
      -- Ternary string functions
      , (TypeCheck.substringUnique, substringRef)
      , (TypeCheck.replaceUnique, replaceRef)
      ]
      <> builtinBinOpRefs

builtinBinOps :: [(BinOp, Unique)]
builtinBinOps =
  [ (val, unique)
  | (val, uniques) <-
      [ (BinOpLt,        TypeCheck.ltUniques)
      , (BinOpLeq,       TypeCheck.leqUniques)
      , (BinOpGt,        TypeCheck.gtUniques)
      , (BinOpGeq,       TypeCheck.geqUniques)
      , (BinOpPlus,      [TypeCheck.plusUnique])
      , (BinOpMinus,     [TypeCheck.minusUnique])
      , (BinOpTimes,     [TypeCheck.timesUnique])
      , (BinOpDividedBy, [TypeCheck.divideUnique])
      , (BinOpModulo,    [TypeCheck.moduloUnique])
      , (BinOpExponent,  [TypeCheck.exponentUnique])
      , (BinOpTrunc,     [TypeCheck.truncUnique])
      , (BinOpCons,      [TypeCheck.consUnique])
      , (BinOpEquals,    [TypeCheck.equalsUnique])
      -- String binary operations
      , (BinOpContains,   [TypeCheck.containsUnique])
      , (BinOpStartsWith, [TypeCheck.startsWithUnique])
      , (BinOpEndsWith,   [TypeCheck.endsWithUnique])
      , (BinOpIndexOf,    [TypeCheck.indexOfUnique])
      , (BinOpSplit,      [TypeCheck.splitUnique])
      , (BinOpCharAt,     [TypeCheck.charAtUnique])
      , (BinOpWhenLast,   [TypeCheck.whenLastUnique])
      , (BinOpWhenNext,   [TypeCheck.whenNextUnique])
      , (BinOpValueAt,    [TypeCheck.valueAtUnique])
      ]
  , unique <- uniques
  ]

----------------------------------------------------------------------------
-- Clock & parsing utilities
----------------------------------------------------------------------------

-- NOTE (T6): all temporal-context access here goes through the instrumented
-- readTc* readers so the observation is recorded into the current force
-- span (see the READER CONTRACT on 'TemporalContext'). The error branches
-- (missing TIMEZONE) throw before any thunk write-back, so their reads are
-- moot but harmless.
evalNullaryBuiltin :: NullaryBuiltinFun -> Machine WHNF
evalNullaryBuiltin = \case
  NullaryTodaySerial -> do
    sysTime <- readTcSystemTime
    mTzName <- readTcDocumentTimezone
    case mTzName of
      Just tzName -> do
        mTz <- liftIO $ tryLoadTZ (Text.unpack tzName)
        case mTz of
          Just tz -> do
            let localTime = TZ.utcToLocalTimeTZ tz sysTime
                todayDay = localDay localTime
            pure $ ValDate todayDay
          Nothing ->
            userException $ UserError $
              "Could not load timezone '" <> tzName <> "' for TODAY."
      Nothing ->
        userException $ UserError
          "TIMEZONE is not declared. TODAY requires 'TIMEZONE IS \"<IANA timezone>\"' in your document."
  NullaryNowSerial -> do
    sysTime <- readTcSystemTime
    mTzName <- readTcDocumentTimezone
    let tzName = fromMaybe "Etc/UTC" mTzName
    pure $ ValDateTime sysTime tzName
  NullaryTimezone -> do
    mTzName <- readTcDocumentTimezone
    case mTzName of
      Just tzName -> pure $ ValString tzName
      Nothing ->
        userException $ UserError
          "TIMEZONE is not declared. Add 'TIMEZONE IS \"<IANA timezone>\"' to your document."
  NullaryCurrentTime -> do
    sysTime <- readTcSystemTime
    mTzName <- readTcDocumentTimezone
    case mTzName of
      Just tzName -> do
        mTz <- liftIO $ tryLoadTZ (Text.unpack tzName)
        case mTz of
          Just tz -> do
            let localTime = TZ.utcToLocalTimeTZ tz sysTime
                tod = localTimeOfDay localTime
            pure $ ValTime tod
          Nothing ->
            userException $ UserError $
              "Could not load timezone '" <> tzName <> "' for CURRENTTIME."
      Nothing ->
        userException $ UserError
          "TIMEZONE is not declared. CURRENTTIME requires 'TIMEZONE IS \"<IANA timezone>\"' in your document."
  NullaryRulesEffectiveDate -> do
    -- Resolve which version of the law is in force, reading axes through the
    -- instrumented readers so every observation (including pre-fallback
    -- @ReadEq Nothing@) lands in the current force span's fingerprint.
    -- Fallback order (option (b), see TEMPORAL-RULE-VERSION-DESIGN.md §6 Q1):
    --   1. tcRuleValidTime  — the rule-version axis, if explicitly pinned;
    --   2. tcValidTime      — else the fact/valid-time axis (law-time tracks
    --                         fact-time, matching the interval builtins);
    --   3. localized today  — else "the rules in force now" (same computation
    --                         as TODAY, via instrumented readers).
    mRuleDay <- readTcRuleValidTime
    case mRuleDay of
      Just day -> pure $ ValDate day
      Nothing -> do
        mValidDay <- readTcValidTime
        case mValidDay of
          Just day -> pure $ ValDate day
          Nothing -> do
            sysTime <- readTcSystemTime
            mTzName <- readTcDocumentTimezone
            case mTzName of
              Just tzName -> do
                mTz <- liftIO $ tryLoadTZ (Text.unpack tzName)
                case mTz of
                  Just tz -> do
                    let localTime = TZ.utcToLocalTimeTZ tz sysTime
                    pure $ ValDate (localDay localTime)
                  Nothing ->
                    userException $ UserError $
                      "Could not load timezone '" <> tzName <> "' for RULES EFFECTIVE DATE."
              Nothing ->
                userException $ UserError
                  "TIMEZONE is not declared. RULES EFFECTIVE DATE (with no EVAL UNDER RULES EFFECTIVE AT or EVAL UNDER VALID TIME in scope) requires 'TIMEZONE IS \"<IANA timezone>\"' in your document."

utcDatestamp :: Time.UTCTime -> Rational
utcDatestamp time =
  fromIntegral (dayNumberFromDay (Time.utctDay time))
    + diffTimeFraction (Time.utctDayTime time)

diffTimeFraction :: Time.DiffTime -> Rational
diffTimeFraction dt =
  let seconds :: Pico
      seconds = realToFrac dt
  in toRational seconds / secondsPerDay

-- | An instant, forced, lowered to the trace's clock: a NUMBER as it is; a
-- DATE by its serial — the same arithmetic as @DATE_SERIAL@, not a call
-- through it (an 'App' inserted into the AST would have no tokens and would
-- break exactprint). Used for an anchor (@WITHIN d OF …@, @AFTER d OF …@,
-- R-Q7C) and for the absolute edges (@AFTER date@, @BEFORE date@, R-X5).
--
-- A DATE is refused when the obligation's clock, at arming, reads an
-- instant that no calendar date has a serial for — anything below
-- @DATE_SERIAL (YMD 1 1 1)@ ('earliestDateSerial'), which is every trace
-- that starts @AT 0@. Until 2026-09-16 such a date was silently a serial in
-- the hundreds of thousands, so on an @AT 0@ trace every act was "in time"
-- for a @WITHIN 0 OF (YMD …)@ and every act would have been for a
-- @BEFORE (YMD …)@, exit 0 (EVERY-EACH-QUANTIFIER-SPEC §5.1.2.1, T1: the
-- origin is not declared at the contract level, and the sorts are not
-- separated — neither is built; this is the machine's answer meanwhile,
-- and it is a heuristic: a floating trace that starts at 365 or above is
-- not caught, and the doc page says so in one sentence). @what@ names the
-- edge for the refusal.
--
-- The lowering itself is 'anchorInstant', the one place it is defined (and
-- what "L4.Lts.WhatIf" reads an unforced anchored deadline through); this
-- is the machine's guard around it.
lowerInstant :: Text -> Reference -> WHNF -> Machine Rational
lowerInstant what armed v = do
  case v of
    ValDate d -> do
      armedT <- readThunk armed >>= \ case
        WHNF (ValNumber t)         -> pure (Just t)
        WHNFWhen _ (ValNumber t) _ _ -> pure (Just t)
        _                          -> pure Nothing
      -- the arming instant is a forced NUMBER on every path that reaches an
      -- edge ('App1' hands the frames the trace's clock); should it not be,
      -- the date is lowered without the check rather than refused for a
      -- reason that is not the drafter's
      case armedT of
        Just t | t < earliestDateSerial -> userException (UserError (floatingClockRefusal what d t))
        _ -> pure ()
    _ -> pure ()
  case anchorInstant v of
    Right t -> pure t
    Left _  -> internalException $ RuntimeTypeError $
      what <> " is expected to be a NUMBER or a DATE but got: " <> prettyLayout v

-- | The serial of the earliest calendar date, @DATE_SERIAL (YMD 1 1 1)@: a
-- clock reading below it is not on the date-serial scale ('lowerInstant').
earliestDateSerial :: Rational
earliestDateSerial = fromIntegral (dayNumberFromDay (Time.fromGregorian 1 1 1))

floatingClockRefusal :: Text -> Time.Day -> Rational -> Text
floatingClockRefusal what d t = Text.unwords
  [ what <> " names the date " <> Text.pack (Time.showGregorian d) <> ", but this obligation's clock"
  , "read " <> prettyRatio t <> " when it was entered, which is not a date serial (DATE_SERIAL"
  , "(YMD 1 1 1) is " <> prettyRatio earliestDateSerial <> "): the trace counts in floating"
  , "units from an origin such as 0, and a date has no place on that scale."
  , "Start the trace at a date serial — #TRACE … AT (DATE_SERIAL (YMD …)) with"
  , "the events stamped the same way — or write the edge as a duration."
  , "(EVERY-EACH-QUANTIFIER-SPEC section 5.1.2.1.)"
  ]

-- | R-X6's report (EVERY-EACH-QUANTIFIER-SPEC §5.1.2, RULED 2026-09-07):
-- the act came before the window opened, so it does not count — and the
-- run says so rather than swallowing it.
--
-- The act is printed through 'printActionPattern', the deontic-action
-- printer (PATTERN-REFERENCE-RULE-SPEC §6): a bare name the checker resolved
-- as a reference is printed bare, as the source spelled it. The generic
-- 'Pattern' printer would re-emit it as @(EXACTLY name)@, the deprecated
-- spelling, for a source that never wrote it.
earlyActNote :: DeonticModal -> NF -> Pattern Resolved -> Rational -> Rational -> Maybe Rational -> Text
earlyActNote modal partyNF actPat stamp open deadlineAt = Text.unwords $
  [ "PARTY " <> prettyLayout partyNF <> " did " <> Text.strip (docText (printActionPattern actPat))
  , "at " <> prettyRatio stamp <> ", before the window opened at " <> prettyRatio open <> ":"
  ] <> case modal of
    DMustNot ->
      [ "the prohibition had not started, so this is not a violation. It stays"
      , "in force" <> untilClose <> "." ]
    _ ->
      [ "the act does not count as performance. The obligation stays live, with"
      , "its deadline untouched" <> untilClose <> ", and may be performed once"
      , "the window is open. (EVERY-EACH-QUANTIFIER-SPEC section 5.1.2, R-X6.)" ]
  where
    untilClose = maybe "" (\ d -> " (the window closes at " <> prettyRatio d <> ")") deadlineAt

-- | The explicitly anchored empty window, met at run time (§5.1.2.2): the
-- offsets were not literals, so the checker could not see it.
emptyWindowNote :: Rational -> Rational -> Text
emptyWindowNote open close = Text.unwords
  [ "This window closes at " <> prettyRatio close <> ", before it opens at " <> prettyRatio open <> ":"
  , "both edges count from one anchor (the WITHIN names it, and the AFTER"
  , "counts from the same place), so no act can be performed in time. Drop"
  , "the anchor from the WITHIN to count it from the instant the window"
  , "opens, or make the closing offset at least the opening one."
  , "(EVERY-EACH-QUANTIFIER-SPEC section 5.1.2.2.)"
  ]

-- | A value as far as it has already been evaluated, for a note's wording:
-- references whose thunks are in WHNF are followed, anything still
-- unevaluated prints as @…@ ('Omitted'). Forces nothing, so it can be
-- called mid-step; a party that has just been matched against an event
-- ('runBinOpEquals' forces the fields it compares) prints whole.
peekNF :: WHNF -> Machine NF
peekNF = go (8 :: Int)
  where
    go 0 _ = pure Omitted
    go d v = MkNF <$> traverse (peekRef (d - 1)) v
    peekRef d r = readThunk r >>= \ case
      WHNF w           -> go d w
      WHNFWhen _ w _ _ -> go d w
      Unevaluated{}    -> pure Omitted

dayNumberFromDay :: Time.Day -> Integer
dayNumberFromDay day =
  Time.diffDays day l4EpochDay - 1

l4EpochDay :: Time.Day
l4EpochDay = Time.fromGregorian 0 1 1

secondsPerDay :: Rational
secondsPerDay = 86400

serialToUTCTime :: Rational -> Time.UTCTime
serialToUTCTime serial =
  -- `floor` (not `properFraction`/`truncate`) so the fractional part is always
  -- in [0,1): `properFraction` truncates toward zero, which for a negative
  -- serial yields a negative `fraction`, hence a negative DiffTime and an
  -- invalid UTCTime. `floor` == `truncate` for all non-negative serials, so
  -- this is behaviour-preserving on every real (all non-negative) input.
  let wholeDays = floor serial :: Integer
      fraction  = serial - fromInteger wholeDays
      day = Time.addDays (wholeDays + 1) l4EpochDay
      seconds :: Pico
      seconds = realToFrac (fraction * secondsPerDay)
  in Time.UTCTime day (realToFrac seconds)

dateFormats :: [String]
dateFormats =
  [ "%Y-%m-%d"
  , "%Y/%m/%d"
  , "%Y.%m.%d"
  , "%m/%d/%Y"
  , "%m-%d-%Y"
  , "%m/%d/%y"
  , "%m-%d-%y"
  , "%d/%m/%Y"
  , "%d-%m-%Y"
  , "%d.%m.%Y"
  , "%d-%b-%Y"
  , "%b %d, %Y"
  , "%d %b %Y"
  ]

toDateFormats :: [String]
toDateFormats =
  [ "%Y-%m-%d"
  , "%Y/%m/%d"
  , "%d-%b-%Y"
  , "%d/%m/%Y"
  , "%b %e, %Y"
  ]

parseNumberText :: Text -> Maybe Rational
parseNumberText raw =
  let trimmed = Text.strip raw
  in if Text.null trimmed
       then Nothing
       else do
         sci :: Sci.Scientific <- readMaybe (Text.unpack trimmed)
         pure (toRational sci)

parseDateText :: Text -> Maybe Time.Day
parseDateText raw =
  let trimmed = Text.strip raw
      variants = [trimmed, Text.toUpper trimmed, Text.toLower trimmed]
  in listToMaybe
       [ day
       | candidate <- variants
       , fmt <- toDateFormats
       , Just day <- [TimeFormat.parseTimeM True TimeFormat.defaultTimeLocale fmt (Text.unpack candidate)]
       , let (year, _, _) = Time.toGregorian day
       , year >= 1
       , year <= 9999
       ]

resolveMaybeInnerType :: Maybe (Type' Resolved) -> Machine (Maybe (Type' Resolved))
resolveMaybeInnerType Nothing = pure Nothing
resolveMaybeInnerType (Just ty) =
  case ty of
    TyApp _ maybeRef [inner]
      | nameToText (TypeCheck.getName maybeRef) == "MAYBE" -> pure (Just inner)
    _ -> pure Nothing

-- | Build a DATE value from a Time.Day. Since DATE is now a builtin type,
-- we simply wrap the day in ValDate.
buildDateValue :: Time.Day -> Maybe (Type' Resolved) -> Machine WHNF
buildDateValue day _mInner = pure $ ValDate day

parseDateValueText :: Text -> Either Text Time.Day
parseDateValueText rawInput =
  let trimmed = Text.strip rawInput
  in if Text.null trimmed
       then Left "DATEVALUE: input is empty."
        else
          case firstSuccessful trimmed of
            Nothing -> Left "DATEVALUE: could not parse date string."
            Just day -> Right day
  where
    firstSuccessful :: Text -> Maybe Time.Day
    firstSuccessful txt = go dateFormats
      where
        str = Text.unpack txt
        go = \case
          [] -> Nothing
          fmt : rest ->
            case TimeFormat.parseTimeM True TimeFormat.defaultTimeLocale fmt str of
              Just day -> Just day
              Nothing -> go rest

data AmPm = AM | PM

parseTimeValueText :: Text -> Either Text Rational
parseTimeValueText rawInput =
  let trimmed = Text.strip rawInput
  in if Text.null trimmed
        then Left "TIMEVALUE: input is empty."
        else do
          (timePortion, mSuffix) <- extractSuffix trimmed
          let pieces = Text.splitOn ":" timePortion
          case pieces of
            [hTxt, mTxt] -> buildTime hTxt mTxt "0" mSuffix
            [hTxt, mTxt, sTxt] -> buildTime hTxt mTxt sTxt mSuffix
            _ -> Left "TIMEVALUE: expected HH:MM or HH:MM:SS."

buildTime :: Text -> Text -> Text -> Maybe AmPm -> Either Text Rational
buildTime hTxt mTxt sTxt mSuffix = do
  hourRaw <- parseNatBound "hour" 0 99 hTxt
  minute <- parseNatBound "minute" 0 59 mTxt
  secondsVal <- parseSecondsPart sTxt
  hour24 <- case mSuffix of
    Nothing -> if hourRaw >= 0 && hourRaw < 24
                  then Right hourRaw
                  else Left "TIMEVALUE: hour must be between 0 and 23."
    Just AM ->
      if hourRaw >= 1 && hourRaw <= 12
        then Right (if hourRaw == 12 then 0 else hourRaw)
        else Left "TIMEVALUE: hour must be between 1 and 12 for AM."
    Just PM ->
      if hourRaw >= 1 && hourRaw <= 12
        then Right (if hourRaw == 12 then 12 else hourRaw + 12)
        else Left "TIMEVALUE: hour must be between 1 and 12 for PM."
  let totalSeconds =
        fromIntegral hour24 * 3600
          + fromIntegral minute * 60
          + secondsVal
  if totalSeconds < 0 || totalSeconds >= fromRational secondsPerDay
    then Left "TIMEVALUE: time must be less than 24 hours."
    else Right (toRational totalSeconds / secondsPerDay)

extractSuffix :: Text -> Either Text (Text, Maybe AmPm)
extractSuffix input =
  let trimmed = Text.dropWhileEnd Char.isSpace input
      letters = Text.takeWhileEnd Char.isLetter trimmed
      rest = Text.dropWhileEnd Char.isLetter trimmed
      base = Text.stripEnd rest
  in if Text.null letters
        then Right (base, Nothing)
        else case Text.toCaseFold letters of
          "am" -> Right (base, Just AM)
          "pm" -> Right (base, Just PM)
          _ -> Left "TIMEVALUE: unknown suffix; only AM/PM are supported."

parseNatBound :: Text -> Int -> Int -> Text -> Either Text Int
parseNatBound label lo hi txt =
  case TR.decimal txt of
    Right (value, rest)
      | Text.null rest && value >= lo && value <= hi -> Right value
      | Text.null rest -> Left (label <> " out of range.")
    _ -> Left ("TIMEVALUE: " <> label <> " must be numeric.")

parseSecondsPart :: Text -> Either Text Rational
parseSecondsPart txt =
  let (wholePart, fractionalPart) = Text.breakOn "." txt
  in do
    sec <- parseNatBound "second" 0 59 wholePart
    frac <-
      if Text.null fractionalPart
        then Right 0
        else do
          let digits = Text.drop 1 fractionalPart
          when (Text.null digits) $
            Left "TIMEVALUE: fractional seconds must have digits."
          fracInt <- parseDigits digits
          let denom = 10 ^ Text.length digits :: Integer
          pure (toRational fracInt / toRational denom)
    pure (fromIntegral sec + frac)

parseDigits :: Text -> Either Text Integer
parseDigits txt =
  if Text.all Char.isDigit txt
    then Right (Text.foldl' (\acc ch -> acc * 10 + toInteger (Char.digitToInt ch)) 0 txt)
    else Left "TIMEVALUE: expected only digits in fractional part."

----------------------------------------------------------------------------
-- Timezone utilities
----------------------------------------------------------------------------

-- | Try to load a TZ from the IANA database. Returns Nothing on failure.
tryLoadTZ :: String -> IO (Maybe TZ.TZ)
tryLoadTZ name =
  (Just <$> TZ.loadTZFromDB name) `catch` \(_ :: SomeException) ->
    -- Fall back to the embedded timezone database.  The system DB may be
    -- unavailable when the LSP runs inside VS Code or other sandboxed
    -- environments on macOS.
    pure $ TZAll.tzByLabel <$> TZAll.fromTZName (TE.encodeUtf8 (Text.pack name))

-- | Extract a timezone string from a TIMEZONE IS expression.
-- Handles string literals directly and simple identifiers by peeking at thunks.
extractTimezoneString :: Environment -> Expr Resolved -> Machine (Maybe Text)
extractTimezoneString _env (Lit _ (StringLit _ s)) = pure (Just s)
extractTimezoneString env (App _ nameRef []) = do
  case Map.lookup (getUnique nameRef) env of
    Just refId ->
      pokeThunk refId $ \_ thunk -> case thunk of
        WHNF (ValString s) -> (thunk, Just s)
        -- peek only (no read recorded): matches baseline behaviour of
        -- accepting a previously-forced cached string (see T6)
        WHNFWhen _ (ValString s) _ _ -> (thunk, Just s)
        Unevaluated _ (Lit _ (StringLit _ s)) _ -> (thunk, Just s)
        _ -> (thunk, Nothing)
    Nothing -> pure Nothing
extractTimezoneString _ _ = pure Nothing

-- | Parse a time string in HH:MM:SS or HH:MM format to TimeOfDay
parseTimeText :: Text -> Maybe TimeOfDay
parseTimeText raw =
  let trimmed = Text.strip raw
      formats = ["%H:%M:%S", "%H:%M:%S%Q", "%H:%M"]
  in listToMaybe
       [ tod
       | fmt <- formats
       , Just tod <- [TimeFormat.parseTimeM True TimeFormat.defaultTimeLocale fmt (Text.unpack trimmed)]
       ]

-- | Parse an ISO-8601 datetime string to UTCTime
parseDatetimeText :: Text -> Maybe UTCTime
parseDatetimeText raw =
  let trimmed = Text.strip raw
      formats =
        [ "%Y-%m-%dT%H:%M:%S%Z"
        , "%Y-%m-%dT%H:%M:%S%Q%Z"
        , "%Y-%m-%dT%H:%M:%SZ"
        , "%Y-%m-%dT%H:%M:%S%QZ"
        , "%Y-%m-%dT%H:%M:%S%z"
        , "%Y-%m-%dT%H:%M:%S%Q%z"
        , "%Y-%m-%d %H:%M:%S%Z"
        , "%Y-%m-%d %H:%M:%S%z"
        ]
  in listToMaybe
       [ utc
       | fmt <- formats
       , Just utc <- [TimeFormat.parseTimeM True TimeFormat.defaultTimeLocale fmt (Text.unpack trimmed)]
       ]

-- | Format a TimeOfDay as HH:MM:SS
formatTimeOfDay :: TimeOfDay -> Text
formatTimeOfDay tod =
  Text.pack $ TimeFormat.formatTime TimeFormat.defaultTimeLocale "%H:%M:%S" tod

-- | Format a 'UTCTime' as a plain ISO-8601 UTC string (e.g.
-- @2026-06-12T08:30:00Z@). Used for ledger provenance positions (M2), where we
-- only have the evaluation clock and no tz context.
formatUTCTimeIso :: UTCTime -> Text
formatUTCTimeIso utc =
  Text.pack $ TimeFormat.formatTime TimeFormat.defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" utc

-- | Format a UTCTime with timezone offset as ISO-8601
formatDateTimeIso :: UTCTime -> Text -> Text
formatDateTimeIso utc tzName =
  case tryLoadTZPure tzName of
    Just tz ->
      let localTime' = TZ.utcToLocalTimeTZ tz utc
          offset = TZ.timeZoneForUTCTime tz utc
          offsetStr = TimeFormat.formatTime TimeFormat.defaultTimeLocale "%z" offset
      in Text.pack (TimeFormat.formatTime TimeFormat.defaultTimeLocale "%Y-%m-%dT%H:%M:%S" localTime') <> Text.pack offsetStr
    Nothing ->
      -- Fallback: format as UTC
      Text.pack $ TimeFormat.formatTime TimeFormat.defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" utc

-- | Pure-ish wrapper for TZ loading (uses unsafePerformIO since TZ data is static)
tryLoadTZPure :: Text -> Maybe TZ.TZ
tryLoadTZPure name = unsafePerformIO $ tryLoadTZ (Text.unpack name)
{-# NOINLINE tryLoadTZPure #-}

-- | Extract TimeOfDay from a WHNF value
expectTimeValue :: WHNF -> Machine TimeOfDay
expectTimeValue (ValTime tod) = pure tod
expectTimeValue val = internalException $ RuntimeTypeError $
  "Expected TIME value but got: " <> prettyLayout val

-- | Extract UTCTime and timezone from a WHNF value
expectDateTimeValue :: WHNF -> Machine (UTCTime, Text)
expectDateTimeValue (ValDateTime utc tz) = pure (utc, tz)
expectDateTimeValue val = internalException $ RuntimeTypeError $
  "Expected DATETIME value but got: " <> prettyLayout val

boolBinOpClosure :: Reference -> Reference -> (Resolved -> Resolved -> Expr Resolved) -> Machine (Value a)
boolBinOpClosure true false buildExpr = do
  let
    mkName = MkName emptyAnno . NormalName
    na = mkName "a"
    nb = mkName "b"
  aDef <- def na
  bDef <- def nb
  aRef <- ref na aDef
  bRef <- ref nb bDef
  pure $ ValClosure
    (MkGivenSig emptyAnno
      [ MkOptionallyTypedName emptyAnno aDef (Just TypeCheck.boolean) Nothing
      , MkOptionallyTypedName emptyAnno bDef (Just TypeCheck.boolean) Nothing
      ])
    (buildExpr aRef bRef)
    ( Map.fromList
      [ (TypeCheck.trueUnique, true)
      , (TypeCheck.falseUnique, false)
      ]
    )

boolUnaryOpClosure :: Reference -> Reference -> (Resolved -> Expr Resolved) -> Machine (Value a)
boolUnaryOpClosure true false buildExpr = do
  let
    mkName = MkName emptyAnno . NormalName
    na = mkName "a"
  aDef <- def na
  aRef <- ref na aDef
  pure $ ValClosure
    (MkGivenSig emptyAnno
      [ MkOptionallyTypedName emptyAnno aDef (Just TypeCheck.boolean) Nothing
      ])
    (buildExpr aRef)
    ( Map.fromList
      [ (TypeCheck.trueUnique, true)
      , (TypeCheck.falseUnique, false)
      ]
    )

andValClosure :: Reference -> Reference -> Machine (Value a)
andValClosure true false =
  boolBinOpClosure true false
    (\aRef bRef ->
      IfThenElse emptyAnno
        (Var emptyAnno aRef)
        (Var emptyAnno bRef)
        falseExpr
    )

notValClosure :: Reference -> Reference -> Machine (Value a)
notValClosure true false =
  boolUnaryOpClosure true false
    (\aRef ->
      IfThenElse emptyAnno
        (Var emptyAnno aRef)
        falseExpr
        trueExpr
    )

orValClosure :: Reference -> Reference -> Machine (Value a)
orValClosure true false =
  boolBinOpClosure true false
    (\aRef bRef ->
      IfThenElse emptyAnno
        (Var emptyAnno aRef)
        trueExpr
        (Var emptyAnno bRef)
    )

impliesValClosure :: Reference -> Reference -> Machine (Value a)
impliesValClosure true false =
  boolBinOpClosure true false
    (\aRef bRef ->
      IfThenElse emptyAnno
        (Var emptyAnno aRef)
        (Var emptyAnno bRef)
        trueExpr
    )

----------------------------------------------------------------------------
-- JSON to Environment conversion for batch processing
----------------------------------------------------------------------------

-- | Write JSON values into existing References in the environment.
-- This should be called after preAllocate has created References for ASSUME'd variables.
-- The function looks up ASSUME'd variables by name from EntityInfo,
-- finds their References in the provided environment, and writes JSON values into them.
writeJSONToReferences :: Aeson.Value -> Environment -> Machine ()
writeJSONToReferences json env = case json of
  Aeson.Object obj -> do
    entityInfo <- getEntityInfo
    let assumedVars =
          [ (u, n, ty)
          | (u, (n, TypeCheck.KnownTerm ty Assumed)) <- Map.toList entityInfo
          ]
    forM_ assumedVars $ \(unique, name, ty) -> do
      let key = nameToText (TypeCheck.getName name)
      case KeyMap.lookup (Key.fromText key) obj of
        Nothing -> pure ()  -- No JSON value for this variable
        Just val -> do
          -- Look up the existing Reference for this variable
          case Map.lookup unique env of
            Nothing -> pure ()  -- No Reference found (shouldn't happen after preAllocate)
            Just existingRef -> do
              -- Convert JSON to WHNF and write into the existing Reference.
              -- NOTE (T6): deliberately a plain WHNF — externally injected
              -- batch input is a per-run constant, not a force result.
              whnf <- jsonValueToWHNFTyped val ty
              updateThunkToWHNF existingRef whnf
  _ -> pure ()
