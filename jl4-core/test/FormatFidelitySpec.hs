{-# LANGUAGE OverloadedStrings #-}

-- | Round-trip coverage for @l4 format@ (exactprint of the parsed AST) on the
-- constructs whose exactprint used to mangle the source. Each case asserts that
-- @exactprint (parse src) == src@; before the corresponding fix each would
-- reorder, duplicate, drop, or re-escape tokens.
--
--   * TIMEZONE IS — used to drop the @TIMEZONE@/@IS@ keywords (unparseable).
--   * UNLESS — used to duplicate the keyword (@l UNLESS UNLESS r@).
--   * non-ASCII string literals — used to re-escape to @\\214@-style decimals.
module FormatFidelitySpec (spec) where

import Base
import qualified Data.Text as T
import L4.ExactPrint (exactprint)
import L4.Parser (execProgramParserWithHintPass)
import Test.Hspec

spec :: Spec
spec =
  describe "l4 format exactprint fidelity" $ do
    describe "TIMEZONE IS" $ do
      it "round-trips a TIMEZONE IS string declaration" $
        roundTrips (T.unlines ["IMPORT prelude", "", "TIMEZONE IS \"Etc/UTC\"", "", "x MEANS 1"])
      it "round-trips a TIMEZONE IS bare-identifier declaration" $
        roundTrips (T.unlines ["IMPORT prelude", "", "TIMEZONE IS EST", "", "x MEANS 1"])

    describe "UNLESS" $ do
      it "round-trips a bare UNLESS" $
        roundTrips (T.unlines ["GIVETH A BOOLEAN", "u MEANS TRUE UNLESS FALSE"])
      it "round-trips UNLESS following an OR chain" $
        roundTrips (T.unlines ["GIVETH A BOOLEAN", "v MEANS TRUE OR FALSE UNLESS TRUE"])

    describe "non-ASCII string literals" $ do
      it "round-trips a Latin-1 literal verbatim" $
        roundTrips (T.unlines ["GIVETH A STRING", "a MEANS \"Österreich\""])
      it "round-trips a CJK literal verbatim" $
        roundTrips (T.unlines ["GIVETH A STRING", "b MEANS \"新加坡共和国\""])
      it "round-trips a bullet symbol verbatim" $
        roundTrips (T.unlines ["GIVETH A STRING", "c MEANS \"•\""])
      it "preserves an escaped source literal as written (does not normalise)" $
        roundTrips (T.unlines ["GIVETH A STRING", "d MEANS \"\\214sterreich\""])

roundTrips :: T.Text -> Expectation
roundTrips src =
  case execProgramParserWithHintPass uri src of
    Left errs ->
      expectationFailure $ "Parser failed with: " <> show errs
    Right (moduleAst, _hints, _warnings) ->
      case exactprint moduleAst of
        Left err -> expectationFailure $ "exactprint failed: " <> show err
        Right printed -> printed `shouldBe` src
  where
    uri = toNormalizedUri (Uri "file:///format-fidelity-spec")
