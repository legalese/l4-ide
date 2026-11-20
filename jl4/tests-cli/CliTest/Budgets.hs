-- | Black-box tests for smucclaw/l4-ide#1075: a directive whose evaluation
-- would not end is stopped by a limit, its result says which, and the
-- directives after it still run. Before the fix the issue's file at
-- @WAIT UNTIL 60@ ran until the machine ran out of memory, and a function
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

runaway, neverStops :: FilePath
runaway = dir </> "runaway.l4"
neverStops = dir </> "never-stops.l4"

fixtures :: [FilePath]
fixtures = [runaway, neverStops]

-- | Each result of @l4 run --json@, as its "limit" (if any) and its "value".
results :: String -> Maybe [(Maybe Aeson.Value, Maybe Aeson.Value)]
results out = do
  Aeson.Object top <- Aeson.decode (BSL8.pack out)
  Aeson.Array rs <- KeyMap.lookup "results" top
  traverse (\ case
              Aeson.Object r -> Just (KeyMap.lookup "limit" r, KeyMap.lookup "value" r)
              _ -> Nothing)
           (foldr (:) [] rs)

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
    sout `shouldSatisfy` ("runaway.l4:9:" `isInfixOf`)

  it "l4 run --eval-timeout stops a function that never stops, and answers the #EVAL after it" $ do
    Output code sout _ <- within bin ["run", "--json", "--eval-timeout", "1", neverStops]
    code `shouldBe` ExitFailure 1
    fmap (map fst) (results sout) `shouldBe` Just [Just (Aeson.String "time"), Nothing]
    fmap (map snd . drop 1) (results sout) `shouldBe` Just [Just (Aeson.String "4")]

  it "l4 run --max-eval-memory-mb stops it too, and says what it counts" $ do
    Output code sout _ <- within bin ["run", "--json", "--max-eval-memory-mb", "100", neverStops]
    code `shouldBe` ExitFailure 1
    fmap (map fst) (results sout) `shouldBe` Just [Just (Aeson.String "memory"), Nothing]
    sout `shouldSatisfy` ("not only what is kept" `isInfixOf`)

  it "l4 run refuses a limit of 0" $ do
    Output code _ serr <- within bin ["run", "--eval-timeout", "0", neverStops]
    code `shouldNotBe` ExitSuccess
    serr `shouldSatisfy` ("expected a whole number above 0" `isInfixOf`)

  it "l4 batch takes the same two flags" $ do
    Output _ sout _ <- within bin ["batch", "--help"]
    sout `shouldSatisfy` ("--eval-timeout" `isInfixOf`)
    sout `shouldSatisfy` ("--max-eval-memory-mb" `isInfixOf`)
