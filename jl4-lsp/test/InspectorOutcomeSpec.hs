-- | What the Inspector says about an @#ASSERT@ for each way it can come out.
--
-- A failed @#ASSERT REFUSED@ ('EL.FailsBecause') has a verdict, and the
-- verdict is false, as a clean FALSE @#ASSERT@'s is ('EL.Fails'). A satisfied
-- @#ASSERT@ is the control on the other side.
module InspectorOutcomeSpec (spec) where

import Test.Hspec

import qualified Data.Aeson as Aeson
import Language.LSP.Protocol.Types (Uri (..), toNormalizedUri)

import qualified L4.EvaluateLazy as EL
import L4.Parser.SrcSpan (SrcPos (..), SrcRange (..))
import LSP.L4.Inspector (DirectiveResult (..), evalDirectiveToResult, successOf)

spec :: Spec
spec = describe "the Inspector on an #ASSERT" do
  let rng = MkSrcRange (MkSrcPos 1 1) (MkSrcPos 1 18) 17 (toNormalizedUri (Uri "file:///outcome.l4"))
      resultFor outcome =
        evalDirectiveToResult mempty "#ASSERT" rng
          (EL.MkEvalDirectiveResult (Just rng) (EL.Assertion outcome) Nothing)
      failedRefused = EL.FailsBecause "expected a refusal, but the expression produced a value"

  it "gives a failed #ASSERT REFUSED a false verdict, as it gives a clean FALSE" do
    successOf (EL.Assertion failedRefused) `shouldBe` Just False
    (resultFor failedRefused).success `shouldBe` Just False
    (resultFor failedRefused).structuredValue `shouldBe` Just (Aeson.Bool False)
    (resultFor EL.Fails).success `shouldBe` Just False
    (resultFor EL.Fails).structuredValue `shouldBe` Just (Aeson.Bool False)

  it "gives a satisfied #ASSERT a true verdict" do
    successOf (EL.Assertion EL.Holds) `shouldBe` Just True
    (resultFor EL.Holds).success `shouldBe` Just True
    (resultFor EL.Holds).structuredValue `shouldBe` Just (Aeson.Bool True)
