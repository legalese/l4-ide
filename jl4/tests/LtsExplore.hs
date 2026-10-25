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
import L4.EvaluateLazy (resolveEvalConfig)
import L4.Import.Resolution (ResolvedImport (..))
import L4.Lts.Explore
import L4.Lts.WhatIf (Rig (..))
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

  describe "the text names no constructor" $ forM_ designs \ c ->
    it c.csFile $ do
      g <- exploreFixture c.csFile propertyCells (Just closing)
      let txt = renderGraph g
      [ n | n <- constructorNames, n `Text.isInfixOf` txt ] `shouldBe` []
  where
    lastMaybe xs = if null xs then Nothing else Just (last xs)
