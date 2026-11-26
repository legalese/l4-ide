{-# LANGUAGE OverloadedStrings #-}

-- | 'L4.API.l4Eval', the entry point of the browser editor (the WASM build),
-- over a module that imports a library whose rules call the rules of a library
-- THAT library imports (smucclaw/l4-ide#1116, review of its fix).
--
-- 'l4Eval' evaluates each resolved import on its own, over an empty
-- environment ('L4.API.evaluateImports'), and gives the module the union of what
-- they made. Each import's rules therefore close over the import's own
-- definitions and the initial environment, and over nothing of what it imports.
-- @excel-date@ imports @daydate@, and its @`Excel 1900 epoch days`@ calls
-- @Day@, a rule of @daydate@.
--
-- Measured 2026-11-26, with the module below:
--
--   * before #1116's fix, both directives answered
--     @Internal error: Day is not in scope. Please report this as a bug.@, with
--     @success@ false;
--   * with it, 693959 and 1, which are what @l4 run@ gives the same module
--     (it hands the module each import's environment together with that of every
--     file the import imports).
--
-- The fix repaired this without being written for it: each directive's copy of
-- the imports' heap ('L4.EvaluateLazy.freshImportsHeap') closes every import's
-- rules over the copies of all the imports' rules, so a rule of one library finds
-- a rule of another. These examples pin the answer the editor gives now, so that
-- a change to the copy that stops it from reaching across imports shows here.
module ApiImportsSpec (spec) where

import Test.Hspec

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import Data.Foldable (toList)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text

import L4.API (l4Eval)

-- | @`Excel 1900 epoch days`@ is @Day `Excel 1900 epoch`@ in @excel-date@, and
-- @Day@ and @Date@ are @daydate@'s. @excelSerial1900@ calls @Day@ in the body
-- of a function.
source :: Text
source = Text.unlines
  [ "IMPORT `excel-date`"
  , ""
  , "#EVAL `Excel 1900 epoch days`"
  , ""
  , "#EVAL excelSerial1900 (Date OF 1, 1, 1900)"
  ]

decode :: Text -> Aeson.Value
decode t = case Aeson.eitherDecodeStrict (Text.encodeUtf8 t) of
  Right v -> v
  Left e -> error ("not JSON: " <> e <> "\n" <> Text.unpack t)

field :: Text -> Aeson.Value -> Maybe Aeson.Value
field k = \case
  Aeson.Object o -> KeyMap.lookup (Key.fromText k) o
  _ -> Nothing

spec :: Spec
spec = describe "l4Eval over an import whose rule calls a rule of the import's own import (smucclaw/l4-ide#1116)" $ do
  it "answers a rule that reads a constant of its own library through another library's rule, and a function that calls one" $ do
    out <- l4Eval source
    let v = decode out
    field "success" v `shouldBe` Just (Aeson.Bool True)
    case field "results" v of
      Just (Aeson.Array rs) ->
        [ (field "result" r, field "success" r) | r <- toList rs ]
          `shouldBe` [ (Just "693959", Just (Aeson.Bool True)), (Just "1", Just (Aeson.Bool True)) ]
      other -> expectationFailure ("expected a results array, got " <> show other <> "\nthe whole answer:\n" <> Text.unpack out)
