-- | @l4 explore@ (REGULATIVE-LOWERING-SPEC.md §4, WP1) over the dinner-race
-- fixtures in @jl4/examples/explore/brief/@, pinned two ways.
--
-- * The numbers. Each fixture's state, transition and pass-over counts are
--   asserted as numbers, not only through a golden, because a golden gets
--   re-blessed and a number does not drift silently. They are the counts
--   the fixtures' README measured with an explorer built outside the tree,
--   through @l4 run@, before this one existed (its "What was checked"
--   table): 12/21/51, 15/30/90, 10/21/39 for the three designs, 13/29/62
--   and 10/21/39 for the mutants — and the probes' hand models' 12/21,
--   15/30, 10/21 (spec §1). Agreement with a second instrument is the point;
--   agreement with last week's output would not be.
-- * The text, byte for byte, under @examples/explore/expected/@.
--
-- Every exploration here is run as the acceptance asks: the clock bounded
-- at closing (@--until 75600@, the README's "bound the clock below closing,
-- or remove the tick edges"), and the cells the properties read kept,
-- since @properties.l4@ fills its inputs from the ledger and has no
-- @RECALL@ of its own for the explorer to find (spec §4.1; 'keepCells').
-- One case runs without the kept cells and one without the clock bound, so
-- that what each of those choices does is pinned too.
--
-- The in-process checker (spec §5, WP2) is pinned on the same fixtures:
-- the verdict of every property of @properties.l4@ on every design, the
-- counterexamples as the paths BRIEF.md's table predicts (D1: check, Bob's
-- purchase, buy; D2: check, re-read, Bob's purchase, buy; the mutants: only
-- P4, by the cancel, and only P2, by the double record), P3 reachable in all
-- five, and the checks' text byte for byte. Every counterexample and
-- witness is run as printed, as source, through 'sourceReplay' — the
-- fixture's text with the @#TRACE@ appended, type-checked again with its
-- import — before the checker reports it, as the CLI does.
--
-- The emitters (spec §6.1, WP3) are pinned on the three designs: which
-- actions get weak fairness under @--fair Alice@, asserted as names (spec
-- §4.6's list, derived from the graph); the files and their order; the
-- @.aut@'s counts; and every file's text, under @expected/*.emit.txt@. That
-- TLC, NuSMV and mCRL2 load the files and what they answer is not a test
-- here, since none of them is installed in CI; it is WP4's harness.
module LtsExplore (spec) where

import Base
import qualified Base.Text as Text
import qualified Data.Aeson.Encode.Pretty as AesonPretty
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text.Encoding as Text
import System.FilePath ((</>), takeFileName)
import Test.Hspec
import Test.Hspec.Golden

import L4.API.VirtualFS (checkWithImports, vfsFromList, TypeCheckWithDepsResult (..))
import L4.EvaluateLazy (EvalDirectiveResult (..), execEvalModuleWithDeonticLog, resolveEvalConfig)
import L4.Import.Resolution (ResolvedImport (..))
import L4.Lts.Explore
import L4.Lts.Explore.Check hiding (CheckResult, propertyCells)
import qualified L4.Lts.Explore.Check as Check
import L4.Lts.Explore.Emit (EmitInput (..), emitBase, emitFiles)
import L4.Lts.Explore.Emit.Model (EmAction (..), Fairness (..), Model (..), buildModel)
import L4.Lts.WhatIf (Rig (..))
import L4.Parser.SrcSpan (SrcPos (..), SrcRange (..))
import L4.Print (prettyLayout)
import L4.TracePolicy (apiDefaultPolicy)
import L4.TypeCheck (CheckResult (..))

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)

import qualified Paths_jl4
import LtsList (importsEnv)

fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0)

-- | The cells @properties.l4@ reads, and how: a @LIST@ input is the whole
-- history, a @MAYBE@ input the latest entry.
propertyCells :: [(Text, Bool)]
propertyCells =
  [ ("open at acceptance", True)     -- P1
  , ("dinners bought", True)         -- P2, P4
  , ("dinners cancelled", True)      -- P2, P4
  , ("dinner status record", True)   -- P3, the non-vacuity control
  , ("belief", False)                -- P3
  , ("plan", False)                  -- P5
  ]

closing :: Rational
closing = 75600

-- | Explore one fixture: its file under @examples/explore/brief/@, the
-- cells kept, the clock bound.
exploreFixture :: FilePath -> [(Text, Bool)] -> Maybe Rational -> IO Graph
exploreFixture rel keep until' = do
  dataDir <- Paths_jl4.getDataDir
  let brief = dataDir </> "examples" </> "explore" </> "brief"
  src <- Text.readFile (brief </> rel)
  props <- Text.readFile (brief </> "properties.l4")
  cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  r <- case checkWithImports (vfsFromList [("properties", props)]) src of
    Left errs -> fail (rel <> ": typecheck failed: " <> show errs)
    Right r -> pure r
  env <- importsEnv cfg r.tcdResolvedImports
  let rig = MkRig {rigConfig = cfg, rigEntityInfo = r.tcdEntityInfo, rigEnv = env, rigModule = r.tcdModule}
      sites = keepCells keep (readSitesOf r.tcdModule [ ri.riTypeChecked.program | ri <- r.tcdResolvedImports ])
      opts = defaultExploreOptions {eoUntil = until'}
  case startsOf r.tcdModule of
    [start] -> explore opts sites rig start >>= either (fail . ((rel <> ": ") <>) . Text.unpack) pure
    other -> fail (rel <> ": expected one contract to explore, found " <> show (length other))

-- | The properties of @properties.l4@, as the brief classes them, and the
-- non-vacuity control (spec §6.3), which is a liveness property here too.
properties :: [Request]
properties =
  [ MkRequest Always "every dinner was accepted while open" Nothing            -- P1
  , MkRequest Always "at most one dinner is bought" Nothing                    -- P2
  , MkRequest Reachable "Alice's belief is stale" Nothing                      -- P3
  , MkRequest Stays "one dinner is bought" Nothing                             -- P4
  , MkRequest Eventually "Alice has bought or stopped" Nothing                 -- P5
  , MkRequest Eventually "one dinner is bought" (Just "the ledger is open")    -- P6
  , MkRequest Eventually "Bob has bought" Nothing                              -- the control
  ]

-- | Explore one fixture with the properties' cells kept (and no others),
-- the clock bound at closing, and check the properties, every path run as
-- printed before it is reported.
checkFixture :: FilePath -> IO (Graph, [Check.CheckResult])
checkFixture rel = (\ (g, rs, _, _) -> (g, rs)) <$> checkFixture' rel

-- | 'checkFixture', with the labels and the resolved properties too, which
-- the emitters read.
checkFixture' :: FilePath -> IO (Graph, [Check.CheckResult], Labels, [Property])
checkFixture' rel = do
  dataDir <- Paths_jl4.getDataDir
  let brief = dataDir </> "examples" </> "explore" </> "brief"
  src <- Text.readFile (brief </> rel)
  props <- Text.readFile (brief </> "properties.l4")
  cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  let typecheck text = either (fail . ((rel <> ": typecheck failed: ") <>) . show) pure
        (checkWithImports (vfsFromList [("properties", props)]) text)
  r <- typecheck src
  env <- importsEnv cfg r.tcdResolvedImports
  let rig = MkRig {rigConfig = cfg, rigEntityInfo = r.tcdEntityInfo, rigEnv = env, rigModule = r.tcdModule}
      modules = r.tcdModule : [ ri.riTypeChecked.program | ri <- r.tcdResolvedImports ]
      opts = defaultExploreOptions {eoUntil = Just closing}
  ps <- either (fail . Text.unpack) pure (traverse (resolveProperty r.tcdEntityInfo modules) properties)
  let sites = keepCells (Check.propertyCells ps) (readSitesOf r.tcdModule [ ri.riTypeChecked.program | ri <- r.tcdResolvedImports ])
      -- the #TRACE as printed, appended to the fixture, type-checked and run
      -- again; the trace's ledgers are those of the one directive below the
      -- fixture's own lines
      sourceReplay printed = do
        r' <- typecheck (src <> "\n" <> printed)
        env' <- importsEnv cfg r'.tcdResolvedImports
        (_, results) <- execEvalModuleWithDeonticLog cfg r'.tcdEntityInfo env' r'.tcdModule
        let ownLines = length (Text.lines src)
        pure case [ l | (MkEvalDirectiveResult {range = Just MkSrcRange {start = MkSrcPos {line = n}}, ledger = l}, _) <- results, n > ownLines ] of
          [l] -> Right l
          ls -> Left ("gave " <> Text.pack (show (length ls)) <> " results below the fixture")
  start <- case startsOf r.tcdModule of
    [s] -> pure s
    other -> fail (rel <> ": expected one contract to explore, found " <> show (length other))
  g <- explore opts sites rig start >>= either (fail . ((rel <> ": ") <>) . Text.unpack) pure
  (rs, labels) <- checkGraph opts rig (Just sourceReplay) g ps
  pure (g, rs, labels, ps)

-- | What the emitters are given for a fixture, as the CLI gives it with
-- @--emit DIR --fair Alice@.
emitInputOf :: FilePath -> IO EmitInput
emitInputOf rel = do
  (g, _, labels, ps) <- checkFixture' rel
  pure MkEmitInput
    { eiBase = emitBase (Text.pack (stemOf rel)) 1 1
    , eiSource = Text.pack (takeFileName rel)
    , eiGraph = g
    , eiProperties = ps
    , eiLabels = labels
    , eiFair = ["Alice"]
    }

-- | A design, and what WP3 must emit for it: the actions given weak
-- fairness, derived from the graph and @--fair Alice@ (spec §4.6: Alice's
-- acts that move, and the ledger answering her, which in these fixtures is
-- inside her act; never Bob's purchase or the message, never a pause).
data EmitCase = MkEmitCase
  { ecFile :: FilePath
  , ecFair :: [Text]
  }

emitCases :: [EmitCase]
emitCases =
  [ MkEmitCase "d1-naive.l4"
      [ "World_Alice_checks_whether_dinner_is_bought", "World_Alice_buys_dinner", "World_Alice_gives_up" ]
  , MkEmitCase "d2-reread.l4"
      [ "World_Alice_checks_whether_dinner_is_bought", "World_Alice_reads_the_ledger_again_OF_TRUE"
      , "World_Alice_buys_dinner", "World_Alice_gives_up" ]
  , MkEmitCase "d3-atomic.l4"
      [ "World_Alice_checks_whether_dinner_is_bought", "World_Alice_buys_dinner_OF_TRUE" ]
  ]

-- | Every emitted file, each under a @==> name <==@ line, as one text.
emittedText :: [Either Text (Text, Text)] -> Text
emittedText files = Text.concat
  [ either (\ why -> "==> NOT WRITTEN <==\n" <> why <> "\n") (\ (name, body) -> "==> " <> name <> " <==\n" <> body) f <> "\n"
  | f <- files ]

-- | A fixture, and what each property must come to: the verdict word, and
-- for a violated or reached one the acts of its path, in order.
data Expect = MkExpect
  { exFile     :: FilePath
  , exVerdicts :: [(Text, Maybe [Text])]
  }

liveness :: [(Text, Maybe [Text])]
liveness = replicate 3 ("unknown", Nothing)

check, bob, buy, reread, buyAnswered, cancel :: Text
check = "`Alice checks whether dinner is bought`"
bob = "`ledger records Bob's purchase`"
buy = "`Alice buys dinner`"
reread = "`Alice reads the ledger again` OF TRUE"
buyAnswered = "`Alice buys dinner` OF TRUE"
cancel = "`Alice cancels the dinner`"

-- | P3's witness is the same two acts in every design: Alice checks while
-- open, then Bob's purchase is recorded.
stale :: (Text, Maybe [Text])
stale = ("holds", Just [check, bob])

expectations :: [Expect]
expectations =
  [ MkExpect "d1-naive.l4" $
      [ ("violated", Just [check, bob, buy]), ("holds", Nothing), stale, ("holds", Nothing) ] <> liveness
  , MkExpect "d2-reread.l4" $
      [ ("violated", Just [check, reread, bob, buy]), ("holds", Nothing), stale, ("holds", Nothing) ] <> liveness
  , MkExpect "d3-atomic.l4" $
      [ ("holds", Nothing), ("holds", Nothing), stale, ("holds", Nothing) ] <> liveness
  , MkExpect "mutants/d3-cancel.l4" $
      [ ("holds", Nothing), ("holds", Nothing), stale, ("violated", Just [check, buyAnswered, cancel]) ] <> liveness
  , MkExpect "mutants/d3-double.l4" $
      [ ("holds", Nothing), ("violated", Just [check, buyAnswered]), stale, ("holds", Nothing) ] <> liveness
  ]

-- | The act of an event, without its party and instant: @PARTY World DOES
-- `x` AT 64800@ is @`x`@.
actOf :: Text -> Text
actOf e = fst (Text.breakOn " AT " (fromMaybe e (Text.stripPrefix "PARTY World DOES " e)))

outcome :: Check.CheckResult -> (Text, Maybe [Text])
outcome r = (verdictWord r.crVerdict, map (actOf . oneLine . prettyLayout) . (.ptEvents) <$> pathOf r.crVerdict)
  where
    oneLine = Text.unwords . Text.words
    pathOf = \ case
      Violated _ mp -> mp
      Reached p -> Just p
      Unknown _ mp -> mp
      Holds _ -> Nothing

goldenOf :: String -> String -> Text -> IO (Golden Text)
goldenOf stem ext output = do
  dataDir <- Paths_jl4.getDataDir
  let root = dataDir </> "examples" </> "explore" </> "expected"
  pure Golden
    { output = output
    , encodePretty = Text.unpack
    , writeToFile = Text.writeFile
    , readFromFile = Text.readFile
    , goldenFile = root </> (stem <> ext)
    , actualFile = Just (root </> (stem <> ext <> ".actual"))
    , failFirstTime = True
    }

-- | A fixture, and what its exploration must count.
data Case = MkCase
  { csFile        :: FilePath
  , csStates      :: Int
  , csTransitions :: Int
  , csPassedOver  :: Int
  }

designs :: [Case]
designs =
  [ MkCase "d1-naive.l4"          12 21 51
  , MkCase "d2-reread.l4"         15 30 90
  , MkCase "d3-atomic.l4"         10 21 39
  , MkCase "mutants/d3-cancel.l4" 13 29 62
  , MkCase "mutants/d3-double.l4" 10 21 39
  ]

-- | Constructor names a reader must never see in the text (as
-- @LtsList@'s list, for the names this module renders from).
constructorNames :: [Text]
constructorNames =
  [ "ValObligation", "ValBreached", "ValFulfilled", "ValROp", "ValQuantified"
  , "Discharging", "Breaching", "Advancing", "PassedOver", "Untried"
  , "TickPast", "NoTick", "ActBy", "KeptAll", "KeptLatest"
  , "EdgeAct", "EdgeTick", "EdgeTerminal", "StopDepth", "StopStates", "MkRefusal"
  ]

stemOf :: FilePath -> String
stemOf = takeWhile (/= '.') . takeFileName

spec :: Spec
spec = do
  describe "the counts the fixtures' README measured" $ forM_ designs \ c ->
    it (c.csFile <> ": " <> show c.csStates <> " states, " <> show c.csTransitions <> " transitions, " <> show c.csPassedOver <> " passed over, complete") $ do
      g <- exploreFixture c.csFile propertyCells (Just closing)
      let cv = g.gCoverage
      (cv.cvStates, cv.cvTransitions, cv.cvPassedOver) `shouldBe` (c.csStates, c.csTransitions, c.csPassedOver)
      length g.gStates `shouldBe` c.csStates
      length g.gTransitions `shouldBe` c.csTransitions
      coverageComplete cv `shouldBe` True
      cv.cvDropped `shouldBe` []
      -- every state of the brief has a candidate the clock bound cut: the
      -- tick past closing (README, "What the explorer must know", point 2)
      cv.cvBeyondClock `shouldBe` c.csStates

  describe "golden" $ forM_ (designs <> [MkCase "refused-number.l4" 0 0 0]) \ c ->
    it (c.csFile <> " explores to stable text") $ do
      g <- exploreFixture c.csFile propertyCells (Just closing)
      goldenOf (stemOf c.csFile) ".txt" (renderGraph g)

  describe "golden JSON" $
    it "d1-naive.l4 explores to stable JSON" $ do
      g <- exploreFixture "d1-naive.l4" propertyCells (Just closing)
      let cfg = AesonPretty.defConfig {AesonPretty.confIndent = AesonPretty.Spaces 2, AesonPretty.confCompare = compare}
      goldenOf "d1-naive" ".json" (Text.decodeUtf8 (BL.toStrict (AesonPretty.encodePretty' cfg (graphJson g))) <> "\n")

  describe "refused-number.l4: a NUMBER payload is refused, by name, and the rest explored" $
    it "names the variable, its type and the constructor, explores Alice's acts, and is not complete" $ do
      g <- exploreFixture "refused-number.l4" propertyCells (Just closing)
      let cv = g.gCoverage
      case cv.cvRefused of
        [r] -> do
          r.rfVariable `shouldBe` "act"
          r.rfType `shouldBe` "Act"
          r.rfWhole `shouldBe` True
          r.rfConstructor `shouldBe` Just "ledger records Bob's purchase"
          r.rfReason `shouldSatisfy` Text.isInfixOf "`recorded at`"
          r.rfReason `shouldSatisfy` Text.isInfixOf "NUMBER"
          r.rfStates `shouldBe` cv.cvStates
        other -> expectationFailure ("expected one refusal, got " <> show other)
      coverageComplete cv `shouldBe` False
      -- the finite constructors beside it: the outset, Alice's check, her
      -- purchase; Bob's purchase never happens, so the message is never sent
      (cv.cvStates, cv.cvTransitions) `shouldBe` (3, 4)
      let line = coverageLine cv
      line `shouldSatisfy` Text.isInfixOf "REFUSED 1: `act` of type Act, constructor `ledger records Bob's purchase`"
      Text.lines (renderGraph g) `shouldSatisfy` (Just line ==) . lastMaybe

  describe "what the choices of the acceptance run do" $ do
    it "without the cells the properties read, D1 merges P1's bad purchase with the good one: 10 states, the two cells named" $ do
      g <- exploreFixture "d1-naive.l4" [] (Just closing)
      (g.gCoverage.cvStates, g.gCoverage.cvTransitions) `shouldBe` (10, 18)
      g.gCoverage.cvDropped `shouldBe` [("OFFICIAL", "dinners bought"), ("OFFICIAL", "open at acceptance")]
      coverageLine g.gCoverage `shouldSatisfy` Text.isInfixOf "write-only cells dropped: OFFICIAL's `dinners bought`, OFFICIAL's `open at acceptance`"

    it "keeping a MAYBE-read cell whole splits states the brief identifies (README point 1: 15 and 27 for D3)" $ do
      g <- exploreFixture "d3-atomic.l4" [ (c, True) | (c, _) <- propertyCells ] (Just closing)
      (g.gCoverage.cvStates, g.gCoverage.cvTransitions) `shouldBe` (15, 27)

    it "without the clock bound, every state's tick past closing reaches a FULFILLED twin, which is terminal" $ do
      g <- exploreFixture "d1-naive.l4" propertyCells Nothing
      let cv = g.gCoverage
      -- 12 brief states and 12 fulfilled ones; 21 edges, 12 ticks, 12 terminal self-loops
      (cv.cvStates, cv.cvTransitions) `shouldBe` (24, 45)
      cv.cvBeyondClock `shouldBe` 0
      coverageComplete cv `shouldBe` True
      length [ () | t <- g.gTransitions, t.tnKind == EdgeTick ] `shouldBe` 12
      length [ () | t <- g.gTransitions, t.tnKind == EdgeTerminal, t.tnFrom == t.tnTo ] `shouldBe` 12
      length (filter (.snTerminal) g.gStates) `shouldBe` 12
      -- the outset's anchor (`closing`, never forced before an event) was
      -- resolved, or the outset would list its tick as untried
      [ t.tnLabel | t <- g.gTransitions, t.tnFrom == 0, t.tnKind == EdgeTick ]
        `shouldBe` ["time passes the deadline 75600 (WAIT UNTIL 75601)"]

  describe "the checker's verdicts (WP2): P1 to P4 as BRIEF.md predicts, P5, P6 and the control unknown" $ forM_ expectations \ e ->
    it e.exFile $ do
      (g, rs) <- checkFixture e.exFile
      map outcome rs `shouldBe` e.exVerdicts
      -- liveness is never guessed
      [ why | Check.MkCheckResult {crVerdict = Unknown why _} <- rs ] `shouldBe` replicate 3 livenessUnknown
      -- the properties' cells are the ones the README's acceptance run keeps,
      -- so the graph is the one WP1 pins
      Just (g.gCoverage.cvStates, g.gCoverage.cvTransitions)
        `shouldBe` lookup e.exFile [ (c.csFile, (c.csStates, c.csTransitions)) | c <- designs ]

  describe "the checks' text (WP2)" $ forM_ designs \ c ->
    it (c.csFile <> " checks to stable text") $ do
      (g, rs) <- checkFixture c.csFile
      goldenOf (stemOf c.csFile) ".check.txt" (Text.unlines (renderChecks g rs))

  describe "the text names no constructor" $ forM_ designs \ c ->
    it c.csFile $ do
      g <- exploreFixture c.csFile propertyCells (Just closing)
      let txt = renderGraph g
      [ n | n <- constructorNames, n `Text.isInfixOf` txt ] `shouldBe` []

  describe "the emitted models (WP3): fairness per labelled action, derived from the graph and --fair Alice" $ forM_ emitCases \ e ->
    it (e.ecFile <> ": " <> show (length e.ecFair) <> " fair actions, the rest named and why, every state with an edge") $ do
      ei <- emitInputOf e.ecFile
      let m = buildModel ei
      [ a.eaIdent | a <- m.mdActions, a.eaFairness == Fair ] `shouldBe` e.ecFair
      -- the environment's acts and the pauses are never fair, and say why
      [ a.eaIdent | a <- m.mdActions, a.eaFairness /= Fair ] `shouldSatisfy` all (\ i ->
        i `elem` [ "World_ledger_records_Bob_s_purchase", "World_Messages_delivers_the_message", "World_Alice_is_done"
                 , "World_Alice_buys_dinner_OF_FALSE", "World_Alice_reads_the_ledger_again_OF_FALSE" ])
      -- the brief's graphs are total, so no unexplored self-loop is added
      m.mdUnexplored `shouldBe` []
      -- every property of properties.l4 is emitted, none refused
      length m.mdProps `shouldBe` length properties
      m.mdNotEmitted `shouldBe` []

  describe "the emitted files (WP3)" $ forM_ designs \ c -> when (c.csFile `elem` map (.ecFile) emitCases) $
    it (c.csFile <> ": the .aut is the graph, edge for edge; one cfg per property; all thirteen files, in the order of section 6.1") $ do
      ei <- emitInputOf c.csFile
      let files = emitFiles ei
          base = Text.pack (map (\ ch -> if ch == '-' then '_' else ch) (stemOf c.csFile))
          named = [ n | Right (n, _) <- files ]
      [ why | Left why <- files ] `shouldBe` []
      named `shouldBe`
        [ base <> ".aut", base <> ".tla", base <> ".cfg" ]
        <> [ base <> "." <> p <> ".cfg"
           | p <- [ "Always_every_dinner_was_accepted_while_open", "Always_at_most_one_dinner_is_bought"
                  , "Never_Alice_s_belief_is_stale", "Stays_one_dinner_is_bought"
                  , "Eventually_Alice_has_bought_or_stopped"
                  , "Eventually_one_dinner_is_bought_if_always_the_ledger_is_open"
                  , "Eventually_Bob_has_bought" ] ]
        <> [ base <> ".smv", base <> ".dot", base <> ".pnml" ]
      case [ body | Right (n, body) <- files, n == base <> ".aut" ] of
        [aut] -> do
          take 1 (Text.lines aut) `shouldBe` ["des (0," <> tshow c.csTransitions <> "," <> tshow c.csStates <> ")"]
          length (Text.lines aut) `shouldBe` c.csTransitions + 1
        other -> expectationFailure ("expected one .aut, got " <> show (length other))
      goldenOf (stemOf c.csFile) ".emit.txt" (emittedText files)
  where
    tshow = Text.pack . show
    lastMaybe xs = if null xs then Nothing else Just (last xs)
