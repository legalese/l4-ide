-- | Black-box tests for smucclaw/l4-ide#1078: JSONDECODE in a position whose
-- type the program fixes only later, by how the result is used.
--
-- The single-module cases are @#ASSERT@s in
-- @examples/ok/jsondecode-inferred-target.l4@. These are the two kinds that
-- an assertion cannot hold: a decode written in an IMPORTED module, and a
-- decode whose JSON does not fit its type, which stops the run. Before the
-- fix the first printed the "reached a CONSIDER" error for @NOTHING@, exit 1,
-- and the other two printed an "Internal error ... Please report this as a
-- bug", exit 1; all three tests fail on a binary built before it (536c95336,
-- measured 2026-11-21).
module CliTest.JsonDecode (spec, fixtures) where

import Data.List (isInfixOf)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import Test.Hspec

import CliTest.Common

dir :: FilePath
dir = "tests-cli" </> "fixtures" </> "jsondecode-1078"

importer, importee, wrongNumber, wrongString :: FilePath
importer = dir </> "main.l4"
importee = dir </> "treelib.l4"
wrongNumber = dir </> "wrong-number.l4"
wrongString = dir </> "wrong-string.l4"

fixtures :: [FilePath]
fixtures = [importer, importee, wrongNumber, wrongString]

-- | The first line of each result @l4 run@ prints.
results :: String -> [String]
results out = [ l | (prev, l) <- zip ("" : lines out) (lines out), prev == "Result:" ]

spec :: FilePath -> Spec
spec bin = describe "JSONDECODE at a type fixed by how its result is used (smucclaw/l4-ide#1078)" $ do
  it "l4 run decodes into a record in an imported module's CONSIDER, exit 0" $ do
    Output code sout serr <- runL4 bin ["run", importer]
    (code, serr) `shouldBe` (ExitSuccess, serr)
    results sout `shouldBe` ["  2"]

  it "l4 run stops, exit 1, naming the JSON number it expected, when a string is decoded where a NUMBER is used" $ do
    Output code sout serr <- runL4 bin ["run", wrongNumber]
    code `shouldBe` ExitFailure 1
    let out = sout <> serr
    out `shouldSatisfy` ("Expected JSON number but got: String \"seven\"" `isInfixOf`)
    out `shouldNotSatisfy` ("Internal error" `isInfixOf`)

  it "l4 run stops, exit 1, naming the JSON string it expected, when a number is decoded where a STRING is used" $ do
    Output code sout serr <- runL4 bin ["run", wrongString]
    code `shouldBe` ExitFailure 1
    let out = sout <> serr
    out `shouldSatisfy` ("Expected JSON string but got: Number 7.0" `isInfixOf`)
    out `shouldNotSatisfy` ("Internal error" `isInfixOf`)
