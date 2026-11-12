-- | Black-box tests for smucclaw/l4-ide#1069: operands that read each
-- other's records. Before the fix @l4 explore@ said the issue's property held,
-- exit 0, and @l4 run@ printed an official record out of time order, exit 0.
-- A @RAND@'s sides now take the trace's events in step, so the issue's file
-- runs with the record in time order and @l4 explore@ finds the race; an
-- @ROR@, which still runs one side after the other, is refused where that
-- order would change the answer, and is the only compound @l4 check@ warns
-- about. Each test below fails on a binary built before the fix.
module CliTest.SiblingReads (spec, fixtures) where

import Data.List (isInfixOf, isPrefixOf, stripPrefix)
import Data.Maybe (mapMaybe)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import Test.Hspec

import CliTest.Common

dir :: FilePath
dir = "tests-cli" </> "fixtures" </> "sibling-reads"

dinnerAB, writerFirst, readerFirst, rorReaderFirst, dinnerOne :: FilePath
dinnerAB = dir </> "dinner-ab.l4"
writerFirst = dir </> "writer-first.l4"
readerFirst = dir </> "reader-first.l4"
rorReaderFirst = dir </> "ror-reader-first.l4"
-- the single-party original, which has no RAND and must not change
dinnerOne = ".." </> "doc" </> "reference" </> "regulative" </> "explore-example.l4"

fixtures :: [FilePath]
fixtures = [dinnerAB, writerFirst, readerFirst, rorReaderFirst, dinnerOne]

property :: [String]
property = ["--until", "100", "--always", "every dinner was accepted while open"]

-- | The official record's entries, as @l4 run@ prints them after "Result:",
-- with each entry's bracketed stamp dropped.
officialRecord :: String -> [String]
officialRecord out =
  let afterResult = drop 1 (dropWhile (/= "Result:") (lines out))
      record = takeWhile (\ l -> "  " `isPrefixOf` l) (drop 1 (dropWhile (/= "Official record:") afterResult))
  in map (trim . takeWhile (/= '[')) record
  where
    trim = reverse . dropWhile (== ' ') . reverse . dropWhile (== ' ')

spec :: FilePath -> Spec
spec bin = describe "operands that read each other's records (smucclaw/l4-ide#1069)" $ do
  it "l4 run runs the issue's file, exit 0, with the official record in the order of the events" $ do
    Output code sout serr <- runL4 bin ["run", dinnerAB]
    (code, serr) `shouldBe` (ExitSuccess, serr)
    officialRecord sout `shouldBe`
      [ "COMMIT `dinner status record` IS opened"
      , "COMMIT `dinner status record` IS taken"
      , "COMMIT `dinners bought` IS `dinner for two`"
      , "COMMIT `open at acceptance` IS FALSE"
      ]

  it "l4 explore finds the issue's race, exit 4, with a counterexample in Alice's and Bob's names" $ do
    Output code sout _ <- runL4 bin (["explore", dinnerAB] <> property)
    code `shouldBe` ExitFailure 4
    sout `shouldSatisfy` ("violated after 3 events" `isInfixOf`)
    sout `shouldNotSatisfy` ("read each other's records" `isInfixOf`)
    let acts = mapMaybe (stripPrefix "    PARTY ") (lines sout)
    take 3 (map (takeWhile (/= ' ')) acts) `shouldBe` ["Alice", "Bob", "Alice"]
    take 3 (map (\ a -> "`buys dinner`" `isInfixOf` a) acts) `shouldBe` [False, True, True]

  it "l4 explore still finds the race in the single-party original, exit 4" $ do
    Output code sout _ <- runL4 bin (["explore", dinnerOne] <> property)
    code `shouldBe` ExitFailure 4
    sout `shouldSatisfy` ("violated after 3 events" `isInfixOf`)

  it "l4 check does not warn on a RAND, whose sides run in step" $ do
    Output code sout serr <- runL4 bin ["check", dinnerAB]
    code `shouldBe` ExitSuccess
    (sout <> serr) `shouldNotSatisfy` ("read each other's records" `isInfixOf`)

  it "l4 run gives the same answer with the sides of the RAND either way round" $ do
    Output wcode wout _ <- runL4 bin ["run", writerFirst]
    Output rcode rout _ <- runL4 bin ["run", readerFirst]
    (wcode, rcode) `shouldBe` (ExitSuccess, ExitSuccess)
    officialRecord wout `shouldBe` ["COMMIT `notice given` IS TRUE", "COMMIT `possession sought` IS TRUE"]
    officialRecord rout `shouldBe` officialRecord wout

  it "l4 run refuses an ROR whose left side reads a record its right side makes earlier, and l4 check warns" $ do
    Output code sout serr <- runL4 bin ["run", rorReaderFirst]
    code `shouldBe` ExitFailure 1
    let out = sout <> serr
    for_' ["read each other's records", "`notice given`", "`possession`", "`notice`", "ROR"] $ \ w ->
      (w, w `isInfixOf` out) `shouldBe` (w, True)
    Output ccode csout cserr <- runL4 bin ["check", rorReaderFirst]
    ccode `shouldBe` ExitSuccess
    (csout <> cserr) `shouldSatisfy` ("may read each other's records" `isInfixOf`)
  where
    for_' xs f = mapM_ f xs
