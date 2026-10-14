{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
-- | A field that lists its options inline, @`tenure` IS ONE OF Owner, Tenant@
-- (specs/proposals/INLINE-ONE-OF-FIELD-SPEC.md, option C; Note [Inline ONE OF
-- on a field] in "L4.Syntax"): what the function schema publishes for it, and
-- where going to a definition lands. The corpus files
-- @jl4/examples/ok/inline-one-of*.l4@ pin the rest (evaluation, exact print,
-- the module schema and the natural-language output).
module InlineOptionsSpec (spec) where

import Test.Hspec
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Map.Strict as Map

import L4.API.VirtualFS (checkWithImports, emptyVFS)
import L4.Export (ExportedFunction(..), getExportedFunctions)
import L4.FindDefinition (findDefinition)
import L4.FunctionSchema (Parameters(..), Parameter(..), parametersFromDecide)
import L4.Import.Resolution (TypeCheckWithDepsResult(..))
import L4.Parser.SrcSpan (SrcPos(..), SrcRange(..))

plot :: Text
plot = Text.unlines
  [ "DECLARE Kind IS ONE OF Arable, Pasture"         -- line 1
  , "DECLARE Plot HAS"                               -- line 2
  , "    `the occupier` IS A STRING"                 -- line 3
  , "    `tenure`       IS ONE OF Owner, Tenant TYPICALLY Owner" -- line 4
  , "    `kind`         IS A Kind"                   -- line 5
  , ""
  , "@export whether the plot is owned"              -- line 7
  , "GIVEN p IS A Plot"                              -- line 8
  , "      t IS A `Plot's tenure`"                   -- line 9
  , "GIVETH A BOOLEAN"
  , "`owned` p t MEANS p's tenure EQUALS Owner AND t EQUALS Owner" -- line 11
  ]

-- | The function-schema 'Parameters' of the single export in a snippet.
exportSchema :: Text -> Either [Text] Parameters
exportSchema source =
  case checkWithImports emptyVFS source of
    Left errs -> Left errs
    Right r -> case getExportedFunctions r.tcdModule of
      [ef] -> Right (parametersFromDecide r.tcdModule ef.exportDecide)
      efs  -> Left ["expected exactly one export, got " <> Text.pack (show (length efs))]

-- | The start of the definition found from a 1-based line and column.
definitionAt :: Text -> Int -> Int -> Either [Text] (Maybe (Int, Int))
definitionAt source line column =
  case checkWithImports emptyVFS source of
    Left errs -> Left errs
    Right r -> Right $
      (\ rng -> (rng.start.line, rng.start.column))
        <$> findDefinition (MkSrcPos line column) r.tcdModule

spec :: Spec
spec = do
  describe "function schema" $ do
    it "publishes an inline field's options with no x-l4-type" $
      case exportSchema plot of
        Left errs -> expectationFailure (show errs)
        Right ps -> do
          let field f = Map.lookup "p" ps.parameterMap >>= (.parameterProperties) >>= Map.lookup f
          fmap (.parameterEnum) (field "tenure") `shouldBe` Just ["Owner", "Tenant"]
          fmap (.parameterL4Type) (field "tenure") `shouldBe` Just Nothing
          -- a DECLAREd enum keeps its name, as before
          fmap (.parameterL4Type) (field "kind") `shouldBe` Just (Just "Kind")

    it "publishes the default, and leaves the field out of required" $
      case exportSchema plot of
        Left errs -> expectationFailure (show errs)
        Right ps -> do
          let p = Map.lookup "p" ps.parameterMap
          fmap (.parameterDefault) (p >>= (.parameterProperties) >>= Map.lookup "tenure")
            `shouldBe` Just (Just "Owner")
          fmap (elem "tenure") (p >>= (.parameterRequired)) `shouldBe` Just False

    it "publishes no x-l4-type for a rule's input that names the generated type" $
      case exportSchema plot of
        Left errs -> expectationFailure (show errs)
        Right ps -> do
          fmap (.parameterL4Type) (Map.lookup "t" ps.parameterMap) `shouldBe` Just Nothing
          fmap (.parameterEnum) (Map.lookup "t" ps.parameterMap) `shouldBe` Just ["Owner", "Tenant"]

  describe "going to a definition" $ do
    it "lands on the field's ONE OF from a rule that names the generated type" $
      -- `Plot's tenure` on line 9 starts at column 14; ONE at line 4, column 23
      definitionAt plot 9 18 `shouldBe` Right (Just (4, 23))

    it "lands on the option where the field lists it" $
      -- `Owner` on line 11 starts at column 37; on line 4 at column 30
      definitionAt plot 11 39 `shouldBe` Right (Just (4, 30))
