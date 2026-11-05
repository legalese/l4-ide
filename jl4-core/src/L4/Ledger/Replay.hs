-- | The instance ledger's evaluator: rows, and perhaps one more event, as a
-- generated L4 module, type-checked once and replayed
-- (OPERATIONAL-LOWERING-SPEC §3.2).
--
-- The generated module is the deployment's source followed by one
-- @#TRACE@ whose lines are the rows ('L4.Ledger.Row.traceBlock'), and, when
-- an event is being tried, that event as its last line, spelled exactly as
-- the proposer sent it. That is the technique the service already uses for
-- runtime events (@jl4-service@'s @EVALTRACE@ wrapper), applied to a
-- @#TRACE@: runtime events reach the evaluator as source, never as a
-- 'Trace' value built from JSON.
--
-- The module is checked __once__, with the event in it, and both replays
-- run off that one check: the head (the directive with its last event
-- dropped) and the head with the event. Two separately checked modules
-- would carry different uniques and source ranges, so their step logs
-- would share no prefix, every step would look like the event's own, and
-- no event would ever read as passed over, silently.
--
-- The classification is "L4.Lts.WhatIf"'s, not a second one: 'classify' on
-- the replay's result, the act's own steps found by 'afterCommonPrefix',
-- pass-over by 'confirmProposed', a tick held to 'confirmTick'. What this
-- module does NOT do is 'tryCandidate': that replays a candidate's own
-- hypothetical, with the engine's witness for a binder and the last
-- event's stamp, where the ledger must replay the act as sent, at the
-- ledger's stamp (R-O4).
module L4.Ledger.Replay
  ( -- * A deployment
    Deployment (..)
    -- * Replays
  , Failure (..)
  , Replayed (..)
  , EventOutcome (..)
  , replay
  , positionAt
  , liftEvents
  , traceModule
  , failureText
    -- * Reading a replay's ledgers
  , officialCount
  , Commit (..)
  ) where

import Base
import qualified Base.DList as DList
import qualified Base.Map as Map
import qualified Base.Text as Text
import System.Timeout (timeout)
import Control.Exception (evaluate)

import L4.API.VirtualFS (checkWithImports, vfsFromList)
import L4.Evaluate.Ledger (LedgerEvent (..), LedgerStore (..), Path)
import L4.Evaluate.ValueLazy (Environment)
import L4.EvaluateLazy (EvalConfig, EvalDirectiveResult (..), execEvalModuleWithEnv)
import L4.EvaluateLazy.DeonticStep (DeonticStep)
import L4.Import.Resolution (ResolvedImport (..), TypeCheckWithDepsResult (..), extractImportNames)
import L4.Ledger.Row
import L4.Lts.List (TraceReport, reportFrom)
import L4.Lts.Marking (Blame (..), contextOf)
import L4.Lts.WhatIf
import L4.Print (prettyLayout)
import L4.Syntax
import qualified L4.TypeCheck as TypeCheck
import L4.TypeCheck (CheckResult (..))

-- | A contract as the ledger runs it: its source, the modules it imports
-- by name, and what a strict proposal is versioned against.
data Deployment = MkDeployment
  { deploymentId      :: !Text
  , deploymentVersion :: !Text
    -- ^ stamped on every row ('L4.Ledger.Row.ruleVersion')
  , deploymentSource  :: !Text
  , deploymentImports :: ![(Text, Text)]
    -- ^ each sibling module the source @IMPORT@s, by import name, with its
    -- source; @prelude@ and the other libraries are found as the type
    -- checker always finds them
  , versionedCells    :: ![Text]
    -- ^ the official cells whose version a strict proposal is checked
    -- against (§2: the resource, not the whole log); empty means the whole
    -- head, so a strict proposal conflicts on any append
  }
  deriving stock (Eq, Show)

-- | Why a replay gave no answer.
data Failure
  = Malformed !Text
    -- ^ the generated module did not parse or type-check: the event is not
    -- one the contract can be given (an act not of its action type, a party
    -- it does not know) or cannot be spelled as a line at all. 'Refused'.
  | Undecided !Text
    -- ^ the evaluator ran and could not decide (a refusal, an error, an
    -- undetermined residual, the time bound). 'Unknown'.
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | A replay, with what the ledger needs of it read out and forced, so the
-- time bound covers the evaluation and not only the call that starts it.
data Replayed = MkReplayed
  { headVerdict   :: !RowVerdict
    -- ^ what the rows came to, classified as an event's verdict would be
    -- (the opening's own row records this)
  , headSteps     :: ![DeonticStep]
  , headLedger    :: ![Text]
    -- ^ every ledger the head's replay wrote, one line per entry, in the
    -- words @l4 run@ prints, without the provenance stamp
  , headOfficial  :: ![Text]
    -- ^ the official record's entries alone
  , headCommits   :: ![Commit]
    -- ^ the same entries, as cells and values
  , headTerminal  :: !Bool
    -- ^ the head is already @FULFILLED@ or @BREACHED@
  , headDeadlines :: ![(Rational, Rational)]
    -- ^ each live deadline the head's marking can read, with the stamp of
    -- the tick past it ('candidatesOf', 'tickPast'); a deadline the marking
    -- cannot read offers no tick, as 'NoTick' says
  , outcome       :: !(Maybe EventOutcome)
    -- ^ the extra event's, when one was tried
  }
  deriving stock (Show, Generic)
  deriving anyclass NFData

data EventOutcome = MkEventOutcome
  { verdict  :: !RowVerdict
  , steps    :: ![DeonticStep]
    -- ^ the steps the event caused, past the head's
  , wrote    :: ![Text]
    -- ^ the entries the event's step appended, each ledger's in turn (the
    -- parties' own, then the official record), in 'ledgerLines'' words
  , ledger   :: ![Text]
  , official :: ![Text]
  , commits  :: ![Commit]
    -- ^ the official record's entries the event's step appended, and only
    -- those: 'wrote' less the parties' own ledgers, but as cells and values
    -- and not as the words @l4 run@ prints, so that nobody has to read a
    -- line to learn what was committed
  }
  deriving stock (Show, Generic)
  deriving anyclass NFData

-- | One entry the official record gained: the cell, as its name without
-- quoting, and the value in the words 'wrote' gives it.
data Commit = MkCommit
  { cell  :: !Text
  , value :: !Text
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | The generated module, checked, with the two directives the replays use.
data Checked = MkChecked
  { rigRows   :: !Rig
  , rowsTrace :: !Trace
  , rigFull   :: !Rig
  , fullTrace :: !Trace
  }

-- | Replay the rows, and when an event is given, the rows with that event
-- appended. The event's verdict is the what-if's classification of what the
-- evaluator did with it; see the module header. The whole of it runs under
-- the time bound (microseconds), and past it is 'Undecided'.
replay :: EvalConfig -> Int -> Deployment -> [Row] -> Maybe (RowEvent, Rational) -> IO (Either Failure Replayed)
replay cfg bound dep rows mextra =
  bounded bound case check cfg dep (map rowEventAt rows) mextra of
    Left f -> pure (Left f)
    Right mk -> mk >>= \ case
      Left f -> pure (Left f)
      Right c -> run c
  where
    run c = position c.rigRows c.rowsTrace >>= \ case
      Nothing -> pure (Left (Undecided "the replay of the rows produced no result"))
      Just pos -> do
        cands <- candidatesOf c.rigRows c.rowsTrace pos
        let headVerdict = classify (contextOf pos.posSteps) pos.posResult
            terminal = case headVerdict of
              Discharging -> True
              Breaching _ -> True
              _           -> False
            deadlines = sortOn fst
              [ (d, t) | MkCandidate {cdKind = TickPast d _, cdHypothetical = Right (Tick t)} <- cands ]
            headLines = ledgerLines pos.posResult.ledger
            headOff = officialLines pos.posResult.ledger
            headCommitted = officialEntries pos.posResult.ledger
        case rowVerdictOf headVerdict of
          Left why -> pure (Left (Undecided why))
          Right headRowVerdict -> do
            mout <- for mextra \ (ev, t) -> position c.rigFull c.fullTrace >>= \ case
              Nothing -> pure (Left (Undecided "the replay with the event produced no result"))
              Just after -> do
                let caused = afterCommonPrefix pos.posSteps after.posSteps
                    raw = classify (contextOf after.posSteps) after.posResult
                    judged = case ev of
                      TickEvent -> confirmTick (TickPast (tickDeadline deadlines t) []) (Tick t) caused raw
                      _ | terminal && not (eventTaken caused) -> PassedOver NoTaker
                        | otherwise -> confirmProposed caused raw
                pure case rowVerdictOf judged of
                  Left why -> Left (Undecided why)
                  Right v -> Right MkEventOutcome
                    { verdict = v
                    , steps = caused
                    , wrote = writtenLines pos.posResult.ledger after.posResult.ledger
                    , ledger = ledgerLines after.posResult.ledger
                    , official = officialLines after.posResult.ledger
                    , commits = officialWrites pos.posResult.ledger after.posResult.ledger
                    }
            case sequence mout of
              Left f -> pure (Left f)
              Right out -> pure (Right MkReplayed
                { headVerdict = headRowVerdict
                , headSteps = pos.posSteps
                , headLedger = headLines
                , headOfficial = headOff
                , headCommits = headCommitted
                , headTerminal = terminal
                , headDeadlines = deadlines
                , outcome = out
                })
    -- the deadline a tick at t passes: the latest one below it
    tickDeadline ds t = maybe t fst (listToMaybe (reverse [ x | x@(d, _) <- ds, d < t ]))

-- | The enabled set at the rows' head: the what-may-I-do-now answer of
-- §3.3, which is "L4.Lts.WhatIf"'s 'enabledSet' over the rows. Advisory:
-- it is computed outside any critical section.
--
-- With it, the same answer as "L4.Lts.List" words it for @l4 lts@
-- ('reportFrom' on the rows' own @#TRACE@), so that a caller that shows
-- the position to a reader does not write a third renderer of it.
positionAt :: EvalConfig -> Int -> Deployment -> [Row] -> IO (Either Failure (EnabledSet, TraceReport))
positionAt cfg bound dep rows =
  boundedLazy bound case check cfg dep (map rowEventAt rows) Nothing of
    Left f -> pure (Left f)
    Right mk -> mk >>= \ case
      Left f -> pure (Left f)
      Right c -> enabledSet c.rigRows c.rowsTrace >>= \ case
        Nothing -> pure (Left (Undecided "the replay of the rows produced no result"))
        Just es -> pure (Right (es, reportFrom c.rowsTrace es))

-- | The rows' events as the type checker resolved them: the @#TRACE@'s
-- event expressions, in order (the opening is the directive itself, not an
-- event). Pure. This is the round trip from a row to what "L4.Lts.WhatIf"
-- replays: a tick row lifts to the @WAIT UNTIL@ application
-- 'hypotheticalExpr' builds for a 'Tick'.
liftEvents :: Deployment -> [(RowEvent, Rational)] -> Either Failure [Expr Resolved]
liftEvents dep evs = do
  r <- typecheck dep evs
  tr <- ourTrace r (length evs - 1)
  pure tr.trEvents

----------------------------------------------------------------------------
-- The generated module
----------------------------------------------------------------------------

-- | Type-check the generated module, and in 'IO' evaluate its imports.
check :: EvalConfig -> Deployment -> [(RowEvent, Rational)] -> Maybe (RowEvent, Rational) -> Either Failure (IO (Either Failure Checked))
check cfg dep evs mextra = do
  let allEvs = evs <> maybeToList mextra
  r <- typecheck dep allEvs
  full <- ourTrace r (length allEvs - 1)
  let rowsEvents = case mextra of
        Just _  -> take (length full.trEvents - 1) full.trEvents
        Nothing -> full.trEvents
      rowsDirective = case full.trDirective of
        Contract a c t _ -> Contract a c t rowsEvents
        d -> d
      rowsTr = MkTrace
        { trDirective = rowsDirective
        , trContract = full.trContract
        , trStart = full.trStart
        , trEvents = rowsEvents
        }
  pure do
    env <- importsEnv cfg r.tcdResolvedImports
    let rigOf d = MkRig
          { rigConfig = cfg
          , rigEntityInfo = r.tcdEntityInfo
          , rigEnv = env
          , rigModule = onlyDirective full.trDirective d r.tcdModule
          }
    pure (Right MkChecked
      { rigRows = rigOf rowsDirective
      , rowsTrace = rowsTr
      , rigFull = rigOf full.trDirective
      , fullTrace = full
      })

-- | The generated module's source: the deployment's, then the @#TRACE@ of
-- these events. Dumped to a file, it is what @l4 run@ replays (the §8 two
-- oracles); the deployment's own @#TRACE@s run there too, before it.
traceModule :: Deployment -> [(RowEvent, Rational)] -> Either Text Text
traceModule dep evs = do
  block <- traceBlock evs
  pure (dep.deploymentSource <> "\n\n" <> block)

typecheck :: Deployment -> [(RowEvent, Rational)] -> Either Failure TypeCheckWithDepsResult
typecheck dep evs = do
  src <- first Malformed (traceModule dep evs)
  r <- first (Malformed . Text.unlines) (checkWithImports (vfsFromList dep.deploymentImports) src)
  if r.tcdSuccess
    then Right r
    else Left (Malformed (Text.unlines
      [ l | e <- r.tcdErrors, TypeCheck.severity e == TypeCheck.SError, l <- TypeCheck.prettyCheckErrorWithContext e ]))

-- | The generated @#TRACE@: the module's last, holding exactly the number of
-- events written. A line that smuggled a second event in would change the
-- count, and is refused.
ourTrace :: TypeCheckWithDepsResult -> Int -> Either Failure Trace
ourTrace r n = case reverse (tracesOf r.tcdModule) of
  (tr : _) | length tr.trEvents == n -> Right tr
           | otherwise -> Left (Malformed ("the trace was written with " <> Text.pack (show n) <> " events and reads back with " <> Text.pack (show (length tr.trEvents))))
  [] -> Left (Malformed "the generated module holds no #TRACE")

-- | The module with every @#TRACE@ dropped but ours, and ours replaced by
-- @d@: the deployment's own traces are its examples, not this instance.
-- ('L4.Lts.WhatIf.replay' keeps only the directive equal to the trace's,
-- so this is belt and braces against a deployment trace that is equal to
-- ours.)
onlyDirective :: Directive Resolved -> Directive Resolved -> Module Resolved -> Module Resolved
onlyDirective ours d (MkModule a uri section) = MkModule a uri (rewrite section)
  where
    rewrite (MkSection sa n aka given decls) = MkSection sa n aka given (mapMaybe keep decls)
    keep = \ case
      Directive da c@Contract{}
        | c == ours -> Just (Directive da d)
        | otherwise -> Nothing
      Section sa s -> Just (Section sa (rewrite s))
      other -> Just other

-- | The imports' heaps: every resolved import evaluated on top of its own
-- imports' heaps, dependencies first, as @l4 lts@ assembles them (jl4-lsp's
-- @GetLazyEvaluationDependencies@). 'checkWithImports' evaluates nothing,
-- so without this a guard calling an imported rule is "not in scope".
importsEnv :: EvalConfig -> [ResolvedImport] -> IO Environment
importsEnv cfg imports = fst <$> foldM visit (Map.empty, Map.empty) (Map.keys byName)
  where
    byName = Map.fromList [ (ri.riModuleName, ri) | ri <- imports ]
    visit (acc, memo) name = case Map.lookup name memo of
      Just _  -> pure (acc, memo)
      Nothing -> case Map.lookup name byName of
        Nothing -> pure (acc, memo)
        Just ri -> do
          let deps = extractImportNames ri.riParsed
          (acc', memo') <- foldM visit (acc, memo) deps
          let depEnv = mconcat [ e | dn <- deps, Just e <- [Map.lookup dn memo'] ]
          (own, _) <- execEvalModuleWithEnv cfg ri.riTypeChecked.entityInfo depEnv ri.riTypeChecked.program
          let env = own <> depEnv
          pure (acc' <> env, Map.insert name env memo')

----------------------------------------------------------------------------
-- Verdicts and ledgers
----------------------------------------------------------------------------

-- | A verdict as a row records it; 'Untried' is no row, it is 'Unknown'.
rowVerdictOf :: Verdict -> Either Text RowVerdict
rowVerdictOf = \ case
  Discharging  -> Right VDischarging
  Breaching b  -> Right (VBreaching b.blParty)
  Advancing _  -> Right VAdvancing
  PassedOver p -> Right (VPassedOver (passOverText p))
  Untried why  -> Left why

passOverText :: PassOver -> Text
passOverText = \ case
  GuardFalse   -> "the act matched, and its PROVIDED came out false"
  TooEarly t   -> "the act came before its window opened, at " <> either id id (renderStamp t)
  WrongAct     -> "not the act awaited"
  WrongParty   -> "not this party's to do"
  NoTaker      -> "no obligation in force took it"

-- | Every entry of every ledger the run wrote, as @l4 run@ prints it less
-- the provenance stamp: parties' own ledgers first, by party, then the
-- official record.
ledgerLines :: LedgerStore -> [Text]
ledgerLines store =
  [ "RECORD " <> party <> "'s " <> entry e
  | (party, led) <- Map.toList store.ownLedgers, e <- DList.toList led ]
  <> officialLines store

officialLines :: LedgerStore -> [Text]
officialLines store = [ "COMMIT " <> entry e | e <- DList.toList store.officialLedger ]

-- | What a step appended: each ledger's entries past the ones it held
-- before. Every ledger is append-only (STATE-AS-LEDGER D2), so the new
-- entries are a suffix of each.
writtenLines :: LedgerStore -> LedgerStore -> [Text]
writtenLines before after =
  [ "RECORD " <> party <> "'s " <> entry e
  | (party, led) <- Map.toList after.ownLedgers
  , let held = length (DList.toList (Map.findWithDefault mempty party before.ownLedgers))
  , e <- drop held (DList.toList led) ]
  <> [ "COMMIT " <> entry e
     | e <- drop (length (DList.toList before.officialLedger)) (DList.toList after.officialLedger) ]

-- | The entries the official record gained between two runs of a ledger,
-- as 'writtenLines' counts them: a suffix, the record being append-only.
officialWrites :: LedgerStore -> LedgerStore -> [Commit]
officialWrites before after =
  [ commitOf e | e <- drop (length (DList.toList before.officialLedger)) (DList.toList after.officialLedger) ]

-- | Every entry the official record holds.
officialEntries :: LedgerStore -> [Commit]
officialEntries store = [ commitOf e | e <- DList.toList store.officialLedger ]

commitOf :: LedgerEvent -> Commit
commitOf (Assign path val _) = MkCommit {cell = Text.intercalate "'s " path, value = prettyLayout val}

entry :: LedgerEvent -> Text
entry (Assign path val _) = pathText path <> " IS " <> prettyLayout val

pathText :: Path -> Text
pathText segs = Text.intercalate "'s " (map (\ s -> "`" <> s <> "`") segs)

-- | How many entries the official record holds for one cell: the cell's
-- version in the sense of §2 (the count of recorded events, not of distinct
-- values).
officialCount :: Text -> [Text] -> Int
officialCount cell = length . filter (Text.isPrefixOf ("COMMIT `" <> cell <> "` IS "))

failureText :: Failure -> Text
failureText = \ case
  Malformed t -> t
  Undecided t -> t

-- | Run under the time bound, forcing the answer inside it.
bounded :: NFData a => Int -> IO (Either Failure a) -> IO (Either Failure a)
bounded micros act = fromMaybe (Left (outOfTime micros)) <$> timeout micros (act >>= evaluate . force)

-- | Run under the time bound without forcing: for an answer with no
-- 'NFData', whose laziness the caller accepts.
boundedLazy :: Int -> IO (Either Failure a) -> IO (Either Failure a)
boundedLazy micros act = fromMaybe (Left (outOfTime micros)) <$> timeout micros act

outOfTime :: Int -> Failure
outOfTime micros = Undecided ("the evaluator did not answer within " <> Text.pack (show micros) <> " microseconds")
