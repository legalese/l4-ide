{-# LANGUAGE OverloadedStrings #-}

-- | The browser's query-plan builder ('QueryPlanWasm.l4QueryPlan') draws a rule
-- with the core ladder. A rule that reads one that refuses on only some paths
-- holds a refusal the plan cannot read, and the builder answers with an error
-- that says where, as the service's 400 does, and not with a plan.
--
-- Only the pure function is driven here: the module's foreign exports exist
-- only when it is built for WASM.
module QueryPlanWasmUnreadableSpec (spec) where

import Test.Hspec
import Control.Monad (forM_)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import qualified Data.ByteString.Lazy as LBS

import QueryPlanWasm (l4QueryPlan)

-- | The rules the cases read, then the rules that read them.
source :: Text
source =
  Text.unlines
    [ "GIVEN person IS A BOOLEAN"
    , "GIVETH A BOOLEAN"
    , "`the person is insured` person MEANS"
    , "  IF person THEN TRUE"
    , "  ELSE REFUSE \"insurance is not modelled\""
    , ""
    , "GIVEN amount IS A NUMBER"
    , "GIVETH A BOOLEAN"
    , "`the amount is allowed` amount MEANS"
    , "  IF amount GREATER THAN 0 THEN TRUE"
    , "  ELSE REFUSE \"an amount of nothing is not modelled\""
    , ""
    , "GIVETH A BOOLEAN"
    , "`the scheme is open` MEANS FALSE"
    , ""
    , "GIVETH A BOOLEAN"
    , "`the residence test is met` MEANS"
    , "  IF `the scheme is open` THEN TRUE"
    , "  ELSE REFUSE \"residence is not modelled\""
    , ""
    , "GIVEN person IS A BOOLEAN"
    , "GIVETH A BOOLEAN"
    , "`the person is covered` person MEANS person"
    , ""
    , "GIVEN adult IS A BOOLEAN"
    , "      applicant IS A BOOLEAN"
    , "GIVETH A BOOLEAN"
    , "callWithInput adult applicant MEANS adult AND `the person is insured` applicant"
    , ""
    , "GIVEN adult IS A BOOLEAN"
    , "      amount IS A NUMBER"
    , "GIVETH A BOOLEAN"
    , "callWithNumber adult amount MEANS adult AND `the amount is allowed` amount"
    , ""
    , "GIVEN adult IS A BOOLEAN"
    , "GIVETH A BOOLEAN"
    , "noInputs adult MEANS adult AND `the residence test is met`"
    , ""
    , "GIVEN adult IS A BOOLEAN"
    , "      applicant IS A BOOLEAN"
    , "GIVETH A BOOLEAN"
    , "cannotRefuse adult applicant MEANS adult AND `the person is covered` applicant"
    ]

-- | The plan the builder gives for a function and answers, as an object.
planOf :: Text -> Text -> KeyMap.KeyMap Aeson.Value
planOf fn bindings =
  case Aeson.decode (LBS.fromStrict (Text.encodeUtf8 (l4QueryPlan source "t.l4" fn bindings))) of
    Just (Aeson.Object o) -> o
    other -> error ("the plan is not a JSON object: " <> show other)

spec :: Spec
spec =
  describe "the browser's query-plan builder, on a rule that reads one that refuses on only some paths" $ do
    forM_
      [ ("a call with a Boolean input", "callWithInput", "{\"adult\": true}", "`the person is insured` OF applicant", "insurance is not modelled")
      , ("a call with a NUMBER input", "callWithNumber", "{\"adult\": true}", "`the amount is allowed` OF amount", "an amount of nothing is not modelled")
      , ("a rule of no inputs", "noInputs", "{\"adult\": true}", "`the residence test is met`", "residence is not modelled")
      ] \(what, fn, bindings, leaf, reason) ->
        it ("answers an error that says where, for " <> what) $
          KeyMap.lookup "error" (planOf fn bindings)
            `shouldBe` Just
              ( Aeson.String $
                  "The query plan cannot order the questions for this rule, because a refusal (\""
                    <> reason
                    <> "\") can be reached from this part of it: "
                    <> leaf
              )

    it "plans a call to a rule that cannot refuse" $ do
      let plan = planOf "cannotRefuse" "{\"adult\": true}"
      (KeyMap.lookup "error" plan, KeyMap.lookup "determined" plan) `shouldBe` (Nothing, Just Aeson.Null)
