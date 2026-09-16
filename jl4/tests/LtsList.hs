-- | The P2a′ list baseline (LTS-VISUALISER.md §1.1a, §7.2): `l4 lts`'s
-- output over three corpus files, pinned byte for byte.
--
-- What the goldens are for, beyond "it still prints the same":
--
-- * @tenancy@ holds the barrier and the fork side by side, at their outset
--   (the file carries no @#TRACE@, so the list is asked for the fresh
--   position, as @--contract@ does). The two used to export identically
--   (P2h); the list must tell them apart in words, and the assertions
--   below say which words.
-- * @every-run-example@ is the reference page's own pair with events, so
--   its step log shows a barrier counting up to its release and a fork
--   continuing per member.
-- * @contracts@ is the classic corpus: a live position with a candidate
--   the what-if cannot instantiate, and two explicit breaches.
-- * @after-example@ is the AFTER reference page's own file: a window with
--   an opening edge (EVERY-EACH-QUANTIFIER-SPEC §5.1.2), seen from an early
--   act — the deadline listed from the OPENING, not the clock, the act
--   "now" passed over as too early, the step log showing the nullity —
--   plus the two-offset window, a right that vests, and the date forms.
--   Added 2026-09-17 (adversarial round 1 of the wave's third rebase, F1\/S1\/S2):
--   no golden had an @AFTER@ before it, and the seam between the wave's
--   opening-relative residual and this list's clock-relative reading went
--   unpinned.
--
-- And one property over all of them: the default output names no Haskell
-- constructor. The reader §1.1a has in mind does not know what a
-- @ValObligation@ is, and the golden alone would not notice if one crept
-- in.
module LtsList (spec) where

import Base
import qualified Base.Map as Map
import qualified Base.Text as Text
import qualified Data.Aeson.Encode.Pretty as AesonPretty
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text.Encoding as Text
import System.FilePath ((</>), joinPath, splitDirectories)
import Test.Hspec
import Test.Hspec.Golden

import L4.API.VirtualFS (checkWithImports, emptyVFS, TypeCheckWithDepsResult (..))
import L4.Evaluate.ValueLazy (Environment)
import L4.EvaluateLazy (EvalConfig, execEvalModuleWithEnv, resolveEvalConfig)
import L4.Import.Resolution (ResolvedImport (..), extractImportNames)
import L4.Lts.List
import L4.Lts.WhatIf (Rig (..), Trace, tracesOf)
import L4.TracePolicy (apiDefaultPolicy)
import L4.TypeCheck (CheckResult (..))

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)

import qualified Paths_jl4

fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0)

-- | Where a case's source lives, and which traces to list.
data Case = MkCase
  { csStem   :: String
    -- ^ the golden's name under @examples/lts/expected/@
  , csSource :: FilePath -> FilePath
    -- ^ the source, given the @jl4@ data dir
  , csFresh  :: [Text]
    -- ^ empty: the file's own @#TRACE@s; else these rules at their outset
  }

cases :: [Case]
cases =
  [ MkCase "contracts" (\ d -> d </> "examples" </> "ok" </> "contracts.l4") []
    -- The reference page's example is not under jl4/: it is read from the
    -- sibling doc/ tree, which is where `doc/test-docs.sh` type-checks it.
    -- An installed data dir would not have it; the golden suite runs in
    -- the source tree, and a missing file fails loudly rather than skips.
  , MkCase "every-run-example" (\ d -> repoRoot d </> "doc" </> "reference" </> "regulative" </> "every-run-example.l4") []
  , MkCase "tenancy" (\ d -> d </> "examples" </> "bpmn" </> "tenancy.l4") ["the tenancy", "receipts"]
  , MkCase "after-example" (\ d -> repoRoot d </> "doc" </> "reference" </> "regulative" </> "after-example.l4") []
  ]

-- | The repository root, from the @jl4@ data dir: one level up. `cabal
-- test` hands the package directory over as @jl4_datadir@, spelled with a
-- trailing @/.@ on some versions, so the path is split and cleaned rather
-- than just @takeDirectory@'d.
repoRoot :: FilePath -> FilePath
repoRoot d = joinPath (init (filter (`notElem` [".", ""]) (splitDirectories d)))

-- | The reports of a case, in order.
reportsOf :: Case -> IO [TraceReport]
reportsOf c = do
  dataDir <- Paths_jl4.getDataDir
  src <- Text.readFile (c.csSource dataDir)
  cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  r <- case checkWithImports emptyVFS src of
    Left errs -> fail (c.csStem <> ": typecheck failed: " <> show errs)
    Right r -> pure r
  env <- importsEnv cfg r.tcdResolvedImports
  let rig0 = MkRig {rigConfig = cfg, rigEntityInfo = r.tcdEntityInfo, rigEnv = env, rigModule = r.tcdModule}
      pick :: Rig -> [Text] -> [Trace] -> IO (Rig, [Trace])
      pick rig [] acc = pure (rig, reverse acc)
      pick rig (n : ns) acc = case freshTrace rig.rigModule n of
        Left why -> fail (c.csStem <> ": " <> Text.unpack why)
        Right (m', tr) -> pick rig {rigModule = m'} ns (tr : acc)
  (rig, traces) <- case c.csFresh of
    [] -> pure (rig0, tracesOf r.tcdModule)
    names -> pick rig0 names []
  fmap catMaybes $ for traces \ tr -> reportOf rig tr

-- | The imports' heaps, as `l4 lts` assembles them (jl4-lsp's
-- @GetLazyEvaluationDependencies@ rule): every resolved import evaluated on
-- top of its own imports' heaps, dependencies first, and the union handed
-- to the rig. 'checkWithImports' type-checks the imports and evaluates
-- nothing, so without this a library VALUE — @YMD@ from @daydate@, which
-- @after-example@'s date traces stamp their clock with — is "not in
-- scope" at replay and the trace lists as "could not be worked out".
-- Added 2026-09-17 with the @after-example@ case; the first three cases
-- use no library value and list the same with or without it.
importsEnv :: EvalConfig -> [ResolvedImport] -> IO Environment
importsEnv cfg imports = fst <$> foldM visit (Map.empty, Map.empty) (Map.keys byName)
  where
    byName = Map.fromList [ (ri.riModuleName, ri) | ri <- imports ]
    -- (every heap evaluated so far, and each module's own heap by name)
    visit (acc, memo) name = case Map.lookup name memo of
      Just _  -> pure (acc, memo)
      Nothing -> case Map.lookup name byName of
        -- not among the resolved imports: nothing to evaluate; the replay
        -- reports whatever is missing
        Nothing -> pure (acc, memo)
        Just ri -> do
          let deps = extractImportNames ri.riParsed
          (acc', memo') <- foldM visit (acc, memo) deps
          let depEnv = mconcat [ e | d <- deps, Just e <- [Map.lookup d memo'] ]
          (own, _) <- execEvalModuleWithEnv cfg ri.riTypeChecked.entityInfo depEnv ri.riTypeChecked.program
          let env = own <> depEnv
          pure (acc' <> env, Map.insert name env memo')

goldenOf :: String -> String -> Text -> IO (Golden Text)
goldenOf stem ext output = do
  dataDir <- Paths_jl4.getDataDir
  let root = dataDir </> "examples" </> "lts" </> "expected"
  pure Golden
    { output = output
    , encodePretty = Text.unpack
    , writeToFile = Text.writeFile
    , readFromFile = Text.readFile
    , goldenFile = root </> (stem <> ext)
    , actualFile = Just (root </> (stem <> ext <> ".actual"))
    , failFirstTime = True
    }

-- | Constructor names a reader must never see. Every 'StepOutcome',
-- 'Branch', 'NormPlacement', 'Verdict' and value constructor the list
-- renders from; if a new one is added to the back end, add it here.
constructorNames :: [Text]
constructorNames =
  [ "Waiting", "PartyMismatch", "ActionMismatch", "GuardFailed", "Matched", "Expired", "Breached"
  , "Joined", "JoinReleased", "JoinExpired", "JoinFailed", "JoinStalled"
  , "ToHence", "ToLest", "ToBreach", "MemberSatisfied", "ForkContinued"
  , "Created", "InEffect", "Violated", "Lapsed", "Awaiting"
  , "Discharging", "Breaching", "Advancing", "PassedOver", "Untried"
  , "GuardFalse", "TooEarly", "WrongAct", "WrongParty", "NoTaker", "EarlyAct"
  , "ValObligation", "ValBreached", "ValFulfilled", "ValROp", "ValQuantified"
  , "DeadlineMissed", "ExplicitBreach", "MkBlame", "KnownParty", "UnforcedParty"
  , "NobodyNamed", "PartyNamed", "UnforcedDeadline", "UnforcedBefore", "NoDeadline", "Remaining"
  , "NoOpening", "UnforcedOpening", "OpensIn"
  , "neverMatches", "NEVERMATCHES"
  ]

spec :: Spec
spec = do
  describe "golden" $ forM_ cases \ c -> do
    it (c.csStem <> " lists to stable text (with the step log)") $ do
      reports <- reportsOf c
      goldenOf c.csStem ".txt" (Text.intercalate "\n" (map (renderReport True) reports))

    it (c.csStem <> " lists to stable JSON (with the step log)") $ do
      reports <- reportsOf c
      let cfg = AesonPretty.defConfig {AesonPretty.confIndent = AesonPretty.Spaces 2, AesonPretty.confCompare = compare}
          bytes = AesonPretty.encodePretty' cfg (map (reportJson True) reports)
      goldenOf c.csStem ".json" (Text.decodeUtf8 (BL.toStrict bytes) <> "\n")

  describe "the text names no constructor" $ forM_ cases \ c ->
    it c.csStem $ do
      reports <- reportsOf c
      let txt = Text.intercalate "\n" (map (renderReport True) reports)
          -- a plain substring search: the names are capitalised and the
          -- prose is not, so "Expired" is caught and "expired" is allowed
          hits = [ n | n <- constructorNames, n `Text.isInfixOf` txt ]
      hits `shouldBe` []

  describe "tenancy: the barrier and the fork read differently" $ do
    it "the barrier's members wait for each other; the fork's do not" $ do
      reports <- reportsOf (cases !! 2)
      case map (renderReport False) reports of
        [barrier, fork] -> do
          barrier `shouldSatisfy` Text.isInfixOf "who must all act before the next step"
          barrier `shouldSatisfy` Text.isInfixOf "the next step is held back until all have acted: 0 of 3 have"
          -- one member acting takes the count to 1 of 3 and releases nothing
          barrier `shouldSatisfy` Text.isInfixOf "the next step is held back until all have acted: 1 of 3 have"
          fork `shouldSatisfy` Text.isInfixOf "each with a next step of their own"
          fork `shouldNotSatisfy` Text.isInfixOf "held back"
          -- the tick breaches both, but the fork's LEST names the member
          barrier `shouldSatisfy` Text.isInfixOf "nothing happens by 14 (the clock reaches 15) → the contract is in breach (no party is named)"
          fork `shouldSatisfy` Text.isInfixOf "nothing happens by 7 (the clock reaches 8) → Tenant OF \"Alice\" is in breach"
        other -> expectationFailure ("expected two reports, got " <> show (length other))

  describe "every-run-example: the step log shows the join" $ do
    it "the barrier counts up and releases once; the fork continues per member" $ do
      reports <- reportsOf (cases !! 1)
      case map (renderReport True) reports of
        (barrierOk : _ : forkOk : _) -> do
          barrierOk `shouldSatisfy` Text.isInfixOf "(3 of 3 have acted; the shared next step waits for the rest)"
          barrierOk `shouldSatisfy` Text.isInfixOf "everyone has acted; the shared next step begins"
          forkOk `shouldSatisfy` Text.isInfixOf "(member 1 of 3: their own next step begins)"
          forkOk `shouldNotSatisfy` Text.isInfixOf "shared next step"
        other -> expectationFailure ("expected four reports, got " <> show (length other))

  describe "contracts: a live position" $ do
    it "the first trace owes B a return, lists the tick as breaching and the act as untriable" $ do
      reports <- reportsOf (cases !! 0)
      case reports of
        (rp : _) -> do
          rp.rpStanding `shouldBe` InProgress
          rp.rpClock `shouldBe` 10
          fmap fst rp.rpNext `shouldBe` Just 14
          let txt = renderReport False rp
          txt `shouldSatisfy` Text.isInfixOf "B MUST return — due by 14 (4 from now)"
          txt `shouldSatisfy` Text.isInfixOf "What could not be tried:"
        [] -> expectationFailure "no reports"
