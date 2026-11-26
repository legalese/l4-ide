-- | Black-box tests for smucclaw/l4-ide#1116: a rule of an imported file with no
-- inputs that reads a ledger kept, across directives, the answer it gave the
-- first directive that forced it.
--
-- @l4 run@ gave each directive (@#TRACE@, @#EVAL@) a fresh copy of the file's
-- own rules, so a rule written in the file read the directive's own ledger.
-- The rules of an imported file were evaluated once for the whole run, and every
-- directive shared them. A rule with no inputs, imported, that reads a ledger
-- (@RECALL@) then answered every later directive with what it answered the first
-- one that forced it; the same rule written in the file did not. Now each
-- directive takes its own copy of the imports' rules
-- ('L4.EvaluateLazy.forEachDirectiveFreshHeap'), and these examples say so.
--
-- THE EXAMPLES WHOSE NAMES DO NOT BEGIN "guard:" WERE RED on the build the tests
-- were written against (@l4@ built from d34c995ef, 2026-11-26), and the fix is
-- the commit that turned them green: 16 of its 26 examples failed and the 10
-- "guard:" examples passed. The guards are:
--
-- * the controls: the same two traces with the rules written in the file, and
--   the skip trace alone, which give the numbers the imported case must give;
-- * the clock-free legs of @l4 lts@ and of @own-eval.l4@. The issue says of
--   @l4 lts@ that it showed the fault only with @JL4_FIXED_NOW@ pinned, and
--   @own-eval.l4@ measured the same; their pinned legs were red;
-- * @own-eval-self.l4@, an imported file with an @#EVAL@ of a rule it defines;
-- * the two rows of @l4 batch@ over a file with no @#TRACE@, which pin each
--   row's own answer and cannot show rows sharing a rule (see the comment at
--   the @l4 batch@ examples);
-- * @ctors.l4@, added with the fix: it guards the repair, not the fault. The
--   copy of the imports' rules closes over the other copies, and each rule of a
--   file must still find the constructors the file declares for itself. It
--   passes on the unfixed build too.
--
-- The fixtures are in @fixtures/run-imported/@. The expected numbers are what
-- the same program gives with every rule in one file (@two-traces-local.l4@ is
-- that file for @two-traces.l4@), measured on an unfixed build with the clock
-- free and with it pinned: the first trace (peek) reads @taken now@ before it
-- commits @taken@, takes its buy, and ends with two @COMMIT@s and
-- @WITHIN 10@; the second (skip) commits first, so its buy is passed over,
-- with one @COMMIT@ and @WITHIN 9@.
module CliTest.RunImported (spec, fixtures) where

import Control.Monad (forM_)
import Data.Aeson (Value (..), eitherDecode)
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString.Lazy.Char8 as BSL8
import Data.Char (isDigit)
import Data.Foldable (toList)
import Data.List (isInfixOf, isPrefixOf, tails)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import Test.Hspec

import CliTest.Common

dir :: FilePath
dir = "tests-cli" </> "fixtures" </> "run-imported"

fixtures :: [FilePath]
fixtures =
  [ dir </> f
  | f <-
      [ "taken.l4", "two-traces.l4", "two-traces-local.l4", "skip-alone.l4", "eval-first.l4"
      , "hop-b.l4", "hop-via.l4", "hop-both.l4", "fn-lib.l4", "fn.l4"
      , "own-eval-b.l4", "own-eval.l4", "own-eval-self-b.l4", "own-eval-self.l4"
      , "trace-alone.l4", "trace-after-skip.l4"
      , "batch-alone.l4", "batch-after-trace.l4", "batch-rows.json", "batch-rows-two.json"
      , "ctor-a.l4", "ctor-b.l4", "ctors.l4"
      ]
  ]

-- | The clock a run is made under: the wall clock, or @JL4_FIXED_NOW@ pinned.
-- The issue measured both, and they differ for @l4 lts@ and for an imported
-- file's own directive.
data Clock = Free | Pinned
  deriving (Eq, Show)

describeClock :: Clock -> String
describeClock = \ case
  Free   -> "the clock free"
  Pinned -> "JL4_FIXED_NOW pinned"

clocks :: [Clock]
clocks = [Free, Pinned]

pinnedNow :: String
pinnedNow = "2025-01-31T15:45:30Z"

-- | Run @l4@ with the clock free (whatever the parent environment says of
-- @JL4_FIXED_NOW@ is dropped) or pinned (by the environment variable, as the
-- issue measured it; @--fixed-now@ gives the same configuration).
runAt :: FilePath -> Clock -> [String] -> IO Output
runAt bin clock args = do
  parent <- getEnvironment
  let rest = filter ((/= "JL4_FIXED_NOW") . fst) parent
      env = case clock of
        Free   -> rest
        Pinned -> ("JL4_FIXED_NOW", pinnedNow) : rest
  runL4WithEnv (Just env) bin args

-- | The text of a run, with the line ends of every platform as one.
clean :: String -> [String]
clean = lines . filter (/= '\r')

-- | The evaluations of @l4 run@'s stdout, each as its lines: a block begins
-- at a line @Evaluation[n] \@ ...@ and runs to the next.
evaluations :: String -> [[String]]
evaluations out = go (clean out)
  where
    go [] = []
    go (l : ls)
      | "Evaluation[" `isPrefixOf` l = let (body, rest) = break ("Evaluation[" `isPrefixOf`) ls in (l : body) : go rest
      | otherwise = go ls

-- | One evaluation as a short line: for a directive whose result is a residual
-- obligation, its deadline and the number of @COMMIT@s in its official record
-- (@WITHIN 10, 2 COMMITs@); for any other, the result as printed (@FALSE@).
summary :: [String] -> String
summary block = case within of
  Just n  -> "WITHIN " <> show n <> ", " <> show commits <> (if commits == 1 then " COMMIT" else " COMMITs")
  Nothing -> result
  where
    result = unwords (map (dropWhile (== ' ')) (takeWhile (not . null) (drop 1 (dropWhile (/= "Result:") block))))
    commits = length [ () | l <- block, "  COMMIT `" `isPrefixOf` l ]
    within = case [ takeWhile isDigit (drop 7 t) | t <- tails result, "WITHIN " `isPrefixOf` t ] of
      (ds : _) | not (null ds) -> Just (read ds :: Int)
      _                        -> Nothing

summaries :: String -> [String]
summaries = map summary . evaluations

-- | An evaluation without its first line, which names the file and the line.
bodyOf :: [String] -> [String]
bodyOf = drop 1

-- | Assert a run exited 0, and give its stdout.
succeeded :: Output -> IO String
succeeded (Output code out err) = do
  case code of
    ExitSuccess -> pure ()
    ExitFailure n -> expectationFailure ("exited " <> show n <> "\n--- stdout ---\n" <> out <> "\n--- stderr ---\n" <> err)
  pure out

firstTraceTakesBuy, secondTracePassesBuyOver :: String
firstTraceTakesBuy = "WITHIN 10, 2 COMMITs"
secondTracePassesBuyOver = "WITHIN 9, 1 COMMIT"

-- | The results of the rows of @l4 batch@'s NDJSON, each row as the list of
-- the @result@ of every directive it ran (a row keeps the file's @#TRACE@s,
-- and its own @#EVAL@ of the export is last).
batchResults :: String -> Either String [[Value]]
batchResults out = mapM row (filter (not . null) (clean out))
  where
    row l = do
      v <- eitherDecode (BSL8.pack l)
      case v of
        Object o | Just (Array xs) <- KeyMap.lookup (Key.fromString "output") o ->
          mapM (\ x -> case x of
                   Object r | Just res <- KeyMap.lookup (Key.fromString "result") r -> Right res
                   _ -> Left ("no result in " <> show x)) (toList xs)
        _ -> Left ("no output in " <> l)

-- | @due by 12 (10 from now)@: the deadline @l4 lts@ words for the first thing
-- owed in each trace it lists, one trace to a block. A trace's block begins at
-- the line that names its contract and its events ("start — after 2 events,
-- the clock stands at 2 (the #TRACE on line 37)").
dueBy :: String -> [String]
dueBy out =
  [ t
  | block <- blocks (clean out)
  , l <- take 1 [ l | l <- block, "due by " `isInfixOf` l ]
  , t <- take 1 [ t | t <- tails l, "due by " `isPrefixOf` t ]
  ]
  where
    blocks ls = case dropWhile (not . isHeader) ls of
      []         -> []
      (h : rest) -> let (body, more) = break isHeader rest in (h : body) : blocks more
    isHeader l = ", the clock stands at " `isInfixOf` l

spec :: FilePath -> Spec
spec bin = describe "smucclaw/l4-ide#1116: a directive reads an imported rule afresh, as it reads the file's own" $ do
  -- 1. the two-file repro
  describe "two traces over `taken now` imported from taken.l4 (two-traces.l4)" $ do
    forM_ clocks \ clock ->
      it ("l4 run, " <> describeClock clock <> ": the second trace passes the buy over, as it does alone") $ do
        out <- succeeded =<< runAt bin clock ["run", dir </> "two-traces.l4"]
        summaries out `shouldBe` [firstTraceTakesBuy, secondTracePassesBuyOver]

    forM_ clocks \ clock -> do
      -- the issue's control: the rules written in the file
      it ("guard: l4 run, " <> describeClock clock <> ": the same two traces with the rules written in the file give the same") $ do
        out <- succeeded =<< runAt bin clock ["run", dir </> "two-traces-local.l4"]
        summaries out `shouldBe` [firstTraceTakesBuy, secondTracePassesBuyOver]
      -- the second trace alone: what the answer is
      it ("guard: l4 run, " <> describeClock clock <> ": the skip trace alone passes the buy over") $ do
        out <- succeeded =<< runAt bin clock ["run", dir </> "skip-alone.l4"]
        summaries out `shouldBe` [secondTracePassesBuyOver]

  -- 2. an #EVAL of the rule where the first trace was
  describe "an #EVAL of the imported rule before the skip trace (eval-first.l4)" $
    forM_ clocks \ clock ->
      it ("l4 run, " <> describeClock clock <> ": the trace after the #EVAL passes the buy over, as it does alone") $ do
        out <- succeeded =<< runAt bin clock ["run", dir </> "eval-first.l4"]
        summaries out `shouldBe` ["FALSE", secondTracePassesBuyOver]

  -- 3. l4 lts
  describe "l4 lts over two-traces.l4" $
    forM_ clocks \ clock ->
      it ((if clock == Free then "guard: " else "") <> "l4 lts, " <> describeClock clock <> ": the second trace's deadline reads due by 11 (9 from now)") $ do
        out <- succeeded =<< runAt bin clock ["lts", dir </> "two-traces.l4"]
        dueBy out `shouldBe` ["due by 12 (10 from now)", "due by 11 (9 from now)"]

  -- 4. two hops
  describe "the rule two import hops away" $ do
    forM_ clocks \ clock -> do
      it ("hop-via.l4, " <> describeClock clock <> ": `taken now` in taken.l4, a rule over it in hop-b.l4, used from a file that imports hop-b.l4 only") $ do
        out <- succeeded =<< runAt bin clock ["run", dir </> "hop-via.l4"]
        summaries out `shouldBe` [firstTraceTakesBuy, secondTracePassesBuyOver]
      it ("hop-both.l4, " <> describeClock clock <> ": the same, from a file that imports taken.l4 and hop-b.l4, using each") $ do
        out <- succeeded =<< runAt bin clock ["run", dir </> "hop-both.l4"]
        summaries out `shouldBe` [firstTraceTakesBuy, secondTracePassesBuyOver]

  -- 5. an imported function
  describe "an imported rule with an input that names an imported rule that reads a ledger (fn.l4)" $
    forM_ clocks \ clock ->
      it ("l4 run, " <> describeClock clock <> ": `closed to` 1, called from both traces, reads `taken now` afresh in each") $ do
        out <- succeeded =<< runAt bin clock ["run", dir </> "fn.l4"]
        summaries out `shouldBe` [firstTraceTakesBuy, secondTracePassesBuyOver]

  -- 6. the imported file has a directive of its own
  describe "an imported file with an #EVAL of its own" $
    forM_ clocks \ clock -> do
      it ((if clock == Free then "guard: " else "") <> "own-eval.l4, " <> describeClock clock
          <> ": an #EVAL in the imported file of `taken now`, which it imports, does not change the importer's answer") $ do
        out <- succeeded =<< runAt bin clock ["run", dir </> "own-eval.l4"]
        summaries out `shouldBe` [secondTracePassesBuyOver]
      it ("guard: own-eval-self.l4, " <> describeClock clock <> ": an #EVAL in the imported file of a rule it defines does not change the importer's answer") $ do
        out <- succeeded =<< runAt bin clock ["run", dir </> "own-eval-self.l4"]
        summaries out `shouldBe` [secondTracePassesBuyOver]

  -- 7. the trace of an #EVALTRACE after a directive that forced the rule
  describe "the trace of an #EVALTRACE of the imported rule" $
    forM_ clocks \ clock ->
      it ("l4 run, " <> describeClock clock <> ": after a trace that forced it, it reads FALSE, as it does alone") $ do
        alone <- succeeded =<< runAt bin clock ["run", dir </> "trace-alone.l4"]
        later <- succeeded =<< runAt bin clock ["run", dir </> "trace-after-skip.l4"]
        let aloneBlock = concatMap bodyOf (take 1 (evaluations alone))
            laterBlock = concatMap bodyOf (take 1 (drop 1 (evaluations later)))
        -- the run alone is the oracle, so that the example fails for a
        -- reason it names if that run is not what it should be
        aloneBlock `shouldSatisfy` any ("└ FALSE" `isInfixOf`)
        laterBlock `shouldBe` aloneBlock

  -- 8. l4 batch
  --
  -- Rows do not share an imported rule: 'processRow' (jl4/app/L4/Cli/Batch.hs:554)
  -- gives each row its own 'runOneshot' (jl4/app/L4/Cli/Common.hs:359), which
  -- builds a new engine state (jl4-lsp/src/LSP/L4/Oneshot.hs:125-129), and with it
  -- a new heap for the file's imports. What a row does share is the module it
  -- runs: the file's directives that `l4 batch` keeps (#TRACE and #CONTRACT; it
  -- drops #EVAL, #EVALTRACE, #CHECK and #ASSERT, jl4-core/src/L4/DirectiveFilter.hs)
  -- and then the row's own #EVAL of the export, which share the file's imports.
  describe "l4 batch over an @export that reads the imported rule" $ do
    forM_ clocks \ clock -> do
      it ("guard: batch-alone.l4, " <> describeClock clock <> ": two rows read an empty ledger and each answers FALSE; this cannot show a row sharing an imported rule with another, since each row's engine state is its own") $ do
        out <- succeeded =<< runAt bin clock ["batch", dir </> "batch-alone.l4", "-i", dir </> "batch-rows-two.json"]
        batchResults out `shouldBe` Right [[Bool False], [Bool False]]
      it ("batch-after-trace.l4, " <> describeClock clock <> ": the row's own evaluation of `taken now` reads its own ledger, not the one the file's #TRACE left") $ do
        out <- succeeded =<< runAt bin clock ["batch", dir </> "batch-after-trace.l4", "-i", dir </> "batch-rows.json"]
        -- the file's #TRACE answers with an obligation, the row's #EVAL last
        batchResults out `shouldBe` Right [[String "<obligation>", Bool False]]

  -- 9. the constructors a file declares for itself, in the rules of an import
  --
  -- Not the fault: a guard on the repair. Each copy of an imported rule closes
  -- over the copies of the others laid over the environment it had, and a
  -- constructor is not copied, so it must still be found in that environment.
  -- Two files each declare an enum and use it in a rule that reads `taken now`.
  describe "constructors an imported file declares for itself (ctors.l4)" $
    forM_ clocks \ clock ->
      it ("guard: " <> describeClock clock <> ": each imported rule finds the constructors of its own file, under each directive") $ do
        out <- succeeded =<< runAt bin clock ["run", dir </> "ctors.l4"]
        summaries out `shouldBe` ["ajar", "raised", "ajar", "raised"]
