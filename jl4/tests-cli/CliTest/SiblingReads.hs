-- | Black-box tests for smucclaw/l4-ide#1069: a compound whose operands read
-- each other's records is refused by every front end that evaluates it, and
-- warned about by @l4 check@. Before the fix @l4 explore@ said the issue's
-- property held, exit 0, and @l4 run@ printed an official record out of time
-- order, exit 0; each test below fails on a binary built before it.
module CliTest.SiblingReads (spec, fixtures) where

import Data.List (isInfixOf)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import Test.Hspec

import CliTest.Common

dir :: FilePath
dir = "tests-cli" </> "fixtures" </> "sibling-reads"

dinnerAB, writerFirst, readerFirst, dinnerOne :: FilePath
dinnerAB = dir </> "dinner-ab.l4"
writerFirst = dir </> "writer-first.l4"
readerFirst = dir </> "reader-first.l4"
-- the single-party original, which has no RAND and must not change
dinnerOne = ".." </> "doc" </> "reference" </> "regulative" </> "explore-example.l4"

fixtures :: [FilePath]
fixtures = [dinnerAB, writerFirst, readerFirst, dinnerOne]

property :: [String]
property = ["--until", "100", "--always", "every dinner was accepted while open"]

spec :: FilePath -> Spec
spec bin = describe "operands that read each other's records (smucclaw/l4-ide#1069)" $ do
  it "l4 run refuses the issue's file, exit 1, naming the record and both sides" $ do
    Output code sout serr <- runL4 bin ["run", dinnerAB]
    code `shouldBe` ExitFailure 1
    let out = sout <> serr
    for_' ["read each other's records", "`dinner status record`", "`Alice's evening`", "`Bob's evening`"] $ \ w ->
      (w, w `isInfixOf` out) `shouldBe` (w, True)

  it "l4 explore no longer says the issue's property holds, and does not exit 0" $ do
    Output code sout serr <- runL4 bin (["explore", dinnerAB] <> property)
    code `shouldNotBe` ExitSuccess
    let out = sout <> serr
    out `shouldNotSatisfy` ("holds in every one of" `isInfixOf`)
    out `shouldSatisfy` ("read each other's records" `isInfixOf`)

  it "l4 explore still finds the race in the single-party original, exit 4" $ do
    Output code sout _ <- runL4 bin (["explore", dinnerOne] <> property)
    code `shouldBe` ExitFailure 4
    sout `shouldSatisfy` ("violated after 3 events" `isInfixOf`)

  it "l4 check warns on the issue's file and still exits 0" $ do
    Output code sout serr <- runL4 bin ["check", dinnerAB]
    code `shouldBe` ExitSuccess
    (sout <> serr) `shouldSatisfy` ("may read each other's records" `isInfixOf`)

  it "l4 run runs a record made on the left before the right side reads it, and refuses the swapped file" $ do
    Output ok _ _ <- runL4 bin ["run", writerFirst]
    ok `shouldBe` ExitSuccess
    Output refused sout serr <- runL4 bin ["run", readerFirst]
    refused `shouldBe` ExitFailure 1
    (sout <> serr) `shouldSatisfy` ("read each other's records" `isInfixOf`)
  where
    for_' xs f = mapM_ f xs
