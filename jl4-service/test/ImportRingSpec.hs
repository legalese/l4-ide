{-# LANGUAGE OverloadedStrings #-}

-- | A bundle with a ring of imports, or a file that imports itself, is refused.
--
-- It must not compile with the import left out. A name from the module left out
-- would read as undefined, the service treats an undefined name in an @\@export@
-- as an input the caller supplies, and the deployment would serve a wrong schema.
module ImportRingSpec (spec) where

import Test.Hspec

import Compiler (compileBundle)
import UnresolvedImportSpec (unresolvedLines, withLog)

import qualified Data.ByteString.Char8 as BS8
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import System.Timeout (timeout)

-- | An exported rule with this body, after these imports.
exported :: [Text] -> Text -> Text
exported modules body = Text.unlines $
  [ "IMPORT " <> m | m <- modules ] <>
  [ ""
  , "@export Works out a number"
  , "GIVEN x IS A NUMBER"
  , "GIVETH A NUMBER"
  , "DECIDE worked x IS " <> body
  ]

-- | Why a bundle was refused, if it was, and what the service logged. The
-- service checks a bundle's files all at once, which is what hung on a ring, so
-- this gives up instead of waiting for ever.
compiled :: Map FilePath Text -> IO (Maybe Text, [BS8.ByteString])
compiled bundle = withLog \logger -> do
  result <- timeout 60_000_000 (compileBundle logger "import-ring" bundle)
  case result of
    Nothing -> fail "compileBundle did not finish"
    Just (Left why) -> pure (Just why)
    Just (Right _) -> pure Nothing

spec :: Spec
spec = describe "a bundle with a ring of imports" do
  let refusedFor :: Text -> Map FilePath Text -> Expectation
      refusedFor reason bundle = do
        (why, _) <- compiled bundle
        why `shouldSatisfy` maybe False (reason `Text.isInfixOf`)

  it "compiles without the ring, which is what the bundles below break" do
    (why, _) <- compiled $ Map.fromList
      [ ("left.l4", exported ["right"] "x TIMES `the rate`")
      , ("right.l4", "DECIDE `the rate` IS 2\n")
      ]
    why `shouldBe` Nothing

  it "is refused when a rule reads a name from the other file" do
    refusedFor "ring of imports" $ Map.fromList
      [ ("left.l4", exported ["right"] "x TIMES `the rate`")
      , ("right.l4", "IMPORT left\n\nDECIDE `the rate` IS 2\n")
      ]

  it "is refused when no rule reads anything from the other file" do
    refusedFor "ring of imports" $ Map.fromList
      [ ("left.l4", exported ["right"] "x TIMES 2")
      , ("right.l4", "IMPORT left\n\nDECIDE `the rate` IS 2\n")
      ]

  it "is refused when the rule is in a file that only imports the ring" do
    refusedFor "ring of imports" $ Map.fromList
      [ ("main.l4", exported ["left"] "x TIMES `the rate`")
      , ("left.l4", "IMPORT right\n\nDECIDE `the rate` IS 2\n")
      , ("right.l4", "IMPORT left\n\nDECIDE `the other rate` IS 3\n")
      ]

  it "is refused when a file imports itself, and that is not a missing module" do
    (why, logLines) <- compiled $ Map.fromList
      [ ("solo.l4", exported ["solo"] "x TIMES 2") ]
    why `shouldSatisfy` maybe False ("cannot import itself" `Text.isInfixOf`)
    unresolvedLines logLines `shouldBe` []
