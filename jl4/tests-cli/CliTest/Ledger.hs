-- | The instance ledger's "two oracles" (OPERATIONAL-LOWERING-SPEC §8): every
-- history the ledger accepts, each accepted prefix dumped as its own
-- @#TRACE@, replays under @l4 run@ to the verdict the ledger returned when it
-- appended that prefix's last row. A divergence is a bug in the ledger,
-- never in the evaluator.
--
-- The ledger (jl4-core's "L4.Ledger.Append", over its in-memory store)
-- drives the dinner fixtures' histories; this module writes every prefix of
-- each history into one file, beside the @properties.l4@ the fixtures
-- import, runs the @l4@ binary on it once, and reads each prefix's
-- @Result:@ and @Official record:@ back out of the text output (@--json@
-- carries no ledger).
--
-- The comparison is as fine as @l4 run@'s output allows, and no finer: a
-- discharging row is @FULFILLED@, a breaching one @BREACHED@, an advancing
-- one neither, and a passed-over one leaves the official record as the
-- prefix before it left it (and every party's own ledger too) and the
-- residual as it was but for its deadline.
-- The machine re-counts a deadline from every event the obligation
-- scrutinises, taken or not, so a passed-over act still moves the printed
-- countdown (measured: @WITHIN 0 OF closing@ prints as @WITHIN 10590@ after
-- an act passed over at 65010), and the residuals are compared with each
-- @WITHIN@ clause blanked. On top of that, every prefix's official record
-- must be the one the ledger's own replay holds.
module CliTest.Ledger (spec, fixtures) where

import Control.Monad (forM, forM_, unless)
import Data.Char (isDigit)
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.List (isPrefixOf)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

import CliTest.Common

import L4.EvaluateLazy (resolveEvalConfig)
import L4.Ledger.Append
import L4.Ledger.Replay
import L4.Ledger.Row
import L4.Ledger.Store
import L4.TracePolicy (apiDefaultPolicy)

d3Fixture, propertiesFixture, reopenFixture :: FilePath
d3Fixture = "examples/explore/brief/d3-atomic.l4"
propertiesFixture = "examples/explore/brief/properties.l4"
reopenFixture = "examples/explore/ledger/d3-reopen.l4"

fixtures :: [FilePath]
fixtures = [d3Fixture, propertiesFixture, reopenFixture]

-- | One step of a history: set the clock, then propose an act, or let the
-- clock's due ticks through.
data Step
  = Propose Rational T.Text (Maybe Rational)
    -- ^ at this clock, this act by World, perhaps claiming a time
  | Ticks Rational

check, bobBuys, bobCancels, buy, buyUnanswered, deliver, done :: T.Text
check = "`Alice checks whether dinner is bought`"
bobBuys = "`ledger records Bob's purchase`"
bobCancels = "`ledger records Bob's cancellation`"
buy = "`Alice buys dinner` TRUE"
buyUnanswered = "`Alice buys dinner` FALSE"
deliver = "`Messages delivers the message`"
done = "`Alice is done`"

spec :: FilePath -> Spec
spec bin = describe "the instance ledger's histories, replayed under l4 run (two oracles)" $ do
  it "Sequence A: four rows, each prefix replays to the ledger's verdict, and no dinner" $
    twoOracles bin d3Fixture
      [Propose 65100 check Nothing, Propose 65160 bobBuys Nothing, Propose 65220 buy Nothing]
      \ official -> countDinners official `shouldBe` 0

  it "Sequence B: the rows replay FULFILLED, and the dinners ledger holds one dinner" $
    twoOracles bin d3Fixture
      [Propose 65100 check Nothing, Propose 65130 buy Nothing, Propose 65160 bobBuys Nothing, Ticks 75700]
      \ official -> countDinners official `shouldBe` 1

  it "a history with passed-over and reported acts replays in seq order" $
    twoOracles bin d3Fixture
      [ Propose 65100 check (Just 60000), Propose 65110 check Nothing, Propose 65160 bobBuys (Just 65000)
      , Propose 65300 deliver (Just 65280), Propose 65250 done (Just 99999), Propose 65400 buyUnanswered Nothing
      , Ticks 75700 ]
      \ official -> countDinners official `shouldBe` 0

  it "the strict pair's history, taken by the default guard, replays with one dinner bought after the cancellation" $
    twoOracles bin reopenFixture
      [ Propose 65100 check Nothing, Propose 65160 bobBuys Nothing, Propose 65190 bobCancels Nothing
      , Propose 65220 buy Nothing, Ticks 75700 ]
      \ official -> countDinners official `shouldBe` 1

  forM_ (zip [1 :: Int ..] (take 3 (pseudoRandomHistories 20261026))) \ (i, acts) ->
    it ("a pseudo-random order of the evening's acts (" <> show i <> ") replays to the ledger's verdicts") $
      twoOracles bin d3Fixture
        ([ Propose (65000 + 10 * fromIntegral j) a Nothing | (j, a) <- zip [1 :: Int ..] acts ] <> [Ticks 75700])
        \ official -> countDinners official `shouldSatisfy` (<= 1)

-- | Drive the history through a fresh ledger, dump every prefix, run l4,
-- and compare prefix by prefix; then hand the last prefix's official
-- record (as l4 run printed it) to the caller's own check.
twoOracles :: FilePath -> FilePath -> [Step] -> ([T.Text] -> Expectation) -> Expectation
twoOracles bin fixture steps final = do
  dep <- deploymentOf fixture
  st <- newMemoryStore
  clockRef <- newIORef 64800
  cfg <- resolveEvalConfig Nothing apiDefaultPolicy
  let l = MkLedger {store = st, clock = readIORef clockRef, evalConfig = cfg, timeBound = 120000000, retryCap = 8}
      inst = MkInstance dep "history"
  created <- createInstance l inst "`the arrangement`"
  expectAppended created
  forM_ (zip [1 :: Int ..] steps) \ (i, s) -> case s of
    Propose t a claimed -> do
      writeIORef clockRef t
      r <- appendIf l inst MkProposed
        { party = "World", action = a, claimedAt = claimed, decidedAgainst = Nothing
        , idempotencyKey = T.pack (show i), strict = False }
      expectAppended r
    Ticks t -> do
      writeIORef clockRef t
      r <- appendDueTicks l inst
      either (\ e -> expectationFailure ("ticks: " <> show e)) (const (pure ())) r
  rows <- st.readRows (instanceKey inst)
  -- the ledger's own replay of each prefix: its official record
  ledgerOfficial <- forM [1 .. length rows] \ k ->
    replay cfg l.timeBound dep (take k rows) Nothing >>= \ case
      Right r -> pure r.headOfficial
      Left f -> fail ("the ledger could not replay its own prefix " <> show k <> ": " <> show f)
  -- one file: the deployment's source, then one #TRACE per prefix
  let blocks = [ either (error . T.unpack) id (traceBlock (map rowEventAt (take k rows))) | k <- [1 .. length rows] ]
      header = dep.deploymentSource <> "\n\n"
      starts = scanl (\ line b -> line + T.count "\n" b + 1) (T.count "\n" header + 1) blocks
      dump = header <> T.intercalate "\n" blocks
  withSystemTempDirectory "l4-ledger-two-oracles" \ dir -> do
    TIO.writeFile (dir </> "properties.l4") =<< TIO.readFile propertiesFixture
    TIO.writeFile (dir </> "ledger-history.l4") dump
    Output code sout serr <- runL4 bin ["run", "-t", "none", dir </> "ledger-history.l4"]
    unless (code == ExitSuccess) $
      expectationFailure ("l4 run exited " <> show code <> "\n" <> serr)
    let evaluations = parseEvaluations "ledger-history.l4" sout
        results = [ lookup line evaluations | line <- take (length rows) starts ]
    forM_ (zip3 [1 :: Int ..] rows results) \ (k, r, res) -> case res of
      Nothing -> expectationFailure ("l4 run printed no result for the #TRACE of prefix " <> show k <> " (line " <> show (starts !! (k - 1)) <> ")\n" <> sout)
      Just ev -> do
        let previous = if k > 1 then results !! (k - 2) else Nothing
        unless (agrees r.verdict ev previous) $ expectationFailure $ unlines
          [ "prefix " <> show k <> ": the ledger said " <> show r.verdict <> " of " <> show r.event
          , "l4 run said: " <> show ev
          , "and of the prefix before it: " <> show previous ]
        (k, ev.official) `shouldBe` (k, ledgerOfficial !! (k - 1))
    case reverse results of
      (Just lastEv : _) -> final lastEv.official
      _ -> expectationFailure "no last prefix"

-- | Does @l4 run@'s answer for a prefix agree with the verdict the ledger
-- put on the prefix's last row?
agrees :: RowVerdict -> Evaluation -> Maybe Evaluation -> Bool
agrees v ev previous = case v of
  VDischarging -> ev.result == "FULFILLED"
  VBreaching _ -> "BREACHED" `T.isPrefixOf` ev.result
  VAdvancing   -> not (terminal ev)
  VPassedOver _ -> case previous of
    Just p  -> blankWithin ev.result == blankWithin p.result && ev.ledgers == p.ledgers
    Nothing -> False
  where
    terminal e = e.result == "FULFILLED" || "BREACHED" `T.isPrefixOf` e.result

-- | A printed residual with each deadline's countdown blanked: @WITHIN 0 OF
-- closing@ and @WITHIN 10590@ both read @WITHIN _@.
blankWithin :: T.Text -> T.Text
blankWithin t = case T.splitOn "WITHIN " t of
  (first : rest) -> T.intercalate "WITHIN _" (first : map dropCountdown rest)
  [] -> t
  where
    dropCountdown piece =
      let afterNumber = T.dropWhile (\ c -> isDigit c || c == '.') piece
      in case T.stripPrefix " OF " afterNumber of
           Just anchored -> T.dropWhile (/= ' ') anchored
           Nothing -> afterNumber

expectAppended :: Result -> Expectation
expectAppended = \ case
  Appended {} -> pure ()
  other -> expectationFailure ("expected Appended, got " <> show other)

deploymentOf :: FilePath -> IO Deployment
deploymentOf fixture = do
  src <- TIO.readFile fixture
  props <- TIO.readFile propertiesFixture
  pure MkDeployment
    { deploymentId = T.pack fixture
    , deploymentVersion = "1"
    , deploymentSource = src
    , deploymentImports = [("properties", props)]
    , versionedCells = ["dinner status record"]
    }

countDinners :: [T.Text] -> Int
countDinners = length . filter ("COMMIT `dinners bought` IS " `T.isPrefixOf`)

-- | One directive's printed answer: its result, and its official record
-- with each entry's provenance stamp dropped.
data Evaluation = MkEvaluation
  { result   :: T.Text
  , official :: [T.Text]
  , ledgers  :: [T.Text]
    -- ^ every ledger's entries, each under its header, stamps dropped
  }
  deriving stock (Show)

-- | @l4 run@'s text output, as @Evaluation[n] \@ file:line:col-…@ blocks,
-- keyed by the line the directive starts on.
parseEvaluations :: String -> String -> [(Int, Evaluation)]
parseEvaluations file out = go (lines out)
  where
    marker = " @ " <> file <> ":"
    go [] = []
    go (l : rest)
      | "Evaluation[" `isPrefixOf` l, Just line <- lineOf l =
          let (body, more) = break ("Evaluation[" `isPrefixOf`) rest
          in (line, evaluationOf body) : go more
      | otherwise = go rest
    lineOf l = case breakOn marker l of
      Just rest -> case takeWhile isDigit rest of
        [] -> Nothing
        ds -> Just (read ds)
      Nothing -> Nothing
    breakOn pat s
      | pat `isPrefixOf` s = Just (drop (length pat) s)
      | otherwise = case s of
          [] -> Nothing
          (_ : xs) -> breakOn pat xs
    evaluationOf body =
      let afterResult = drop 1 (dropWhile (/= "Result:") body)
          resultLines = takeWhile (not . isHeader) afterResult
          afterOfficial = drop 1 (dropWhile (/= "Official record:") body)
          officialLines = takeWhile ("  " `isPrefixOf`) afterOfficial
      in MkEvaluation
           { result = T.strip (T.unwords (map T.pack (filter (not . null) resultLines)))
           , official = map (stripStamp . T.strip . T.pack) officialLines
           , ledgers = ledgerBlocks body
           }
    -- each "Ledger (p):" or "Official record:" header, then its entries
    ledgerBlocks body = case dropWhile (not . isLedgerHeader) body of
      [] -> []
      (h : more) ->
        let (entries, rest) = span ("  " `isPrefixOf`) more
        in T.pack h : map (stripStamp . T.strip . T.pack) entries <> ledgerBlocks rest
    isLedgerHeader l = "Ledger" `isPrefixOf` l || l == "Official record:"
    isHeader l = any (`isPrefixOf` l) ["Ledger", "Official record:", "Trace:", "Evaluation["]
    -- "COMMIT `x` IS v   [source=COMMIT, at=…]" -> "COMMIT `x` IS v"
    stripStamp t = T.strip (fst (T.breakOn "   [" t))

-- | Orders of the evening's acts from a fixed seed: a little linear
-- congruential generator, so the histories are the same on every run and
-- need no generator library.
pseudoRandomHistories :: Integer -> [[T.Text]]
pseudoRandomHistories seed = chunks (map pick (drop 1 (iterate next seed)))
  where
    alphabet = [check, bobBuys, buy, buyUnanswered, deliver, done]
    next x = (x * 6364136223846793005 + 1442695040888963407) `mod` (2 ^ (63 :: Int))
    pick x = alphabet !! fromInteger ((x `div` 65536) `mod` fromIntegral (length alphabet))
    chunks xs = let (a, b) = splitAt 6 xs in a : chunks b
