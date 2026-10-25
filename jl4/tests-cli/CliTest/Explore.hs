-- | Black-box tests for @l4 explore@ (REGULATIVE-LOWERING-SPEC.md §4, WP1):
-- the exit status a CI job reads, and the coverage line it ends with. The
-- graphs themselves are pinned in @jl4/tests/LtsExplore.hs@; what only the
-- binary can show is that an incomplete exploration does not exit 0
-- (§4.2: "a CI job cannot read a refused run as green").
module CliTest.Explore (spec, fixtures) where

import Data.List (isInfixOf, isPrefixOf)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import Test.Hspec

import CliTest.Common

brief :: FilePath
brief = "examples" </> "explore" </> "brief"

fixtures :: [FilePath]
fixtures = [ brief </> f | f <- ["d1-naive.l4", "d3-atomic.l4", "refused-number.l4", "properties.l4"] ]

-- | The acceptance run of the fixtures' README: the clock bounded at
-- closing, the cells the properties read kept.
acceptance :: [String]
acceptance =
  [ "--until", "75600"
  , "--keep", "open at acceptance", "--keep", "dinners bought", "--keep", "dinners cancelled"
  , "--keep", "dinner status record", "--keep-latest", "belief", "--keep-latest", "plan"
  ]

lastLine :: String -> String
lastLine = \ s -> case lines s of
  [] -> ""
  ls -> last ls

spec :: FilePath -> Spec
spec bin = describe "l4 explore" $ do
  it "explores D1 to the probes' 12 states and 21 transitions, ends with the coverage line, and exits 0" $ do
    Output code sout _ <- runL4 bin (["explore", brief </> "d1-naive.l4"] <> acceptance)
    code `shouldBe` ExitSuccess
    lastLine sout `shouldSatisfy` ("Coverage: 12 states, 21 transitions; frontier exhausted; nothing refused; nothing untried" `isPrefixOf`)

  it "explores D3 to 10 states and 21 transitions and exits 0" $ do
    Output code sout _ <- runL4 bin (["explore", brief </> "d3-atomic.l4"] <> acceptance)
    code `shouldBe` ExitSuccess
    lastLine sout `shouldSatisfy` ("Coverage: 10 states, 21 transitions; frontier exhausted" `isPrefixOf`)

  it "refuses refused-number.l4's NUMBER payload by name and exits 2" $ do
    Output code sout _ <- runL4 bin (["explore", brief </> "refused-number.l4"] <> acceptance)
    code `shouldBe` ExitFailure 2
    let line = lastLine sout
    line `shouldSatisfy` ("Coverage: " `isPrefixOf`)
    line `shouldSatisfy` ("REFUSED 1: `act` of type Act, constructor `ledger records Bob's purchase` (its field `recorded at` is a NUMBER" `isInfixOf`)

  it "exits 3 when the depth bound stops it, and says so" $ do
    Output code sout _ <- runL4 bin (["explore", brief </> "d1-naive.l4", "--max-depth", "2"] <> acceptance)
    code `shouldBe` ExitFailure 3
    lastLine sout `shouldSatisfy` ("frontier NOT exhausted" `isInfixOf`)

  it "puts the coverage line on stderr too when the graph is JSON" $ do
    Output code sout serr <- runL4 bin (["explore", brief </> "refused-number.l4", "--json"] <> acceptance)
    code `shouldBe` ExitFailure 2
    sout `shouldSatisfy` ("\"coverage\"" `isInfixOf`)
    lastLine serr `shouldSatisfy` ("Coverage: " `isPrefixOf`)

  it "exits 1 on a --contract that names no rule" $ do
    Output code _ serr <- runL4 bin ["explore", brief </> "d1-naive.l4", "--contract", "no such rule"]
    code `shouldBe` ExitFailure 1
    serr `shouldSatisfy` ("no rule named `no such rule`" `isInfixOf`)
