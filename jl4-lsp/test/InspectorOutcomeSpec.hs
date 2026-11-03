-- | What the Inspector says about an @#ASSERT@ for each way it can come out.
--
-- A failed @#ASSERT REFUSED@ ('EL.FailsBecause') has a verdict, and the
-- verdict is false, as a clean FALSE @#ASSERT@'s is ('EL.Fails'). A satisfied
-- @#ASSERT@ is the control on the other side. A refused @#ASSERT@ has no
-- verdict, and neither has a refusing @#EVAL@: a refusal is neither a success
-- nor a failure. That holds for both of the Inspector's shapes: the answer to
-- @l4/evalDirectiveResult@ ('evalDirectiveToResult') and a row of the
-- @l4/directiveResultsUpdated@ notification ('evalDirectiveToUpdateItem').
module InspectorOutcomeSpec (spec) where

import Test.Hspec

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import Language.LSP.Protocol.Types (Uri (..), toNormalizedUri)

import qualified L4.EvaluateLazy as EL
import L4.Parser.SrcSpan (SrcPos (..), SrcRange (..))
import LSP.L4.Inspector
  ( DirectiveResult (..)
  , DirectiveUpdateItem (..)
  , evalDirectiveToResult
  , evalDirectiveToUpdateItem
  )

spec :: Spec
spec = describe "the Inspector on an #ASSERT" do
  let rng = MkSrcRange (MkSrcPos 1 1) (MkSrcPos 1 18) 17 (toNormalizedUri (Uri "file:///outcome.l4"))
      resultFor outcome =
        evalDirectiveToResult mempty "#ASSERT" rng
          (EL.MkEvalDirectiveResult (Just rng) (EL.Assertion outcome) Nothing)
      evalResultFor value =
        evalDirectiveToResult mempty "#EVAL" rng
          (EL.MkEvalDirectiveResult (Just rng) (EL.Reduction value) Nothing)
      updateItemFor value =
        evalDirectiveToUpdateItem mempty (\_ _ -> "")
          (EL.MkEvalDirectiveResult (Just rng) value Nothing)
      failedRefused = EL.FailsBecause "expected a refusal, but the expression produced a value"
      successKey v = case Aeson.toJSON v of
        Aeson.Object o -> KeyMap.lookup "success" o
        _ -> Nothing

  it "gives a failed #ASSERT REFUSED a false verdict, as it gives a clean FALSE" do
    (resultFor failedRefused).success `shouldBe` Just False
    (resultFor failedRefused).structuredValue `shouldBe` Just (Aeson.Bool False)
    (resultFor EL.Fails).success `shouldBe` Just False
    (resultFor EL.Fails).structuredValue `shouldBe` Just (Aeson.Bool False)

  it "gives a satisfied #ASSERT a true verdict" do
    (resultFor EL.Holds).success `shouldBe` Just True
    (resultFor EL.Holds).structuredValue `shouldBe` Just (Aeson.Bool True)

  it "gives a refused #ASSERT and a refusing #EVAL no verdict, true or false" do
    let refusal = EL.MkRefusal "not modelled"
        refused = resultFor (EL.Refused refusal)
        refusing = evalResultFor (EL.ReducedRefused refusal)
    refused.success `shouldBe` Nothing
    refusing.success `shouldBe` Nothing
    refused.structuredValue `shouldBe` Nothing
    refusing.structuredValue `shouldBe` Nothing
    successKey refused `shouldBe` Just Aeson.Null
    successKey refusing `shouldBe` Just Aeson.Null

  it "gives a refused #ASSERT and a refusing #EVAL no verdict, true or false, in the notification of directive results" do
    let refusal = EL.MkRefusal "not modelled"
        outcomes =
          [ EL.Assertion (EL.Refused refusal)
          , EL.Reduction (EL.ReducedRefused refusal)
          , EL.Assertion EL.Holds
          , EL.Assertion EL.Fails
          ]
    case traverse updateItemFor outcomes of
      Just [refused, refusing, held, failed] -> do
        refused.success `shouldBe` Nothing
        refusing.success `shouldBe` Nothing
        held.success `shouldBe` Just True
        failed.success `shouldBe` Just False
        successKey refused `shouldBe` Just Aeson.Null
        successKey refusing `shouldBe` Just Aeson.Null
      other -> expectationFailure ("expected a row for each directive, which has a range, got " <> show other)
