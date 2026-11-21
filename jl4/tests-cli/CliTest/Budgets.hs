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
import Data.List (isInfixOf)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import Test.Hspec

import CliTest.Common

dir :: FilePath
dir = "tests-cli" </> "fixtures" </> "budgets"

runaway, neverStops, ends, stopMain, stopLib, stopOnly, stopThenTrace, batchNeverStops, batchImportsStop, batchRows :: FilePath
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

fixtures :: [FilePath]
fixtures = [runaway, neverStops, ends, stopMain, stopLib, stopOnly, stopThenTrace, batchNeverStops, batchImportsStop, batchRows]

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

  it "l4 run --max-calls stops a function that calls itself, names it, and answers the #EVAL after it" $ do
    Output code sout _ <- within bin ["run", "--json", "--max-calls", "1000", neverStops]
    code `shouldBe` ExitFailure 1
    fmap (map fst) (results sout) `shouldBe` Just [Just (Aeson.String "applications"), Nothing]
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
    Output code _ serr <- within bin ["run", "--max-calls", "0", neverStops]
    code `shouldNotBe` ExitSuccess
    serr `shouldSatisfy` ("expected a whole number above 0, or none" `isInfixOf`)

  it "l4 run takes none for either count: a function stopped at --max-calls 1000 answers under none" $ do
    Output code1 sout1 _ <- within bin ["run", "--json", "--max-calls", "1000", ends]
    code1 `shouldBe` ExitFailure 1
    fmap (map fst) (results sout1) `shouldBe` Just [Just (Aeson.String "applications")]
    Output code2 sout2 _ <- within bin ["run", "--json", "--max-calls", "none", "--max-open", "none", ends]
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
      ["batch", "--continue-on-error", "--max-calls", "1000", "--format", "ndjson", batchNeverStops, "--inputs", batchRows]
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
    sout `shouldSatisfy` ("--max-calls" `isInfixOf`)
