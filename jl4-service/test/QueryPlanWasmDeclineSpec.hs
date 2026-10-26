{-# LANGUAGE OverloadedStrings #-}

-- | The web editor's query planner, the pure function its browser build
-- exports, run natively here: a rule that may refuse to answer is declined
-- with the one value core gives for such a rule, also when the refusal sits
-- in a definition the rule calls, where the ladder does not show it.
module QueryPlanWasmDeclineSpec (spec) where

import Test.Hspec

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text

import L4.Decision.EditorQueryPlan (l4QueryPlan)

-- | A helper that refuses for a person who is not insured, rules that read it,
-- a rule with a refusal of its own, a rule over a number, and a rule that
-- cannot refuse.
editorSource :: Text
editorSource = Text.unlines
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
  , "GIVETH A BOOLEAN"
  , "DECIDE minor IF IF adult THEN FALSE ELSE REFUSE \"minors are not modelled\""
  , ""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A NUMBER"
  , "fee n MEANS IF n < 0 THEN REFUSE \"a negative fee is not modelled\" ELSE n"
  , ""
  , "GIVEN adult IS A BOOLEAN"
  , "      resident IS A BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "DECIDE planned IF adult AND resident"
  ]

-- | What the planner answers for the rule of that name, with no input known.
planFor :: Text -> Maybe Aeson.Value
planFor fn = Aeson.decodeStrict' (Text.encodeUtf8 (l4QueryPlan editorSource "file:///editor.l4" fn "{}"))

-- | The decline for a rule, with its one reason.
declined :: Text -> Text -> Maybe Aeson.Value
declined rule reason = Just $ Aeson.object
  [ "error" Aeson..= ("No query plan for " <> rule <> ": it may refuse to answer, with the reason \"" <> reason <> "\".")
  , "kind" Aeson..= ("declined" :: Text)
  , "rule" Aeson..= rule
  , "reasons" Aeson..= [reason]
  ]

spec :: Spec
spec = describe "the web editor's query planner, run natively" do
  it "declines a rule that may refuse through a definition it calls" do
    planFor "covered" `shouldBe` declined "covered" "insurance is not modelled"
  it "declines a rule with a REFUSE of its own" do
    planFor "minor" `shouldBe` declined "minor" "minors are not modelled"
  it "declines a rule over a number that may refuse" do
    planFor "fee" `shouldBe` declined "fee" "a negative fee is not modelled"
  it "plans a rule that cannot refuse" do
    case planFor "planned" of
      Just (Aeson.Object o) -> KeyMap.lookup "determined" o `shouldBe` Just Aeson.Null
      other -> expectationFailure ("not a plan: " <> show other)
