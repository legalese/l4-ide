{-# LANGUAGE OverloadedStrings #-}

-- | The web editor's query planner, the pure function its browser build
-- exports, run natively here: a rule that may refuse to answer is declined
-- with the one value core gives for such a rule, also when the refusal sits
-- in a definition the rule calls, where the ladder does not show it, and when
-- it sits in a library the file imports.
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

-- | A rule that reaches @YMD@, from the @daydate@ library the editor's file
-- imports, and the same rule with its date built by @Date@, which cannot
-- refuse. @YMD@ refuses a year that is not a whole number, a month that is
-- not a whole number from 1 to 12, and a day that the month does not have,
-- even though this rule calls it on a date that exists.
ymdSource :: Text
ymdSource = Text.unlines
  [ "IMPORT daydate"
  , ""
  , "GIVEN late IS A BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "DECIDE overdueY IF late AND DATE_DAY (YMD 2026 7 28) EQUALS 28"
  , ""
  , "GIVEN late IS A BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "DECIDE overdueByDate IF late AND DATE_DAY (Date 28 7 2026) EQUALS 28"
  ]

-- | What the planner answers for the rule of that name in the source, with no
-- input known.
planIn :: Text -> Text -> Maybe Aeson.Value
planIn source fn = Aeson.decodeStrict' (Text.encodeUtf8 (l4QueryPlan source "file:///editor.l4" fn "{}"))

-- | What the planner answers for the rule of that name in 'editorSource'.
planFor :: Text -> Maybe Aeson.Value
planFor = planIn editorSource

-- | The decline for a rule, with its one reason.
declined :: Text -> Text -> Maybe Aeson.Value
declined rule reason = Just $ Aeson.object
  [ "error" Aeson..= ("No query plan for " <> rule <> ": it may refuse to answer, with the reason \"" <> reason <> "\".")
  , "kind" Aeson..= ("declined" :: Text)
  , "rule" Aeson..= rule
  , "reasons" Aeson..= [reason]
  ]

-- | The decline for a rule with three reasons, which the sentence joins with
-- a comma and an "or", as the REPL's does.
declinedThrice :: Text -> (Text, Text, Text) -> Maybe Aeson.Value
declinedThrice rule (r1, r2, r3) = Just $ Aeson.object
  [ "error" Aeson..= ("No query plan for " <> rule <> ": it may refuse to answer, with the reason \"" <> r1 <> "\", \"" <> r2 <> "\" or \"" <> r3 <> "\".")
  , "kind" Aeson..= ("declined" :: Text)
  , "rule" Aeson..= rule
  , "reasons" Aeson..= [r1, r2, r3]
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

  -- The refusals are in @daydate@, a library the file imports, not in the
  -- file, and the date the rule gives YMD is one that exists.
  describe "a rule that calls YMD from the daydate library" do
    it "declines it, with every reason YMD can refuse with" do
      planIn ymdSource "overdueY" `shouldBe`
        declinedThrice "overdueY"
          ( "YMD: that month has no such day in that year"
          , "YMD: the month is not a whole number from 1 to 12"
          , "YMD: the year is not a whole number"
          )
    -- The control: the rule with its date built by Date is planned, so the
    -- decline above is YMD's and not the import's or the date's.
    it "plans the same rule written with Date" do
      case planIn ymdSource "overdueByDate" of
        Just (Aeson.Object o) -> do
          KeyMap.lookup "kind" o `shouldBe` Nothing
          KeyMap.lookup "determined" o `shouldBe` Just Aeson.Null
        other -> expectationFailure ("not a plan: " <> show other)
