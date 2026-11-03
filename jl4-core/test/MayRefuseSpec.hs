{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | The reasons a definition may refuse to answer with, read from what is
-- written ('L4.Refusal.refusalReasons'), and the one answer a query planner
-- gives for a rule that may refuse ('L4.Refusal.planDecline').
--
-- A REFUSE reached through a name is the house style, one named definition
-- per refusal, so most cases follow names: through calls, a WHERE, a LET, an
-- AKA, a computed field, a clause group, recursion, a regulative rule's
-- HENCE, another section, and imports.
module MayRefuseSpec (spec) where

import Test.Hspec

import qualified Data.Aeson as Aeson
import Data.Foldable (for_)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text

import L4.API.VirtualFS (ResolvedImport (..), TypeCheckWithDepsResult (..), checkWithImportsAndUri, vfsFromList)
import L4.Refusal (PlanDecline (..), declineMessage, planDecline, refusalReasons)
import L4.Syntax (AppForm (..), Decide (..), Module, Resolved, foldTopLevelDecides, getActual, rawName, rawNameToText)
import L4.TypeCheck (severity)
import L4.TypeCheck.Types (CheckResult (..), Severity (..))

-- | The main module, checked with the given modules to import (name and
-- source), then every module it reads: itself first, then each module it
-- imports, directly or not.
checkedModules :: [(Text, Text)] -> [Text] -> IO [Module Resolved]
checkedModules imports srcLines =
  case checkWithImportsAndUri (vfsFromList imports) "main" (Text.unlines srcLines) of
    Left errs -> fail ("the module did not check:\n" <> Text.unpack (Text.unlines errs))
    Right r -> case filter ((== SError) . severity) r.tcdErrors of
      [] -> pure (r.tcdModule : map (\ri -> ri.riTypeChecked.program) r.tcdResolvedImports)
      errs -> fail ("the module has type errors: " <> show (length errs))

-- | The main module's top-level definition of that name.
decideNamed :: Text -> [Module Resolved] -> IO (Decide Resolved)
decideNamed name mods = case mods of
  main : _
    | [d] <- foldTopLevelDecides (\d@(MkDecide _ _ (MkAppForm _ h _ _) _) -> [d | rawNameToText (rawName (getActual h)) == name]) main
    -> pure d
  _ -> fail ("no one definition named " <> Text.unpack name)

-- | The reasons the main module's definition @rule@ may refuse with.
reasonsOf :: [(Text, Text)] -> [Text] -> IO (Set.Set Text)
reasonsOf imports srcLines = do
  mods <- checkedModules imports srcLines
  refusalReasons mods <$> decideNamed "rule" mods

-- | A rule over a number that answers 100 from the year 2000 and otherwise
-- the given expression, after the given definitions.
feeInYear :: [Text] -> Text -> [Text]
feeInYear defs before2000 =
  defs <>
  [ ""
  , "GIVEN y IS A NUMBER"
  , "GIVETH A NUMBER"
  , "rule y MEANS"
  , "    IF y >= 2000"
  , "    THEN 100"
  , "    ELSE " <> before2000
  ]

-- | A named refusal.
oldFeeRefuses :: [Text]
oldFeeRefuses =
  [ "GIVETH A NUMBER"
  , "`the old fee` MEANS REFUSE \"fees before 2000 are not encoded\""
  ]

-- | The control: the same name, with a value.
oldFeeIsFifty :: [Text]
oldFeeIsFifty =
  [ "GIVETH A NUMBER"
  , "`the old fee` MEANS 50"
  ]

-- | A second called definition, with a value.
firstFeeIsFifty :: [Text]
firstFeeIsFifty =
  [ "GIVETH A NUMBER"
  , "`the first fee` MEANS 50"
  ]

oldFee :: Set.Set Text
oldFee = Set.singleton "fees before 2000 are not encoded"

-- | @base@ holds the refusal, @older@ and @newer@ each import it, and the
-- main module imports both and calls @older@.
importDiamond :: [(Text, Text)]
importDiamond =
  [ ("base", Text.unlines oldFeeRefuses)
  , ("older", Text.unlines
      [ "IMPORT base"
      , ""
      , "GIVEN y IS A NUMBER"
      , "GIVETH A NUMBER"
      , "`the old fee in year` y MEANS `the old fee`"
      ])
  , ("newer", Text.unlines
      [ "IMPORT base"
      , ""
      , "GIVETH A NUMBER"
      , "`the new fee` MEANS 100"
      ])
  ]

-- | Two definitions that call each other; the second refuses below zero.
parity :: [Text] -> [Text]
parity belowZero =
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`is even` n MEANS IF n EQUALS 0 THEN TRUE ELSE `is odd` (n - 1)"
  , ""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`is odd` n MEANS"
  , "    IF n < 0 THEN " <> Text.unwords belowZero
  , "    ELSE IF n EQUALS 0 THEN FALSE ELSE `is even` (n - 1)"
  , ""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "rule n MEANS `is even` n"
  ]

-- | A regulative rule whose HENCE names a definition with the given body.
henceNamed :: [Text] -> [Text]
henceNamed body =
  [ "DECLARE Party IS ONE OF `alice`"
  , "DECLARE Action IS ONE OF `pay`"
  , ""
  , "GIVETH A DEONTIC OF Party, Action"
  , "`what follows payment` MEANS"
  ]
  <> map ("    " <>) body <>
  [ ""
  , "GIVETH A DEONTIC OF Party, Action"
  , "rule MEANS"
  , "    PARTY `alice`"
  , "    MUST `pay`"
  , "    WITHIN 10"
  , "    HENCE `what follows payment`"
  ]

-- | A helper that refuses for a person who is not insured, and two rules that
-- read it: one with a refusal of its own as well, and a third rule that
-- cannot refuse.
coverage :: [Text]
coverage =
  [ "GIVEN person IS A BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "`the person is insured` person MEANS"
  , "    IF person THEN TRUE"
  , "    ELSE REFUSE \"insurance is not modelled\""
  , ""
  , "GIVEN adult IS A BOOLEAN"
  , "      applicant IS A BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "DECIDE covered IF adult AND `the person is insured` applicant"
  , ""
  , "GIVEN adult IS A BOOLEAN"
  , "      applicant IS A BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "DECIDE checked IF"
  , "    IF adult THEN `the person is insured` applicant"
  , "    ELSE REFUSE \"minors are not modelled\""
  , ""
  , "GIVEN adult IS A BOOLEAN"
  , "      resident IS A BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "DECIDE planned IF adult AND resident"
  , ""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A NUMBER"
  , "`the fee for` n MEANS"
  , "    IF n > 0 THEN n"
  , "    ELSE IF n EQUALS 0"
  , "           THEN REFUSE \"a fee of nothing is not modelled\""
  , "           ELSE REFUSE \"a negative fee is not modelled\""
  , ""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "DECIDE `the fee is due` IF `the fee for` n GREATER THAN 0"
  ]

-- | What a planner answers for the definition of that name in 'coverage'.
declineFor :: Text -> IO (Maybe PlanDecline)
declineFor name = do
  mods <- checkedModules [] coverage
  planDecline mods <$> decideNamed name mods

spec :: Spec
spec = do
  describe "the reasons a definition may refuse with" do
    it "is the reason of a REFUSE written in it" do
      reasonsOf [] (feeInYear [] "REFUSE \"fees before 2000 are not encoded\"") `shouldReturn` oldFee
    it "is every reason written in it, on every path" do
      reasonsOf [] (feeInYear [] "IF y < 0 THEN REFUSE \"a negative year\" ELSE REFUSE \"fees before 2000 are not encoded\"")
        `shouldReturn` Set.fromList ["a negative year", "fees before 2000 are not encoded"]
    it "holds a reason that no input reaches" do
      reasonsOf [] (feeInYear [] "IF FALSE THEN REFUSE \"never reached\" ELSE 50") `shouldReturn` Set.singleton "never reached"
    it "is empty for a definition with no REFUSE" do
      reasonsOf [] (feeInYear oldFeeIsFifty "`the old fee`") `shouldReturn` Set.empty
    it "holds the reason of a definition it calls" do
      reasonsOf [] (feeInYear oldFeeRefuses "`the old fee`") `shouldReturn` oldFee
    it "holds the reason of a definition two calls away" do
      reasonsOf []
        (feeInYear (oldFeeRefuses <> ["", "GIVEN y IS A NUMBER", "GIVETH A NUMBER", "`the old fee in year` y MEANS `the old fee`"])
                   "`the old fee in year` y")
        `shouldReturn` oldFee
    it "holds the reason of the second of two definitions it calls, whichever is written first" do
      reasonsOf [] (feeInYear (firstFeeIsFifty <> [""] <> oldFeeRefuses) "`the first fee` PLUS `the old fee`") `shouldReturn` oldFee
      reasonsOf [] (feeInYear (oldFeeRefuses <> [""] <> firstFeeIsFifty) "`the first fee` PLUS `the old fee`") `shouldReturn` oldFee
    it "holds the reason of a definition called with named inputs" do
      reasonsOf []
        (feeInYear ["GIVEN n IS A NUMBER", "GIVETH A NUMBER", "`the old fee for` n MEANS REFUSE \"fees before 2000 are not encoded\""]
                   "`the old fee for` WITH n IS y")
        `shouldReturn` oldFee
    it "holds the reason of a WHERE definition" do
      reasonsOf [] (feeInYear [] "`the old fee`" <> ["  WHERE", "    `the old fee` MEANS REFUSE \"fees before 2000 are not encoded\""])
        `shouldReturn` oldFee
    it "holds the reason of a LET definition" do
      reasonsOf [] (feeInYear [] "LET x MEANS REFUSE \"fees before 2000 are not encoded\" IN x PLUS 1") `shouldReturn` oldFee
    it "holds the reason of a definition called by its AKA name" do
      reasonsOf []
        (feeInYear ["GIVETH A NUMBER", "`the old fee` AKA `the fee before 2000` MEANS REFUSE \"fees before 2000 are not encoded\""]
                   "`the fee before 2000`")
        `shouldReturn` oldFee
    it "holds the reason of every clause of a clause group it calls" do
      reasonsOf []
        (feeInYear
          [ "GIVEN n IS A NUMBER"
          , "GIVETH A NUMBER"
          , "DECIDE `the old fee` 0 IS REFUSE \"year zero is not encoded\""
          , "DECIDE `the old fee` n IS REFUSE \"fees before 2000 are not encoded\""
          ]
          "`the old fee` y")
        `shouldReturn` Set.fromList ["year zero is not encoded", "fees before 2000 are not encoded"]
    it "holds the reason of a computed field it reads" do
      reasonsOf []
        [ "DECLARE Person HAS"
        , "    `age`   IS A NUMBER"
        , "    `adult` IS A BOOLEAN"
        , "        MEANS IF `age` >= 18 THEN TRUE ELSE REFUSE \"minors are not modelled\""
        , ""
        , "GIVEN p IS A Person"
        , "GIVETH A BOOLEAN"
        , "rule p MEANS p's `adult`"
        ]
        `shouldReturn` Set.singleton "minors are not modelled"
    it "holds the reason of a definition in another section" do
      reasonsOf []
        [ "§ `Old fees`"
        , "GIVEN n IS A NUMBER"
        , "GIVETH A NUMBER"
        , "`the old fee` n MEANS REFUSE \"fees before 2000 are not encoded\""
        , ""
        , "§ `Rules`"
        , "GIVEN y IS A NUMBER"
        , "GIVETH A NUMBER"
        , "rule y MEANS IF y >= 2000 THEN 100 ELSE `the old fee` y"
        ]
        `shouldReturn` Set.singleton "fees before 2000 are not encoded"
    it "holds the reason reached through mutual recursion" do
      reasonsOf [] (parity ["REFUSE \"negative numbers are not modelled\""]) `shouldReturn` Set.singleton "negative numbers are not modelled"
    it "is empty, and found, for mutual recursion with no REFUSE" do
      reasonsOf [] (parity ["FALSE"]) `shouldReturn` Set.empty
    it "holds the reason of a definition named by a HENCE" do
      reasonsOf [] (henceNamed ["REFUSE \"what follows payment is not modelled\""])
        `shouldReturn` Set.singleton "what follows payment is not modelled"
      reasonsOf [] (henceNamed ["FULFILLED"]) `shouldReturn` Set.empty
    it "holds the reason of an imported definition" do
      reasonsOf [("fees", Text.unlines oldFeeRefuses)] ("IMPORT fees" : "" : feeInYear [] "`the old fee`") `shouldReturn` oldFee
      reasonsOf [("fees", Text.unlines oldFeeIsFifty)] ("IMPORT fees" : "" : feeInYear [] "`the old fee`") `shouldReturn` Set.empty
    it "holds the reason of a definition two imports away, through a module imported twice" do
      reasonsOf importDiamond ("IMPORT older" : "IMPORT newer" : "" : feeInYear [] "`the old fee in year` y") `shouldReturn` oldFee
    it "holds no reason of a definition it does not name" do
      reasonsOf [] (feeInYear oldFeeRefuses "50") `shouldReturn` Set.empty
    it "is the same when a module is passed twice" do
      mods <- checkedModules importDiamond ("IMPORT older" : "IMPORT newer" : "" : feeInYear [] "`the old fee in year` y")
      rule <- decideNamed "rule" mods
      refusalReasons (mods <> mods) rule `shouldBe` refusalReasons mods rule

  describe "what a query planner answers for a rule that may refuse" do
    it "plans a rule that cannot refuse" do
      declineFor "planned" `shouldReturn` Nothing
    it "declines a rule that may refuse through a definition it calls, with the reason" do
      declineFor "covered" `shouldReturn` Just (MkPlanDecline "covered" ["insurance is not modelled"])
    it "declines a rule with each reason it may refuse with, its own and a called definition's" do
      declineFor "checked" `shouldReturn` Just (MkPlanDecline "checked" ["insurance is not modelled", "minors are not modelled"])
    it "declines a rule whose refusals sit inside one comparison, and names the rule as L4 writes it" do
      declineFor "the fee is due" `shouldReturn`
        Just (MkPlanDecline "`the fee is due`" ["a fee of nothing is not modelled", "a negative fee is not modelled"])
    it "says why in one sentence, which names the rule and every reason" do
      for_
        [ ( MkPlanDecline "covered" ["insurance is not modelled"]
          , "No query plan for covered: it may refuse to answer, with the reason \"insurance is not modelled\"." )
        , ( MkPlanDecline "checked" ["insurance is not modelled", "minors are not modelled"]
          , "No query plan for checked: it may refuse to answer, with the reason \"insurance is not modelled\" or \"minors are not modelled\"." )
        , ( MkPlanDecline "`the fee is due`" ["a", "b", "c"]
          , "No query plan for `the fee is due`: it may refuse to answer, with the reason \"a\", \"b\" or \"c\"." )
        ]
        \(d, msg) -> declineMessage d `shouldBe` msg
    it "is one JSON value, which carries that sentence, the rule and its reasons" do
      Aeson.toJSON (MkPlanDecline "checked" ["insurance is not modelled", "minors are not modelled"])
        `shouldBe` Aeson.object
          [ "error" Aeson..= ("No query plan for checked: it may refuse to answer, with the reason \"insurance is not modelled\" or \"minors are not modelled\"." :: Text)
          , "kind" Aeson..= ("declined" :: Text)
          , "rule" Aeson..= ("checked" :: Text)
          , "reasons" Aeson..= (["insurance is not modelled", "minors are not modelled"] :: [Text])
          ]
