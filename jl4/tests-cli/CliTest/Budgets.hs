-- | Black-box tests for smucclaw/l4-ide#1075: a directive whose evaluation
-- would not end is stopped by a limit, and its result says which. After a
-- counted limit (open obligations, function applications) the directives
-- after it still run; after the opt-in time or memory limit none does, and
-- each says so (ruling L2 of the Recursion Limits bench). Before the fix the issue's file at
-- @WAITUNTIL 60@ ran until the machine ran out of memory, and a function
-- that calls itself with new inputs ran forever; each test here is run
-- under a timeout so that a limit that never fires fails the test instead
-- of hanging the suite.
module CliTest.Budgets (spec, fixtures) where

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString.Lazy.Char8 as BSL8
import Data.Foldable (for_)
import Data.List (isInfixOf, isPrefixOf, tails)
import System.Directory (doesFileExist, makeAbsolute)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (CreateProcess (..), proc, readCreateProcessWithExitCode)
import Test.Hspec

import CliTest.Common

dir :: FilePath
dir = "tests-cli" </> "fixtures" </> "budgets"

runaway, neverStops, ends, stopMain, stopLib, stopOnly, stopThenTrace, batchNeverStops, batchImportsStop, batchRows, proveSteps, coverageSteps, replTrace, neverStopsTraced :: FilePath
runaway = dir </> "runaway.l4"
neverStops = dir </> "never-stops.l4"
ends = dir </> "ends.l4"
stopMain = dir </> "stopmain.l4"
stopLib = dir </> "stoplib.l4"
stopOnly = dir </> "stoponly.l4"
stopThenTrace = dir </> "stop-then-trace.l4"
batchNeverStops = dir </> "batch-never-stops.l4"
batchImportsStop = dir </> "batch-imports-stop.l4"
batchRows = dir </> "batch-never-stops.json"
proveSteps = dir </> "prove-steps.l4"
coverageSteps = dir </> "coverage-steps.l4"
replTrace = dir </> "repl-trace.l4"
neverStopsTraced = dir </> "never-stops-traced.l4"

fixtures :: [FilePath]
fixtures = [runaway, neverStops, ends, stopMain, stopLib, stopOnly, stopThenTrace, batchNeverStops, batchImportsStop, batchRows, proveSteps, coverageSteps, replTrace, neverStopsTraced]

-- | Each result of @l4 run --json@, as its "limit" (if any) and its "value".
results :: String -> Maybe [(Maybe Aeson.Value, Maybe Aeson.Value)]
results = resultsBy \ r -> (KeyMap.lookup "limit" r, KeyMap.lookup "value" r)

-- | Each result's "evaluated" key: present, and false, only on a directive
-- the run stopped before.
evaluated :: String -> Maybe [Maybe Aeson.Value]
evaluated = resultsBy (KeyMap.lookup "evaluated")

resultsBy :: (Aeson.Object -> a) -> String -> Maybe [a]
resultsBy pick out = do
  Aeson.Object top <- Aeson.decode (BSL8.pack out)
  Aeson.Array rs <- KeyMap.lookup "results" top
  traverse (\ case
              Aeson.Object r -> Just (pick r)
              _ -> Nothing)
           (foldr (:) [] rs)

-- | The "status" of one envelope of @l4 batch --format ndjson@.
status :: String -> Maybe Aeson.Value
status line = do
  Aeson.Object env <- Aeson.decode (BSL8.pack line)
  KeyMap.lookup "status" env

-- | Run, giving up after a minute: every case here ends in a few seconds.
within :: FilePath -> [String] -> IO Output
within bin args = runL4Within 60 bin args >>= \ case
  Nothing -> expectationFailure ("l4 " <> unwords args <> " did not finish within 60 s: a limit did not fire") >> fail "timeout"
  Just o -> pure o

spec :: FilePath -> Spec
spec bin = describe "limits on one directive (smucclaw/l4-ide#1075)" $ do
  it "l4 run stops the issue's #TRACE at the limit on open obligations, names the rule, and answers the #EVAL after it, exit 1" $ do
    Output code sout _ <- within bin ["run", "--json", runaway]
    code `shouldBe` ExitFailure 1
    fmap (map fst) (results sout) `shouldBe` Just [Just (Aeson.String "obligations"), Nothing]
    fmap (map snd . drop 1) (results sout) `shouldBe` Just [Just (Aeson.String "2")]
    sout `shouldSatisfy` ("obligations were open at once" `isInfixOf`)
    sout `shouldSatisfy` ("in w3, at runaway.l4:9:" `isInfixOf`)
    sout `shouldSatisfy` ("--max-open none" `isInfixOf`)

  it "l4 run --max-open sets the limit on open obligations" $ do
    Output code sout _ <- within bin ["run", "--json", "--max-open", "5", runaway]
    code `shouldBe` ExitFailure 1
    fmap (map fst) (results sout) `shouldBe` Just [Just (Aeson.String "obligations"), Nothing]
    sout `shouldSatisfy` ("more than 5 obligations" `isInfixOf`)

  it "l4 run --max-steps stops a function that calls itself, names it, and answers the #EVAL after it" $ do
    Output code sout _ <- within bin ["run", "--json", "--max-steps", "1000", neverStops]
    code `shouldBe` ExitFailure 1
    fmap (map fst) (results sout) `shouldBe` Just [Just (Aeson.String "steps"), Nothing]
    fmap (map snd . drop 1) (results sout) `shouldBe` Just [Just (Aeson.String "4")]
    sout `shouldSatisfy` ("in countDown, at never-stops.l4:" `isInfixOf`)

  it "l4 run --eval-timeout stops the run at a function that never stops: the #EVAL after it is not evaluated" $ do
    Output code sout _ <- within bin ["run", "--json", "--eval-timeout", "1", neverStops]
    code `shouldBe` ExitFailure 1
    fmap (map fst) (results sout) `shouldBe` Just [Just (Aeson.String "time"), Just (Aeson.String "time")]
    evaluated sout `shouldBe` Just [Nothing, Just (Aeson.Bool False)]
    sout `shouldSatisfy` ("I did not evaluate this: the run stopped at never-stops.l4:11:" `isInfixOf`)

  it "l4 run --max-eval-memory-mb stops the run too, and says what it counts" $ do
    Output code sout _ <- within bin ["run", "--json", "--max-eval-memory-mb", "100", neverStops]
    code `shouldBe` ExitFailure 1
    fmap (map fst) (results sout) `shouldBe` Just [Just (Aeson.String "memory"), Just (Aeson.String "memory")]
    evaluated sout `shouldBe` Just [Nothing, Just (Aeson.Bool False)]
    sout `shouldSatisfy` ("not only what is kept" `isInfixOf`)

  it "l4 run refuses a limit of 0" $ do
    Output code _ serr <- within bin ["run", "--eval-timeout", "0", neverStops]
    code `shouldNotBe` ExitSuccess
    serr `shouldSatisfy` ("expected a whole number above 0" `isInfixOf`)

  it "l4 run refuses a count of 0" $ do
    Output code _ serr <- within bin ["run", "--max-steps", "0", neverStops]
    code `shouldNotBe` ExitSuccess
    serr `shouldSatisfy` ("expected a whole number above 0, or none" `isInfixOf`)

  it "l4 run takes none for either count: a function stopped at --max-steps 1000 answers under none" $ do
    Output code1 sout1 _ <- within bin ["run", "--json", "--max-steps", "1000", ends]
    code1 `shouldBe` ExitFailure 1
    fmap (map fst) (results sout1) `shouldBe` Just [Just (Aeson.String "steps")]
    Output code2 sout2 _ <- within bin ["run", "--json", "--max-steps", "none", "--max-open", "none", ends]
    code2 `shouldBe` ExitSuccess
    fmap (map snd) (results sout2) `shouldBe` Just [Just (Aeson.String "0")]

  it "l4 run --eval-timeout stops the run at an imported file's #EVAL: this file's #EVAL is not evaluated" $ do
    Output code sout _ <- within bin ["run", "--json", "--eval-timeout", "1", stopMain]
    code `shouldBe` ExitFailure 1
    sout `shouldSatisfy` ("I did not evaluate this: the run stopped at stoplib.l4:8:" `isInfixOf`)

  it "l4 run --eval-timeout fails, and says where the run stopped, when it stopped in an imported file and this file has no #EVAL" $ do
    Output code sout serr <- within bin ["run", "--eval-timeout", "1", stopOnly]
    code `shouldBe` ExitFailure 1
    sout `shouldNotSatisfy` ("Checking succeeded" `isInfixOf`)
    serr `shouldSatisfy` ("l4 run: stoplib.l4:8:" `isInfixOf`)
    serr `shouldSatisfy` ("I stopped the run" `isInfixOf`)

  it "l4 run --json says ok false when the run stopped in an imported file and this file has no #EVAL, and gives the place on stderr" $ do
    Output code sout serr <- within bin ["run", "--json", "--eval-timeout", "1", stopOnly]
    code `shouldBe` ExitFailure 1
    (do Aeson.Object o <- Aeson.decode (BSL8.pack sout); KeyMap.lookup "ok" o) `shouldBe` Just (Aeson.Bool False)
    serr `shouldSatisfy` ("l4 run: stoplib.l4:8:" `isInfixOf`)

  it "l4 run --eval-timeout: an #EVALTRACE after the stop says it was not evaluated, not that its trace failed" $ do
    Output code sout _ <- within bin ["run", "--eval-timeout", "1", stopThenTrace]
    code `shouldBe` ExitFailure 1
    sout `shouldSatisfy` ("(not evaluated)" `isInfixOf`)
    sout `shouldNotSatisfy` ("internal error" `isInfixOf`)

  it "l4 batch stops at a row past the time limit, even with --continue-on-error, and says so" $ do
    Output code sout serr <- within bin
      ["batch", "--continue-on-error", "--eval-timeout", "1", "--format", "ndjson", batchNeverStops, "--inputs", batchRows]
    code `shouldBe` ExitFailure 1
    map status (lines (filter (/= '\r') sout)) `shouldBe` [Just (Aeson.String "success"), Just (Aeson.String "error")]
    serr `shouldSatisfy` ("stopped at row 2" `isInfixOf`)

  it "l4 batch goes on past a row stopped by a count, under --continue-on-error" $ do
    Output code sout _ <- within bin
      ["batch", "--continue-on-error", "--max-steps", "1000", "--format", "ndjson", batchNeverStops, "--inputs", batchRows]
    code `shouldBe` ExitFailure 1
    map status (lines (filter (/= '\r') sout)) `shouldBe` map (Just . Aeson.String) ["success", "error", "success"]

  it "l4 batch says where the run stopped when an imported file's #EVAL stops it, at row 1" $ do
    Output code _ serr <- within bin
      ["batch", "--continue-on-error", "--eval-timeout", "1", "--format", "ndjson", batchImportsStop, "--inputs", batchRows]
    code `shouldBe` ExitFailure 1
    serr `shouldSatisfy` ("stopped at row 1: the run stopped at stoplib.l4:8:" `isInfixOf`)

  it "l4 batch takes the same four flags" $ do
    Output _ sout _ <- within bin ["batch", "--help"]
    sout `shouldSatisfy` ("--eval-timeout" `isInfixOf`)
    sout `shouldSatisfy` ("--max-eval-memory-mb" `isInfixOf`)
    sout `shouldSatisfy` ("--max-open" `isInfixOf`)
    sout `shouldSatisfy` ("--max-steps" `isInfixOf`)

  -- The REPL ran each plain line as an #EVAL and collected its trace, about
  -- 10 KB a step, then printed only the answer. It now collects a trace only
  -- for a :trace or :traceascii line, which shows it (decided by Claude 2026-11-21, pending Meng's review). What
  -- the REPL keeps is pinned in jl4-core's BudgetSpec; this pins what it shows.
  describe "the REPL keeps a trace only where it shows one (decided by Claude 2026-11-21, pending Meng's review)" $ do
    mRepl <- runIO $ lookupEnv "L4_REPL_BIN" >>= \ case
      Just p -> do
        ok <- doesFileExist p
        pure (if ok then Just p else Nothing)
      Nothing -> do
        (code, out, _) <- readCreateProcessWithExitCode (proc "cabal" ["list-bin", "exe:jl4-repl"]) ""
        let path = takeWhile (`notElem` ("\r\n" :: String)) out
        ok <- doesFileExist path
        pure (if code == ExitSuccess && ok then Just path else Nothing)
    -- the REPL's output for these lines, then :quit, on repl-trace.l4
    let session queries check = case mRepl of
          Nothing -> pendingWith "jl4-repl was not found: set L4_REPL_BIN, or build it with `cabal build jl4-repl`"
          Just repl -> do
            file <- makeAbsolute replTrace
            -- in a directory of its own, because the REPL keeps a history file there
            sout <- withSystemTempDirectory "l4-repl-trace" \ work -> do
              (_, o, _) <- readCreateProcessWithExitCode (proc repl [file]) {cwd = Just work}
                             (unlines (queries <> [":quit"]))
              pure (filter (/= '\r') o)
            check sout
        times needle hay = length (filter (needle `isPrefixOf`) (tails hay))
    it "answers a plain line as before, and :trace and :traceascii still show a trace" $
      session ["`double` 3", ":trace `double` 3", ":traceascii `double` 3"] \ sout -> do
        sout `shouldSatisfy` ("jl4> 6\n" `isInfixOf`)
        sout `shouldSatisfy` ("digraph" `isInfixOf`)
        sout `shouldSatisfy` ("double OF 3" `isInfixOf`)
        sout `shouldSatisfy` ("Trace:" `isInfixOf`)

    -- the trace commands pass a line already written as a directive through
    -- unchanged, so they trace it themselves rather than rely on the policy
    -- for plain lines (decided by Claude 2026-11-21, pending Meng's review)
    it ":trace and :traceascii show an #EVAL line's trace, and :traceascii its value" $
      session [":trace #EVAL `double` 3", ":traceascii #EVAL `double` 3"] \ sout -> do
        times "digraph" sout `shouldBe` 1
        sout `shouldSatisfy` ("Result: 6\n\nTrace:\n" `isInfixOf`)
        sout `shouldNotSatisfy` ("no trace available" `isInfixOf`)

    it ":trace and :traceascii show an #ASSERT line's trace, and :traceascii its outcome" $
      session [":trace #ASSERT `double` 3 EQUALS 6", ":traceascii #ASSERT `double` 3 EQUALS 7"] \ sout -> do
        times "digraph" sout `shouldBe` 1
        sout `shouldSatisfy` ("Result: False (assertion failed)\n\nTrace:\n" `isInfixOf`)
        sout `shouldNotSatisfy` ("no trace available" `isInfixOf`)

    it "a #CHECK line has nothing to trace, on either command, as before" $
      session [":trace #CHECK `double` 3", ":traceascii #CHECK `double` 3"] \ sout ->
        times "jl4> (no result)\n" sout `shouldBe` 2

  -- A trace keeps a record of every step, so a directive that collects one
  -- has a lower work number of its own (decided by Claude 2026-11-21, pending
  -- Meng's review). Each stop at 100,000 holds about 1 GB.
  describe "a directive that collects a trace" $ do
    it "l4 run stops a runaway #EVALTRACE at 100,000 steps, and says its limit is the lower one" $ do
      Output code sout serr <- within bin ["run", neverStopsTraced]
      code `shouldBe` ExitFailure 1
      (sout <> serr) `shouldSatisfy` ("more than 100000 steps" `isInfixOf`)
      (sout <> serr) `shouldSatisfy` ("so it has a lower limit than the 10000000 steps of one that collects none" `isInfixOf`)
      (sout <> serr) `shouldSatisfy` ("--max-steps N to set both limits to N" `isInfixOf`)

    it "l4 trace stops it at the same number" $ do
      Output code _ serr <- within bin ["trace", neverStopsTraced]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("more than 100000 steps" `isInfixOf`)

    it "--max-steps sets it too, and then the message is the usual one" $ do
      Output code sout serr <- within bin ["run", "--max-steps", "1000", neverStopsTraced]
      code `shouldBe` ExitFailure 1
      (sout <> serr) `shouldSatisfy` ("more than 1000 steps" `isInfixOf`)
      (sout <> serr) `shouldNotSatisfy` ("collects a trace" `isInfixOf`)

  -- Ruled by Meng 2026-11-21, extending L2: every other command that evaluates
  -- counts too, by default, with the same flags; and none of them reads an
  -- answer off an evaluation a limit stopped.
  describe "every command that evaluates (ruled by Meng 2026-11-21, extending L2)" $ do
    it "l4 trace names a directive a count stopped, and fails, where it used to draw nothing and exit 0" $ do
      Output code _ serr <- within bin ["trace", "--max-steps", "1000", neverStops]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("l4 trace: I stopped evaluating: it took more than 1000 steps" `isInfixOf`)

    it "l4 lts stops the issue's #TRACE at the default open number, where it used to run out of memory" $ do
      Output _ sout _ <- within bin ["lts", runaway]
      sout `shouldSatisfy` ("more than 10000 obligations were open at once" `isInfixOf`)

    it "l4 lts takes --max-open" $ do
      Output _ sout _ <- within bin ["lts", "--max-open", "100", runaway]
      sout `shouldSatisfy` ("more than 100 obligations were open at once" `isInfixOf`)

    it "l4 explore refuses a contract whose outset a count stopped, and says why" $ do
      Output code sout serr <- within bin ["explore", "--max-steps", "1", runaway, "--contract", "w1"]
      code `shouldBe` ExitFailure 1
      (sout <> serr) `shouldSatisfy` ("could not be run at its outset: I stopped evaluating: it took more than 1 steps" `isInfixOf`)

    it "l4 coverage covers the decision under the default limits" $ do
      Output code sout _ <- within bin ["coverage", coverageSteps]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("1 decision covered" `isInfixOf`)

    it "l4 coverage does not cover a decision whose inputs a count stopped, and says why, rather than read them as raising" $ do
      Output code sout _ <- within bin ["coverage", "--max-steps", "1", coverageSteps]
      code `shouldBe` ExitFailure 3
      sout `shouldSatisfy` ("NOT COVERED: the evaluator stopped at a limit at an input it tried: I stopped evaluating" `isInfixOf`)
      sout `shouldNotSatisfy` ("raises" `isInfixOf`)

    it "l4 prove proves the first assertion and refutes the second under the default limits" $ withZ3 $ do
      Output code sout _ <- within bin ["prove", proveSteps]
      code `shouldBe` ExitFailure 2
      sout `shouldSatisfy` ("proved   prove-steps.l4:18:" `isInfixOf`)
      sout `shouldSatisfy` ("refuted  prove-steps.l4:21:" `isInfixOf`)

    it "l4 prove calls both unknown when a count stopped the evaluator, neither proved nor refuted" $ withZ3 $ do
      Output code sout _ <- within bin ["prove", "--max-steps", "1", proveSteps]
      code `shouldBe` ExitFailure 3
      sout `shouldSatisfy` ("unknown  prove-steps.l4:18:" `isInfixOf`)
      sout `shouldSatisfy` ("unknown  prove-steps.l4:21:" `isInfixOf`)
      sout `shouldSatisfy` ("the evaluator stopped at a limit before it could decide it" `isInfixOf`)
      sout `shouldNotSatisfy` ("refuted  prove-steps" `isInfixOf`)

    it "each of them takes the same four flags" $
      for_ ["trace", "lts", "explore", "coverage", "prove", "verify"] \ verb -> do
        Output _ sout _ <- within bin [verb, "--help"]
        for_ ["--max-open", "--max-steps", "--eval-timeout", "--max-eval-memory-mb"] \ flag ->
          (verb, sout) `shouldSatisfy` ((flag `isInfixOf`) . snd)
