{-# LANGUAGE OverloadedStrings #-}

-- | Regression coverage for smucclaw/l4-ide#919: the 'ToConcreteNodes'
-- instances for 'Event' had their @atFirst@ branches swapped, so
-- @l4 format@ (exactprint of the parsed AST) scrambled every event:
-- @PARTY Tenant DOES pay AT 30@ printed as @PARTY 30 / DOES Tenant AT pay@.
-- Exactprint must be the identity on source text.
module EventExactPrintSpec (spec) where

import Base
import qualified Data.Text as T
import L4.ExactPrint (exactprint)
import L4.Parser (execProgramParserWithHintPass)
import Test.Hspec

spec :: Spec
spec =
  describe "Event exact-print round-trip (issue #919)" $ do
    it "round-trips PARTY ... DOES ... AT ... (atFirst = False)" $
      roundTrips (prologue <> "ev MEANS PARTY Tenant DOES pay AT 30\n")

    it "round-trips AT ... PARTY ... DOES ... (atFirst = True)" $
      roundTrips (prologue <> "ev2 MEANS AT 30 PARTY Tenant DOES pay\n")

    it "round-trips multiline events" $
      roundTrips $
        prologue
          <> T.unlines
            [ "ev3 MEANS"
            , "  PARTY Tenant"
            , "  DOES pay"
            , "  AT 30"
            ]

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
    uri = toNormalizedUri (Uri "file:///event-exactprint-spec")

prologue :: T.Text
prologue =
  T.unlines
    [ "IMPORT prelude"
    , ""
    , "DECLARE Actor IS ONE OF Tenant, Landlord"
    , ""
    , "GIVEN a IS AN Actor"
    , "GIVETH A BOOLEAN"
    , "pay a MEANS TRUE"
    , ""
    ]
