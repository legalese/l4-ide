-- | What the ladder's evaluation of an application answers for each way a
-- result comes out. A refusal is answered with an error response, as an
-- evaluation that raises is, and the response carries the refusal as its
-- data, so a client can tell the two apart. Each error response is read as
-- it goes on the wire, as JSON.
module LadderEvalAppSpec (spec) where

import Test.Hspec

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as Aeson.KeyMap
import Data.Text (Text)

import qualified L4.EvaluateLazy as EL
import L4.EvaluateLazy.Exceptions (EvalException (..), UserEvalException (..))
import LSP.L4.Actions (ladderEvalAppResult)
import LSP.L4.Viz.CustomProtocol (EvalAppResult (..))
import qualified LSP.L4.Viz.VizExpr as Ladder

spec :: Spec
spec = describe "the ladder's evaluation of an application" do
  let -- the error response, as JSON, or Nothing for an answer
      errorResponse r = either (Just . Aeson.toJSON) (const Nothing) r
      -- the data of an error response, which is Nothing when it has none
      dataOf :: Maybe Aeson.Value -> Maybe (Maybe Aeson.Value)
      dataOf = \case
        Just (Aeson.Object o) -> Just (Aeson.KeyMap.lookup "data" o)
        _ -> Nothing
      notModelled = Aeson.object ["kind" Aeson..= ("refused" :: Text), "reason" Aeson..= ("not modelled" :: Text)]

  it "answers a refusal with an error response that carries the refusal and its reason as its data" do
    errorResponse (ladderEvalAppResult (EL.Reduction (EL.ReducedRefused (EL.MkRefusal "not modelled"))))
      `shouldBe` Just (Aeson.object
        [ "code" Aeson..= (-32803 :: Int)
        , "message" Aeson..= ("The model refuses to answer:\n  not modelled\n" :: Text)
        , "data" Aeson..= notModelled ])

  it "answers a refused assertion with an error response that carries the refusal as its data" do
    dataOf (errorResponse (ladderEvalAppResult (EL.Assertion (EL.Refused (EL.MkRefusal "not modelled")))))
      `shouldBe` Just (Just notModelled)

  it "answers an evaluation that raises with an error response that carries no data" do
    dataOf (errorResponse (ladderEvalAppResult (EL.Reduction (EL.ReducedErrored (UserEvalException StackOverflow)))))
      `shouldBe` Just Nothing

  it "answers a satisfied assertion with TRUE" do
    either (const Nothing) Just (ladderEvalAppResult (EL.Assertion EL.Holds))
      `shouldBe` Just (EvalAppResult Ladder.TrueV)
